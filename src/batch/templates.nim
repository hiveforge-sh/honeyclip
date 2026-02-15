import std/[strformat, os]
import toml_serialization

type
  WatermarkConfig* = object
    ## Watermark overlay configuration
    enabled*: bool             ## Enable watermark overlay
    imagePath*: string         ## Path to logo PNG/image
    position*: string          ## Position: "top-left", "top-right", "bottom-left", "bottom-right", "center"
    offsetX*: int              ## Pixel offset from edge (default 10)
    offsetY*: int              ## Pixel offset from edge (default 10)
    scale*: float              ## Fraction of video width (default 0.1)
    opacity*: float            ## 0.0-1.0 transparency (default 1.0)

  IntroOutroConfig* = object
    ## Intro/outro clip configuration
    introPath*: string         ## Path to intro clip (empty = none)
    outroPath*: string         ## Path to outro clip (empty = none)

  CaptionStyleConfig* = object
    ## Caption style override configuration
    preset*: string            ## Preset name: "traditional", "modern", "tiktok"
    fontPath*: string          ## Custom font path override
    fontSize*: int             ## Size override (0 = use preset default)
    color*: string             ## Hex color override ("" = use preset)
    position*: string          ## Position: "bottom", "center", "top" ("" = use preset)
    outline*: bool             ## Outline enabled (default false)
    shadow*: bool              ## Shadow enabled (default false)
    backgroundBox*: bool       ## Background box enabled (default false)

  BrandConfig* = object
    ## Brand template configuration
    watermark*: WatermarkConfig
    introOutro*: IntroOutroConfig
    captionStyle*: CaptionStyleConfig

  BatchTemplate* = object
    # Editing options (map to --edit, --margin, etc.)
    edit*: string              ## --edit expression (e.g., "audio")
    margin*: string            ## --margin duration (e.g., "0.2s")
    whenSilent*: string        ## --when-silent action (e.g., "cut()")
    whenNormal*: string        ## --when-normal action (e.g., "nil()")
    # Output options
    outputFormat*: string      ## -ex export format (e.g., "mp4")
    outputSuffix*: string      ## Suffix appended to output filename (e.g., "_edited")
    outputDir*: string         ## Output directory (empty = same as input)
    # Engagement options
    engage*: string            ## --engage value (threshold or preset name)
    # Analysis options
    noFaces*: bool             ## --no-faces flag
    noTranscript*: bool        ## --no-transcript flag
    # Brand configuration
    brand*: BrandConfig        ## Brand template (watermark, intro/outro, caption style)

proc loadTemplate*(path: string): BatchTemplate =
  ## Load TOML template from file path
  try:
    result = Toml.loadFile(path, BatchTemplate)
  except CatchableError as e:
    raise newException(IOError, &"Failed to load template: {path}: {e.msg}")

proc toArgs*(tmpl: BatchTemplate): seq[string] =
  ## Convert template fields to CLI argument sequence
  result = @[]

  if tmpl.edit != "":
    result.add("--edit")
    result.add(tmpl.edit)

  if tmpl.margin != "":
    result.add("--margin")
    result.add(tmpl.margin)

  if tmpl.whenSilent != "":
    result.add("--when-silent")
    result.add(tmpl.whenSilent)

  if tmpl.whenNormal != "":
    result.add("--when-normal")
    result.add(tmpl.whenNormal)

  if tmpl.outputFormat != "":
    result.add("-ex")
    result.add(tmpl.outputFormat)

  if tmpl.engage != "":
    result.add("--engage")
    result.add(tmpl.engage)

  if tmpl.noFaces:
    result.add("--no-faces")

  if tmpl.noTranscript:
    result.add("--no-transcript")

  # Brand configuration: watermark
  if tmpl.brand.watermark.enabled and tmpl.brand.watermark.imagePath != "":
    result.add("--watermark")
    result.add(tmpl.brand.watermark.imagePath)

    if tmpl.brand.watermark.position != "":
      result.add("--watermark-position")
      result.add(tmpl.brand.watermark.position)

    if tmpl.brand.watermark.scale != 0.0:
      result.add("--watermark-scale")
      result.add($tmpl.brand.watermark.scale)

    if tmpl.brand.watermark.opacity != 0.0 and tmpl.brand.watermark.opacity != 1.0:
      result.add("--watermark-opacity")
      result.add($tmpl.brand.watermark.opacity)

    if tmpl.brand.watermark.offsetX != 0 or tmpl.brand.watermark.offsetY != 0:
      result.add("--watermark-offset")
      result.add($tmpl.brand.watermark.offsetX & "x" & $tmpl.brand.watermark.offsetY)

  # Brand configuration: intro/outro
  if tmpl.brand.introOutro.introPath != "":
    result.add("--intro")
    result.add(tmpl.brand.introOutro.introPath)

  if tmpl.brand.introOutro.outroPath != "":
    result.add("--outro")
    result.add(tmpl.brand.introOutro.outroPath)

  # Brand configuration: caption style
  if tmpl.brand.captionStyle.preset != "":
    result.add("--caption-preset")
    result.add(tmpl.brand.captionStyle.preset)

  if tmpl.brand.captionStyle.fontPath != "":
    result.add("--caption-font")
    result.add(tmpl.brand.captionStyle.fontPath)

  if tmpl.brand.captionStyle.fontSize > 0:
    result.add("--caption-size")
    result.add($tmpl.brand.captionStyle.fontSize)

  if tmpl.brand.captionStyle.color != "":
    result.add("--caption-color")
    result.add(tmpl.brand.captionStyle.color)

  if tmpl.brand.captionStyle.position != "":
    result.add("--caption-position")
    result.add(tmpl.brand.captionStyle.position)

proc validateTemplate*(tmpl: BatchTemplate): seq[string] =
  ## Returns list of validation warnings (empty = valid)
  result = @[]

  # Check for conflicting options
  if tmpl.edit != "" and tmpl.engage != "":
    result.add("Both 'edit' and 'engage' are set - engage filtering may conflict with edit expression")

  # Check output format is known (basic validation)
  if tmpl.outputFormat != "":
    const knownFormats = ["mp4", "mov", "avi", "mkv", "webm", "premiere", "resolve", "final-cut-pro", "shotcut", "kdenlive"]
    if tmpl.outputFormat notin knownFormats:
      result.add(&"Output format '{tmpl.outputFormat}' is not a commonly used format - ensure it's supported")

  # Validate brand configuration
  if tmpl.brand.watermark.enabled and tmpl.brand.watermark.imagePath == "":
    result.add("Watermark enabled but no image path specified")

  if tmpl.brand.introOutro.introPath != "" and not fileExists(tmpl.brand.introOutro.introPath):
    result.add(&"Intro file not found: {tmpl.brand.introOutro.introPath}")

  if tmpl.brand.introOutro.outroPath != "" and not fileExists(tmpl.brand.introOutro.outroPath):
    result.add(&"Outro file not found: {tmpl.brand.introOutro.outroPath}")
