import std/[strformat, os]
import toml_serialization

type
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
