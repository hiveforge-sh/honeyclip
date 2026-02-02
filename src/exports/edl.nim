import std/[json, os, strformat, strutils]

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
