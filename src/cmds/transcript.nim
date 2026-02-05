import std/[strformat, strutils, os, tables]
import ../log
import ../util/fun
import ../transcript/[types, extract, formats, diarization, grouping]

proc countSpeakers*(transcript: Transcript): int =
  ## Count unique speakers in transcript (excluding -1 unassigned)
  var seen: set[int8]
  for word in transcript.words:
    if word.speaker >= 0 and word.speaker < 128:
      seen.incl(int8(word.speaker))
  result = seen.card

proc createBackup*(filePath: string) =
  ## Create backup of file if it exists (rename to .bak)
  ## If .bak already exists, overwrite it
  if fileExists(filePath):
    let bakPath = filePath & ".bak"
    if fileExists(bakPath):
      removeFile(bakPath)
    moveFile(filePath, bakPath)

proc generateOutputPath*(inputPath: string, outputDir: string, ext: string): string =
  ## Generate output file path
  ## If outputDir is empty, use same directory as input
  let (dir, name, _) = splitFile(inputPath)
  let targetDir = if outputDir != "": outputDir else: dir
  result = targetDir / name & ext

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var outputDir: string = ""
  var format: string = ""
  var maxChars: int = 42
  var singleSpeaker: bool = false
  var speakerMapPath: string = ""
  var speakerColors: bool = false
  var language: string = ""
  var vadModel: string = ""
  var confidenceThreshold: float = 0.5
  var compact: bool = false
  var dryRun: bool = false
  var useStdout: bool = false
  var noBackup: bool = false
  var isDebug: bool = false

  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip transcript file model [options]

Extract transcript with word timestamps, speaker diarization, export to SRT/VTT/JSON

Options:
  -o, --output DIR        Output directory (default: same as input)
  --format FORMAT         Output format for --stdout (srt, vtt, json)
  --max-chars NUM         Max characters per caption line (default: 42)
  --single-speaker        Skip speaker diarization
  --speaker-map FILE      JSON file mapping speaker IDs to names
  --speaker-colors        Enable VTT speaker colors (default: off)
  --language LANG         Override language detection
  --vad-model PATH        VAD model for whisper
  --confidence NUM        Confidence threshold for [?] markers (default: 0.5)
  --compact               Minified JSON output
  --dry-run               Preview transcript without writing files
  --stdout                Output to terminal (requires --format)
  --no-backup             Don't create .bak files when overwriting
  --debug                 Show debug information
  --help                  Show this help
"""
      quit(0)
    of "--debug":
      isDebug = true
    of "--single-speaker":
      singleSpeaker = true
    of "--speaker-colors":
      speakerColors = true
    of "--compact":
      compact = true
    of "--dry-run":
      dryRun = true
    of "--stdout":
      useStdout = true
    of "--no-backup":
      noBackup = true
    of "-o", "--output":
      expecting = "output"
    of "--format":
      expecting = "format"
    of "--max-chars":
      expecting = "max-chars"
    of "--speaker-map":
      expecting = "speaker-map"
    of "--language":
      expecting = "language"
    of "--vad-model":
      expecting = "vad-model"
    of "--confidence":
      expecting = "confidence"
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
        outputDir = key
      of "format":
        format = key.toLowerAscii()
      of "max-chars":
        try:
          maxChars = parseInt(key)
        except ValueError:
          error &"Invalid max-chars value: {key}"
      of "speaker-map":
        speakerMapPath = key
      of "language":
        language = key
      of "vad-model":
        vadModel = key
      of "confidence":
        try:
          confidenceThreshold = parseFloat(key)
        except ValueError:
          error &"Invalid confidence value: {key}"
      expecting = ""

  # Validate arguments
  if inputPath == "":
    error "A media file is required. Usage: honeyclip transcript file model [options]"

  if model == "":
    model = findWhisperModel()
    if model == "":
      error "No whisper model found. Download one to ~/.cache/whisper/ or specify path.\nFind models at: https://huggingface.co/ggerganov/whisper.cpp"
    else:
      echo &"Using whisper model: {extractFilename(model)}"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  if not fileExists(model):
    error &"Model not found: {model}\nDownload from: https://huggingface.co/ggerganov/whisper.cpp"

  if useStdout and format == "":
    error "--stdout requires --format (srt, vtt, or json)"

  if format != "" and format notin ["srt", "vtt", "json"]:
    error &"Invalid format: {format}. Choices: srt, vtt, json"

  if maxChars < 10 or maxChars > 200:
    error &"Invalid max-chars value: {maxChars}. Must be between 10 and 200"

  if confidenceThreshold < 0.0 or confidenceThreshold > 1.0:
    error &"Invalid confidence value: {confidenceThreshold}. Must be between 0.0 and 1.0"

  # Load speaker map if provided
  var speakerMap = initTable[int, string]()
  if speakerMapPath != "":
    if not fileExists(speakerMapPath):
      warning &"Speaker map file not found: {speakerMapPath}"
    else:
      speakerMap = loadSpeakerMap(speakerMapPath)
      if isDebug:
        debug &"Loaded speaker map with {speakerMap.len} entries"

  # Extract transcript
  if not dryRun:
    conwrite(&"Extracting transcript from {inputPath}...")

  var transcript: Transcript
  try:
    transcript = extractTranscript(inputPath, model, language, vadModel)
  except IOError as e:
    error &"Failed to extract transcript: {e.msg}"

  if transcript.words.len == 0:
    error "No transcript content extracted"

  # Run diarization unless --single-speaker
  if not singleSpeaker:
    if checkDiarizationAvailable():
      if not dryRun:
        conwrite("Running speaker diarization...")
      try:
        let diarization = diarizeAudio(inputPath, maxSpeakers = 10)
        applySpeakersToTranscript(transcript, diarization)
        if isDebug:
          debug &"Diarization found {diarization.numSpeakers} speakers"
      except IOError as e:
        warning &"Diarization failed: {e.msg}. Continuing without speaker labels."
    else:
      warning "pyannote.audio not available. Skipping diarization. Install via: pip install pyannote.audio torch"

  # Group into captions
  let captions = groupIntoCaptions(transcript, maxChars)

  # Output based on mode
  if dryRun:
    # Print preview summary
    echo ""
    echo "Transcript preview:"
    echo &"  Duration: {float(transcript.duration) / 1000.0:.1f}s"
    echo &"  Words: {transcript.words.len}"
    echo &"  Speakers: {countSpeakers(transcript)}"
    echo &"  Captions: {captions.len}"
    echo &"  Language: {transcript.language}"
    echo ""

    # Show first few captions as preview
    let previewCount = min(5, captions.len)
    echo &"First {previewCount} captions:"
    for i in 0 ..< previewCount:
      let c = captions[i]
      let startTime = formatTimestamp(c.startMs, usePeriod = true)
      let endTime = formatTimestamp(c.endMs, usePeriod = true)
      echo &"  [{startTime} --> {endTime}] {c.text}"

  elif useStdout:
    # Output to terminal
    case format:
    of "srt":
      exportSRT(captions, "-", confidenceThreshold = confidenceThreshold)
    of "vtt":
      exportVTT(captions, "-", speakerColors, confidenceThreshold = confidenceThreshold)
    of "json":
      exportJSON(transcript, captions, "-", compact)
    else:
      discard

  else:
    # Default: output all three formats
    let basePath = generateOutputPath(inputPath, outputDir, "")

    # Create backup files if needed
    if not noBackup:
      createBackup(basePath & ".srt")
      createBackup(basePath & ".vtt")
      createBackup(basePath & ".json")

    # Ensure output directory exists
    if outputDir != "" and not dirExists(outputDir):
      createDir(outputDir)

    # Export all formats
    exportSRT(captions, basePath & ".srt", confidenceThreshold = confidenceThreshold)
    exportVTT(captions, basePath & ".vtt", speakerColors, confidenceThreshold = confidenceThreshold)
    exportJSON(transcript, captions, basePath & ".json", compact)

    conwrite("")
    echo &"Created: {basePath}.srt, .vtt, .json"
