## Caption styling system with ASS subtitle generation
##
## This module provides:
## - CaptionStyle type for configuring caption appearance
## - Style presets (traditional, modern/tiktok)
## - Speaker color palette for visual differentiation
## - ASS subtitle file generation with word-level timing (karaoke tags)

import std/[strformat, strutils, os, random, osproc]
import ../transcript/grouping

type
  CaptionPosition* = enum
    ## Position of caption text on screen
    cpBottomCenter = "bottom-center"  # Traditional subtitle position (default)
    cpTopCenter = "top-center"        # Avoid bottom UI elements
    cpCenter = "center"               # TikTok/Reels style

  CaptionStyle* = object
    ## Complete styling configuration for captions

    # Font settings
    fontPath*: string        # Full path to TTF/OTF file
    fontName*: string        # Font name for NLE export
    fontSize*: int           # Font size in pixels (48-72 typical)

    # Colors
    color*: string           # Primary text color (hex #RRGGBB)
    speakerColors*: seq[string]  # Override color per speaker

    # Outline
    outline*: bool
    outlineWidth*: int       # Width in pixels (3-5 typical)
    outlineColor*: string    # Hex color

    # Shadow
    shadow*: bool
    shadowX*: int            # Horizontal offset in pixels
    shadowY*: int            # Vertical offset in pixels
    shadowColor*: string     # Hex color

    # Background box
    backgroundBox*: bool
    boxColor*: string        # Color with alpha (e.g., "black@0.6")
    boxPadding*: int         # Padding in pixels

    # Position
    position*: CaptionPosition
    marginBottom*: int       # Distance from bottom edge in pixels
    marginTop*: int          # Distance from top edge in pixels

    # Word highlighting
    highlightEnabled*: bool  # Enable word-by-word reveal via karaoke tags

const
  # Speaker color palette - visually distinct colors
  SpeakerColorPalette* = [
    "#00d4ff",  # Speaker 0: Cyan
    "#ff6b6b",  # Speaker 1: Red/Pink
    "#4ecb71",  # Speaker 2: Green
    "#ffe66d",  # Speaker 3: Yellow
    "#a29bfe"   # Speaker 4: Purple
  ]

proc getSpeakerColor*(speaker: int): string =
  ## Get color for speaker index
  ## Returns white (#ffffff) for invalid/unassigned speakers
  if speaker >= 0 and speaker < SpeakerColorPalette.len:
    result = SpeakerColorPalette[speaker]
  else:
    result = "#ffffff"

proc getDefaultFontPath*(): string =
  ## Get platform-specific default font path
  when defined(windows):
    result = "C:/Windows/Fonts/arialbd.ttf"
  elif defined(linux):
    result = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
  elif defined(macosx):
    result = "/Library/Fonts/Arial Bold.ttf"
  else:
    result = ""

proc getPreset*(name: string): CaptionStyle =
  ## Get predefined caption style
  ## Available presets: "traditional", "modern", "tiktok" (alias for modern)

  case name
  of "traditional":
    result = CaptionStyle(
      fontPath: getDefaultFontPath(),
      fontName: "Arial Bold",
      fontSize: 60,
      color: "#ffffff",
      speakerColors: @[],
      outline: true,
      outlineWidth: 4,
      outlineColor: "#000000",
      shadow: false,
      shadowX: 0,
      shadowY: 0,
      shadowColor: "#000000",
      backgroundBox: false,
      boxColor: "",
      boxPadding: 0,
      position: cpBottomCenter,
      marginBottom: 150,
      marginTop: 0,
      highlightEnabled: false
    )

  of "modern", "tiktok":
    result = CaptionStyle(
      fontPath: getDefaultFontPath(),
      fontName: "Arial Bold",
      fontSize: 72,
      color: "#000000",
      speakerColors: @[],
      outline: false,
      outlineWidth: 0,
      outlineColor: "#000000",
      shadow: false,
      shadowX: 0,
      shadowY: 0,
      shadowColor: "#000000",
      backgroundBox: true,
      boxColor: "yellow@0.8",
      boxPadding: 20,
      position: cpCenter,
      marginBottom: 0,
      marginTop: 0,
      highlightEnabled: false
    )

  else:
    # Default to traditional
    result = getPreset("traditional")

# ASS Format Utilities

proc formatASSTime*(ms: int64): string =
  ## Convert milliseconds to ASS timestamp format (H:MM:SS.cc)
  ## ASS uses centiseconds (hundredths of a second)
  let totalSeconds = ms div 1000
  let centiseconds = (ms mod 1000) div 10
  let hours = totalSeconds div 3600
  let minutes = (totalSeconds mod 3600) div 60
  let seconds = totalSeconds mod 60

  result = &"{hours}:{minutes:02}:{seconds:02}.{centiseconds:02}"

proc escapeASSText*(text: string): string =
  ## Escape special ASS characters
  result = text
  result = result.replace("\\", "\\\\")
  result = result.replace("{", "\\{")
  result = result.replace("}", "\\}")
  result = result.replace("\n", "\\n")

proc colorToASS*(hexColor: string): string =
  ## Convert hex color (#RRGGBB) to ASS format (&HAABBGGRR)
  ## ASS uses BGR order with alpha prefix
  var color = hexColor
  if color.startsWith("#"):
    color = color[1..^1]

  # Parse RGB
  let r = parseHexInt(color[0..1])
  let g = parseHexInt(color[2..3])
  let b = parseHexInt(color[4..5])

  # Convert to BGR format with alpha=00 (opaque)
  result = &"&H00{b:02X}{g:02X}{r:02X}"

proc getASSAlignment*(pos: CaptionPosition): int =
  ## Get ASS alignment value for position
  ## ASS alignment: 1-3 bottom, 4-6 middle, 7-9 top (left-center-right)
  case pos
  of cpBottomCenter: 2
  of cpCenter: 5
  of cpTopCenter: 8

# ASS Generation

proc generateASSHeader*(style: CaptionStyle, width: int, height: int): string =
  ## Generate ASS file header with style definition
  result = "[Script Info]\n"
  result.add(&"Title: honeyclip captions\n")
  result.add(&"ScriptType: v4.00+\n")
  result.add(&"PlayResX: {width}\n")
  result.add(&"PlayResY: {height}\n")
  result.add(&"WrapStyle: 0\n\n")

  result.add("[V4+ Styles]\n")
  result.add("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n")

  # Build style line
  let styleName = "Default"
  let fontname = style.fontName
  let fontsize = style.fontSize
  let primaryColor = colorToASS(style.color)
  let secondaryColor = colorToASS(style.color)  # Used for karaoke
  let outlineColor = colorToASS(style.outlineColor)

  # Background color (for text box)
  var backColor = "&H00000000"  # Transparent by default
  if style.backgroundBox and style.boxColor.len > 0:
    # Parse color@alpha format
    let parts = style.boxColor.split("@")
    if parts.len == 2:
      let boxColorHex = parts[0]
      let alpha = parseFloat(parts[1])
      let alphaHex = int(255 * (1.0 - alpha))  # ASS alpha: 00=opaque, FF=transparent

      # Convert named colors to hex
      var colorHex = boxColorHex
      if colorHex == "yellow":
        colorHex = "#ffff00"
      elif colorHex == "black":
        colorHex = "#000000"
      elif colorHex == "white":
        colorHex = "#ffffff"

      if colorHex.startsWith("#"):
        colorHex = colorHex[1..^1]

      let r = parseHexInt(colorHex[0..1])
      let g = parseHexInt(colorHex[2..3])
      let b = parseHexInt(colorHex[4..5])
      backColor = &"&H{alphaHex:02X}{b:02X}{g:02X}{r:02X}"

  let bold = -1  # True
  let italic = 0
  let underline = 0
  let strikeout = 0
  let scaleX = 100
  let scaleY = 100
  let spacing = 0
  let angle = 0.0
  let borderStyle = if style.backgroundBox: 3 else: 1  # 1=outline, 3=opaque box
  let outline = if style.outline: style.outlineWidth else: 0
  let shadow = if style.shadow: 2 else: 0
  let alignment = getASSAlignment(style.position)

  # Margins
  let marginL = 0
  let marginR = 0
  var marginV = 0
  if style.position == cpBottomCenter:
    marginV = style.marginBottom
  elif style.position == cpTopCenter:
    marginV = style.marginTop

  let encoding = 1  # UTF-8

  result.add(&"Style: {styleName},{fontname},{fontsize},{primaryColor},{secondaryColor},{outlineColor},{backColor},{bold},{italic},{underline},{strikeout},{scaleX},{scaleY},{spacing},{angle},{borderStyle},{outline},{shadow},{alignment},{marginL},{marginR},{marginV},{encoding}\n\n")

proc generateASSDialogue*(caption: Caption, style: CaptionStyle, styleName: string = "Default"): string =
  ## Generate ASS dialogue line for a caption
  ## Includes word-level timing via karaoke tags if highlightEnabled
  let startTime = formatASSTime(caption.startMs)
  let endTime = formatASSTime(caption.endMs)

  var text = ""

  # Apply speaker color if specified
  if caption.speaker >= 0 and style.speakerColors.len > 0:
    if caption.speaker < style.speakerColors.len:
      let speakerColor = colorToASS(style.speakerColors[caption.speaker])
      text.add(&"{{\\c{speakerColor}}}")
  elif caption.speaker >= 0:
    # Use default speaker color palette
    let speakerColor = colorToASS(getSpeakerColor(caption.speaker))
    if speakerColor != colorToASS("#ffffff"):  # Only add if not default white
      text.add(&"{{\\c{speakerColor}}}")

  # Build text with karaoke tags if highlighting enabled
  if style.highlightEnabled and caption.words.len > 0:
    for i, word in caption.words:
      let durationMs = word.endMs - word.startMs
      let durationCs = durationMs div 10  # Convert to centiseconds
      text.add(&"{{\\k{durationCs}}}{escapeASSText(word.text)}")
      if i < caption.words.len - 1:
        text.add(" ")
  else:
    text = escapeASSText(caption.text)

  result = &"Dialogue: 0,{startTime},{endTime},{styleName},,0,0,0,,{text}"

proc generateASS*(captions: seq[Caption], style: CaptionStyle, width: int = 1920, height: int = 1080): string =
  ## Generate complete ASS subtitle file
  result = generateASSHeader(style, width, height)

  result.add("[Events]\n")
  result.add("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")

  for caption in captions:
    result.add(generateASSDialogue(caption, style))
    result.add("\n")

proc writeASSFile*(captions: seq[Caption], style: CaptionStyle, outputPath: string, width: int = 1920, height: int = 1080) =
  ## Write ASS subtitle file to disk
  let content = generateASS(captions, style, width, height)
  writeFile(outputPath, content)

# FFmpeg Filter Integration

proc escapeFilterPath*(path: string): string =
  ## Escape path for FFmpeg filter syntax
  ## Windows: C:/path -> C\\:/path
  ## Backslashes: \\ -> \\\\
  ## Single quotes: ' -> \\'
  result = path
  result = result.replace("\\", "\\\\")
  result = result.replace(":", "\\:")
  result = result.replace("'", "\\'")

proc buildASSFilter*(assPath: string): string =
  ## Build FFmpeg ass filter string
  ## Example output: "ass=filename='C\\:/temp/captions.ass'"
  let escapedPath = escapeFilterPath(assPath)
  result = &"ass=filename='{escapedPath}'"

proc escapeDrawtextText*(text: string): string =
  ## Escape text for drawtext filter
  result = text
  result = result.replace("\\", "\\\\")
  result = result.replace("'", "\\'")
  result = result.replace(":", "\\:")
  result = result.replace("\n", "\\n")

proc buildDrawtextFilter*(text: string, style: CaptionStyle, startMs, endMs: int64): string =
  ## Build FFmpeg drawtext filter for simple text overlay
  ## No word highlighting - for basic caption burning
  let startSec = float(startMs) / 1000.0
  let endSec = float(endMs) / 1000.0
  let escapedText = escapeDrawtextText(text)
  let escapedFontPath = escapeFilterPath(style.fontPath)

  # Build filter parts
  var parts: seq[string] = @[]
  parts.add(&"fontfile='{escapedFontPath}'")
  parts.add(&"fontsize={style.fontSize}")
  parts.add(&"fontcolor={style.color}")
  parts.add("x=(w-text_w)/2")  # Center horizontally

  # Y position based on style
  case style.position
  of cpBottomCenter:
    parts.add(&"y=h-{style.marginBottom}")
  of cpCenter:
    parts.add("y=(h-text_h)/2")
  of cpTopCenter:
    parts.add(&"y={style.marginTop}")

  # Outline
  if style.outline:
    parts.add(&"borderw={style.outlineWidth}")
    parts.add(&"bordercolor={style.outlineColor}")

  # Shadow
  if style.shadow:
    parts.add(&"shadowx={style.shadowX}")
    parts.add(&"shadowy={style.shadowY}")
    parts.add(&"shadowcolor={style.shadowColor}")

  # Background box
  if style.backgroundBox:
    parts.add("box=1")
    parts.add(&"boxcolor={style.boxColor}")
    parts.add(&"boxborderw={style.boxPadding}")

  # Text and timing
  parts.add(&"text='{escapedText}'")
  parts.add(&"enable='between(t,{startSec},{endSec})'")

  result = "drawtext=" & parts.join(":")

# Caption Burning Integration

type
  CaptionBurnConfig* = object
    ## Configuration for burning captions into video
    style*: CaptionStyle
    width*: int            # Video width in pixels
    height*: int           # Video height in pixels
    useHighlight*: bool    # Enable word-by-word reveal (default false)
    tempDir*: string       # Where to write ASS file (default system temp)

proc prepareCaptionFilter*(captions: seq[Caption], config: CaptionBurnConfig): tuple[filter: string, tempFile: string] =
  ## Generate ASS file and filter string for caption burning
  ## Returns (filter string, temp file path)
  ## Caller is responsible for cleanup of temp file

  # Generate unique temp filename
  randomize()
  let randomSuffix = rand(100000..999999)
  let tempDir = if config.tempDir.len > 0: config.tempDir else: getTempDir()
  let tempFile = joinPath(tempDir, &"honeyclip_captions_{randomSuffix}.ass")

  # Generate and write ASS content
  var style = config.style
  style.highlightEnabled = config.useHighlight
  let assContent = generateASS(captions, style, config.width, config.height)
  writeFile(tempFile, assContent)

  # Build filter string
  let filterString = buildASSFilter(tempFile)

  result = (filterString, tempFile)

proc cleanupCaptionTemp*(tempFile: string) =
  ## Remove temp ASS file
  ## Ignores errors if file doesn't exist
  try:
    if fileExists(tempFile):
      removeFile(tempFile)
  except:
    discard

proc burnCaptions*(inputPath, outputPath: string, captions: seq[Caption], config: CaptionBurnConfig, ffmpegPath: string = "ffmpeg"): int =
  ## Burn captions into video using FFmpeg
  ## Returns FFmpeg exit code (0 = success)

  # Generate ASS file and filter string
  let (filterString, tempFile) = prepareCaptionFilter(captions, config)

  try:
    # Build FFmpeg command
    let args = @[
      "-i", inputPath,
      "-vf", filterString,
      "-c:a", "copy",  # Copy audio unchanged
      "-y",            # Overwrite output
      outputPath
    ]

    # Execute FFmpeg
    let process = startProcess(
      ffmpegPath,
      args = args,
      options = {poUsePath, poParentStreams}
    )

    result = process.waitForExit()
    process.close()
  finally:
    # Clean up temp file
    cleanupCaptionTemp(tempFile)
