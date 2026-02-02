import std/os
import std/terminal
import std/strformat
import std/strutils

import ../about

func formatBytes(size: var float): (string, string) =
  for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
    if size < 1024.0:
      return (fmt"{size:.2f}", unit)
    size = size / 1024.0
  return (fmt"{size:.2f}", "PiB")

proc showSystemCache() =
  ## Display system cache in temp directory
  let cacheDir = getTempDir() / fmt"ae-{version}"

  var totalSize = 0.0
  try:
    for (kind, path) in walkDir(cacheDir):
      case kind
      of pcFile:
        var size = getFileSize(path).float
        totalSize += size
        let (sizeNum, sizeUnit) = formatBytes(size)

        let (_, key, _) = splitFile(path)
        let hashPart = key[0 ..< 16]
        let restPart = key[16 .. ^1]

        stdout.styledWrite(fgYellow, "entry: ")
        stdout.write "\e[90m", hashPart, "\e[0m"
        stdout.styledWriteLine(restPart, "  ", fgYellow, "size: ", fgGreen,
          sizeNum, " ", fgBlue, sizeUnit, resetStyle)

      else:
        discard
  except:
    discard

  if totalSize == 0.0:
    echo "Empty cache"
  else:
    let (totalNum, totalUnit) = formatBytes(totalSize)
    stdout.styledWriteLine("\n", fgYellow, "total cache size: ", fgGreen,
        totalNum, " ", fgBlue, totalUnit, resetStyle)

proc showFaceCache() =
  ## Display face cache in current directory's .honeyclip/ folder
  let faceCache = getCurrentDir() / ".honeyclip"
  if not dirExists(faceCache):
    echo "No face cache in current directory"
    return

  var totalSize = 0.0
  var fileCount = 0
  for (kind, path) in walkDir(faceCache):
    if kind == pcFile and path.endsWith(".bin"):
      inc fileCount
      var size = getFileSize(path).float
      totalSize += size
      let (sizeNum, sizeUnit) = formatBytes(size)
      let (_, name, _) = splitFile(path)
      stdout.styledWrite(fgCyan, "face cache: ")
      stdout.styledWriteLine(name, "  ", fgYellow, "size: ", fgGreen, sizeNum, " ", fgBlue, sizeUnit, resetStyle)

  if fileCount == 0:
    echo "Face cache empty"
  else:
    let (totalNum, totalUnit) = formatBytes(totalSize)
    stdout.styledWriteLine(fgYellow, "Total: ", fgGreen, totalNum, " ", fgBlue, totalUnit, resetStyle)

proc main*(args: seq[string]) =
  # Handle --clear-faces flag
  if args.len > 0 and args[0] == "--clear-faces":
    let faceCache = getCurrentDir() / ".honeyclip"
    if dirExists(faceCache):
      try:
        removeDir(faceCache)
        echo "Face cache cleared"
      except:
        echo "Failed to clear face cache"
    else:
      echo "No face cache found"
    return

  # Handle --info flag (show both caches)
  if args.len > 0 and args[0] == "--info":
    echo "=== System Cache ==="
    showSystemCache()
    echo ""
    echo "=== Face Cache ==="
    showFaceCache()
    return

  # Legacy behavior: clean/clear system cache
  if args.len > 0 and args[0] in ["clean", "clear"]:
    let cacheDir = getTempDir() / fmt"ae-{version}"
    try:
      removeDir cacheDir
    except:
      discard
    return

  # Default: show system cache only
  showSystemCache()
