## File-path FFmpeg subprocess chain for Phase 22 audio enhancement:
## hum removal, de-essing, two-pass loudnorm, resampling, MP3 decode,
## silence-bounded chunking and crossfade reassembly.
##
## The FFmpeg CLI is resolved by analyze/audio_enhance.ffmpegBin
## (HONEYCLIP_FFMPEG, then the in-tree build next to the honeyclip binary,
## then PATH; never the current directory). Every path and
## filter string passed to a subprocess is wrapped in quoteShell (T-22-03).

import std/[osproc, os, strutils, strformat, json, sequtils, math]
import ../analyze/audio_enhance

type
  AudioProbe* = object
    sampleRate*: int
    channels*: int
    layout*: string          ## FFmpeg layout name, e.g. "stereo", "5.1(side)"
    durationSec*: float
    audioTracks*: int
    containerStart*: float   ## banner `start:` of the input
    audioStarts*: seq[float] ## per audio stream `start X` (0 when not shown)

proc ffBase(): string =
  quoteShell(ffmpegBin()) & " -hide_banner -nostats -y"

proc runFf(args: string): bool =
  let (_, code) = execCmdEx(ffBase() & " -loglevel error " & args)
  code == 0

proc parseChannels*(token: string): int =
  ## Channel count from the layout token of an FFmpeg `Audio:` banner line;
  ## 0 when unknown (never a guess). Handles the `(side)`/`(wide)`/`(back)`
  ## suffix variants, `X.Y` and `X.Y.Z` layouts (5.1, 7.1.4, 22.2), named
  ## layouts, `N channels` and custom `FL+FR+LFE` lists (WR-11).
  var t = token.strip.toLowerAscii
  if t.endsWith(" channels") or " channels (" in t:
    try: return parseInt(t.split(' ')[0]) except ValueError: return 0
  let paren = t.find('(')
  if paren > 0: t = t[0 ..< paren].strip
  case t
  of "mono": return 1
  of "stereo", "downmix", "binaural": return 2
  of "quad": return 4
  of "hexagonal": return 6
  of "octagonal", "cube": return 8
  of "hexadecagonal": return 16
  else: discard
  if '+' in t:
    return t.split('+').len
  let parts = t.split('.')
  if parts.len in 2 .. 3:
    var total = 0
    for part in parts:
      try: total += parseInt(part)
      except ValueError: return 0
    return total
  0

proc probeChannelsDecoded(path: string): int =
  ## Fallback for layouts parseChannels does not know: decode one frame of
  ## the first audio stream and read ashowinfo's `channels:`; 0 if unknown.
  let (output, code) = execCmdEx(ffBase() & " -loglevel info -i " & quoteShell(path) &
    " -map 0:a:0 -frames:a 1 -af ashowinfo -f null -")
  if code != 0: return 0
  for line in output.splitLines:
    if "ashowinfo" in line and " n:0 " in line:
      for tok in line.splitWhitespace:
        if tok.startsWith("channels:"):
          try: return parseInt(tok[9 .. ^1]) except ValueError: return 0
  0

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
      for f in l.split(','):
        let ft = f.strip
        if ft.startsWith("start:"):
          try: result.containerStart = parseFloat(ft[6 .. ^1].strip)
          except ValueError: discard
    if l.startsWith("Stream #") and "Audio:" in l:
      inc result.audioTracks
      var st = 0.0
      for f in l.split(','):
        let ft = f.strip
        if ft.startsWith("start "):
          try: st = parseFloat(ft[6 .. ^1].split(' ')[0])
          except ValueError: discard
      result.audioStarts.add st
    if result.sampleRate == 0 and "Audio:" in l:
      let fields = l.split("Audio:")[1].split(',')
      for i, f in fields:
        let ft = f.strip
        if ft.endsWith(" Hz"):
          try: result.sampleRate = parseInt(ft[0 .. ^4])
          except ValueError: discard
          if i + 1 < fields.len:
            result.channels = parseChannels(fields[i + 1])
            if result.channels > 0:
              result.layout = fields[i + 1].strip
          break
  if result.sampleRate > 0 and result.channels == 0:
    result.channels = probeChannelsDecoded(path)

proc audioStartOffset*(path: string; track: int = 0): float =
  ## When audio stream `track` starts, in seconds, on the timeline FFmpeg
  ## gives input 0 of a mux (input start already subtracted). Extracted and
  ## enhanced WAVs always start at 0, so the mux must shift them by this
  ## much to keep the source's A/V offset (WR-09). Measured from the first
  ## decoded frame (ashowinfo), which matches what the WAV extraction keeps;
  ## falls back to the banner's stream `start` when that filter is missing.
  let (output, code) = execCmdEx(ffBase() & " -loglevel info -i " & quoteShell(path) &
    &" -map 0:a:{track} -frames:a 1 -af ashowinfo -f null -")
  if code == 0:
    for line in output.splitLines:
      if "ashowinfo" in line and " n:0 " in line:
        for tok in line.splitWhitespace:
          if tok.startsWith("pts_time:"):
            try: return parseFloat(tok[9 .. ^1])
            except ValueError: discard
  let p = probeAudio(path)
  if track >= 0 and track < p.audioStarts.len and p.audioStarts[track] != 0.0:
    return p.audioStarts[track] - p.containerStart
  0.0

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

const
  targetLufs* = -16.0
  peakCeilingDb* = -2.0  ## limiter ceiling, a little under -1.5 dBTP

proc buildLinearLoudnessFilter*(measuredI: float; sampleRate: int): string =
  ## Second pass of the loudness step: one constant gain to reach
  ## targetLufs, then a peak limiter that only acts on peaks above the
  ## ceiling (at 4x the rate, approximating true peak).
  ##
  ## loudnorm's own pass 2 is not used: it silently switches from linear
  ## to dynamic normalization whenever the gain would push true peak past
  ## its limit (or the loudness range exceeds its target). Dynamic mode
  ## raises quiet passages, which lifts the noise a denoiser just removed
  ## (measured: 4.6 of 13.7 dB undone on speech after DeepFilterNet).
  let gain = targetLufs - measuredI
  let ceiling = pow(10.0, peakCeilingDb / 20.0)
  &"volume={gain:.2f}dB,aresample={sampleRate * 4}," &
    &"alimiter=limit={ceiling:.4f}:attack=1:release=50:level=0," &
    &"aresample={sampleRate}"

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
  var mi, mth: string
  try:
    let m = parseJson(out1[jsonStart .. jsonEnd])
    mi = m["input_i"].getStr
    mth = m["input_thresh"].getStr
  except CatchableError:
    return false
  # Silent input reports -inf; loudnorm cannot be measured, so copy through.
  if "inf" in mi.toLowerAscii or "inf" in mth.toLowerAscii:
    return runFf("-i " & quoteShell(inputPath) & " " & quoteShell(outputPath))
  var inputI: float
  try: inputI = parseFloat(mi)
  except ValueError: return false
  let rate = probeAudio(inputPath).sampleRate
  if rate <= 0: return false
  runFf("-i " & quoteShell(inputPath) & " -af " &
        quoteShell(buildLinearLoudnessFilter(inputI, rate)) & " " &
        quoteShell(outputPath)) and fileExists(outputPath)

proc decodeMp3ToWav*(inputPath, outputPath: string): bool =
  ## OQ-3: the ElevenLabs response is MP3; decode to WAV before filtering.
  runFf("-i " & quoteShell(inputPath) & " -f wav " & quoteShell(outputPath)) and
    fileExists(outputPath)

proc extractAudioTrack*(inputPath, outputPath: string; track: int): bool =
  ## Write audio stream `track` (0-based) of inputPath to a PCM WAV.
  runFf("-i " & quoteShell(inputPath) & &" -map 0:a:{track} -vn -f wav " &
        quoteShell(outputPath)) and fileExists(outputPath)

proc resampleTo48k*(inputPath, outputPath: string): bool =
  ## 48 kHz working copy that keeps the source channel layout (stereo, 5.1,
  ## ...): every stage of the chain is multichannel. -vn so a video input
  ## yields just its audio.
  runFf("-i " & quoteShell(inputPath) & " -vn -ar 48000 -f wav " &
        quoteShell(outputPath)) and fileExists(outputPath)

proc splitChannels*(inputPath, outDir: string; channels: int): seq[string] =
  ## One mono WAV per channel, in channel order; @[] on failure.
  createDir(outDir)
  for c in 0 ..< channels:
    let outp = outDir / &"ch_{c:02}.wav"
    if not runFf("-i " & quoteShell(inputPath) & " -af " &
                 quoteShell(&"pan=mono|c0=c{c}") & " " & quoteShell(outp)):
      return @[]
    result.add outp

proc buildJoinChannelsCmd*(inputs: seq[string]; outputPath, layout: string): string =
  ## Rebuild a multichannel WAV from per-channel mono WAVs, in input order.
  ## amerge keeps that order and channelmap then names the layout without
  ## remixing. (`join` is not used: it matches each mono input to the FC
  ## channel first and rotates the front channels.)
  var args = ""
  var pads = ""
  var order: seq[string]
  for i, f in inputs:
    args.add "-i " & quoteShell(f) & " "
    pads.add &"[{i}:a]"
    order.add $i
  let named = layout != "" and not layout.endsWith("channels")
  var filter = &"{pads}amerge=inputs={inputs.len}"
  if named:
    filter.add &",channelmap=map={order.join(\"|\")}:channel_layout={layout}"
  ffBase() & " -loglevel error " & args & "-filter_complex " & quoteShell(filter) &
    " " & quoteShell(outputPath)

proc joinChannels*(inputs: seq[string]; outputPath, layout: string): bool =
  let (_, code) = execCmdEx(buildJoinChannelsCmd(inputs, outputPath, layout))
  code == 0 and fileExists(outputPath)

proc resampleFromWav*(inputPath, outputPath: string;
                      sampleRate: int; channels: int): bool =
  runFf("-i " & quoteShell(inputPath) & &" -ar {sampleRate} -ac {channels} " &
        quoteShell(outputPath)) and fileExists(outputPath)

const crossfadeMsDefault* = 50

proc chunkBounds*(total, maxChunkSec: float; cuts: seq[float];
                  overlap: float): seq[float] =
  ## Chunk boundaries @[0.0, ..., total]: each cut is the latest silence
  ## midpoint in (cur + 10% of max, cur + max], else a hard cut, so no chunk
  ## exceeds maxChunkSec. WR-06: the last chunk is never shorter than
  ## max(1s, 4 * overlap). A tiny tail (0.02s of a 1200.02s file) is shorter
  ## than the crossfade, which breaks the length-preserving reassembly, and
  ## backends may reject it; the cut before it moves earlier instead.
  let minTail = max(1.0, 4.0 * overlap)
  result = @[0.0]
  var cur = 0.0
  while total - cur > maxChunkSec:
    var limit = cur + maxChunkSec
    if total - limit < minTail and total - minTail > cur:
      limit = total - minTail
    var best = -1.0
    for c in cuts:
      if c > cur + maxChunkSec * 0.1 and c <= limit and c > best:
        best = c
    if best < 0.0: best = limit
    result.add best
    cur = best
  result.add total

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
  # No chunkDir: a fresh private temp dir, never a guessable shared name (WR-07).
  let dir = if chunkDir != "": chunkDir
            else: createPrivateTempDir("honeyclip_chunks_")
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

  let overlap = overlapMs.float / 1000.0
  let bounds = chunkBounds(total, maxChunkSec, cuts, overlap)
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
