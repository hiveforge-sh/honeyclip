import std/[strformat, strutils, os, json, tables, algorithm, times]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../ffmpeg
import ../analyze/[clips, engagement, engagement_types, hooks, audio, motion, faces]
import ../exports/edl
import ../transcript/[types, extract]

# Import BarType from log for initBar
from ../log import BarType

proc formatTimestamp*(ms: int64): string =
  ## Format milliseconds as [M:SS]
  let totalSeconds = ms div 1000
  let minutes = totalSeconds div 60
  let seconds = totalSeconds mod 60
  &"[{minutes}:{seconds:02}]"

proc generateOutputPath*(inputPath: string, outputDir: string, ext: string): string =
  ## Generate output file path
  ## If outputDir is empty, use same directory as input
  let (dir, name, _) = splitFile(inputPath)
  let targetDir = if outputDir != "": outputDir else: dir
  result = targetDir / name & ext

proc printClipList*(clips: seq[Clip], inputPath: string) =
  ## Print detected clips in human-readable format
  echo ""
  echo &"Detected Clips ({clips.len} total)"
  echo "=========================="
  echo ""

  for clip in clips:
    let startTime = formatTimestamp(clip.startMs)
    let endTime = formatTimestamp(clip.endMs)
    let duration = (clip.endMs - clip.startMs) div 1000
    let hookStr = if clip.hasHook: " [HOOK]" else: ""

    echo &"  #{clip.rank}: {startTime}-{endTime} ({duration}s) Score: {clip.engagementScore:.0f}{hookStr}"

    # Truncate text
    if clip.text.len > 0:
      var text = clip.text.replace("\n", " ").strip()
      if text.len > 70:
        text = text[0..67] & "..."
      echo &"      \"{text}\""
    echo ""

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var outputDir: string = ""
  var topN: int = 5
  var minDuration: int = 15
  var maxDuration: int = 60
  var introSkip: int = 0
  var outroSkip: int = 0
  var showList: bool = false
  var exportClips: bool = false
  var noMetadata: bool = false
  var noFaces: bool = false
  var concurrent: int = 4
  var isDebug: bool = false

  # Parse arguments
  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip clips file model [options]

Detect and export engaging clips from video

Arguments:
  file                    Input video file
  model                   Whisper model for transcript extraction

Options:
  --list                  List detected clips (preview mode)
  --export                Export clips (renders video files)
  -n, --top N             Number of top clips (default: 5)
  -o, --output DIR        Output directory for clips
  --min-duration SECS     Minimum clip duration (default: 15)
  --max-duration SECS     Maximum clip duration (default: 60)
  --intro-skip SECS       Skip first N seconds (default: 0)
  --outro-skip SECS       Skip last N seconds (default: 0)
  --no-metadata           Skip EDL/JSON metadata export
  --no-faces              Skip face detection (faster)
  --concurrent N          Max parallel renders (default: 4)
  --debug                 Show debug information
  --help                  Show this help

Workflow:
  1. honeyclip clips video.mp4 model --list    # Preview clips
  2. honeyclip clips video.mp4 model --export  # Export clips
"""
      quit(0)
    of "--list":
      showList = true
    of "--export":
      exportClips = true
    of "-n", "--top":
      expecting = "top"
    of "-o", "--output":
      expecting = "output"
    of "--min-duration":
      expecting = "min-duration"
    of "--max-duration":
      expecting = "max-duration"
    of "--intro-skip":
      expecting = "intro-skip"
    of "--outro-skip":
      expecting = "outro-skip"
    of "--no-metadata":
      noMetadata = true
    of "--no-faces":
      noFaces = true
    of "--concurrent":
      expecting = "concurrent"
    of "--debug":
      isDebug = true
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        # Positional arguments: file, then model
        if inputPath == "":
          inputPath = key
        elif model == "":
          model = key
        else:
          error &"Unexpected positional argument: {key}"
      of "top":
        topN = parseInt(key)
        expecting = ""
      of "output":
        outputDir = key
        expecting = ""
      of "min-duration":
        minDuration = parseInt(key)
        expecting = ""
      of "max-duration":
        maxDuration = parseInt(key)
        expecting = ""
      of "intro-skip":
        introSkip = parseInt(key)
        expecting = ""
      of "outro-skip":
        outroSkip = parseInt(key)
        expecting = ""
      of "concurrent":
        concurrent = parseInt(key)
        expecting = ""

  # Check for incomplete argument
  if expecting != "":
    error &"Missing value for {expecting}"

  # Validate arguments
  if inputPath == "":
    error "A video file is required. Usage: honeyclip clips file model [options]"

  if model == "":
    error "A whisper model is required. Find models at: https://huggingface.co/ggerganov/whisper.cpp"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  if not fileExists(model):
    error &"Model not found: {model}\nDownload from: https://huggingface.co/ggerganov/whisper.cpp"

  if not showList and not exportClips:
    # Default to list mode if neither specified
    showList = true

  var bar = initBar(BarType.modern)
  defer: bar.destroy()

  # Step 1: Extract transcript
  let transcriptStart = epochTime()
  bar.start(100.0, "Extracting transcript")
  var transcript: Transcript
  try:
    transcript = extractTranscript(inputPath, model, "", "")
  except IOError as e:
    error &"Failed to extract transcript: {e.msg}"
  bar.`end`()
  let transcriptTime = epochTime() - transcriptStart
  let wordCount = transcript.words.len

  # Step 2: Open container for analysis
  var container = av.open(inputPath)
  defer: container.close()

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

  # Step 4: Detect scene changes
  bar.start(100.0, "Detecting scene changes")
  let sceneChanges = extractSceneChanges(inputPath)
  bar.`end`()

  # Step 5: Detect clip boundaries and clips
  bar.start(100.0, "Detecting clip boundaries")
  var detectionParams = defaultClipDetectionParams()
  detectionParams.minClipDurationMs = minDuration * 1000
  detectionParams.maxClipDurationMs = maxDuration * 1000
  detectionParams.introSkipMs = introSkip * 1000
  detectionParams.outroSkipMs = outroSkip * 1000

  let boundaries = detectBoundaries(timeline, sceneChanges, detectionParams)
  var detectedClips = detectClips(timeline, boundaries, detectionParams)
  bar.`end`()

  if detectedClips.len == 0:
    echo ""
    echo "No clips detected meeting criteria."
    echo &"  Min duration: {minDuration}s"
    echo &"  Max duration: {maxDuration}s"
    quit(0)

  # Step 6: Rank clips
  bar.start(float(detectedClips.len), "Ranking clips")
  var rankingParams = defaultClipRankingParams()
  rankingParams.topN = topN
  let rankedClips = rankClips(detectedClips, rankingParams)
  bar.`end`()

  # Print summary
  if not quiet:
    echo ""
    echo &"Found {rankedClips.len} clips from {detectedClips.len} candidates"
    echo &"  Words analyzed: {wordCount}"
    echo &"  Scene changes: {sceneChanges.len}"
    echo &"  Transcript: {transcriptTime:.1f}s, Analysis: {analyzeTime:.1f}s"
    echo ""

  # Step 6: Output based on mode
  if showList:
    printClipList(rankedClips, inputPath)

  if exportClips:
    echo &"Exporting {rankedClips.len} clips..."

    # Determine output directory
    let effectiveOutputDir = if outputDir != "":
      outputDir
    else:
      let (dir, name, _) = splitFile(inputPath)
      dir / name & "_clips"

    # Export video clips
    var exportParams = defaultClipExportParams()
    exportParams.outputDir = effectiveOutputDir
    exportParams.maxConcurrent = concurrent

    let results = batchExportClips(inputPath, rankedClips, exportParams,
      proc(completed, total: int) =
        conwrite(&"Exporting clips: {completed}/{total}")
    )

    conwrite("")
    echo ""
    echo "Export Results:"
    for r in results:
      let status = if r.success: "OK" else: &"FAILED: {r.error}"
      echo &"  #{r.clip.rank}: {extractFilename(r.outputPath)} - {status}"

    # Export metadata unless disabled
    if not noMetadata:
      echo ""

      # Convert to EDLClip
      var edlClips: seq[EDLClip] = @[]
      for clip in rankedClips:
        edlClips.add(EDLClip(
          startMs: clip.startMs,
          endMs: clip.endMs,
          engagementScore: clip.engagementScore,
          text: clip.text,
          rank: clip.rank
        ))

      # Export EDL
      let edlPath = effectiveOutputDir / "clips.edl"
      exportCMX3600EDL(edlClips, edlPath, extractFilename(inputPath))
      echo &"Created: {edlPath}"

      # Export JSON
      let jsonPath = effectiveOutputDir / "clips.json"
      exportClipsJSON(edlClips, jsonPath, inputPath)
      echo &"Created: {jsonPath}"

    echo ""
    echo &"Clips exported to: {effectiveOutputDir}"
