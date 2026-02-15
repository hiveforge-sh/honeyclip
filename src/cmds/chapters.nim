import std/[strformat, strutils, os, times, json, osproc, tables]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../ffmpeg
import ../analyze/[chapters, clips, engagement, engagement_types, hooks]
import ../metadata/[types as metadataTypes, apply]
import ../exports/[markers, fcp11, edl]
import ../transcript/[types, extract]
from ../log import BarType

proc formatTimestamp*(ms: int64): string =
  ## Format milliseconds as [M:SS]
  let totalSeconds = ms div 1000
  let minutes = totalSeconds div 60
  let seconds = totalSeconds mod 60
  &"[{minutes}:{seconds:02}]"

proc printChapterList*(chapters: seq[Chapter], duration: int64) =
  ## Print detected chapters to terminal
  echo ""
  echo &"Detected Chapters ({chapters.len} total)"
  echo "=========================="
  echo ""
  for i, ch in chapters:
    let startTime = formatTimestamp(ch.startMs)
    let endTime = formatTimestamp(ch.endMs)
    let durSec = (ch.endMs - ch.startMs) div 1000
    let sourceStr = if ch.source == csEngagement: "engagement" else: "scene"
    let scoreStr = if ch.score > 0: &" (score: {ch.score:.0f})" else: ""
    echo &"  {i+1}. {startTime}-{endTime} ({durSec}s) [{sourceStr}]{scoreStr}"
    echo &"      {ch.title}"
  echo ""

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var mode: string = "combined"
  var exportFormat: string = ""
  var outputPath: string = ""
  var hooksPath: string = ""
  var threshold: float = 0.4
  var minSpacing: int = 30
  var minScore: int = 60
  var maxChapters: int = 10
  var noFaces: bool = false
  var noTranscript: bool = false
  var isDebug: bool = false
  var quietMode: bool = false

  # Parse arguments
  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip chapters file [model] [options]

Auto-generate chapters from scene changes and engagement peaks

Arguments:
  file                    Input video file
  model                   Whisper model (auto-detected from ~/.cache/whisper/)

Options:
  --mode MODE             Chapter detection mode: scene, engagement, combined
                          (default: combined)
  --export FORMAT         Export format: mp4, fcpxml, edl, json
                          (default: print to terminal)
  -o, --output PATH       Output file path
  --threshold N           Scene detection threshold 0.0-1.0 (default: 0.4)
  --min-spacing SECS      Minimum seconds between chapters (default: 30)
  --min-score N           Minimum engagement score for peaks (default: 60)
  --max-chapters N        Maximum number of chapters (default: 10)
  --no-faces              Skip face detection (faster)
  --no-transcript         Skip transcript (scene-only mode)
  --hooks PATH            Custom hook patterns JSON file
  -q, --quiet             Suppress progress output
  --debug                 Show debug information
  --help                  Show this help

Modes:
  scene       - Chapters at visual scene changes
  engagement  - Chapters at high-engagement peaks
  combined    - Both sources merged (default)

Examples:
  honeyclip chapters video.mp4                           # List chapters
  honeyclip chapters video.mp4 --mode scene              # Scene-only
  honeyclip chapters video.mp4 --export mp4              # Embed in MP4
  honeyclip chapters video.mp4 --export fcpxml -o ch.xml # FCPXML markers
"""
      quit(0)
    of "--mode":
      expecting = "mode"
    of "--export":
      expecting = "export"
    of "-o", "--output":
      expecting = "output"
    of "--threshold":
      expecting = "threshold"
    of "--min-spacing":
      expecting = "min-spacing"
    of "--min-score":
      expecting = "min-score"
    of "--max-chapters":
      expecting = "max-chapters"
    of "--no-faces":
      noFaces = true
    of "--no-transcript":
      noTranscript = true
    of "--hooks":
      expecting = "hooks"
    of "-q", "--quiet":
      quietMode = true
      quiet = true
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
      of "mode":
        mode = key
        expecting = ""
      of "export":
        exportFormat = key
        expecting = ""
      of "output":
        outputPath = key
        expecting = ""
      of "threshold":
        threshold = parseFloat(key)
        expecting = ""
      of "min-spacing":
        minSpacing = parseInt(key)
        expecting = ""
      of "min-score":
        minScore = parseInt(key)
        expecting = ""
      of "max-chapters":
        maxChapters = parseInt(key)
        expecting = ""
      of "hooks":
        hooksPath = key
        expecting = ""

  # Check for incomplete argument
  if expecting != "":
    error &"Missing value for {expecting}"

  # Validate arguments
  if inputPath == "":
    error "A video file is required. Usage: honeyclip chapters file [model] [options]"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Validate mode
  if mode notin ["scene", "engagement", "combined"]:
    error &"Invalid mode: {mode}. Must be: scene, engagement, or combined"

  # If engagement mode required, validate model exists
  if mode != "scene" and not noTranscript:
    if model == "":
      model = findWhisperModel()
      if model == "":
        error "No whisper model found. Download one to ~/.cache/whisper/ or specify path (or use --no-transcript for scene-only).\nFind models at: https://huggingface.co/ggerganov/whisper.cpp"
      else:
        echo &"Using whisper model: {extractFilename(model)}"

    if not fileExists(model):
      error &"Model not found: {model}\nDownload from: https://huggingface.co/ggerganov/whisper.cpp"

  # If scene-only mode and no model specified, auto-set no-transcript
  if mode == "scene" and model == "":
    noTranscript = true

  var bar = initBar(if quietMode: BarType.none else: BarType.modern)
  defer: bar.destroy()

  # Step 1: Extract transcript (unless --no-transcript or scene-only)
  var transcript: Transcript
  var transcriptTime: float = 0.0
  if not noTranscript and mode != "scene":
    let transcriptStart = epochTime()
    bar.start(100.0, "Extracting transcript")
    try:
      transcript = extractTranscript(inputPath, model, "", "")
    except IOError as e:
      error &"Failed to extract transcript: {e.msg}"
    bar.`end`()
    transcriptTime = epochTime() - transcriptStart

  # Step 2: Open container, get timebase
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

  # Get duration from container
  let duration = if container.video.len > 0:
                   int64(float64(container.video[0].duration) * float64(tb.num) / float64(tb.den) * 1000.0)
                 elif container.audio.len > 0:
                   int64(float64(container.audio[0].duration) * float64(tb.num) / float64(tb.den) * 1000.0)
                 else:
                   0i64

  # Step 3: Load hooks (if engagement mode)
  var patterns: seq[HookPattern]
  var hooksLoadedPath: string
  if mode != "scene":
    try:
      let videoDir = parentDir(inputPath)
      (patterns, hooksLoadedPath) = loadAllHooks(hooksPath, videoDir, isDebug)
    except ValueError as e:
      error e.msg
    except IOError as e:
      error e.msg

    # If template was generated, exit early
    if hooksPath != "" and hooksLoadedPath == "" and fileExists(hooksPath):
      quit(0)

  # Step 4: Analyze engagement (unless mode == "scene")
  var timeline: EngagementTimeline
  if mode == "scene":
    # Create dummy timeline with just duration
    timeline = EngagementTimeline(
      duration: duration,
      avgScore: 0.0,
      hookCount: 0,
      params: defaultEngagementParams(),
      segments: @[]
    )
  else:
    let analyzeStart = epochTime()
    try:
      let params = defaultEngagementParams()
      timeline = analyzeEngagement(bar, container, inputPath, transcript, tb,
                                    params, patterns, not noFaces)
    except Exception as e:
      error &"Failed to analyze engagement: {e.msg}"
    let analyzeTime = epochTime() - analyzeStart

    if not quietMode:
      echo ""
      echo "Analysis complete"
      if not noTranscript:
        echo &"  Transcript: {transcriptTime:.1f}s ({transcript.words.len} words)"
      echo &"  Analysis: {analyzeTime:.1f}s ({timeline.segments.len} segments)"

  # Step 5: Detect scene changes (unless mode == "engagement")
  var sceneChanges: seq[float64] = @[]
  if mode != "engagement":
    bar.start(100.0, "Detecting scene changes")
    sceneChanges = extractSceneChanges(inputPath, threshold)
    bar.`end`()

  # Step 6: Build ChapterParams
  var chapterParams = defaultChapterParams()
  chapterParams.mode = mode
  chapterParams.sceneThreshold = threshold
  chapterParams.minSpacingMs = minSpacing * 1000
  chapterParams.minScore = minScore.float32
  chapterParams.maxChapters = maxChapters

  # Step 7: Detect engagement peaks (if mode != "scene")
  var engagementPeaks: seq[int64] = @[]
  if mode != "scene":
    engagementPeaks = detectEngagementPeaks(
      timeline,
      chapterParams.minSpacingMs,
      chapterParams.minScore,
      chapterParams.maxChapters
    )

  # Step 8: Generate chapters
  let chapters = generateChapters(sceneChanges, engagementPeaks, timeline, chapterParams)

  if chapters.len == 0:
    echo ""
    echo "No chapters detected meeting criteria."
    if mode == "engagement":
      echo &"  Min engagement score: {minScore}"
    echo &"  Min spacing: {minSpacing}s"
    quit(0)

  # Step 9: Print chapter list (always, unless --quiet)
  if not quietMode:
    printChapterList(chapters, duration)

  # Step 10: Export if specified
  if exportFormat != "":
    case exportFormat:
    of "mp4":
      # Generate output path
      let outputFile = if outputPath != "":
                         outputPath
                       else:
                         let (dir, name, ext) = splitFile(inputPath)
                         dir / name & "_chapters" & ext

      # Convert chapters to ChapterMarker
      let chapterMarkers = chaptersToMetadata(chapters)

      # Create metadata template
      var tmpl = MetadataTemplate(
        global: initTable[string, string](),
        chapters: chapterMarkers
      )

      # Write ffmetadata file
      let metadataPath = writeFFMetadataFile(tmpl)

      if not quietMode:
        echo ""
        echo "Embedding chapters in MP4..."

      # Apply to video via FFmpeg
      let ffmpegCmd = "ffmpeg"
      let ffmpegArgs = @[
        "-i", inputPath,
        "-i", metadataPath,
        "-map_metadata", "1",
        "-codec", "copy",
        outputFile
      ]

      let exitCode = execCmd(&"{ffmpegCmd} {ffmpegArgs.join(\" \")}")
      if exitCode != 0:
        error "FFmpeg command failed"

      if not quietMode:
        echo &"Created: {outputFile}"

    of "fcpxml":
      # Generate output path
      let outputFile = if outputPath != "":
                         outputPath
                       else:
                         let (dir, name, _) = splitFile(inputPath)
                         dir / name & "_chapters.fcpxml"

      # Convert to Markers
      let markerList = chaptersToMarkers(chapters)

      # Write FCPXML
      writeMarkersFCPXML(markerList, outputFile, extractFilename(inputPath))

      if not quietMode:
        echo ""
        echo &"Created: {outputFile}"

    of "edl":
      # Generate output path
      let outputFile = if outputPath != "":
                         outputPath
                       else:
                         let (dir, name, _) = splitFile(inputPath)
                         dir / name & "_chapters.edl"

      # Convert to Markers
      let markerList = chaptersToMarkers(chapters)

      # Write EDL
      exportMarkersEDL(markerList, outputFile, extractFilename(inputPath))

      if not quietMode:
        echo ""
        echo &"Created: {outputFile}"

    of "json":
      # Generate output path
      let outputFile = if outputPath != "":
                         outputPath
                       else:
                         let (dir, name, _) = splitFile(inputPath)
                         dir / name & "_chapters.json"

      # Convert to JSON
      var jsonArray = newJArray()
      for ch in chapters:
        jsonArray.add(%* {
          "startMs": ch.startMs,
          "endMs": ch.endMs,
          "title": ch.title,
          "source": if ch.source == csEngagement: "engagement" else: "scene",
          "score": ch.score
        })

      # Write JSON
      writeFile(outputFile, jsonArray.pretty())

      if not quietMode:
        echo ""
        echo &"Created: {outputFile}"

    else:
      error &"Unknown export format: {exportFormat}. Must be: mp4, fcpxml, edl, or json"
