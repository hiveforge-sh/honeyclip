import std/[os, strformat, strutils, cpuinfo, times, osproc]
import malebolgia
import ./templates
import ./checkpoint
import ./discover
import ../log

type
  BatchConfig* = object
    tmpl*: BatchTemplate
    inputPath*: string
    outputDir*: string
    jobs*: int
    resume*: bool

  BatchResult* = object
    path*: string
    success*: bool
    error*: string
    durationMs*: int64

proc processOneFile(inputFile: string, tmpl: BatchTemplate, inputRoot: string, outputDir: string): BatchResult =
  ## Process a single file using the template settings
  let startTime = cpuTime()

  # Generate output path
  let outputExt = if tmpl.outputFormat != "": "." & tmpl.outputFormat else: ""
  let outputPath = generateOutputPath(
    inputFile,
    inputRoot,
    outputDir,
    tmpl.outputSuffix,
    outputExt
  )

  # Create output directory if it doesn't exist
  let outDir = parentDir(outputPath)
  if not dirExists(outDir):
    createDir(outDir)

  # Build CLI args from template
  var args = tmpl.toArgs()

  # Prepend input file and append output
  var fullArgs = @[inputFile] & args & @["-o", outputPath]

  # Get honeyclip executable path
  let exePath = getAppFilename()

  # Build command
  let cmd = exePath & " " & fullArgs.join(" ")

  # Execute as subprocess
  try:
    let (output, exitCode) = execCmdEx(cmd)

    let duration = int64((cpuTime() - startTime) * 1000)

    if exitCode == 0:
      result = BatchResult(
        path: inputFile,
        success: true,
        error: "",
        durationMs: duration
      )
    else:
      result = BatchResult(
        path: inputFile,
        success: false,
        error: &"Exit code {exitCode}: {output}",
        durationMs: duration
      )
  except CatchableError as e:
    let duration = int64((cpuTime() - startTime) * 1000)
    result = BatchResult(
      path: inputFile,
      success: false,
      error: e.msg,
      durationMs: duration
    )

proc runBatch*(config: BatchConfig) =
  ## Main batch orchestrator
  # Discover files
  let allFiles = findVideoFiles(config.inputPath)

  # Determine checkpoint path
  let cpPath = checkpointPath(config.inputPath)

  # Handle resume
  var state: CheckpointState
  var filesToProcess: seq[string]

  if config.resume and hasCheckpoint(config.inputPath):
    # Load existing checkpoint
    state = loadCheckpoint(cpPath)
    filesToProcess = state.pendingFiles(allFiles)

    let completed = state.completed.len
    let failed = state.failed.len
    let pending = filesToProcess.len

    echo &"[batch] Resuming: {pending} files remaining ({completed} completed, {failed} failed)"
  else:
    if config.resume and not hasCheckpoint(config.inputPath):
      echo "[batch] No checkpoint found. Starting from scratch."

    # Create new checkpoint (use inputPath as templatePath placeholder)
    state = newCheckpoint("", config.inputPath, allFiles.len)
    filesToProcess = allFiles

  if filesToProcess.len == 0:
    echo "[batch] No files to process."
    state.printSummary()
    return

  # Determine worker count
  let workers = if config.jobs == 0: cpuinfo.countProcessors() else: config.jobs

  # Determine output directory
  let outputDir = if config.outputDir != "": config.outputDir else: config.tmpl.outputDir

  # Determine input root for path generation
  let inputRoot = if dirExists(config.inputPath): config.inputPath else: parentDir(config.inputPath)

  echo &"[batch] Processing {filesToProcess.len} files with {workers} worker(s)"

  # Process files in chunks for checkpoint granularity
  let chunkSize = max(1, workers * 2)
  var processedCount = state.completed.len + state.failed.len

  for chunkStart in countup(0, filesToProcess.len - 1, chunkSize):
    let chunkEnd = min(chunkStart + chunkSize, filesToProcess.len)
    let chunk = filesToProcess[chunkStart ..< chunkEnd]

    var results = newSeq[BatchResult](chunk.len)
    var m = createMaster()
    m.awaitAll:
      for i, file in chunk:
        m.spawn processOneFile(file, config.tmpl, inputRoot, outputDir) -> results[i]

    # Update checkpoint after chunk
    for r in results:
      if r.success:
        state.markCompleted(r.path)
        echo &"[batch] [{processedCount + 1}/{state.totalFiles}] Completed: {extractFilename(r.path)} ({r.durationMs / 1000:.1f}s)"
      else:
        state.markFailed(r.path, r.error)
        echo &"[batch] [{processedCount + 1}/{state.totalFiles}] Failed: {extractFilename(r.path)} - {r.error}"
      processedCount += 1

    state.saveCheckpoint(cpPath)

  # Print summary
  state.printSummary()
