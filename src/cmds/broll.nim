## honeyclip broll subcommand
##
## Detects B-roll insertion points from a transcript, generates B-roll clips
## via ComfyUI or Veo, rewrites prompts via Gemini Flash, optionally muxes
## the final video, and writes a marker JSON sidecar.

import std/[strformat, strutils, os, terminal, times]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../ffmpeg
import ../config
import ../http_client
import ../analyze/[broll, engagement, engagement_types, hooks]
import ../broll/[provider, fitting, flash, markers, render, veo]
import ../transcript/[types, extract]
from ../log import BarType

const helpText = """usage: honeyclip broll file [model] [options]

Auto-generate B-roll inserts at detected timeline points.

Arguments:
  file                    Input video file
  model                   Whisper model (auto-detected from ~/.cache/whisper/)

Options:
  --backend BACKEND       comfyui | veo | auto (default: auto -- local first)
  --comfy-url URL         ComfyUI server URL (default: http://127.0.0.1:8188)
  --workflow PATH         ComfyUI workflow JSON template (required for ComfyUI)
  --model NAME            Veo model (default: veo-3.0-fast-generate-001)
  --max-broll N           Cap on inserted B-roll clips (default: derived from duration)
  --min-spacing SECS      Minimum seconds between insertions (default: 30)
  --render                Mux final video with B-roll inserts
  -o, --output PATH       Output path (default: {input}_broll.json or _broll.mp4)
  --yes                   Skip cost-confirmation prompt (Veo)
  -q, --quiet             Suppress progress output
  --debug                 Show debug information
  --help                  Show this help

Examples:
  honeyclip broll video.mp4                                   # marker JSON, auto backend
  honeyclip broll video.mp4 --backend veo --yes               # Veo, skip cost prompt
  honeyclip broll video.mp4 --workflow wf.json --render -o out.mp4
"""

proc main*(cArgs: seq[string]) =
  var inputPath = ""
  var whisperModel = ""
  var backend = "auto"
  var comfyUrl = ""
  var workflowPath = ""
  var veoModel = "veo-3.0-fast-generate-001"
  var maxBroll = -1
  var minSpacingSec = 30
  var doRender = false
  var outputPath = ""
  var autoYes = false
  var quietMode = false
  var debugMode = false

  var expecting = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key
    of "--help", "-h":
      echo helpText
      quit(0)
    of "--backend":
      expecting = "backend"
    of "--comfy-url":
      expecting = "comfy-url"
    of "--workflow":
      expecting = "workflow"
    of "--model":
      expecting = "model"
    of "--max-broll":
      expecting = "max-broll"
    of "--min-spacing":
      expecting = "min-spacing"
    of "--render":
      doRender = true
    of "-o", "--output":
      expecting = "output"
    of "--yes":
      autoYes = true
    of "-q", "--quiet":
      quietMode = true
      quiet = true
    of "--debug":
      debugMode = true
      isDebug = true
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"
      case expecting
      of "":
        if inputPath == "":
          inputPath = key
        elif whisperModel == "":
          whisperModel = key
        else:
          error &"Unexpected positional argument: {key}"
      of "backend":
        backend = key
        expecting = ""
      of "comfy-url":
        comfyUrl = key
        expecting = ""
      of "workflow":
        workflowPath = key
        expecting = ""
      of "model":
        veoModel = key
        expecting = ""
      of "max-broll":
        maxBroll = parseInt(key)
        expecting = ""
      of "min-spacing":
        minSpacingSec = parseInt(key)
        expecting = ""
      of "output":
        outputPath = key
        expecting = ""
      else:
        expecting = ""

  if expecting != "":
    error &"Missing value for --{expecting}"

  if inputPath == "":
    echo helpText
    quit(1)

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Resolve config
  let apiKey = resolveGeminiKey()
  if comfyUrl == "":
    comfyUrl = resolveComfyUrl()

  let http: HttpClientLike = newRealHttpClient()

  # Resolve provider early so we fail fast before long transcript/analysis.
  let prov =
    try:
      resolveProvider(backend, comfyUrl, workflowPath, apiKey, veoModel, http)
    except ValueError as e:
      error e.msg

  # Find whisper model if needed
  if whisperModel == "":
    whisperModel = findWhisperModel()
    if whisperModel == "":
      error "No whisper model found. Download one to ~/.cache/whisper/ or specify path.\nFind models at: https://huggingface.co/ggerganov/whisper.cpp"
    elif not quietMode:
      echo &"Using whisper model: {extractFilename(whisperModel)}"

  if not fileExists(whisperModel):
    error &"Model not found: {whisperModel}"

  var bar = initBar(if quietMode: BarType.none else: BarType.modern)
  defer: bar.destroy()

  # Extract transcript
  var transcript: Transcript
  bar.start(100.0, "Extracting transcript")
  try:
    transcript = extractTranscript(inputPath, whisperModel, "", "")
  except IOError as e:
    error &"Failed to extract transcript: {e.msg}"
  bar.`end`()

  # Open container
  var container: InputContainer
  try:
    container = av.open(inputPath)
  except IOError as e:
    error &"Failed to open media file: {e.msg}"
  defer: container.close()

  var tb: AVRational
  if container.video.len > 0:
    tb = container.video[0].time_base
  elif container.audio.len > 0:
    tb = container.audio[0].time_base
  else:
    error "No video or audio stream found"

  let durationMs = if container.video.len > 0:
                     int64(float64(container.video[0].duration) * float64(tb.num) / float64(tb.den) * 1000.0)
                   elif container.audio.len > 0:
                     int64(float64(container.audio[0].duration) * float64(tb.num) / float64(tb.den) * 1000.0)
                   else:
                     0i64

  # Analyze engagement
  bar.start(100.0, "Analyzing engagement")
  let engagementTimeline = block:
    try:
      let params = defaultEngagementParams()
      analyzeEngagement(bar, container, inputPath, transcript, tb, params,
                        loadBuiltinPatterns(), not quietMode)
    except Exception as e:
      error &"Failed to analyze engagement: {e.msg}"
  bar.`end`()

  # Detect B-roll insertion points
  var brollParams = defaultBrollParams()
  brollParams.minSpacingMs = int64(minSpacingSec) * 1000
  brollParams.maxInsertions = maxBroll

  let candidates = detectBrollInsertions(transcript, engagementTimeline, brollParams)
  let chosen = selectInsertions(candidates, brollParams, durationMs)

  if chosen.len == 0:
    echo "No B-roll insertion points detected."
    quit(0)

  if not quietMode:
    echo &"Detected {chosen.len} B-roll insertion point(s)"

  # Veo cost gate
  if prov.kind == bpVeo:
    let isTty = isatty(stdout)
    if not confirmVeoCost(chosen.len, prov.model, isTty, autoYes):
      error "Aborted by user (or non-TTY without --yes)."

  # Generate clips
  let outDir = getTempDir() / &"honeyclip_broll_{epochTime():.0f}"
  createDir(outDir)
  defer:
    try: removeDir(outDir) except CatchableError: discard
  var clips: seq[ClipResult]
  var prompts: seq[string]
  for ins in chosen:
    let visualPrompt = rewritePrompt(http, apiKey, ins.contextText)
    prompts.add visualPrompt
    var r = generate(prov, http, ins, visualPrompt, outDir)
    # Apply fitting if needed
    if r.success and abs(r.actualDurationMs - ins.pauseMs) > 200:
      let strat = selectFittingStrategy(r.actualDurationMs, ins.pauseMs)
      if strat notin {fsNone, fsRequestExtra}:
        let fitted = outDir / &"broll_fit_{ins.startMs}.mp4"
        if fitClipDuration(r.clipPath, ins.pauseMs, r.actualDurationMs, strat, fitted):
          r.clipPath = fitted
          r.actualDurationMs = ins.pauseMs
    clips.add r

  # Determine output paths
  let (dir, name, ext) = splitFile(inputPath)
  let defaultMarker = dir / name & "_broll.json"
  let defaultRender = dir / name & "_broll" & ext
  let resolvedOut = if outputPath != "": outputPath
                    elif doRender: defaultRender
                    else: defaultMarker

  if doRender:
    let markerSidecar = changeFileExt(resolvedOut, "json")
    writeBrollMarkersJson(inputPath, chosen, clips, prompts, markerSidecar)
    if not renderWithBroll(inputPath, chosen, clips, durationMs, resolvedOut):
      error &"Render failed; marker JSON written to {markerSidecar}"
    if not quietMode:
      info &"Wrote {resolvedOut} and marker sidecar {markerSidecar}"
  else:
    writeBrollMarkersJson(inputPath, chosen, clips, prompts, resolvedOut)
    if not quietMode:
      info &"Wrote {resolvedOut}"
