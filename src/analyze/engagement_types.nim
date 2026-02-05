## Engagement scoring types and normalization utilities
##
## This module defines data structures for multi-modal engagement scoring.
## Engagement scores combine audio energy, motion levels, and speech features
## to identify the most engaging segments of a video.

import std/algorithm

type
  EngagementSegment* = object
    ## A scored video segment with multi-modal engagement data
    startMs*: int64              # Start timestamp in milliseconds
    endMs*: int64                # End timestamp in milliseconds
    text*: string                # Transcript text (empty for non-speech segments)
    score*: float32              # Combined engagement score (0-100)
    scoreRelative*: float32      # Score normalized within this video
    scoreAbsolute*: float32      # Score using fixed thresholds
    audioScore*: float32         # Raw audio energy score (0-100)
    motionScore*: float32        # Raw motion level score (0-100)
    speechScore*: float32        # Raw speech feature score (0-100)
    hasHook*: bool               # True if hook pattern detected
    hookMatches*: seq[string]    # Names of matched hook patterns
    faceCount*: int              # Number of stable faces in segment
    speaker*: int                # Speaker index (-1 = unassigned, 0+ = speaker)

  EngagementParams* = object
    ## Parameters for engagement analysis
    audioWeight*: float32        # Weight for audio signal (default 0.333)
    motionWeight*: float32       # Weight for motion signal (default 0.333)
    speechWeight*: float32       # Weight for speech signal (default 0.333)
    hookBoost*: float32          # Score boost for hooks (default 15.0)
    faceBoostPerFace*: float32   # Score boost per face (default 5.0, max 10.0 total)
    minSegmentDurationMs*: int64 # Minimum segment duration (default 2000ms)
    mergeThreshold*: float32     # Merge segments within N points (default 10.0)
    normalizeLowPct*: float      # Low percentile for normalization (default 0.05)
    normalizeHighPct*: float     # High percentile for normalization (default 0.95)

  EngagementTimeline* = object
    ## Full engagement analysis result
    segments*: seq[EngagementSegment]
    duration*: int64             # Total duration in milliseconds
    avgScore*: float32           # Average engagement score
    hookCount*: int              # Number of hooks detected
    params*: EngagementParams    # Parameters used (for reproducibility)

# Default parameters
proc defaultEngagementParams*(): EngagementParams =
  ## Create default engagement analysis parameters
  result.audioWeight = 0.333f
  result.motionWeight = 0.333f
  result.speechWeight = 0.333f
  result.hookBoost = 15.0f
  result.faceBoostPerFace = 5.0f
  result.minSegmentDurationMs = 2000
  result.mergeThreshold = 10.0f
  result.normalizeLowPct = 0.05
  result.normalizeHighPct = 0.95

# Helper constructors
proc newEngagementSegment*(startMs, endMs: int64): EngagementSegment =
  ## Create a new engagement segment with default values
  result.startMs = startMs
  result.endMs = endMs
  result.text = ""
  result.score = 0.0f
  result.scoreRelative = 0.0f
  result.scoreAbsolute = 0.0f
  result.audioScore = 0.0f
  result.motionScore = 0.0f
  result.speechScore = 0.0f
  result.hasHook = false
  result.hookMatches = @[]
  result.faceCount = 0
  result.speaker = -1

proc isEmpty*(seg: EngagementSegment): bool =
  ## Check if segment has no text (non-speech segment)
  seg.text.len == 0

proc durationMs*(seg: EngagementSegment): int64 =
  ## Calculate segment duration in milliseconds
  seg.endMs - seg.startMs

# Percentile-based normalization
proc computePercentileBounds*(signal: seq[float32], lowPct: float = 0.05,
                               highPct: float = 0.95): tuple[low, high: float32] =
  ## Compute percentile bounds without normalizing
  ## Returns (lowValue, highValue) at specified percentiles
  if signal.len == 0:
    return (0.0f, 0.0f)

  if signal.len == 1:
    return (signal[0], signal[0])

  # Sort a copy to find percentiles
  var sorted = signal
  sorted.sort()

  # Calculate percentile indices
  let lowIdx = int(float(sorted.len - 1) * lowPct)
  let highIdx = int(float(sorted.len - 1) * highPct)

  result.low = sorted[lowIdx]
  result.high = sorted[highIdx]

proc normalizeValue*(value: float32, lowVal, highVal: float32): float32 =
  ## Normalize single value given pre-computed percentile bounds
  ## Maps [lowVal, highVal] to [0, 100]
  if lowVal >= highVal:
    # Edge case: all values are the same
    return 50.0f

  # Clamp to bounds
  let clamped = if value < lowVal: lowVal
                elif value > highVal: highVal
                else: value

  # Scale to 0-100
  result = ((clamped - lowVal) / (highVal - lowVal)) * 100.0f

proc normalizePercentile*(signal: seq[float32], lowPct: float = 0.05,
                          highPct: float = 0.95): seq[float32] =
  ## Normalize signal to 0-100 using percentile range
  ## More robust than min-max for video data with outliers
  ##
  ## Example: With lowPct=0.05 and highPct=0.95, values below the 5th
  ## percentile are clamped to 0, values above 95th percentile clamped
  ## to 100, and values in between are scaled linearly.
  if signal.len == 0:
    return @[]

  if signal.len == 1:
    return @[50.0f]

  # Compute percentile bounds
  let bounds = computePercentileBounds(signal, lowPct, highPct)

  # Handle edge case: all values the same
  if bounds.low >= bounds.high:
    result = newSeq[float32](signal.len)
    for i in 0 ..< result.len:
      result[i] = 50.0f
    return result

  # Normalize each value
  result = newSeq[float32](signal.len)
  for i in 0 ..< signal.len:
    result[i] = normalizeValue(signal[i], bounds.low, bounds.high)

# Test block for development
when isMainModule:
  # Test basic normalization
  let signal = @[0.0f, 10.0f, 20.0f, 100.0f]
  let normalized = normalizePercentile(signal)
  echo "Input:  ", signal
  echo "Output: ", normalized

  # With default percentiles (5%, 95%), the 100.0 outlier should be clamped
  # 5th percentile is at index 0.15 (between 0.0 and 10.0)
  # 95th percentile is at index 2.85 (between 20.0 and 100.0)
  # So roughly [0.0-20.0] maps to [0-100]
  echo "Outlier (100.0) clamped: ", normalized[3] == 100.0f

  # Test edge cases
  echo "\nEdge cases:"
  echo "Empty: ", normalizePercentile(@[])
  echo "Single: ", normalizePercentile(@[42.0f])
  echo "All same: ", normalizePercentile(@[5.0f, 5.0f, 5.0f, 5.0f])
