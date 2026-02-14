import std/[json, os, times, sets, strformat]

type
  FileResult* = object
    path*: string
    error*: string      ## Empty if successful

  CheckpointState* = object
    templatePath*: string
    inputPath*: string
    totalFiles*: int
    completed*: seq[string]
    failed*: seq[FileResult]
    startTime*: float64
    lastUpdate*: float64

proc checkpointPath*(inputPath: string): string =
  ## Returns .honeyclip-batch.json in the input directory (or next to input file)
  if fileExists(inputPath):
    # Input is a file - checkpoint goes in parent directory
    result = parentDir(inputPath) / ".honeyclip-batch.json"
  else:
    # Input is a directory - checkpoint goes inside it
    result = inputPath / ".honeyclip-batch.json"

proc newCheckpoint*(templatePath, inputPath: string, totalFiles: int): CheckpointState =
  ## Creates new checkpoint with current epochTime() as startTime
  result = CheckpointState(
    templatePath: templatePath,
    inputPath: inputPath,
    totalFiles: totalFiles,
    completed: @[],
    failed: @[],
    startTime: epochTime(),
    lastUpdate: epochTime()
  )

proc saveCheckpoint*(state: CheckpointState, path: string) =
  ## Atomic save: write to temp file, then rename
  let tempPath = path & ".tmp"
  let jsonData = pretty(%state)
  writeFile(tempPath, jsonData)

  # Windows may fail on atomic rename if target exists
  # Try moveFile, if it fails, remove target and retry
  try:
    moveFile(tempPath, path)
  except OSError:
    # Remove existing file and retry
    if fileExists(path):
      removeFile(path)
    moveFile(tempPath, path)

proc loadCheckpoint*(path: string): CheckpointState =
  ## Parse JSON file into CheckpointState
  if not fileExists(path):
    raise newException(IOError, &"Checkpoint file not found: {path}")

  let jsonData = readFile(path)
  result = to(parseJson(jsonData), CheckpointState)

proc hasCheckpoint*(inputPath: string): bool =
  ## Returns true if checkpoint file exists at expected location
  let cpPath = checkpointPath(inputPath)
  result = fileExists(cpPath)

proc markCompleted*(state: var CheckpointState, filePath: string) =
  ## Add to completed list, update lastUpdate
  state.completed.add(filePath)
  state.lastUpdate = epochTime()

proc markFailed*(state: var CheckpointState, filePath: string, error: string) =
  ## Add FileResult to failed list, update lastUpdate
  state.failed.add(FileResult(path: filePath, error: error))
  state.lastUpdate = epochTime()

proc pendingFiles*(state: CheckpointState, allFiles: seq[string]): seq[string] =
  ## Returns files not in completed or failed lists
  var processed = initHashSet[string]()
  for f in state.completed:
    processed.incl(f)
  for f in state.failed:
    processed.incl(f.path)

  result = @[]
  for f in allFiles:
    if f notin processed:
      result.add(f)

proc printSummary*(state: CheckpointState) =
  ## Print batch summary: total, completed, failed counts, elapsed time
  let elapsed = state.lastUpdate - state.startTime
  let elapsedMin = elapsed / 60.0

  echo ""
  echo &"[batch] Processing complete:"
  echo &"  Total files: {state.totalFiles}"
  echo &"  Completed: {state.completed.len}"
  echo &"  Failed: {state.failed.len}"
  echo &"  Elapsed time: {elapsedMin:.1f} minutes"

  if state.failed.len > 0:
    echo ""
    echo "[batch] Failed files:"
    for fr in state.failed:
      echo &"  - {fr.path}"
      echo &"    Error: {fr.error}"
