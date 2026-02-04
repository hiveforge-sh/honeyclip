import std/[algorithm, json, os, strformat, strutils]

#[
Export clips as CMX3600 EDL (Edit Decision List) format for NLE import.

CMX3600 is the industry standard EDL format, supported by:
- Adobe Premiere Pro
- DaVinci Resolve
- Final Cut Pro
- Avid Media Composer
- Most other professional video editors

EDL format spec (SMPTE 258M):
- Simple text format with fixed-width fields
- TITLE line at top
- Event lines with timecode and edit info
- Comment lines (asterisk prefix) for metadata
- 999 event limit (sufficient for clip exports)
]#

type
  ClipValidationError* = object of CatchableError
    ## Raised when clip boundaries are invalid

  EDLClip* = object
    ## Data transfer object for EDL/JSON export
    ## CLI converts Clip -> EDLClip before calling export functions
    startMs*: int64
    endMs*: int64
    engagementScore*: float32
    text*: string            # Truncated transcript for comment
    rank*: int               # Clip rank (1 = best)

proc formatTimecode*(ms: int64, fps: float = 30.0): string =
  ## Format milliseconds as SMPTE timecode HH:MM:SS:FF
  ## Default 30fps for maximum compatibility
  let totalFrames = int((ms.float64 / 1000.0) * fps)
  let frames = totalFrames mod int(fps)
  let totalSeconds = totalFrames div int(fps)
  let seconds = totalSeconds mod 60
  let totalMinutes = totalSeconds div 60
  let minutes = totalMinutes mod 60
  let hours = totalMinutes div 60
  &"{hours:02}:{minutes:02}:{seconds:02}:{frames:02}"

proc parseTimecode*(tc: string, fps: float = 30.0): int64 =
  ## Parse SMPTE timecode back to milliseconds
  ## Format: HH:MM:SS:FF
  let parts = tc.split(':')
  if parts.len != 4:
    return 0

  let hours = parseInt(parts[0])
  let minutes = parseInt(parts[1])
  let seconds = parseInt(parts[2])
  let frames = parseInt(parts[3])

  let totalFrames = hours * 3600 * int(fps) +
                    minutes * 60 * int(fps) +
                    seconds * int(fps) +
                    frames

  result = int64(totalFrames.float64 / fps * 1000.0)

proc exportCMX3600EDL*(clips: seq[EDLClip], outputPath: string,
                       sourceName: string, fps: float = 30.0) =
  ## Export clips as CMX3600 EDL file
  ##
  ## CMX3600 format (SMPTE 258M):
  ## - TITLE line at top
  ## - Event lines: EVENT REEL EDIT_TYPE TRANSITION SOURCE_IN SOURCE_OUT RECORD_IN RECORD_OUT
  ## - Comment lines (asterisk prefix) for metadata
  ##
  ## Args:
  ##   clips: Clips to export
  ##   outputPath: Output .edl file path
  ##   sourceName: Source video name (max 8 chars for reel name)
  ##   fps: Frame rate for timecode (default 30.0)

  var lines: seq[string] = @[]

  # Header
  lines.add("TITLE: Engagement Clips")
  lines.add("")

  # Track record timeline position
  var recordPosition: int64 = 0

  for i, clip in clips:
    let eventNum = $(i + 1)
    let paddedEvent = eventNum.align(3, '0')  # 001, 002, etc.

    # Reel name: max 8 chars, uppercase, alphanumeric
    var reelName = sourceName
    if reelName.len > 8:
      reelName = reelName[0..7]
    reelName = reelName.toUpperAscii()
    for c in reelName:
      if not (c.isAlphaNumeric() or c == '_'):
        reelName = reelName.replace($c, "_")

    # Timecodes
    let sourceIn = formatTimecode(clip.startMs, fps)
    let sourceOut = formatTimecode(clip.endMs, fps)
    let recordIn = formatTimecode(recordPosition, fps)
    let clipDuration = clip.endMs - clip.startMs
    let recordOut = formatTimecode(recordPosition + clipDuration, fps)

    # Event line: EVENT REEL EDIT_TYPE TRANSITION SOURCE_IN SOURCE_OUT RECORD_IN RECORD_OUT
    # V = video only, C = cut transition
    lines.add(&"{paddedEvent}  {reelName.align(8)}  V     C        {sourceIn} {sourceOut} {recordIn} {recordOut}")

    # Comment lines with metadata (asterisk prefix)
    lines.add(&"* ENGAGEMENT_SCORE: {clip.engagementScore:.1f}")
    lines.add(&"* RANK: {clip.rank}")

    # Truncate text for comment (max 60 chars)
    if clip.text.len > 0:
      var text = clip.text.replace("\n", " ").strip()
      if text.len > 60:
        text = text[0..57] & "..."
      lines.add(&"* TRANSCRIPT: {text}")

    lines.add("")  # Blank line between events

    recordPosition += clipDuration

  # Write file
  writeFile(outputPath, lines.join("\n"))

proc exportClipsJSON*(clips: seq[EDLClip], outputPath: string,
                      sourcePath: string, params: JsonNode = nil) =
  ## Export clips as JSON with full engagement breakdown
  ##
  ## JSON structure:
  ## {
  ##   "source": "video.mp4",
  ##   "clip_count": 5,
  ##   "params": {...},
  ##   "clips": [
  ##     {
  ##       "rank": 1,
  ##       "start_ms": 30000,
  ##       "end_ms": 60000,
  ##       "duration_ms": 30000,
  ##       "start_timecode": "00:00:30:00",
  ##       "end_timecode": "00:01:00:00",
  ##       "engagement_score": 85.2,
  ##       "text": "..."
  ##     }
  ##   ]
  ## }

  var root = %* {
    "source": extractFilename(sourcePath),
    "clip_count": clips.len,
    "clips": newJArray()
  }

  if params != nil:
    root["params"] = params

  for clip in clips:
    let clipJson = %* {
      "rank": clip.rank,
      "start_ms": clip.startMs,
      "end_ms": clip.endMs,
      "duration_ms": clip.endMs - clip.startMs,
      "start_timecode": formatTimecode(clip.startMs),
      "end_timecode": formatTimecode(clip.endMs),
      "engagement_score": clip.engagementScore,
      "text": clip.text
    }
    root["clips"].add(clipJson)

  writeFile(outputPath, root.pretty())

proc loadClipsFromJson*(jsonPath: string): tuple[clips: seq[EDLClip], source: string] =
  ## Load clips from JSON project file
  ##
  ## Returns clips sorted by rank and source video path.
  ## Raises ClipValidationError if JSON is malformed or file not found.

  if not fileExists(jsonPath):
    raise newException(ClipValidationError, &"File not found: {jsonPath}")

  let jsonData = parseFile(jsonPath)

  let source = jsonData["source"].getStr()

  var clips: seq[EDLClip] = @[]
  for clipJson in jsonData["clips"]:
    let clip = EDLClip(
      startMs: clipJson["start_ms"].getBiggestInt(),
      endMs: clipJson["end_ms"].getBiggestInt(),
      engagementScore: clipJson["engagement_score"].getFloat().float32,
      text: clipJson.getOrDefault("text").getStr(""),
      rank: clipJson["rank"].getInt()
    )
    clips.add(clip)

  # Sort by rank
  clips.sort(proc(a, b: EDLClip): int = cmp(a.rank, b.rank))

  return (clips, source)

proc validateClipBoundaries*(clips: seq[EDLClip], videoDurationMs: int64 = int64.high): seq[string] =
  ## Validate clip boundaries, return list of errors
  ##
  ## Checks:
  ## - start < end for each clip
  ## - start >= 0 and end <= videoDuration
  ## - No overlapping clips

  var errors: seq[string] = @[]

  # Sort by start time for overlap checking
  var sorted = clips
  sorted.sort(proc(a, b: EDLClip): int = cmp(a.startMs, b.startMs))

  for i, clip in sorted:
    # Check start < end
    if clip.startMs >= clip.endMs:
      errors.add(&"Clip #{clip.rank}: start ({clip.startMs}ms) must be less than end ({clip.endMs}ms)")

    # Check bounds
    if clip.startMs < 0:
      errors.add(&"Clip #{clip.rank}: start ({clip.startMs}ms) cannot be negative")
    if clip.endMs > videoDurationMs:
      errors.add(&"Clip #{clip.rank}: end ({clip.endMs}ms) exceeds video duration ({videoDurationMs}ms)")

    # Check overlap with next clip
    if i < sorted.len - 1:
      let nextClip = sorted[i + 1]
      if clip.endMs > nextClip.startMs:
        errors.add(&"Clip #{clip.rank} ({clip.startMs}-{clip.endMs}ms) overlaps with Clip #{nextClip.rank} ({nextClip.startMs}-{nextClip.endMs}ms)")

  return errors

proc saveClipsWithVersion*(clips: seq[EDLClip], jsonPath: string,
                           sourcePath: string, params: JsonNode = nil): int =
  ## Save clips JSON with automatic version history
  ##
  ## If file exists, renames to .v{N} before writing new version.
  ## Returns version number of new file.

  var version = 1

  # Check for existing file and version history
  if fileExists(jsonPath):
    # Find next available version number
    while fileExists(&"{jsonPath}.v{version}"):
      version += 1

    # Rename current file to version
    moveFile(jsonPath, &"{jsonPath}.v{version}")
    version += 1  # New file is version+1

  # Write new file using existing exportClipsJSON
  exportClipsJSON(clips, jsonPath, sourcePath, params)

  return version

proc getVersionHistory*(jsonPath: string): seq[string] =
  ## Get list of version history files
  ## Returns sorted list of .v1, .v2, etc. files

  result = @[]
  var version = 1
  while fileExists(&"{jsonPath}.v{version}"):
    result.add(&"{jsonPath}.v{version}")
    version += 1

proc adjustClipBoundary*(clips: var seq[EDLClip], clipRank: int,
                         newStartMs, newEndMs: int64,
                         videoDurationMs: int64 = int64.high): seq[string] =
  ## Adjust boundaries of a single clip by rank
  ##
  ## Args:
  ##   clips: Mutable seq of clips to modify
  ##   clipRank: Rank of clip to adjust (1-based)
  ##   newStartMs: New start time in milliseconds
  ##   newEndMs: New end time in milliseconds
  ##   videoDurationMs: Video duration for bounds checking
  ##
  ## Returns:
  ##   Empty seq on success, or list of validation errors

  # Find clip by rank
  var found = false
  for i, clip in clips.mpairs:
    if clip.rank == clipRank:
      # Create modified clip for validation
      var modified = clips
      modified[i].startMs = newStartMs
      modified[i].endMs = newEndMs

      # Validate all boundaries
      let errors = validateClipBoundaries(modified, videoDurationMs)
      if errors.len > 0:
        return errors

      # Apply changes
      clips[i].startMs = newStartMs
      clips[i].endMs = newEndMs
      found = true
      break

  if not found:
    return @[&"Clip #{clipRank} not found"]

  return @[]

proc adjustClipBoundaryAndSave*(jsonPath: string, clipRank: int,
                                 newStartMs, newEndMs: int64,
                                 videoDurationMs: int64 = int64.high): tuple[success: bool, errors: seq[string], version: int] =
  ## Load clips, adjust boundary, validate, and save with version history
  ##
  ## Convenience function for CLI usage.

  var (clips, source) = loadClipsFromJson(jsonPath)

  let errors = adjustClipBoundary(clips, clipRank, newStartMs, newEndMs, videoDurationMs)
  if errors.len > 0:
    return (false, errors, 0)

  let version = saveClipsWithVersion(clips, jsonPath, source)
  return (true, @[], version)
