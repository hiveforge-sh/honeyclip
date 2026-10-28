## AudioProvider variant, backend resolution and the enhance() dispatch.
import std/[strutils, os, strformat]
import ./[deepfilter, elevenlabs, ffmpeg_chain]
import ../analyze/audio_enhance
import ../http_client
import ../log

type
  AudioProviderKind* = enum apLocal, apElevenlabs, apFfmpeg
  AudioProvider* = object
    fromAuto*: bool  ## chosen by --backend=auto (may fall back; WR-10)
    case kind*: AudioProviderKind
    of apLocal, apFfmpeg: discard
    of apElevenlabs: apiKey*: string
  AudioResult* = object
    outputPath*: string
    backendUsed*: AudioProviderKind
    err*: string
    backendFailed*: bool  ## the denoise/isolation backend itself failed

proc backendName*(k: AudioProviderKind): string =
  case k
  of apLocal: "local (DeepFilterNet)"
  of apElevenlabs: "elevenlabs"
  of apFfmpeg: "ffmpeg"

proc alwaysWarn*(msg: string) =
  ## A warning -q cannot hide (log.warning can): used when honeyclip uploads
  ## audio or substitutes a backend the user did not name.
  try: stderr.writeLine "Warning! " & msg
  except IOError: discard

const noNeuralBackendMsg* =
  "--backend=auto: no neural backend is available, so the FFmpeg-only chain " &
  "is used. For better noise reduction install DeepFilterNet " &
  "(pip install deepfilternet) or set ELEVENLABS_API_KEY " &
  "(or [elevenlabs] apiKey in config.toml)."

proc resolveProvider*(forceBackend, apiKey: string;
                      dfAvailable: bool): AudioProvider =
  ## Core logic with DeepFilterNet availability injected (deterministic tests).
  case forceBackend.toLowerAscii
  of "local":
    if not dfAvailable:
      raise newException(ValueError,
        "Backend 'local' requires DeepFilterNet: pip install deepfilternet")
    return AudioProvider(kind: apLocal)
  of "ffmpeg":
    # FFmpeg-only chain (afftdn + hum/de-ess + loudnorm); no neural backend.
    return AudioProvider(kind: apFfmpeg)
  of "elevenlabs":
    if apiKey == "":
      raise newException(ValueError,
        "Backend 'elevenlabs' requires ELEVENLABS_API_KEY env var or config.toml [elevenlabs] apiKey")
    return AudioProvider(kind: apElevenlabs, apiKey: apiKey)
  of "auto", "":
    if dfAvailable:
      return AudioProvider(kind: apLocal, fromAuto: true)
    if apiKey != "":
      # WR-02: the user never named a cloud backend, so the upload must be
      # visible, and -q cannot hide it.
      alwaysWarn "--backend=auto: DeepFilterNet is not installed and " &
        "an ElevenLabs API key is set, so this audio will be uploaded to " &
        "ElevenLabs (" & elevenlabsBaseUrl() & ") for processing. " &
        "Use --backend=ffmpeg to keep it on this machine."
      return AudioProvider(kind: apElevenlabs, apiKey: apiKey, fromAuto: true)
    # WR-10: the FFmpeg chain always works, so auto uses it as the last
    # resort instead of failing, and says so.
    alwaysWarn noNeuralBackendMsg
    return AudioProvider(kind: apFfmpeg, fromAuto: true)
  else:
    raise newException(ValueError, "Unknown --backend: " & forceBackend)

proc resolveProvider*(forceBackend, apiKey: string): AudioProvider =
  ## Detects DeepFilterNet lazily (only when it can matter).
  let needsDf = forceBackend.toLowerAscii in ["local", "auto", ""]
  resolveProvider(forceBackend, apiKey, needsDf and isDeepFilterAvailable())

proc applyProviderStages*(p: AudioProvider; flags: var EnhancementFlags;
                          voiceIsolation: StageMode): seq[string] =
  ## Provider-driven stages (WR-05). Voice isolation is what the ElevenLabs
  ## backend does, so `auto` means on there: choosing --backend=elevenlabs
  ## must not silently skip the call (and the cost gate) because the noise
  ## heuristic found the audio clean. Other backends cannot isolate voices;
  ## returns the warnings to show when the user forced it on anyway.
  case p.kind
  of apElevenlabs:
    if voiceIsolation == smAuto: flags.voiceIsolation = true
  of apLocal, apFfmpeg:
    flags.voiceIsolation = false
    if voiceIsolation == smOn:
      let name = if p.kind == apLocal: "local" else: "ffmpeg"
      result.add "--voice-isolation=on is only supported by --backend=elevenlabs; " &
        "the " & name & " backend ignores it (use --denoise to control noise reduction)"

const
  chunkTriggerSecDefault* = 3600.0
  chunkTriggerBytes* = 500'i64 * 1024 * 1024
  chunkSecDefault* = 600.0

proc runDeepFilterKeepingChannels(inWav, workDir: string; channels: int;
                                  layout: string
                                 ): tuple[ok: bool, outWav, err: string] =
  ## DeepFilterNet on the multichannel WAV; if it hands back fewer channels
  ## than it was given, rerun it per channel and rejoin in the source layout
  ## so stereo/5.1 never collapses to mono. Local, so the rerun costs time only.
  let r = runDeepFilter(inWav, workDir / "df")
  if not r.ok: return (false, "", r.err)
  if channels <= 1 or probeAudio(r.outputPath).channels >= channels:
    return (true, r.outputPath, "")
  debug "DeepFilterNet returned fewer channels; processing each channel"
  let parts = splitChannels(inWav, workDir / "split", channels)
  if parts.len != channels: return (false, "", "Failed to split channels")
  var cleaned: seq[string]
  for i, part in parts:
    let rc = runDeepFilter(part, workDir / &"df_ch{i:02}")
    if not rc.ok: return (false, "", rc.err)
    cleaned.add rc.outputPath
  let joined = workDir / "df_joined.wav"
  if not joinChannels(cleaned, joined, layout):
    return (false, "", "Failed to rejoin DeepFilterNet channels")
  (true, joined, "")

proc runBackend(p: AudioProvider, http: HttpClientLike, inWav, workDir: string,
                flags: EnhancementFlags; channels: int = 1; layout: string = ""
               ): tuple[ok: bool, outWav, err: string] =
  ## One backend pass over a 48kHz WAV in the source channel layout; returns
  ## the cleaned WAV with the same channel count where the backend allows.
  createDir(workDir)
  case p.kind
  of apLocal:
    if not flags.denoise: return (true, inWav, "")
    return runDeepFilterKeepingChannels(inWav, workDir, channels, layout)
  of apElevenlabs:
    if not (flags.denoise or flags.voiceIsolation): return (true, inWav, "")
    let raw = workDir / "el_raw.bin"
    let r = elevenlabsIsolate(http, p.apiKey, inWav, raw)
    if not r.ok: return (false, "", r.err)
    let decoded = workDir / "el_decoded.wav"
    if not decodeMp3ToWav(raw, decoded):
      return (false, "", "Failed to decode ElevenLabs response")
    # Uploading each channel separately would multiply the bill, so a
    # reduced-channel response is kept and reported instead.
    let got = probeAudio(decoded).channels
    if channels > 1 and got > 0 and got < channels:
      warning &"ElevenLabs returned {got}-channel audio for a {channels}-channel " &
        "source; the output repeats it across channels and loses the original " &
        "stereo/surround image (--backend=local or --backend=ffmpeg keep it)"
    return (true, decoded, "")
  of apFfmpeg:
    if not flags.denoise: return (true, inWav, "")
    let outp = workDir / "afftdn.wav"
    if not runAfftdn(inWav, outp): return (false, "", "afftdn failed")
    return (true, outp, "")

proc enhance*(p: AudioProvider, http: HttpClientLike, inputPath, outDir: string,
              flags: EnhancementFlags, autoYes, isTty: bool;
              keepTmp: bool = false;
              chunkTriggerSec: float = chunkTriggerSecDefault;
              chunkSec: float = chunkSecDefault): AudioResult =
  ## resample to 48k (source channels kept) -> backend (chunked when long) ->
  ## hum/de-ess -> two-pass loudnorm -> resample back to the source rate.
  ## Returns outputPath "" (with err set) on any failure or a denied cost gate.
  result = AudioResult(outputPath: "", backendUsed: p.kind)
  let tmpDir = outDir & ".tmp"
  createDir(outDir)
  createDir(tmpDir)
  defer:
    if not keepTmp:
      try: removeDir(tmpDir) except CatchableError: discard

  let probe = probeAudio(inputPath)
  if probe.sampleRate <= 0:
    result.err = "No readable audio stream in " & inputPath
    return
  if probe.channels <= 0:
    # WR-11: never guess (a guess of 2 silently downmixed 5.1 sources).
    result.err = "Could not determine the channel layout of the audio in " & inputPath
    return

  let resampled = tmpDir / "resampled.wav"
  if not resampleTo48k(inputPath, resampled):
    result.err = "Failed to resample input to 48kHz"
    return

  # The container banner can say `Duration: N/A` (some MKV/WebM/streamed
  # files), so measure the audio that will actually be processed (WR-01).
  var dur = probeAudio(resampled).durationSec
  if dur <= 0.0:
    # 48 kHz s16le: 96000 bytes per second per channel after the 44-byte header.
    dur = max(0.0, (getFileSize(resampled) - 44).float /
                   (96000.0 * probe.channels.float))
  if dur <= 0.0: dur = probe.durationSec

  # T-22-04: confirm cost before any HTTP traffic. An unknown duration is
  # never auto-approved (confirmElevenlabsCost requires --yes or a prompt).
  if p.kind == apElevenlabs and (flags.denoise or flags.voiceIsolation):
    if not confirmElevenlabsCost(dur, isTty, autoYes):
      result.err = "ElevenLabs cost not confirmed"
      return

  var current = resampled
  let big = dur > chunkTriggerSec or
            (fileExists(inputPath) and getFileSize(inputPath) > chunkTriggerBytes)
  if big:
    let chunks = chunkAtSilence(resampled, chunkSec, tmpDir / "chunks")
    var cleaned: seq[string]
    for i, c in chunks:
      let r = runBackend(p, http, c, tmpDir / &"backend_{i:04}", flags,
                         probe.channels, probe.layout)
      if not r.ok:
        result.err = r.err
        result.backendFailed = true
        return
      cleaned.add r.outWav
    let joined = tmpDir / "joined.wav"
    if not reassembleWithCrossfade(cleaned, joined):
      result.err = "Failed to reassemble chunks"
      return
    current = joined
  else:
    let r = runBackend(p, http, resampled, tmpDir / "backend", flags,
                       probe.channels, probe.layout)
    if not r.ok:
      result.err = r.err
      result.backendFailed = true
      return
    current = r.outWav

  if flags.humRemoval or flags.deEss:
    let filtered = tmpDir / "after_hum_deess.wav"
    if not runHumDeess(current, filtered, flags):
      result.err = "Hum/de-ess filter chain failed"
      return
    current = filtered

  let normed = tmpDir / "loudnorm.wav"
  if not runLoudnormTwoPassSubprocess(current, normed):
    result.err = "Loudness normalization failed"
    return

  let finalWav = outDir / "enhanced.wav"
  if not resampleFromWav(normed, finalWav, probe.sampleRate, probe.channels):
    result.err = "Failed to restore source sample rate/channels"
    return
  result.outputPath = finalWav
