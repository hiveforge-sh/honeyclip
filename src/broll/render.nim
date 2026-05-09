## FFmpeg mux pipeline for B-roll insertion in honeyclip
##
## Builds a segment plan (alternating source + B-roll), normalizes B-roll clips
## to match source resolution/fps, writes a concat list, and muxes the final output.
## All FFmpeg invocations use execCmdEx (mirror Phase 19-02 pattern).
## Paths are shell-quoted (T-21-06 compliance).

import std/[os, osproc, strformat, strutils, times]
import ../analyze/broll as brollAnalyze
import ../log
import comfyui  # for ClipResult

type
  SegmentKind* = enum skSource, skBroll
  SegmentPlan* = object
    kind*: SegmentKind
    startMs*: int64
    endMs*: int64
    sourceIndex*: int   ## for skBroll: index into clips[]; -1 for skSource

proc buildSegmentPlan*(durationMs: int64,
                       insertions: seq[brollAnalyze.BrollInsertion]): seq[SegmentPlan] =
  ## Walk insertions in chronological order, emit alternating source/broll segments.
  ## Guarantees full coverage of [0, durationMs] with no overlaps.
  ## Caller guarantees insertions are sorted and non-overlapping.
  var cursor: int64 = 0
  for i, ins in insertions:
    if ins.startMs > cursor:
      result.add SegmentPlan(kind: skSource, startMs: cursor, endMs: ins.startMs,
                             sourceIndex: -1)
    result.add SegmentPlan(kind: skBroll, startMs: ins.startMs, endMs: ins.endMs,
                           sourceIndex: i)
    cursor = ins.endMs
  if cursor < durationMs:
    result.add SegmentPlan(kind: skSource, startMs: cursor, endMs: durationMs,
                           sourceIndex: -1)

proc escapeConcatPath*(p: string): string =
  ## Escape a file path for use inside single-quoted FFmpeg concat-demuxer entries.
  ## FFmpeg concat-demuxer uses its own escaping: backslashes and single quotes
  ## must be escaped so a path like "it's" becomes "it'\''s".
  p.replace("\\", "\\\\").replace("'", "\\'")

proc buildConcatList*(plan: seq[SegmentPlan], srcSegmentPaths: seq[string],
                      brollClipPaths: seq[string]): string =
  ## Build FFmpeg concat-demuxer file content. Uses single-quoted path syntax.
  ## srcSegmentPaths is parallel to occurrences of skSource in plan.
  var srcIdx = 0
  for s in plan:
    case s.kind
    of skSource:
      result.add &"file '{escapeConcatPath(srcSegmentPaths[srcIdx])}'\n"
      inc srcIdx
    of skBroll:
      result.add &"file '{escapeConcatPath(brollClipPaths[s.sourceIndex])}'\n"

proc normalizeBrollClipCmd*(brollPath: string, targetW, targetH: int,
                            targetFps: float, outPath: string): string =
  ## Build FFmpeg command to re-encode a B-roll clip to source resolution + fps.
  ## Pure builder; paths are shell-quoted (T-21-06).
  &"ffmpeg -y -i {brollPath.quoteShell} -vf scale={targetW}:{targetH},fps={targetFps:.3f} -c:v libx264 -preset fast -an {outPath.quoteShell}"

proc renderWithBroll*(sourceVideo: string,
                      insertions: seq[brollAnalyze.BrollInsertion],
                      clips: seq[ClipResult],
                      durationMs: int64,
                      outputPath: string,
                      tmpDir: string = ""): bool =
  ## Full render pipeline:
  ## 1. ffprobe source for resolution + fps
  ## 2. Normalize each B-roll clip to match source
  ## 3. Build segment plan + extract source segments via ffmpeg
  ## 4. Write concat list and concatenate via ffmpeg -f concat
  ## 5. Extract source audio
  ## 6. Mux video + audio into final output
  let workDir = if tmpDir != "": tmpDir
                else: getTempDir() / &"honeyclip_broll_{epochTime():.0f}"
  createDir(workDir)
  try:
    # 1. Probe source for w/h/fps
    let probeCmd = &"ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 {sourceVideo.quoteShell}"
    let (probeOut, probeCode) = execCmdEx(probeCmd)
    if probeCode != 0:
      error &"ffprobe failed on {sourceVideo}: {probeOut}"
      return false
    let parts = probeOut.strip.split(',')
    if parts.len < 3:
      error &"ffprobe output unexpected: {probeOut}"
      return false
    let targetW = parts[0].parseInt
    let targetH = parts[1].parseInt
    let fpsParts = parts[2].split('/')
    if fpsParts.len < 2 or fpsParts[1] == "0":
      error &"ffprobe returned unparseable frame rate: {parts[2]}"
    let targetFps = fpsParts[0].parseFloat / fpsParts[1].parseFloat
    if targetFps <= 0.0:
      error &"ffprobe returned non-positive frame rate: {targetFps}"

    # 2. Normalize each B-roll clip
    var normalizedPaths: seq[string]
    for i, c in clips:
      if not c.success:
        warning &"Skipping failed clip at insertion {i}"
        return false
      let normPath = workDir / &"broll_norm_{i}.mp4"
      let cmd = normalizeBrollClipCmd(c.clipPath, targetW, targetH, targetFps, normPath)
      let (normOut, normCode) = execCmdEx(cmd)
      if normCode != 0:
        error &"Normalize failed: {normOut}"
        return false
      normalizedPaths.add normPath

    # 3. Build segment plan + extract source segments
    let plan = buildSegmentPlan(durationMs, insertions)
    var srcSegmentPaths: seq[string]
    var srcCount = 0
    for s in plan:
      if s.kind == skSource:
        let segPath = workDir / &"src_seg_{srcCount}.mp4"
        let startSec = s.startMs.float / 1000.0
        let durSec = (s.endMs - s.startMs).float / 1000.0
        let cmd = &"ffmpeg -y -ss {startSec:.3f} -t {durSec:.3f} -i {sourceVideo.quoteShell} -c:v libx264 -preset fast -an {segPath.quoteShell}"
        let (segOut, segCode) = execCmdEx(cmd)
        if segCode != 0:
          error &"Source segment extraction failed: {segOut}"
          return false
        srcSegmentPaths.add segPath
        inc srcCount

    # 4. Write concat list and concatenate
    let listPath = workDir / "concat_list.txt"
    writeFile(listPath, buildConcatList(plan, srcSegmentPaths, normalizedPaths))
    let tempVideo = workDir / "temp_video.mp4"
    let concatCmd = &"ffmpeg -y -f concat -safe 0 -i {listPath.quoteShell} -c copy {tempVideo.quoteShell}"
    let (concatOut, concatCode) = execCmdEx(concatCmd)
    if concatCode != 0:
      error &"Concat failed: {concatOut}"
      return false

    # 5. Extract source audio
    let srcAudio = workDir / "source_audio.aac"
    let audioCmd = &"ffmpeg -y -i {sourceVideo.quoteShell} -vn -c:a aac {srcAudio.quoteShell}"
    let (audioOut, audioCode) = execCmdEx(audioCmd)
    if audioCode != 0:
      error &"Audio extraction failed: {audioOut}"
      return false

    # 6. Mux video + audio
    let muxCmd = &"ffmpeg -y -i {tempVideo.quoteShell} -i {srcAudio.quoteShell} -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 {outputPath.quoteShell}"
    let (muxOut, muxCode) = execCmdEx(muxCmd)
    if muxCode != 0:
      error &"Mux failed: {muxOut}"
      return false
    return true
  finally:
    try: removeDir(workDir) except CatchableError: discard
