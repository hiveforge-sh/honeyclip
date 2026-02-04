## AAF export via pyaaf2 Python library
##
## AAF (Advanced Authoring Format) is used by:
##   - Avid Media Composer
##   - Adobe After Effects
##   - DaVinci Resolve
##
## Since AAF SDK is complex COM-based C++, we use pyaaf2 via subprocess.
## This requires Python 3 and pyaaf2 to be installed.

import std/[json, os, osproc, strformat, strutils, tempfiles]
import markers

type
  AAFExportError* = object of CatchableError
    ## Raised when AAF export fails

proc checkPyaaf2Available*(): bool =
  ## Check if pyaaf2 Python package is available
  let (output, exitCode) = execCmdEx("python -c \"import aaf2; print('ok')\"")
  return exitCode == 0 and "ok" in output

proc markerTypeToString(mt: MarkerType): string =
  ## Convert marker type to JSON string value
  case mt
  of mtEngagementPeak: "engagement_peak"
  of mtSceneBoundary: "scene_boundary"
  of mtSpeakerChange: "speaker_change"

proc markersToJson*(markers: seq[Marker], videoPath: string): JsonNode =
  ## Convert markers to JSON format expected by export_aaf.py
  var markerArray = newJArray()
  for m in markers:
    markerArray.add(%* {
      "type": markerTypeToString(m.markerType),
      "timestamp_ms": m.timestampMs,
      "duration_ms": m.durationMs,
      "name": m.name,
      "comment": m.comment,
      "color": m.color
    })

  result = %* {
    "video": videoPath,
    "markers": markerArray
  }

proc findExportScript(): string =
  ## Locate the export_aaf.py script
  ## Checks relative to executable, source directory, and working directory

  # Try relative to executable (installed location)
  let exeDir = getAppDir()
  let exePath = exeDir / "scripts" / "export_aaf.py"
  if fileExists(exePath):
    return exePath

  # Try relative to source file (development)
  let srcDir = currentSourcePath().parentDir.parentDir.parentDir
  let srcPath = srcDir / "scripts" / "export_aaf.py"
  if fileExists(srcPath):
    return srcPath

  # Try working directory
  let cwdPath = getCurrentDir() / "scripts" / "export_aaf.py"
  if fileExists(cwdPath):
    return cwdPath

  return ""

proc exportAAF*(videoPath: string, markers: seq[Marker], outputPath: string, fps: float = 30.0, simple: bool = false) =
  ## Export markers as AAF file
  ##
  ## Args:
  ##   videoPath: Path to source video (for reference in AAF)
  ##   markers: Markers to include
  ##   outputPath: Output AAF file path
  ##   fps: Frame rate for timecode (default 30)
  ##   simple: Use simplified marker format for compatibility
  ##
  ## Raises:
  ##   AAFExportError if Python/pyaaf2 not available or script fails

  if not checkPyaaf2Available():
    raise newException(AAFExportError,
      "pyaaf2 not available. Install with: pip install pyaaf2")

  # Find the Python script
  let scriptPath = findExportScript()
  if scriptPath == "":
    raise newException(AAFExportError,
      "export_aaf.py not found. Ensure it exists in scripts/ directory.")

  # Create temp directory for JSON file
  let tempDir = getTempDir() / "honeyclip_aaf"
  if not dirExists(tempDir):
    createDir(tempDir)

  let tempJson = tempDir / "markers.json"

  # Write markers to temp JSON file
  writeFile(tempJson, $markersToJson(markers, videoPath))
  defer:
    try:
      removeFile(tempJson)
    except:
      discard  # Ignore cleanup errors

  # Build command with proper quoting for paths
  var cmd = &"python \"{scriptPath}\" --input \"{tempJson}\" --output \"{outputPath}\" --video \"{videoPath}\" --fps {fps}"
  if simple:
    cmd &= " --simple"

  let (output, exitCode) = execCmdEx(cmd)

  if exitCode != 0:
    raise newException(AAFExportError, &"AAF export failed: {output}")

proc exportMarkersAAF*(markers: seq[Marker], outputPath: string, videoPath: string = "untitled.mp4", fps: float = 30.0) =
  ## Export markers only (convenience wrapper)
  ##
  ## Args:
  ##   markers: Markers to export
  ##   outputPath: Output AAF file path
  ##   videoPath: Source video path reference (default "untitled.mp4")
  ##   fps: Frame rate for timecode (default 30)
  exportAAF(videoPath, markers, outputPath, fps)
