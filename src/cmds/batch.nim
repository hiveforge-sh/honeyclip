import std/[strformat, strutils, os]
import ../log
import ../batch/[templates, discover, runner, checkpoint]

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var templatePath: string = ""
  var outputDir: string = ""
  var jobs: int = 0              # 0 = auto (CPU core count)
  var resume: bool = false       # --resume flag
  var dryRun: bool = false       # --dry-run flag

  # Parse arguments
  var i = 0
  while i < cArgs.len:
    let arg = cArgs[i]
    case arg:
    of "--template", "-t":
      inc i
      if i < cArgs.len:
        templatePath = cArgs[i]
    of "--output", "-o":
      inc i
      if i < cArgs.len:
        outputDir = cArgs[i]
    of "--jobs", "-j":
      inc i
      if i < cArgs.len:
        jobs = parseInt(cArgs[i])
    of "--resume":
      resume = true
    of "--dry-run":
      dryRun = true
    else:
      if inputPath == "":
        inputPath = arg
      else:
        error &"Unknown argument: {arg}"
    inc i

  # Validate required arguments
  if inputPath == "":
    error "Usage: honeyclip batch <input-path> --template <template.toml> [options]\n\n" &
          "Options:\n" &
          "  -t, --template FILE    TOML template with processing settings (required)\n" &
          "  -o, --output DIR       Output directory (default: same as input)\n" &
          "  -j, --jobs N           Number of parallel workers (default: CPU cores)\n" &
          "  --resume               Resume from previous checkpoint\n" &
          "  --dry-run              Show what would be processed without doing it"

  if templatePath == "":
    error "Template file required. Use --template <file.toml>"

  if not fileExists(templatePath):
    error &"Template file not found: {templatePath}"

  # Load template
  let tmpl = loadTemplate(templatePath)
  let warnings = validateTemplate(tmpl)
  for w in warnings:
    echo &"[batch] Warning: {w}"

  # Discover files
  let files = findVideoFiles(inputPath)
  if files.len == 0:
    error &"No video files found at: {inputPath}"

  echo &"[batch] Template: {templatePath}"
  echo &"[batch] Found {files.len} video file(s)"

  if dryRun:
    echo "[batch] Dry run -- files that would be processed:"
    for f in files:
      echo &"  {f}"
    return

  # Check resume without checkpoint
  if resume and not hasCheckpoint(inputPath):
    echo "[batch] No checkpoint found. Starting from scratch."

  # Create batch config and run
  let config = BatchConfig(
    tmpl: tmpl,
    inputPath: inputPath,
    outputDir: if outputDir != "": outputDir else: tmpl.outputDir,
    jobs: jobs,
    resume: resume
  )
  runBatch(config)
