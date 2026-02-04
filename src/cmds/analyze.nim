import std/[strformat, strutils, os, json, terminal, tables]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../ffmpeg
import ../analyze/[engagement, engagement_types, hooks, clips, presets]
import ../exports/[edl, project]
import ../transcript/[types, extract]
import ../cmds/engagement as engagementModule

from ../log import BarType

proc generateOutputPath(inputPath: string, suffix: string, ext: string): string =
  let (dir, name, _) = splitFile(inputPath)
  result = dir / name & suffix & ext

proc printTopClips(clips: seq[Clip], limit: int = 5) =
  echo ""
  echo &"Top {min(limit, clips.len)} Clips"
  echo "================="
  for i in 0 ..< min(limit, clips.len):
    let clip = clips[i]
    let startSec = clip.startMs div 1000
    let endSec = clip.endMs div 1000
    let hookStr = if clip.hasHook: " [HOOK]" else: ""
    echo &"  #{clip.rank}: [{startSec div 60}:{startSec mod 60:02}]-[{endSec div 60}:{endSec mod 60:02}] Score: {clip.engagementScore:.0f}{hookStr}"
  echo ""

proc promptNextAction(): string =
  ## TTY-aware prompt for next action
  if not stdin.isatty():
    return "done"  # Non-interactive mode

  echo "What would you like to do next?"
  echo "  [e] Export clips as video files"
  echo "  [n] Export to NLE (Premiere/Resolve/FCP)"
  echo "  [d] Done (exit)"
  echo ""
  stdout.write("Choice [e/n/d]: ")
  stdout.flushFile()

  let response = stdin.readLine().strip().toLowerAscii()
  case response:
  of "e", "export": return "export"
  of "n", "nle": return "nle"
  else: return "done"

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var outputDir: string = ""
  var topN: int = 5
  var noFaces: bool = false
  var noTranscript: bool = false
  var fresh: bool = false
  var dryRun: bool = false
  var presetName: string = ""
  var isDebug: bool = false

  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip analyze file model [options]

Analyze video engagement and detect clips (convenience workflow)

Arguments:
  file                    Input video file
  model                   Whisper model for transcript extraction

Options:
  -n, --top N             Number of top clips to show (default: 5)
  -o, --output DIR        Output directory for files
  --preset NAME           Use named preset (viral, podcast, tutorial, interview,
                          tiktok, youtube, instagram)
  --no-faces              Skip face detection (faster)
  --no-transcript         Skip transcript extraction (audio/motion only)
  --fresh                 Ignore cache, re-run analysis
  --dry-run               Show what would be analyzed without running
  --debug                 Show debug information
  --help                  Show this help

Workflow:
  1. Extracts transcript (unless --no-transcript)
  2. Analyzes engagement (audio, motion, speech, faces)
  3. Detects optimal clip boundaries
  4. Saves engagement.json and project file
  5. Prompts for export action (TTY only)
"""
      quit(0)
    of "--debug":
      isDebug = true
    of "--no-faces":
      noFaces = true
    of "--no-transcript":
      noTranscript = true
    of "--fresh":
      fresh = true
    of "--dry-run":
      dryRun = true
    of "-n", "--top":
      expecting = "top"
    of "-o", "--output":
      expecting = "output"
    of "--preset":
      expecting = "preset"
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        if inputPath == "":
          inputPath = key
        elif model == "":
          model = key
        else:
          error &"Unexpected argument: {key}"
      of "top":
        topN = parseInt(key)
      of "output":
        outputDir = key
      of "preset":
        if not Presets.hasKey(key):
          error &"Unknown preset: {key}. Available: viral, podcast, tutorial, interview, tiktok, youtube, instagram"
        presetName = key
      expecting = ""

  # Validate arguments
  if inputPath == "":
    error "A video file is required. Usage: honeyclip analyze file model [options]"

  if not noTranscript and model == "":
    error "A whisper model is required (or use --no-transcript). Find models at: https://huggingface.co/ggerganov/whisper.cpp"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  if not noTranscript and model != "" and not fileExists(model):
    error &"Model not found: {model}"

  # Determine output paths
  let effectiveOutputDir = if outputDir != "": outputDir else: splitFile(inputPath).dir
  let engagePath = generateOutputPath(inputPath, "", ".engage.json")
  let projectPath = generateOutputPath(inputPath, "", ".honeyclip")

  if dryRun:
    echo "Dry run - would perform these steps:"
    if not noTranscript:
      echo &"  1. Extract transcript from {inputPath}"
    else:
      echo "  1. Skip transcript (--no-transcript)"
    if not noFaces:
      echo "  2. Detect faces"
    else:
      echo "  2. Skip face detection (--no-faces)"
    echo "  3. Analyze engagement (audio, motion" & (if not noTranscript: ", speech" else: "") & ")"
    echo "  4. Detect clip boundaries"
    echo &"  5. Save: {engagePath}"
    echo &"  6. Save: {projectPath}"
    quit(0)

  var bar = initBar(BarType.modern)
  defer: bar.destroy()

  # Check cache
  var timeline: EngagementTimeline
  if not fresh and fileExists(engagePath):
    if stdin.isatty():
      echo &"Using cached engagement data: {engagePath}"
      echo "(Use --fresh to re-analyze)"
    # Load cached engagement data
    let engageData = parseFile(engagePath)
    timeline.duration = engageData["duration_ms"].getBiggestInt()
    timeline.avgScore = engageData["avg_score"].getFloat().float32
    timeline.hookCount = engageData["hook_count"].getInt(0)

    for seg in engageData["segments"]:
      timeline.segments.add(EngagementSegment(
        startMs: seg["start_ms"].getBiggestInt(),
        endMs: seg["end_ms"].getBiggestInt(),
        score: seg["score"].getFloat().float32,
        scoreRelative: seg["score_relative"].getFloat().float32,
        scoreAbsolute: seg["score_absolute"].getFloat().float32,
        audioScore: seg["audio_score"].getFloat().float32,
        motionScore: seg["motion_score"].getFloat().float32,
        speechScore: seg["speech_score"].getFloat().float32,
        text: seg["text"].getStr(""),
        hasHook: seg["has_hook"].getBool(false),
        faceCount: seg["face_count"].getInt(0),
        speaker: seg["speaker"].getInt(-1)
      ))
  else:
    # Full analysis pipeline
    # Step 1: Extract transcript
    var transcript: Transcript
    if not noTranscript:
      bar.start(100.0, "Extracting transcript")
      try:
        transcript = extractTranscript(inputPath, model, "", "")
      except IOError as e:
        error &"Failed to extract transcript: {e.msg}"
      bar.`end`()

    # Step 2: Open container
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

    # Step 3: Analyze engagement
    try:
      var params = defaultEngagementParams()
      if presetName != "":
        let preset = Presets[presetName]
        params.audioWeight = preset.audioWeight
        params.motionWeight = preset.motionWeight
        params.speechWeight = preset.speechWeight
      let patterns = loadBuiltinPatterns()
      timeline = analyzeEngagement(bar, container, inputPath, transcript, tb,
                                    params, patterns, not noFaces)
    except Exception as e:
      error &"Failed to analyze engagement: {e.msg}"

    # Save engagement JSON
    let jsonStr = engagementModule.timelineToJson(timeline)
    writeFile(engagePath, jsonStr)
    if stdin.isatty():
      echo &"Created: {engagePath}"

  # Step 4: Detect scene changes
  bar.start(100.0, "Detecting scene changes")
  let sceneChanges = extractSceneChanges(inputPath)
  bar.`end`()

  # Step 5: Detect clip boundaries
  bar.start(100.0, "Detecting clip boundaries")
  var detectionParams = defaultClipDetectionParams()
  let boundaries = detectBoundaries(timeline, sceneChanges, detectionParams)
  var detectedClips = detectClips(timeline, boundaries, detectionParams)
  bar.`end`()

  # Step 6: Rank clips
  bar.start(float(detectedClips.len), "Ranking clips")
  var rankingParams = defaultClipRankingParams()
  rankingParams.topN = topN
  let rankedClips = rankClips(detectedClips, rankingParams)
  bar.`end`()

  # Step 7: Create/update project file
  var project = newProject(inputPath)
  for clip in rankedClips:
    project.clips.add(ProjectClip(
      startMs: clip.startMs,
      endMs: clip.endMs,
      engagementScore: clip.engagementScore,
      adjustedScore: clip.adjustedScore,
      text: clip.text,
      rank: clip.rank
    ))
  saveProject(project, projectPath)
  if stdin.isatty():
    echo &"Created: {projectPath}"

  # Step 8: Print results and prompt
  printTopClips(rankedClips, topN)

  let action = promptNextAction()
  case action:
  of "export":
    echo "Run: honeyclip export --project \"" & projectPath & "\" --render"
  of "nle":
    echo "Run: honeyclip export --project \"" & projectPath & "\" --nle premiere"
  else:
    echo "Analysis complete."
