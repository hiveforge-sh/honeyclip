## honeyclip enhance subcommand
##
## AI audio enhancement: denoise (DeepFilterNet locally or the ElevenLabs
## Voice Isolator, or an FFmpeg-only chain), hum removal, de-essing and
## two-pass loudness normalisation. Outputs the video with enhanced audio, or
## the cleaned WAV with --audio-only.

import std/[parseopt, strutils, os, terminal]
import ../audio/[provider, render, ffmpeg_chain]
import ../analyze/audio_enhance
import ../config
import ../http_client
import ../log

const helpText* = """usage: honeyclip enhance file [options]

Enhance speech audio: noise reduction, hum removal, de-essing, loudness.

Arguments:
  file                    Input video or audio file

Options:
  --backend=BACKEND       auto | local | elevenlabs | ffmpeg (default: auto)
                            auto        local if DeepFilterNet works, else
                                        elevenlabs if a key is set (warns
                                        that audio is uploaded), else ffmpeg;
                                        falls back to ffmpeg, with a warning,
                                        if the chosen backend fails
                            local       DeepFilterNet (pip install deepfilternet)
                            elevenlabs  Voice Isolator API (ELEVENLABS_API_KEY
                                        or [elevenlabs] apiKey in config.toml)
                            ffmpeg      FFmpeg-only chain, no neural model
  --denoise=MODE          on | off | auto (default: auto)
  --voice-isolation=MODE  on | off | auto (default: auto). ElevenLabs only;
                            auto means on with --backend=elevenlabs
  --de-reverb=MODE        off | auto (default: auto). Reserved: no backend
                            de-reverbs yet, so `on` is rejected
  --de-ess=MODE           on | off | auto (default: auto)
  --hum-removal=MODE      on | off | auto (default: auto)
  --audio-track N         Audio track to enhance, counting from 1 (default: 1).
                            Other tracks are copied through unchanged.
  --audio-only            Write only the cleaned audio: a WAV by default, or
                            the format -o names (e.g. clean.mp3, clean.m4a)
  -o, --output PATH       Output path (default: {input}.enhanced.{ext})
  --yes                   Skip the ElevenLabs cost confirmation
  -q, --quiet             Suppress progress output
  --debug                 Show debug information
  --help                  Show this help

Examples:
  honeyclip enhance talk.mp4
  honeyclip enhance talk.mp4 --backend=elevenlabs --yes
  honeyclip enhance talk.mp4 --audio-only -o talk_clean.wav
"""

type
  EnhanceOptions* = object
    inputPath*: string
    backend*: string
    denoise*, voiceIsolation*, deReverb*, deEss*, humRemoval*: StageMode
    audioOnly*: bool
    audioTrack*: int  ## 1-based, as shown to users
    outputPath*: string
    autoYes*: bool
    quiet*: bool
    debug*: bool
    helpShown*: bool

proc parseStage(s: string): StageMode =
  case s.toLowerAscii
  of "on": smOn
  of "off": smOff
  of "auto", "": smAuto
  else: raise newException(ValueError, "stage flag must be on|off|auto: " & s)

proc parseArgs*(args: seq[string]): tuple[opts: EnhanceOptions, code: int] =
  ## Pure argument parsing: returns exit code 0 to continue (or after --help,
  ## with opts.helpShown set) and 2 on usage errors.
  result.opts.backend = "auto"
  result.opts.audioTrack = 1
  # `--flag value` and `-o value` are joined into `--flag=value` first;
  # parseopt only reliably handles the `=`/`:` forms.
  const valueFlags = ["-o", "--output", "--backend", "--denoise",
                      "--voice-isolation", "--de-reverb", "--de-ess",
                      "--hum-removal", "--audio-track"]
  var joined: seq[string]
  var i = 0
  while i < args.len:
    if args[i] in valueFlags and i + 1 < args.len:
      joined.add args[i] & "=" & args[i + 1]
      i += 2
    else:
      joined.add args[i]
      i += 1
  var p = initOptParser(joined)
  try:
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdShortOption, cmdLongOption:
        case p.key.toLowerAscii
        of "backend": result.opts.backend = p.val
        of "denoise": result.opts.denoise = parseStage(p.val)
        of "voice-isolation": result.opts.voiceIsolation = parseStage(p.val)
        of "de-reverb": result.opts.deReverb = parseStage(p.val)
        of "de-ess": result.opts.deEss = parseStage(p.val)
        of "hum-removal": result.opts.humRemoval = parseStage(p.val)
        of "audio-only": result.opts.audioOnly = true
        of "audio-track":
          let n = parseInt(p.val)
          if n < 1: raise newException(ValueError, "--audio-track must be 1 or more")
          result.opts.audioTrack = n
        of "o", "output": result.opts.outputPath = p.val
        of "yes": result.opts.autoYes = true
        of "q", "quiet": result.opts.quiet = true
        of "debug": result.opts.debug = true
        of "help":
          echo helpText
          result.opts.helpShown = true
          return (result.opts, 0)
        else:
          stderr.writeLine "unknown flag: " & p.key
          stderr.writeLine helpText
          return (result.opts, 2)
      of cmdArgument:
        if result.opts.inputPath == "":
          result.opts.inputPath = p.key
        else:
          stderr.writeLine "unexpected arg: " & p.key
          return (result.opts, 2)
  except ValueError as e:
    stderr.writeLine e.msg
    return (result.opts, 2)
  result.code = 0

proc run*(args: seq[string]): int =
  let (opts, code) = parseArgs(args)
  if code != 0: return code
  if opts.helpShown: return 0
  if opts.inputPath == "":
    stderr.writeLine helpText
    return 2
  if not fileExists(opts.inputPath):
    stderr.writeLine "Error! file not found: " & opts.inputPath
    return 1
  if opts.quiet: quiet = true
  if opts.debug: isDebug = true
  if opts.deReverb == smOn:
    # WR-05: no backend de-reverbs (DeepFilterNet does not), so refuse
    # rather than accept the flag and do nothing.
    stderr.writeLine "Error! --de-reverb=on is not supported: no backend implements de-reverberation yet"
    return 2
  if ffmpegBin() == "":
    stderr.writeLine "Error! ffmpeg not found: set HONEYCLIP_FFMPEG or put ffmpeg on PATH"
    return 1

  var provider: AudioProvider
  try:
    provider = resolveProvider(opts.backend, resolveElevenlabsKey())
  except ValueError as e:
    stderr.writeLine "Error! " & e.msg
    return 1

  let inExt = opts.inputPath.splitFile.ext.toLowerAscii
  let audioInput = inExt in [".wav", ".mp3", ".m4a", ".flac", ".aac", ".ogg", ".opus"]
  let wantWav = opts.audioOnly or audioInput

  let trackCount = probeAudio(opts.inputPath).audioTracks
  let track = opts.audioTrack - 1
  if trackCount > 0 and track >= trackCount:
    stderr.writeLine "Error! --audio-track " & $opts.audioTrack & " requested but " &
      opts.inputPath & " has " & $trackCount & " audio track(s)"
    return 1
  if trackCount > 1:
    let others = if wantWav: "other tracks are not written with a WAV output"
                 else: "passing the other " & $(trackCount - 1) &
                       " through unchanged"
    warning opts.inputPath & " has " & $trackCount & " audio tracks: enhancing track " &
      $opts.audioTrack & ", " & others & " (choose with --audio-track N)"

  # WR-07: a unique, atomically created (0700 on POSIX) work dir; every
  # intermediate file of this run lives inside it.
  let outDir = try: createPrivateTempDir("honeyclip_enhance_")
               except OSError as e:
                 stderr.writeLine "Error! could not create a temporary directory: " & e.msg
                 return 1
  defer:
    try: removeDir(outDir) except CatchableError: discard

  # Multi-track input: work on the selected track alone so the analyzer and
  # every backend see exactly the audio that gets enhanced.
  var source = opts.inputPath
  if trackCount > 1 or track > 0:
    source = outDir / "selected_track.wav"
    if not extractAudioTrack(opts.inputPath, source, track):
      stderr.writeLine "Error! could not read audio track " & $opts.audioTrack
      return 1

  let modes = (denoise: opts.denoise, voiceIsolation: opts.voiceIsolation,
               deReverb: opts.deReverb, deEss: opts.deEss,
               humRemoval: opts.humRemoval)
  var flags = analyzeAudioForEnhancement(source, modes)
  for w in provider.applyProviderStages(flags, opts.voiceIsolation):
    warning w
  debug "stages: denoise=" & $flags.denoise & " voiceIsolation=" &
        $flags.voiceIsolation & " humRemoval=" & $flags.humRemoval &
        " deEss=" & $flags.deEss

  let http = newRealHttpClient(timeoutMs = 300_000)
  let tty = isatty(stdin) and isatty(stdout)
  var res = provider.enhance(http, source, outDir / "work", flags,
                             opts.autoYes, tty)
  # WR-10: auto mode falls back to the always-available FFmpeg chain when the
  # chosen backend itself fails, and says so. An explicit --backend=local or
  # --backend=elevenlabs never falls back, and neither does a denied cost
  # gate (backendFailed is false then).
  if res.outputPath == "" and res.backendFailed and provider.fromAuto and
     provider.kind != apFfmpeg:
    alwaysWarn "--backend=auto: the " & backendName(provider.kind) &
      " backend failed (" & res.err & "); falling back to the FFmpeg-only chain"
    res = AudioProvider(kind: apFfmpeg, fromAuto: true).enhance(
      http, source, outDir / "work_ffmpeg", flags, opts.autoYes, tty)
  if res.outputPath == "":
    stderr.writeLine "Error! Enhancement failed: " &
      (if res.err != "": res.err else: "backend error")
    return 1

  let finalOut =
    if opts.outputPath != "": opts.outputPath
    elif wantWav: opts.inputPath.changeFileExt("") & ".enhanced.wav"
    else: opts.inputPath.changeFileExt("") & ".enhanced" & inExt
  var ok: bool
  if wantWav:
    ok = writeAudioOnly(res.outputPath, finalOut)
  else:
    # WR-09: the enhanced WAV starts at 0; keep the source audio's offset.
    let offset = audioStartOffset(opts.inputPath, max(track, 0))
    debug "audio start offset: " & $offset & "s"
    ok = muxEnhancedAudio(opts.inputPath, res.outputPath, finalOut,
                          track, trackCount, audioOffset = offset)
  if not ok:
    stderr.writeLine "Error! could not write output: " & finalOut
    return 1
  info "Enhanced output: " & finalOut
  return 0

proc main*(args: seq[string]) =
  let code = run(args)
  if code != 0: quit(code)
