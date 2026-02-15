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
