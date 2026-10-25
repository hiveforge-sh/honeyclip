## File-path FFmpeg subprocess chain for Phase 22 audio enhancement:
## hum removal, de-essing, two-pass loudnorm, resampling, MP3 decode,
## silence-bounded chunking and crossfade reassembly.
##
## The FFmpeg CLI is resolved by analyze/audio_enhance.ffmpegBin
## (HONEYCLIP_FFMPEG, then build/ffmpeg(.exe), then PATH). Every path and
## filter string passed to a subprocess is wrapped in quoteShell (T-22-03).

import std/[osproc, os, strutils, strformat, json, sequtils]
import ../analyze/audio_enhance

type
  AudioProbe* = object
    sampleRate*: int
    channels*: int
    durationSec*: float
    audioTracks*: int

proc ffBase(): string =
  quoteShell(ffmpegBin()) & " -hide_banner -nostats -y"

proc runFf(args: string): bool =
  let (_, code) = execCmdEx(ffBase() & " -loglevel error " & args)
  code == 0

proc parseChannels(token: string): int =
  let t = token.strip.toLowerAscii
  case t
  of "mono": 1
  of "stereo": 2
  of "quad": 4
  else:
    if t.endsWith(" channels"):
      try: parseInt(t.split(' ')[0]) except ValueError: 2
    elif t.len == 3 and t[1] == '.':
      try: parseInt($t[0]) + parseInt($t[2]) except ValueError: 2
    else: 2

proc parseDuration(s: string): float =
  ## "HH:MM:SS.xx" -> seconds; 0 when unparsable.
  let parts = s.strip.split(':')
  if parts.len != 3: return 0.0
  try:
    result = parseFloat(parts[0]) * 3600.0 + parseFloat(parts[1]) * 60.0 +
             parseFloat(parts[2])
  except ValueError:
    result = 0.0

proc probeAudio*(path: string): AudioProbe =
  ## Sample rate, channels and duration of the first audio stream, plus the
  ## number of audio streams, parsed from the FFmpeg banner (no ffprobe in
  ## the in-tree build).
  if not fileExists(path): return
  let (output, _) = execCmdEx(ffBase() & " -i " & quoteShell(path))
  for line in output.splitLines:
    let l = line.strip
    if result.durationSec == 0.0 and l.startsWith("Duration:"):
      result.durationSec = parseDuration(l[9 .. ^1].split(',')[0])
    if l.startsWith("Stream #") and "Audio:" in l:
      inc result.audioTracks
    if result.sampleRate == 0 and "Audio:" in l:
      let fields = l.split("Audio:")[1].split(',')
      for i, f in fields:
        let ft = f.strip
        if ft.endsWith(" Hz"):
          try: result.sampleRate = parseInt(ft[0 .. ^4])
          except ValueError: discard
          if i + 1 < fields.len:
            result.channels = parseChannels(fields[i + 1])
          break

proc buildHumDeessCmd*(inputPath, outputPath: string,
                       notch50Hz, notch60Hz, deEss: bool): string =
  var filters: seq[string] = @[]
  if notch50Hz: filters.add "equalizer=f=50:t=h:w=10:g=-40"
  if notch60Hz: filters.add "equalizer=f=60:t=h:w=10:g=-40"
  if deEss: filters.add "deesser=i=0.5:m=0.5:f=0.5"
  if filters.len == 0: filters.add "anull"
  result = ffBase() & " -loglevel error -i " & quoteShell(inputPath) &
           " -af " & quoteShell(filters.join(",")) & " " & quoteShell(outputPath)

proc runHumDeess*(inputPath, outputPath: string, flags: EnhancementFlags): bool =
  ## Wave 3 simplification: notch both 50 and 60 Hz when hum removal is on.
  let cmd = buildHumDeessCmd(inputPath, outputPath,
                             flags.humRemoval, flags.humRemoval, flags.deEss)
  let (_, code) = execCmdEx(cmd)
  code == 0 and fileExists(outputPath)

proc runAfftdn*(inputPath, outputPath: string): bool =
  ## FFmpeg-only denoise used when no neural backend is selected.
  runFf("-i " & quoteShell(inputPath) & " -af " & quoteShell("afftdn=nf=-25") &
        " " & quoteShell(outputPath)) and fileExists(outputPath)

proc runLoudnormTwoPassSubprocess*(inputPath, outputPath: string): bool =
  # Pass 1: measure; the JSON block is printed on stderr (merged by execCmdEx).
  let p1 = ffBase() & " -i " & quoteShell(inputPath) & " -af " &
           quoteShell("loudnorm=I=-16:LRA=11:TP=-1.5:print_format=json") &
           " -f null -"
  let (out1, code1) = execCmdEx(p1)
  if code1 != 0: return false
  let jsonStart = out1.rfind('{')
  let jsonEnd = out1.rfind('}')
  if jsonStart < 0 or jsonEnd <= jsonStart: return false
  var mi, mlra, mtp, mth, off: string
  try:
    let m = parseJson(out1[jsonStart .. jsonEnd])
    mi = m["input_i"].getStr
    mlra = m["input_lra"].getStr
    mtp = m["input_tp"].getStr
    mth = m["input_thresh"].getStr
    off = m["target_offset"].getStr
  except CatchableError:
    return false
  # Silent input reports -inf; loudnorm cannot be measured, so copy through.
  if "inf" in mi.toLowerAscii or "inf" in mth.toLowerAscii:
    return runFf("-i " & quoteShell(inputPath) & " " & quoteShell(outputPath))
  let p2filter = "loudnorm=I=-16:LRA=11:TP=-1.5:linear=true:" &
                 &"measured_I={mi}:measured_LRA={mlra}:measured_TP={mtp}:" &
                 &"measured_thresh={mth}:offset={off}"
  runFf("-i " & quoteShell(inputPath) & " -af " & quoteShell(p2filter) &
        " " & quoteShell(outputPath)) and fileExists(outputPath)

proc decodeMp3ToWav*(inputPath, outputPath: string): bool =
  ## OQ-3: the ElevenLabs response is MP3; decode to WAV before filtering.
  runFf("-i " & quoteShell(inputPath) & " -f wav " & quoteShell(outputPath)) and
    fileExists(outputPath)

proc extractAudioTrack*(inputPath, outputPath: string; track: int): bool =
  ## Write audio stream `track` (0-based) of inputPath to a PCM WAV.
  runFf("-i " & quoteShell(inputPath) & &" -map 0:a:{track} -vn -f wav " &
        quoteShell(outputPath)) and fileExists(outputPath)

proc resampleTo48kMono*(inputPath, outputPath: string): bool =
  ## -vn so a video input yields just its audio.
  runFf("-i " & quoteShell(inputPath) & " -vn -ar 48000 -ac 1 -f wav " &
        quoteShell(outputPath)) and fileExists(outputPath)

proc resampleFromWav*(inputPath, outputPath: string;
                      sampleRate: int; channels: int): bool =
  runFf("-i " & quoteShell(inputPath) & &" -ar {sampleRate} -ac {channels} " &
        quoteShell(outputPath)) and fileExists(outputPath)

const crossfadeMsDefault* = 50

proc chunkAtSilence*(inputPath: string; maxChunkSec: float;
                     chunkDir: string = "";
                     overlapMs: int = crossfadeMsDefault): seq[string] =
  ## Duration <= maxChunkSec returns @[inputPath]. Otherwise split at the
  ## midpoint of detected silences, never exceeding maxChunkSec per chunk
  ## (hard cut when a window holds no silence). Chunks are PCM WAVs.
  ## Every chunk but the last runs overlapMs past its boundary so that
  ## reassembleWithCrossfade with the same duration preserves total length.
  let total = probeAudio(inputPath).durationSec
  if total <= 0.0 or total <= maxChunkSec: return @[inputPath]
  let dir = if chunkDir != "": chunkDir
            else: getTempDir() / ("honeyclip_chunks_" & $getCurrentProcessId())
  createDir(dir)

  let (sdOut, _) = execCmdEx(ffBase() & " -i " & quoteShell(inputPath) & " -af " &
                             quoteShell("silencedetect=noise=-30dB:d=0.5") &
                             " -f null -")
  var starts, ends: seq[float]
  for line in sdOut.splitLines:
    try:
      if "silence_start:" in line:
        starts.add parseFloat(line.split("silence_start:")[1].strip.split(' ')[0])
      elif "silence_end:" in line:
        ends.add parseFloat(line.split("silence_end:")[1].strip.split(' ')[0])
    except ValueError:
      discard
  var cuts: seq[float]
  for i in 0 ..< starts.len:
    let e = if i < ends.len: ends[i] else: total
    cuts.add (starts[i] + e) / 2.0

  var bounds: seq[float] = @[0.0]
  var cur = 0.0
  while total - cur > maxChunkSec:
    var best = cur + maxChunkSec
    # latest silence midpoint in (cur + 10% of max, cur + max]
    for c in cuts:
      if c > cur + maxChunkSec * 0.1 and c <= cur + maxChunkSec and
         (best == cur + maxChunkSec or c > best):
        best = c
    bounds.add best
    cur = best
  bounds.add total

  let overlap = overlapMs.float / 1000.0
  for i in 0 ..< bounds.len - 1:
    let outp = dir / &"chunk_{i:04}.wav"
    let stop = if i < bounds.len - 2: min(bounds[i+1] + overlap, total)
               else: bounds[i+1]
    if not runFf(&"-ss {bounds[i]:.3f} -to {stop:.3f} -i " &
                 quoteShell(inputPath) & " -vn " & quoteShell(outp)):
      return @[inputPath]
    result.add outp

proc reassembleWithCrossfade*(chunks: seq[string]; outputPath: string;
                              crossfadeMs: int = crossfadeMsDefault): bool =
  if chunks.len == 0: return false
  if chunks.len == 1:
    try:
      copyFile(chunks[0], outputPath)
      return true
    except CatchableError:
      return false
  var inputs = ""
  for c in chunks:
    inputs.add "-i " & quoteShell(c) & " "
  var fc: seq[string]
  for i in 0 ..< chunks.high:
    let prev = if i == 0: "[0]" else: &"[a{i}]"
    fc.add &"{prev}[{i+1}]acrossfade=d={crossfadeMs.float / 1000.0}[a{i+1}]"
  let lastLabel = "[a" & $chunks.high & "]"
  runFf(inputs & "-filter_complex " & quoteShell(fc.join(";")) &
        " -map " & quoteShell(lastLabel) & " " & quoteShell(outputPath)) and
    fileExists(outputPath)
