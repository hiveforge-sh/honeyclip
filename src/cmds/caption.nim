import std/[os, strutils, strformat, parseopt, json]
import ../transcript/[types, grouping, formats, extract]
import ../render/captions
import ../exports/[fcp7, fcp11]
import ../log
import ../media
import ../util/fun

const helpText = """usage: honeyclip caption <subcommand> [options]

Subcommands:
  burn    Burn captions into video
  export  Export captions to NLE project

Common options:
  --input, -i <file>      Input video or JSON transcript
  --transcript, -t <file> Transcript JSON file (if input is video)
  --style <preset>        Style preset: traditional, modern (default: traditional)
  --highlight             Enable word-by-word highlight effect

Burn options:
  --output, -o <file>     Output video file (required)
  --font <path>           Custom font file path
  --fontsize <size>       Font size in pixels (default: 60)
  --color <hex>           Text color (default: #ffffff)
  --position <pos>        Position: bottom, center, top (default: bottom)
  --outline               Enable outline (default: on for traditional)
  --no-outline            Disable outline
  --shadow                Enable drop shadow
  --box                   Enable background box
  --box-color <color>     Background box color (default: black@0.6)

Export options:
  --output, -o <file>     Output project file (required)
  --format <fmt>          Export format: fcp7, fcpxml (default: fcp7)
  --absolute-paths        Use absolute media paths (default: relative)
"""

proc parseCaptionStyle*(args: seq[string]): CaptionStyle =
  ## Parse caption style from CLI args
  var styleName = "traditional"
  var fontSize = 60
  var color = "#ffffff"
  var position = cpBottomCenter
  var outline = -1  # -1 = use preset default, 0 = disabled, 1 = enabled
  var shadow = false
  var box = false
  var boxColor = "black@0.6"
  var fontPath = ""
  var highlight = false

  var expecting = ""
  for rawKey in args:
    let key = handleKey(rawKey)
    case key:
    of "--style":
      expecting = "style"
    of "--fontsize":
      expecting = "fontsize"
    of "--color":
      expecting = "color"
    of "--position":
      expecting = "position"
    of "--outline":
      outline = 1
    of "--no-outline":
      outline = 0
    of "--shadow":
      shadow = true
    of "--box":
      box = true
    of "--box-color":
      expecting = "box-color"
    of "--font":
      expecting = "font"
    of "--highlight":
      highlight = true
    else:
      if not key.startsWith("--"):
        case expecting:
        of "style":
          styleName = key
        of "fontsize":
          try:
            fontSize = parseInt(key)
          except ValueError:
            error &"Invalid fontsize: {key}"
        of "color":
          color = key
        of "position":
          case key:
          of "bottom": position = cpBottomCenter
          of "center": position = cpCenter
          of "top": position = cpTopCenter
          else:
            error &"Invalid position: {key}. Choices: bottom, center, top"
        of "box-color":
          boxColor = key
        of "font":
          fontPath = key
        expecting = ""

  # Start with preset
  result = getPreset(styleName)

  # Override with CLI options
  if fontSize != 60:
    result.fontSize = fontSize
  if color != "#ffffff":
    result.color = color
  result.position = position
  if outline >= 0:
    result.outline = (outline == 1)
  if shadow:
    result.shadow = true
  if box:
    result.backgroundBox = true
    result.boxColor = boxColor
  if fontPath != "":
    result.fontPath = fontPath
  result.highlightEnabled = highlight

proc loadTranscriptFromJSON*(path: string): Transcript =
  ## Load transcript from JSON file
  let jsonContent = readFile(path)
  let root = parseJson(jsonContent)

  result = newTranscript()
  result.language = root["language"].getStr("")
  result.duration = root["duration_ms"].getInt()

  # Load words
  for wordNode in root["words"]:
    var word: Word
    word.text = wordNode["text"].getStr()
    word.startMs = wordNode["start_ms"].getInt()
    word.endMs = wordNode["end_ms"].getInt()
    word.confidence = wordNode["confidence"].getFloat()
    word.speaker = int8(wordNode["speaker"].getInt())
    if wordNode.hasKey("is_non_speech") and wordNode["is_non_speech"].getBool():
      word.isNonSpeech = true
      word.label = wordNode["label"].getStr()
    result.words.add(word)

proc loadCaptionsFromArgs(inputPath, transcriptPath: string, maxChars: int): seq[Caption] =
  ## Load captions from input video or transcript JSON
  var transcript: Transcript

  if transcriptPath != "":
    # Load from explicit transcript file
    if not fileExists(transcriptPath):
      error &"Transcript file not found: {transcriptPath}"
    transcript = loadTranscriptFromJSON(transcriptPath)
  elif inputPath.endsWith(".json"):
    # Input is a transcript file
    if not fileExists(inputPath):
      error &"Input file not found: {inputPath}"
    transcript = loadTranscriptFromJSON(inputPath)
  else:
    # Would need to extract transcript from video - not implemented in this command
    error "Input video transcript extraction not supported. Use 'honeyclip transcript' first, then pass JSON with --transcript or as input"

  # Group into captions
  result = groupIntoCaptions(transcript, maxChars)

proc runCaptionBurn(args: seq[string]) =
  ## Burn captions into video
  var inputPath = ""
  var outputPath = ""
  var transcriptPath = ""
  var maxChars = 42

  var expecting = ""
  for rawKey in args:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo helpText
      quit(0)
    of "--input", "-i":
      expecting = "input"
    of "--output", "-o":
      expecting = "output"
    of "--transcript", "-t":
      expecting = "transcript"
    of "--max-chars":
      expecting = "max-chars"
    else:
      if not key.startsWith("--"):
        case expecting:
        of "":
          if inputPath == "":
            inputPath = key
          elif outputPath == "":
            outputPath = key
        of "input":
          inputPath = key
        of "output":
          outputPath = key
        of "transcript":
          transcriptPath = key
        of "max-chars":
          try:
            maxChars = parseInt(key)
          except ValueError:
            error &"Invalid max-chars: {key}"
        expecting = ""

  # Validate
  if inputPath == "":
    error "Missing required argument: --input <file>"
  if outputPath == "":
    error "Missing required argument: --output <file>"
  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Load captions
  let captions = loadCaptionsFromArgs(inputPath, transcriptPath, maxChars)
  if captions.len == 0:
    error "No captions found in transcript"

  # Get video dimensions from input
  let mediaInfo = initMediaInfo(inputPath)
  let (width, height) = mediaInfo.getRes()

  # Parse style options
  let style = parseCaptionStyle(args)

  # Build config
  let config = CaptionBurnConfig(
    style: style,
    width: width,
    height: height,
    useHighlight: style.highlightEnabled,
    tempDir: ""
  )

  # Burn captions
  conwrite(&"Burning captions into {outputPath}...")
  let exitCode = burnCaptions(inputPath, outputPath, captions, config)

  if exitCode == 0:
    conwrite("")
    echo &"Created: {outputPath}"
  else:
    error &"FFmpeg failed with exit code: {exitCode}"

proc runCaptionExport(args: seq[string]) =
  ## Export captions to NLE project
  var inputPath = ""
  var outputPath = ""
  var transcriptPath = ""
  var format = "fcp7"
  var absolutePaths = false
  var maxChars = 42

  var expecting = ""
  for rawKey in args:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo helpText
      quit(0)
    of "--input", "-i":
      expecting = "input"
    of "--output", "-o":
      expecting = "output"
    of "--transcript", "-t":
      expecting = "transcript"
    of "--format":
      expecting = "format"
    of "--absolute-paths":
      absolutePaths = true
    of "--max-chars":
      expecting = "max-chars"
    else:
      if not key.startsWith("--"):
        case expecting:
        of "":
          if inputPath == "":
            inputPath = key
          elif outputPath == "":
            outputPath = key
        of "input":
          inputPath = key
        of "output":
          outputPath = key
        of "transcript":
          transcriptPath = key
        of "format":
          format = key.toLowerAscii()
        of "max-chars":
          try:
            maxChars = parseInt(key)
          except ValueError:
            error &"Invalid max-chars: {key}"
        expecting = ""

  # Validate
  if inputPath == "":
    error "Missing required argument: --input <file>"
  if outputPath == "":
    error "Missing required argument: --output <file>"
  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"
  if format notin ["fcp7", "fcpxml"]:
    error &"Invalid format: {format}. Choices: fcp7, fcpxml"

  # Load captions
  let captions = loadCaptionsFromArgs(inputPath, transcriptPath, maxChars)
  if captions.len == 0:
    error "No captions found in transcript"

  # Get media info for video path (if input is video)
  var videoPath = inputPath
  if transcriptPath != "":
    videoPath = inputPath  # Input is the video when --transcript is separate
  elif inputPath.endsWith(".json"):
    error "When input is JSON transcript, you must provide video path with --input <video> --transcript <json>"

  # Parse style for export
  let style = parseCaptionStyle(args)

  # Export based on format
  conwrite(&"Exporting captions to {format.toUpperAscii()} format...")

  case format:
  of "fcp7":
    writeCaptionOnlyFCP7(videoPath, captions, style, outputPath)
    conwrite("")
    echo &"Created: {outputPath}"
  of "fcpxml":
    writeCaptionOnlyFCPXML(videoPath, captions, style, outputPath)
    conwrite("")
    echo &"Created: {outputPath}"
  else:
    error &"Unknown format: {format}"

proc main*(cArgs: seq[string]) =
  ## Caption command entry point
  if cArgs.len == 0 or cArgs[0] in ["--help", "-h"]:
    echo helpText
    quit(0)

  let subcommand = cArgs[0]
  let subArgs = if cArgs.len > 1: cArgs[1..^1] else: @[]

  case subcommand:
  of "burn":
    runCaptionBurn(subArgs)
  of "export":
    runCaptionExport(subArgs)
  of "--help", "-h":
    echo helpText
  else:
    error &"Unknown subcommand: {subcommand}. Available: burn, export"
