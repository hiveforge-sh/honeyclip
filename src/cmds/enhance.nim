## honeyclip enhance subcommand
##
## AI audio enhancement: denoise (DeepFilterNet locally or the ElevenLabs
## Voice Isolator, or an FFmpeg-only chain), hum removal, de-essing and
## two-pass loudness normalisation. Outputs the video with enhanced audio, or
## the cleaned WAV with --audio-only.

import std/[parseopt, strutils, os, terminal]
import ../audio/[provider, render]
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
                            local       DeepFilterNet (pip install deepfilternet)
                            elevenlabs  Voice Isolator API (ELEVENLABS_API_KEY
                                        or [elevenlabs] apiKey in config.toml)
                            ffmpeg      FFmpeg-only chain, no neural model
  --denoise=MODE          on | off | auto (default: auto)
  --voice-isolation=MODE  on | off | auto (default: auto)
  --de-reverb=MODE        on | off | auto (default: auto)
  --de-ess=MODE           on | off | auto (default: auto)
  --hum-removal=MODE      on | off | auto (default: auto)
  --audio-only            Write the cleaned WAV instead of a video
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
  # `--flag value` and `-o value` are joined into `--flag=value` first;
  # parseopt only reliably handles the `=`/`:` forms.
  const valueFlags = ["-o", "--output", "--backend", "--denoise",
                      "--voice-isolation", "--de-reverb", "--de-ess",
                      "--hum-removal"]
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

  var provider: AudioProvider
  try:
    provider = resolveProvider(opts.backend, resolveElevenlabsKey())
  except ValueError as e:
    stderr.writeLine "Error! " & e.msg
    return 1

  let modes = (denoise: opts.denoise, voiceIsolation: opts.voiceIsolation,
               deReverb: opts.deReverb, deEss: opts.deEss,
               humRemoval: opts.humRemoval)
  let flags = analyzeAudioForEnhancement(opts.inputPath, modes)
  debug "stages: denoise=" & $flags.denoise & " voiceIsolation=" &
        $flags.voiceIsolation & " humRemoval=" & $flags.humRemoval &
        " deEss=" & $flags.deEss

  let outDir = getTempDir() / ("honeyclip_enhance_" & $getCurrentProcessId())
  defer:
    try: removeDir(outDir) except CatchableError: discard
  let http = newRealHttpClient(timeoutMs = 300_000)
  let tty = isatty(stdin) and isatty(stdout)
  let res = provider.enhance(http, opts.inputPath, outDir, flags,
                             opts.autoYes, tty)
  if res.outputPath == "":
    stderr.writeLine "Error! Enhancement failed: " &
      (if res.err != "": res.err else: "backend error")
    return 1

  let inExt = opts.inputPath.splitFile.ext.toLowerAscii
  let audioInput = inExt in [".wav", ".mp3", ".m4a", ".flac", ".aac", ".ogg", ".opus"]
  let wantWav = opts.audioOnly or audioInput
  let finalOut =
    if opts.outputPath != "": opts.outputPath
    elif wantWav: opts.inputPath.changeFileExt("") & ".enhanced.wav"
    else: opts.inputPath.changeFileExt("") & ".enhanced" & inExt
  let ok = if wantWav: writeAudioOnly(res.outputPath, finalOut)
           else: muxEnhancedAudio(opts.inputPath, res.outputPath, finalOut)
  if not ok:
    stderr.writeLine "Error! could not write output: " & finalOut
    return 1
  info "Enhanced output: " & finalOut
  return 0

proc main*(args: seq[string]) =
  let code = run(args)
  if code != 0: quit(code)
