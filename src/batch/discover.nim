import std/[os, strutils, algorithm]

const VideoExtensions* = [".mp4", ".mov", ".avi", ".mkv", ".webm", ".flv", ".wmv", ".m4v", ".ts"]

proc findVideoFiles*(inputPath: string): seq[string] =
  ## Find all video files - if path is a file, return it; if directory, scan recursively
  if not fileExists(inputPath) and not dirExists(inputPath):
    raise newException(IOError, "Path does not exist: " & inputPath)

  # If it's a file, return it directly
  if fileExists(inputPath):
    return @[inputPath]

  # It's a directory - walk recursively
  result = @[]
  for file in walkDirRec(inputPath, yieldFilter = {pcFile}):
    let ext = splitFile(file).ext.toLowerAscii()
    if ext in VideoExtensions:
      result.add(file)

  # Sort for deterministic ordering
  result.sort()

proc generateOutputPath*(inputPath: string, inputRoot: string, outputDir: string, suffix: string, ext: string): string =
  ## Generate output path preserving directory structure
  ## - inputPath: full path to input file
  ## - inputRoot: root directory of input (for preserving structure)
  ## - outputDir: output directory (empty = same as input)
  ## - suffix: suffix to append before extension (e.g., "_edited")
  ## - ext: new extension (empty = keep original)

  let (dir, name, origExt) = splitFile(inputPath)

  # Determine the final extension
  let finalExt = if ext != "": ext else: origExt

  # Determine the base output directory
  if outputDir == "":
    # Output goes next to input file
    result = dir / (name & suffix & finalExt)
  else:
    # Recreate relative path from inputRoot under outputDir
    var relativePath = ""
    if inputRoot != "" and inputPath.startsWith(inputRoot):
      # Extract the relative portion
      relativePath = inputPath[inputRoot.len .. ^1]
      # Remove leading path separator if present
      if relativePath.startsWith($DirSep) or relativePath.startsWith("/"):
        relativePath = relativePath[1 .. ^1]
    else:
      # No common root - just use filename
      relativePath = extractFilename(inputPath)

    # Build output path preserving directory structure
    let (relDir, relName, _) = splitFile(relativePath)
    let outDir = if relDir != "": outputDir / relDir else: outputDir
    result = outDir / (relName & suffix & finalExt)
