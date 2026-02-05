## Meta command - Apply metadata to video/audio files from templates
##
## Usage:
##   honeyclip meta video.mp4                    # Auto-discover template
##   honeyclip meta video.mp4 --template t.json  # Use specific template
##   honeyclip meta video.mp4 --title "My Video" # Override title
##   honeyclip meta video.mp4 --output out.mp4   # Write to new file
##   honeyclip meta video.mp4 --dry-run          # Show metadata, don't apply

import std/[strformat, os, tables, osproc, streams]
import ../log
import ../util/fun
import ../metadata/[types, parser, apply]

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var outputPath: string = ""
  var templatePath: string = ""

  # Override flags
  var titleOverride: string = ""
  var authorOverride: string = ""
  var copyrightOverride: string = ""
  var descriptionOverride: string = ""
  var dateOverride: string = ""

  # Options
  var dryRun: bool = false
  var showHelp: bool = false
  var inPlace: bool = false

  # Parse arguments
  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      showHelp = true
    of "--template", "-t":
      expecting = "template"
    of "--output", "-o":
      expecting = "output"
    of "--title":
      expecting = "title"
    of "--author", "--artist":
      expecting = "author"
    of "--copyright":
      expecting = "copyright"
    of "--description", "--desc":
      expecting = "description"
    of "--date":
      expecting = "date"
    of "--dry-run", "-n":
      dryRun = true
    of "--in-place", "-i":
      inPlace = true
    else:
      if expecting != "":
        case expecting:
        of "template": templatePath = key
        of "output": outputPath = key
        of "title": titleOverride = key
        of "author": authorOverride = key
        of "copyright": copyrightOverride = key
        of "description": descriptionOverride = key
        of "date": dateOverride = key
        else: discard
        expecting = ""
      elif inputPath == "":
        inputPath = key
      else:
        echo &"Unknown argument: {key}"

  if showHelp or inputPath == "":
    echo """usage: honeyclip meta [options] <input>

Apply metadata to video/audio files from JSON templates

Template:
  --template, -t PATH     Use specific template file
                          Default: auto-discover .honeyclip-meta.json

Output:
  --output, -o PATH       Write to new file (default: modify in place)
  --dry-run, -n           Show metadata without applying

Overrides (override template values):
  --title TEXT            Set title metadata
  --author TEXT           Set artist/author metadata
  --copyright TEXT        Set copyright notice
  --description TEXT      Set description/comment
  --date DATE             Set date (ISO format: YYYY-MM-DD)

Template format (.honeyclip-meta.json):
  {
    "version": 1,
    "global": {
      "title": "${VIDEO_TITLE}",
      "artist": "${AUTHOR_NAME}",
      "copyright": "Copyright ${YEAR} ${AUTHOR_NAME}",
      "date": "${ISO_DATE}"
    },
    "chapters": [
      {"start_ms": 0, "end_ms": 30000, "title": "Introduction"}
    ]
  }

Template variables:
  ${VIDEO_TITLE}   - Input filename without extension
  ${AUTHOR_NAME}   - From --author or HONEYCLIP_AUTHOR env var
  ${YEAR}          - Current year (4 digits)
  ${ISO_DATE}      - Current date (YYYY-MM-DD)
  ${FILENAME}      - Input filename with extension

Examples:
  honeyclip meta video.mp4                          # Apply auto-discovered template
  honeyclip meta video.mp4 --template custom.json   # Use specific template
  honeyclip meta video.mp4 --title "My Title"       # Override title
  honeyclip meta video.mp4 --dry-run                # Preview metadata
"""
    return

  # Validate input exists
  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Find or load template
  var tmpl: MetadataTemplate
  if templatePath != "":
    if not fileExists(templatePath):
      error &"Template not found: {templatePath}"
    tmpl = loadTemplate(templatePath)
    echo &"Loaded template: {templatePath}"
  else:
    let discovered = findTemplate(inputPath)
    if discovered != "":
      tmpl = loadTemplate(discovered)
      echo &"Using template: {discovered}"
    else:
      tmpl = defaultTemplate()
      echo "Using default template"

  # Substitute variables
  tmpl = substituteVariables(tmpl, inputPath, authorOverride)

  # Apply CLI overrides
  var overrides = initTable[string, string]()
  if titleOverride != "":
    overrides["title"] = titleOverride
  if authorOverride != "":
    overrides["artist"] = authorOverride  # Use "artist" for MP4 compatibility
  if copyrightOverride != "":
    overrides["copyright"] = copyrightOverride
  if descriptionOverride != "":
    overrides["description"] = descriptionOverride
  if dateOverride != "":
    overrides["date"] = dateOverride

  if overrides.len > 0:
    tmpl = merge(tmpl, overrides)

  # Dry run: show metadata and exit
  if dryRun:
    echo "Metadata to apply:"
    echo "=================="
    for key, val in tmpl.global:
      echo &"  {key}: {val}"
    if tmpl.chapters.len > 0:
      echo ""
      echo "Chapters:"
      for i, ch in tmpl.chapters:
        let startSec = ch.startMs div 1000
        let endSec = ch.endMs div 1000
        echo &"  [{i+1}] {startSec}s - {endSec}s: {ch.title}"
    return

  # Determine output path
  let actualOutput = if outputPath != "": outputPath
                     elif inPlace: inputPath
                     else:
                       # Default: add "_meta" suffix
                       let (dir, name, ext) = splitFile(inputPath)
                       dir / (name & "_meta" & ext)

  # Generate ffmetadata file
  let metadataFile = writeFFMetadataFile(tmpl)
  defer: removeFile(metadataFile)

  # Build FFmpeg command
  var ffmpegArgs: seq[string] = @[
    "-i", inputPath,
    "-i", metadataFile,
    "-map_metadata", "1",
    "-codec", "copy"
  ]

  # Handle in-place: write to temp then move
  var tempOutput = actualOutput
  if inPlace or actualOutput == inputPath:
    tempOutput = getTempDir() / ("honeyclip_temp_" & extractFilename(inputPath))

  ffmpegArgs.add("-y")  # Overwrite
  ffmpegArgs.add(tempOutput)

  echo &"Applying metadata to: {actualOutput}"
  debug &"FFmpeg args: {ffmpegArgs}"

  let process = startProcess("ffmpeg", args = ffmpegArgs,
                             options = {poUsePath, poStdErrToStdOut})
  let exitCode = process.waitForExit()
  let outputStr = process.outputStream.readAll()
  process.close()

  if exitCode != 0:
    error &"FFmpeg failed (exit {exitCode}):\n{outputStr}"

  # Move temp file if in-place
  if tempOutput != actualOutput:
    moveFile(tempOutput, actualOutput)

  echo &"Metadata applied successfully"
