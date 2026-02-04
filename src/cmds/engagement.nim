import std/[strformat, strutils, os, json, tables, algorithm, times]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../ffmpeg
import ../analyze/[engagement, engagement_types, hooks, audio, motion, faces]
import ../transcript/[types, extract]

# Import BarType from log for initBar
from ../log import BarType

proc paramsToJson*(params: EngagementParams): JsonNode =
  ## Convert engagement params to JSON
  %* {
    "audio_weight": params.audioWeight,
    "motion_weight": params.motionWeight,
    "speech_weight": params.speechWeight,
    "hook_boost": params.hookBoost,
    "face_boost_per_face": params.faceBoostPerFace,
    "min_segment_duration_ms": params.minSegmentDurationMs,
    "merge_threshold": params.mergeThreshold,
    "normalize_low_pct": params.normalizeLowPct,
    "normalize_high_pct": params.normalizeHighPct
  }

proc segmentToJson*(seg: EngagementSegment): JsonNode =
  ## Convert engagement segment to JSON
  %* {
    "start_ms": seg.startMs,
    "end_ms": seg.endMs,
    "text": seg.text,
    "score": seg.score,
    "score_relative": seg.scoreRelative,
    "score_absolute": seg.scoreAbsolute,
    "audio_score": seg.audioScore,
    "motion_score": seg.motionScore,
    "speech_score": seg.speechScore,
    "has_hook": seg.hasHook,
    "face_count": seg.faceCount,
    "speaker": seg.speaker
  }

proc timelineToJson*(timeline: EngagementTimeline, compact: bool = false): string =
  ## Convert engagement timeline to JSON
  var root = %* {
    "duration_ms": timeline.duration,
    "avg_score": timeline.avgScore,
    "hook_count": timeline.hookCount,
    "params": paramsToJson(timeline.params),
    "segments": newJArray()
  }

  for seg in timeline.segments:
    root["segments"].add(segmentToJson(seg))

  if compact:
    result = $root
  else:
    result = root.pretty()

proc formatTimestamp*(ms: int64): string =
  ## Format milliseconds as [M:SS]
  let totalSeconds = ms div 1000
  let minutes = totalSeconds div 60
  let seconds = totalSeconds mod 60
  &"[{minutes}:{seconds:02}]"

proc printSummary*(timeline: EngagementTimeline) =
  ## Print human-readable summary to stdout
  echo ""
  echo "Engagement Analysis Summary"
  echo "==========================="

  # Duration and average
  let durationSec = timeline.duration div 1000
  let minutes = durationSec div 60
  let seconds = durationSec mod 60
  echo &"Duration: {minutes}m {seconds}s"
  echo &"Average Score: {timeline.avgScore:.1f}"
  echo &"Hooks Detected: {timeline.hookCount}"
  echo ""

  # Top segments (highest scores)
  echo "Top Segments:"
  var sortedSegs = timeline.segments
  sortedSegs.sort(proc(a, b: EngagementSegment): int = cmp(b.score, a.score))

  let topCount = min(5, sortedSegs.len)
  for i in 0 ..< topCount:
    let seg = sortedSegs[i]
    let startTime = formatTimestamp(seg.startMs)
    let endTime = formatTimestamp(seg.endMs)
    # Truncate text to 50 chars
    var text = seg.text
    if text.len > 50:
      text = text[0..47] & "..."
    echo &"  {i+1}. {startTime}-{endTime} Score: {seg.score:.0f} \"{text}\""

  echo ""

  # Score distribution
  echo "Score Distribution:"
  var high = 0
  var medium = 0
  var low = 0
  for seg in timeline.segments:
    if seg.score >= 75.0:
      high += 1
    elif seg.score >= 50.0:
      medium += 1
    else:
      low += 1
  echo &"  High (75-100): {high} segments"
  echo &"  Medium (50-74): {medium} segments"
  echo &"  Low (0-49): {low} segments"
  echo ""

proc generateOutputPath*(inputPath: string, outputDir: string, ext: string): string =
  ## Generate output file path
  ## If outputDir is empty, use same directory as input
  let (dir, name, _) = splitFile(inputPath)
  let targetDir = if outputDir != "": outputDir else: dir
  result = targetDir / name & ext

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var outputPath: string = ""
  var outputDir: string = ""
  var hooksPath: string = ""
  var showSummary: bool = false
  var useStdout: bool = false
  var compact: bool = false
  var noFaces: bool = false
  var isDebug: bool = false
  var quietMode: bool = false
  var verboseMode: bool = false

  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip engage file model [options]

Analyze video engagement with audio, motion, speech, and face detection

Arguments:
  file                    Input video file
  model                   Whisper model for transcript extraction

Options:
  -o, --output PATH       Output JSON path (default: input.engage.json)
  --summary               Print summary instead of writing JSON
  --stdout                Output JSON to terminal
  --no-faces              Skip face detection (faster)
  --hooks PATH            Custom hook patterns JSON file
  --compact               Minified JSON output
  -q, --quiet             Suppress progress output
  --verbose               Show detailed progress even when piped
  --debug                 Show debug information
  --help                  Show this help
"""
      quit(0)
    of "--debug":
      isDebug = true
    of "-q", "--quiet":
      quietMode = true
      quiet = true  # Set global quiet flag for log.nim
    of "--verbose":
      verboseMode = true
    of "--summary":
      showSummary = true
    of "--stdout":
      useStdout = true
    of "--compact":
      compact = true
    of "--no-faces":
      noFaces = true
    of "-o", "--output":
      expecting = "output"
    of "--hooks":
      expecting = "hooks"
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        if inputPath == "":
          inputPath = key
        elif model == "":
          model = key
      of "output":
        outputPath = key
      of "hooks":
        hooksPath = key
      expecting = ""

  # Validate arguments
  if inputPath == "":
    error "A video file is required. Usage: honeyclip engage file model [options]"

  if model == "":
    error "A whisper model is required. Find models at: https://huggingface.co/ggerganov/whisper.cpp"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  if not fileExists(model):
    error &"""Model not found: {model}

Download whisper models from:
  https://huggingface.co/ggerganov/whisper.cpp/tree/main

Example:
  curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"""

  if hooksPath != "" and not fileExists(hooksPath):
    error &"Hooks file not found: {hooksPath}"

  # Determine output path
  if outputPath == "" and not showSummary and not useStdout:
    outputPath = generateOutputPath(inputPath, outputDir, ".engage.json")

  # Load custom hooks if provided
  var customHooks: seq[HookPattern] = @[]
  if hooksPath != "":
    if isDebug:
      debug &"Loading custom hooks from: {hooksPath}"
    # Load and parse hooks JSON
    # For now, use default hooks
    # TODO: Implement hook JSON loading

  # Determine effective verbosity
  let isTTY = stdin.isatty()
  let showProgress = (isTTY or verboseMode) and not quietMode

  var bar = initBar(if showProgress: BarType.modern else: BarType.none)
  defer: bar.destroy()

  # Step 1: Extract transcript with progress
  let transcriptStart = epochTime()
  if showProgress:
    bar.start(100.0, "Extracting transcript")
  var transcript: Transcript
  try:
    transcript = extractTranscript(inputPath, model, "", "")
  except IOError as e:
    error &"Failed to extract transcript: {e.msg}"
  if showProgress:
    bar.`end`()
  let transcriptTime = epochTime() - transcriptStart

  if transcript.words.len == 0:
    error "No transcript content extracted"

  # Step 2: Open container for analysis
  var container: InputContainer
  try:
    container = av.open(inputPath)
  except IOError as e:
    error &"Failed to open media file: {e.msg}"
  defer: container.close()

  # Get timebase from video stream (or audio if no video)
  var tb: AVRational
  if container.video.len > 0:
    tb = container.video[0].time_base
  elif container.audio.len > 0:
    tb = container.audio[0].time_base
  else:
    error "No video or audio stream found"

  # Step 3: Analyze engagement (uses internal per-step progress)
  let analyzeStart = epochTime()
  var timeline: EngagementTimeline
  try:
    let params = defaultEngagementParams()
    let patterns = loadBuiltinPatterns()
    timeline = analyzeEngagement(bar, container, inputPath, transcript, tb,
                                  params, patterns, not noFaces)
  except Exception as e:
    error &"Failed to analyze engagement: {e.msg}"
  let analyzeTime = epochTime() - analyzeStart

  # Print timing summary if not quiet and not outputting to stdout/summary
  if showProgress and not showSummary and not useStdout:
    echo ""
    echo "Analysis complete"
    echo &"  Transcript: {transcriptTime:.1f}s ({transcript.words.len} words)"
    echo &"  Analysis: {analyzeTime:.1f}s ({timeline.segments.len} segments)"
    if timeline.hookCount > 0:
      echo &"  Hooks detected: {timeline.hookCount}"

  # Step 3: Output results
  if showSummary:
    printSummary(timeline)
  elif useStdout:
    echo timelineToJson(timeline, compact)
  else:
    # Write to file
    let jsonStr = timelineToJson(timeline, compact)
    try:
      writeFile(outputPath, jsonStr)
      if showProgress:
        conwrite("")
        echo &"Created: {outputPath}"
    except IOError as e:
      error &"Failed to write output file: {e.msg}"
