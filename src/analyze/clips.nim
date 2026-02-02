## Clip boundary detection combining scene changes, engagement drops, and speech alignment
##
## This module provides automatic clip segmentation for short-form video export.
## Clips are detected by combining multiple signals:
##   - Scene changes (visual cuts from FFmpeg scdet filter)
##   - Engagement drops (score differences between segments)
##   - Speech boundaries (sentence ends for natural cuts)
##
## The multi-signal approach produces clips that feel like natural "moments"
## suitable for social media (TikTok, Reels, Shorts).

import std/[algorithm, strformat, strutils, osproc]
import engagement_types

type
  BoundaryReason* = enum
    ## Why a clip boundary was created
    SceneChange       # scdet filter detected visual cut
    EngagementDrop    # Score dropped > threshold
    SpeechBoundary    # Sentence end for natural cuts

  ClipBoundary* = object
    ## A single point where a clip should be split
    timestampMs*: int64
    reason*: BoundaryReason

  Clip* = object
    ## A detected video clip with engagement metadata
    startMs*: int64
    endMs*: int64
    engagementScore*: float32      # Average score from segments
    adjustedScore*: float32        # After overlap penalty
    text*: string                  # Combined transcript text
    audioScore*: float32           # Average audio score
    motionScore*: float32          # Average motion score
    speechScore*: float32          # Average speech score
    hasHook*: bool                 # Any segment has hook
    faceCount*: int                # Max faces in any segment
    rank*: int                     # Final rank (1 = best)

  ClipDetectionParams* = object
    ## Parameters for clip boundary detection and extraction
    engagementDropThreshold*: float32  # Score drop to trigger split (default 20.0)
    minClipDurationMs*: int64          # Minimum clip length (default 15000)
    maxClipDurationMs*: int64          # Maximum clip length (default 60000)
    targetClipDurationMs*: int64       # Target length (default 30000)
    mergeWindowMs*: int64              # Merge boundaries within window (default 2000)
    introSkipMs*: int64                # Skip first N ms (default 0)
    outroSkipMs*: int64                # Skip last N ms (default 0)

# ===== Default parameters =====

proc defaultClipDetectionParams*(): ClipDetectionParams =
  ## Create default clip detection parameters
  ##
  ## Optimized for short-form social media content:
  ##   - 15-60 second clips (target 30s)
  ##   - 20 point engagement drop threshold
  ##   - 2 second merge window for nearby boundaries
  result.engagementDropThreshold = 20.0f
  result.minClipDurationMs = 15000    # 15 seconds
  result.maxClipDurationMs = 60000    # 60 seconds
  result.targetClipDurationMs = 30000 # 30 seconds
  result.mergeWindowMs = 2000         # 2 seconds
  result.introSkipMs = 0
  result.outroSkipMs = 0

# ===== Helper functions =====

proc durationMs*(clip: Clip): int64 =
  ## Calculate clip duration in milliseconds
  clip.endMs - clip.startMs

proc mergeNearbyBoundaries*(boundaries: seq[ClipBoundary], windowMs: int64): seq[ClipBoundary] =
  ## Merge boundaries within windowMs, prefer SceneChange > EngagementDrop > SpeechBoundary
  ##
  ## When multiple boundaries fall within the window, keep the highest priority one:
  ##   1. SceneChange (visual cut is strongest signal)
  ##   2. EngagementDrop (content shift)
  ##   3. SpeechBoundary (avoid mid-sentence cuts)
  if boundaries.len == 0:
    return @[]

  result = @[]
  var currentGroup: seq[ClipBoundary] = @[boundaries[0]]

  for i in 1 ..< boundaries.len:
    let boundary = boundaries[i]
    let prevBoundary = currentGroup[^1]

    if boundary.timestampMs - prevBoundary.timestampMs <= windowMs:
      # Within merge window - add to current group
      currentGroup.add(boundary)
    else:
      # Outside window - commit current group and start new one
      # Find highest priority boundary in group
      var best = currentGroup[0]
      for b in currentGroup:
        if b.reason < best.reason:  # Lower enum value = higher priority
          best = b
      result.add(best)
      currentGroup = @[boundary]

  # Commit final group
  if currentGroup.len > 0:
    var best = currentGroup[0]
    for b in currentGroup:
      if b.reason < best.reason:
        best = b
    result.add(best)

# ===== Scene change detection =====

proc extractSceneChanges*(inputPath: string, threshold: float = 0.4): seq[float64] =
  ## Extract scene change timestamps using FFmpeg scdet filter
  ##
  ## Args:
  ##   inputPath: Path to video file
  ##   threshold: Scene change detection threshold (0.0-1.0, default 0.4)
  ##
  ## Returns:
  ##   Timestamps in seconds where scene changes detected
  ##
  ## Uses FFmpeg scdet filter with metadata output. Parses stderr for
  ## lavfi.scd.time entries which indicate when score > threshold.
  result = @[]

  # Run FFmpeg and capture output (stderr redirected to stdout)
  let output = execProcess("ffmpeg", args = @[
    "-i", inputPath,
    "-vf", &"scdet=t={threshold}:s=1",
    "-f", "null", "-"
  ], options = {poStdErrToStdOut, poUsePath})

  # Parse lavfi.scd.time from output
  # Format: "lavfi.scd.time: 12.345678"
  for line in output.splitLines():
    if "lavfi.scd.time" in line:
      let parts = line.split(":")
      if parts.len >= 2:
        try:
          let timestamp = parseFloat(parts[1].strip())
          result.add(timestamp)
        except ValueError:
          discard

# ===== Speech boundary helpers =====

proc findNearestSentenceBoundary*(timeline: EngagementTimeline,
                                   targetMs: int64,
                                   searchWindowMs: int64 = 2000): int64 =
  ## Find nearest segment end (sentence boundary) to target timestamp
  ##
  ## Returns original targetMs if no sentence boundary within window.
  ## Sentence boundaries are defined as the end of segments with text
  ## (non-speech segments like silence or music don't have boundaries).
  var bestMatch = targetMs
  var bestDistance = int64.high

  for seg in timeline.segments:
    if seg.text.len > 0:  # Only speech segments have sentence boundaries
      let distance = abs(seg.endMs - targetMs)
      if distance < bestDistance and distance <= searchWindowMs:
        bestDistance = distance
        bestMatch = seg.endMs

  return bestMatch

proc isWithinSpeech*(timeline: EngagementTimeline, timestampMs: int64): bool =
  ## Check if timestamp falls within a speech segment
  for seg in timeline.segments:
    if seg.text.len > 0 and seg.startMs <= timestampMs and timestampMs < seg.endMs:
      return true
  return false

# ===== Boundary detection =====

proc detectBoundaries*(timeline: EngagementTimeline,
                       sceneChanges: seq[float64],
                       params: ClipDetectionParams): seq[ClipBoundary] =
  ## Combine scene changes, engagement drops, and speech boundaries
  ##
  ## Multi-signal approach:
  ##   1. Add scene changes as primary boundaries (visual cuts)
  ##   2. Add engagement drops (score difference > threshold between segments)
  ##   3. Sort and merge nearby boundaries (within mergeWindowMs)
  ##   4. Align to sentence boundaries (extend to complete thoughts)
  ##
  ## Args:
  ##   timeline: Engagement analysis result with scored segments
  ##   sceneChanges: Scene change timestamps from extractSceneChanges
  ##   params: Detection parameters
  ##
  ## Returns:
  ##   Sorted sequence of clip boundaries with reasons
  var boundaries: seq[ClipBoundary] = @[]

  # 1. Add scene changes as primary boundaries
  for sceneTs in sceneChanges:
    boundaries.add(ClipBoundary(
      timestampMs: (sceneTs * 1000.0).int64,
      reason: SceneChange
    ))

  # 2. Add engagement drops (major score changes)
  for i in 1 ..< timeline.segments.len:
    let scoreDrop = timeline.segments[i-1].score - timeline.segments[i].score
    if scoreDrop >= params.engagementDropThreshold:
      boundaries.add(ClipBoundary(
        timestampMs: timeline.segments[i].startMs,
        reason: EngagementDrop
      ))

  # 3. Sort and merge nearby boundaries
  boundaries.sort(proc(a, b: ClipBoundary): int = cmp(a.timestampMs, b.timestampMs))
  boundaries = mergeNearbyBoundaries(boundaries, params.mergeWindowMs)

  # 4. Align to sentence boundaries (avoid mid-sentence cuts)
  # If boundary falls within speech segment, extend to segment.endMs
  for i in 0 ..< boundaries.len:
    let boundary = boundaries[i]
    if timeline.isWithinSpeech(boundary.timestampMs):
      # Extend to nearest sentence boundary
      boundaries[i].timestampMs = timeline.findNearestSentenceBoundary(
        boundary.timestampMs,
        params.mergeWindowMs
      )

  # Remove duplicates after alignment (multiple boundaries may align to same sentence end)
  var unique: seq[ClipBoundary] = @[]
  if boundaries.len > 0:
    unique.add(boundaries[0])
    for i in 1 ..< boundaries.len:
      if boundaries[i].timestampMs != unique[^1].timestampMs:
        unique.add(boundaries[i])

  return unique

# ===== Clip extraction =====

proc detectClips*(timeline: EngagementTimeline,
                  boundaries: seq[ClipBoundary],
                  params: ClipDetectionParams): seq[Clip] =
  ## Convert boundaries to clips, applying duration constraints
  ##
  ## Process:
  ##   1. Skip intro/outro based on params
  ##   2. Create clips between consecutive boundaries
  ##   3. Filter clips outside duration range
  ##   4. Calculate clip scores as weighted average of segment scores
  ##   5. Combine segment texts, hooks, face counts
  ##
  ## Args:
  ##   timeline: Engagement analysis result with scored segments
  ##   boundaries: Clip boundaries from detectBoundaries
  ##   params: Detection parameters
  ##
  ## Returns:
  ##   Sequence of clips with engagement metadata
  result = @[]

  if boundaries.len == 0:
    return result

  # Apply intro/outro skip
  let videoStartMs = params.introSkipMs
  let videoEndMs = timeline.duration - params.outroSkipMs

  # Create clips between consecutive boundaries
  var clipStarts: seq[int64] = @[videoStartMs]
  for boundary in boundaries:
    if boundary.timestampMs > videoStartMs and boundary.timestampMs < videoEndMs:
      clipStarts.add(boundary.timestampMs)
  clipStarts.add(videoEndMs)

  # Build clips from boundaries
  for i in 0 ..< clipStarts.len - 1:
    let startMs = clipStarts[i]
    let endMs = clipStarts[i + 1]
    let durationMs = endMs - startMs

    # Filter by duration constraints
    if durationMs < params.minClipDurationMs or durationMs > params.maxClipDurationMs:
      continue

    # Calculate clip scores from segments
    var totalScore = 0.0f
    var totalAudioScore = 0.0f
    var totalMotionScore = 0.0f
    var totalSpeechScore = 0.0f
    var segmentCount = 0
    var texts: seq[string] = @[]
    var hasHook = false
    var maxFaceCount = 0

    for seg in timeline.segments:
      # Check if segment overlaps with clip
      if seg.endMs > startMs and seg.startMs < endMs:
        totalScore += seg.score
        totalAudioScore += seg.audioScore
        totalMotionScore += seg.motionScore
        totalSpeechScore += seg.speechScore
        segmentCount += 1

        if seg.text.len > 0:
          texts.add(seg.text)

        if seg.hasHook:
          hasHook = true

        if seg.faceCount > maxFaceCount:
          maxFaceCount = seg.faceCount

    # Skip clips with no segments (shouldn't happen, but guard)
    if segmentCount == 0:
      continue

    # Create clip with averaged scores
    result.add(Clip(
      startMs: startMs,
      endMs: endMs,
      engagementScore: totalScore / segmentCount.float32,
      adjustedScore: totalScore / segmentCount.float32,  # Will be adjusted during ranking
      text: texts.join(" "),
      audioScore: totalAudioScore / segmentCount.float32,
      motionScore: totalMotionScore / segmentCount.float32,
      speechScore: totalSpeechScore / segmentCount.float32,
      hasHook: hasHook,
      faceCount: maxFaceCount,
      rank: 0  # Will be set during ranking
    ))
