## Chapter detection module for honeyclip
##
## This module provides automatic chapter generation from scene changes and
## engagement peaks. Chapters can be exported to MP4 metadata or NLE markers.
##
## Features:
## - Engagement peak detection with minimum spacing constraints
## - Scene-based, engagement-based, or combined chapter modes
## - Export to ChapterMarker (MP4 metadata) and Marker (NLE) formats

import std/[algorithm, math]
import engagement_types
import ../metadata/types
import ../exports/markers

type
  ChapterSource* = enum
    csScene         ## From scene change detection
    csEngagement    ## From engagement peak detection

  Chapter* = object
    startMs*: int64
    endMs*: int64
    title*: string
    source*: ChapterSource
    score*: float32    # Engagement score (0 if scene-only)

  ChapterParams* = object
    mode*: string                # "scene", "engagement", "combined" (default "combined")
    sceneThreshold*: float       # Scene detection threshold for FFmpeg scdet (default 0.4, passed through to extractSceneChanges)
    minSpacingMs*: int64         # Minimum ms between chapters (default 30000)
    minScore*: float32           # Minimum engagement score for peaks (default 60.0)
    maxChapters*: int            # Maximum number of chapters (default 10)
    dedupeWindowMs*: int64       # Window for merging nearby scene+engagement markers (default 5000)

proc defaultChapterParams*(): ChapterParams =
  ## Create default chapter parameters
  result.mode = "combined"
  result.sceneThreshold = 0.4
  result.minSpacingMs = 30000     # 30 seconds
  result.minScore = 60.0f
  result.maxChapters = 10
  result.dedupeWindowMs = 5000    # 5 seconds

proc detectEngagementPeaks*(timeline: EngagementTimeline,
                             minSpacingMs: int64 = 30000,
                             minScore: float32 = 60.0,
                             maxPeaks: int = 10): seq[int64] =
  ## Find engagement peaks for chapter markers using local maxima detection
  ##
  ## Algorithm (from RESEARCH.md Pattern 2):
  ## 1. Find local maxima where score > neighbors and >= minScore
  ## 2. Sort candidates by score descending
  ## 3. Greedy selection with minimum spacing constraint
  ## 4. Cap at maxPeaks
  ## 5. Sort selected timestamps chronologically
  ##
  ## Args:
  ##   timeline: EngagementTimeline with scored segments
  ##   minSpacingMs: Minimum time between peaks (default 30s)
  ##   minScore: Minimum engagement score threshold
  ##   maxPeaks: Maximum number of peaks to return
  ##
  ## Returns: Timestamps of peak moments in milliseconds

  # Edge case: empty or single segment
  if timeline.segments.len <= 2:
    return @[]

  type Peak = tuple[timestamp: int64, score: float32]
  var candidates: seq[Peak] = @[]

  # Find local maxima: for each segment i (1..len-2)
  for i in 1 ..< timeline.segments.len - 1:
    let curr = timeline.segments[i]
    let prev = timeline.segments[i-1]
    let next = timeline.segments[i+1]

    # Check if local maximum
    if curr.score >= minScore and
       curr.score > prev.score and
       curr.score > next.score:
      candidates.add((curr.startMs, curr.score))

  # Sort candidates by score descending
  candidates.sort(proc(a, b: Peak): int =
    cmp(b.score, a.score))

  # Greedy selection with minimum spacing
  var selected: seq[int64] = @[]
  for peak in candidates:
    var tooClose = false
    for existing in selected:
      if abs(peak.timestamp - existing) < minSpacingMs:
        tooClose = true
        break

    if not tooClose:
      selected.add(peak.timestamp)

    if selected.len >= maxPeaks:
      break

  # Sort chronologically and return
  selected.sort()
  return selected

proc generateChapters*(sceneTimes: seq[float64],
                        engagementPeaks: seq[int64],
                        timeline: EngagementTimeline,
                        params: ChapterParams): seq[Chapter] =
  ## Generate chapters from scene and engagement signals
  ##
  ## Modes:
  ##   "scene" - Scene boundaries only
  ##   "engagement" - Engagement peaks only
  ##   "combined" - Merge both with deduplication (default)
  ##
  ## CRITICAL: Per RESEARCH.md Pitfall 4, endMs must be startMs of next chapter
  ## minus 1 (not equal to next startMs). Last chapter endMs = timeline.duration.
  ##
  ## Args:
  ##   sceneTimes: Scene change timestamps in seconds (float64)
  ##   engagementPeaks: Engagement peak timestamps in milliseconds
  ##   timeline: EngagementTimeline for score lookup and duration
  ##   params: ChapterParams with mode and constraints
  ##
  ## Returns: Sequence of Chapter objects with proper timing and titles

  var chapters: seq[Chapter] = @[]

  case params.mode:
  of "scene":
    # Convert scene times from seconds to milliseconds
    var sceneTimesMs: seq[int64] = @[]
    for time in sceneTimes:
      sceneTimesMs.add(int64(time * 1000.0))

    # Filter scenes within minSpacingMs (keep first)
    var filtered: seq[int64] = @[]
    if sceneTimesMs.len > 0:
      filtered.add(sceneTimesMs[0])

    for i in 1 ..< sceneTimesMs.len:
      if sceneTimesMs[i] - filtered[^1] >= params.minSpacingMs:
        filtered.add(sceneTimesMs[i])

    # Cap at maxChapters (keep evenly distributed if too many)
    if filtered.len > params.maxChapters:
      let step = filtered.len div params.maxChapters
      var evenly: seq[int64] = @[]
      for i in 0 ..< params.maxChapters:
        evenly.add(filtered[i * step])
      filtered = evenly

    # Create chapters
    for i, time in filtered:
      let endMs = if i < filtered.len - 1:
                    filtered[i+1] - 1
                  else:
                    timeline.duration
      chapters.add(Chapter(
        startMs: time,
        endMs: endMs,
        title: "Scene " & $(i + 1),
        source: csScene,
        score: 0.0f
      ))

  of "engagement":
    # Use engagement peak timestamps directly
    for i, peakTime in engagementPeaks:
      # Find engagement score from timeline segments
      var score = 0.0f
      for seg in timeline.segments:
        if peakTime >= seg.startMs and peakTime < seg.endMs:
          score = seg.score
          break

      let endMs = if i < engagementPeaks.len - 1:
                    engagementPeaks[i+1] - 1
                  else:
                    timeline.duration

      let label = labelForScore(score)
      chapters.add(Chapter(
        startMs: peakTime,
        endMs: endMs,
        title: "Peak #" & $(i + 1) & " - " & label,
        source: csEngagement,
        score: score
      ))

  of "combined":
    # Collect all scene times (as ms) and engagement peaks with source tags
    type MarkerCandidate = tuple[time: int64, source: ChapterSource, score: float32]
    var allMarkers: seq[MarkerCandidate] = @[]

    # Add scene markers
    for time in sceneTimes:
      allMarkers.add((int64(time * 1000.0), csScene, 0.0f))

    # Add engagement markers
    for peakTime in engagementPeaks:
      var score = 0.0f
      for seg in timeline.segments:
        if peakTime >= seg.startMs and peakTime < seg.endMs:
          score = seg.score
          break
      allMarkers.add((peakTime, csEngagement, score))

    # Sort by timestamp
    allMarkers.sort(proc(a, b: MarkerCandidate): int =
      cmp(a.time, b.time))

    # Deduplicate: if two markers within dedupeWindowMs, keep engagement one
    var i = 0
    while i < allMarkers.len:
      if i < allMarkers.len - 1:
        let curr = allMarkers[i]
        let next = allMarkers[i+1]
        if next.time - curr.time < params.dedupeWindowMs:
          # Keep engagement marker over scene marker
          if curr.source == csEngagement:
            allMarkers.delete(i+1)
          else:
            allMarkers.delete(i)
          continue
      i += 1

    # Apply minSpacing filter across combined list
    var spaced: seq[MarkerCandidate] = @[]
    if allMarkers.len > 0:
      spaced.add(allMarkers[0])

    for marker in allMarkers[1..^1]:
      if marker.time - spaced[^1].time >= params.minSpacingMs:
        spaced.add(marker)

    # Cap at maxChapters
    if spaced.len > params.maxChapters:
      let step = spaced.len div params.maxChapters
      var capped: seq[MarkerCandidate] = @[]
      for i in 0 ..< params.maxChapters:
        capped.add(spaced[i * step])
      spaced = capped

    # Generate chapters with proper titles and endMs
    var engagementCount = 0
    var sceneCount = 0
    for i, marker in spaced:
      let endMs = if i < spaced.len - 1:
                    spaced[i+1].time - 1
                  else:
                    timeline.duration

      var title: string
      if marker.source == csEngagement:
        engagementCount += 1
        let label = labelForScore(marker.score)
        title = "Peak #" & $engagementCount & " - " & label
      else:
        sceneCount += 1
        title = "Scene " & $sceneCount

      chapters.add(Chapter(
        startMs: marker.time,
        endMs: endMs,
        title: title,
        source: marker.source,
        score: marker.score
      ))

  else:
    # Unknown mode, return empty
    discard

  return chapters

proc chaptersToMetadata*(chapters: seq[Chapter]): seq[ChapterMarker] =
  ## Convert Chapters to ChapterMarker for MP4 metadata export
  ##
  ## Used by generateFFMetadata in metadata/apply.nim
  result = @[]
  for chapter in chapters:
    result.add(ChapterMarker(
      startMs: chapter.startMs,
      endMs: chapter.endMs,
      title: chapter.title
    ))

proc chaptersToMarkers*(chapters: seq[Chapter]): seq[Marker] =
  ## Convert Chapters to Marker for NLE export
  ##
  ## Args:
  ##   chapters: Sequence of Chapter objects
  ##
  ## Returns: Sequence of Marker objects with proper type, color, and metadata
  result = @[]
  for chapter in chapters:
    let markerType = if chapter.source == csEngagement:
                       mtEngagementPeak
                     else:
                       mtSceneBoundary

    let comment = if chapter.source == csEngagement:
                    "Score: " & $(chapter.score.int) & "/100"
                  else:
                    "Scene boundary"

    result.add(Marker(
      markerType: markerType,
      timestampMs: chapter.startMs,
      durationMs: chapter.endMs - chapter.startMs,
      name: chapter.title,
      comment: comment,
      color: getMarkerColor(markerType)
    ))
