## Main engagement scoring module combining audio, motion, speech, and face signals
##
## This module implements the core engagement algorithm that:
## - Aligns signals from different timebases to sentence boundaries
## - Normalizes audio and motion signals using percentile ranges
## - Scores speech features (rate, confidence)
## - Detects hooks with text + prosody indicators
## - Applies face detection boosts
## - Produces both relative (within-video) and absolute (cross-video) scores

import std/[math, algorithm, sequtils, options]
import ./engagement_types
import ./hooks
import ./audio
import ./motion
import ./faces
import ../transcript/types
import ../av
import ../ffmpeg
import ../util/bar

# ===== Signal alignment helpers =====

proc msToIndex*(ms: int64, tb: AVRational): int64 =
  ## Convert milliseconds to timebase index
  (ms * tb.num) div (1000 * tb.den)

proc indexToMs*(index: int64, tb: AVRational): int64 =
  ## Convert timebase index to milliseconds
  (index * 1000 * tb.den) div tb.num

proc getSignalRange*(signal: seq[float32], startIdx, endIdx: int64): seq[float32] =
  ## Extract signal values for index range, handling bounds
  let safeStart = max(0, startIdx.int)
  let safeEnd = min(signal.len, endIdx.int)
  if safeStart >= safeEnd:
    return @[]
  signal[safeStart..<safeEnd]

proc averageSignal*(signal: seq[float32], startIdx, endIdx: int64): float32 =
  ## Average signal over index range
  let range = getSignalRange(signal, startIdx, endIdx)
  if range.len == 0:
    return 0.0f
  var sum: float32 = 0.0f
  for v in range:
    sum += v
  sum / range.len.float32

# ===== Face counting helper =====

proc countFacesInRange*(faceFrames: seq[FrameFaces], startMs, endMs: int64): int =
  ## Count stable faces in time range (max face count from any frame)
  var maxFaces = 0
  for frame in faceFrames:
    let frameMs = (frame.timestamp * 1000.0).int64
    if frameMs >= startMs and frameMs <= endMs:
      var stableCount = 0
      for face in frame.faces:
        if face.stable:
          stableCount += 1
      maxFaces = max(maxFaces, stableCount)
  maxFaces

# ===== Speech feature scoring =====

proc scoreSpeechFeatures*(words: seq[Word]): float32 =
  ## Score speech features: rate, pauses, confidence
  ## Returns 0-100 score based on speaking characteristics
  if words.len == 0:
    return 50.0f  # Neutral for non-speech

  # Calculate features
  let durationMs = words[^1].endMs - words[0].startMs
  if durationMs <= 0:
    return 50.0f

  let wordsPerMinute = (words.len.float * 60000.0) / durationMs.float
  let avgConfidence = words.mapIt(it.confidence).foldl(a + b, 0.0) / words.len.float

  # Score: Higher is more engaging
  # Optimal speaking rate: 120-180 wpm
  var rateScore: float32 = 0.0
  if wordsPerMinute < 80:
    rateScore = 30.0  # Too slow
  elif wordsPerMinute < 120:
    rateScore = 50.0 + (wordsPerMinute - 80) * 0.5
  elif wordsPerMinute <= 180:
    rateScore = 70.0 + (wordsPerMinute - 120) * 0.5
  else:
    rateScore = max(50.0, 100.0 - (wordsPerMinute - 180) * 0.3)  # Too fast

  # Confidence factor
  let confidenceScore = avgConfidence.float32 * 100.0

  # Combine (60% rate, 40% confidence)
  (rateScore * 0.6 + confidenceScore * 0.4)

# ===== Absolute scoring helper =====

proc scoreAbsolute*(audioRaw, motionRaw, speechScore: float32,
                    faceCount: int, hasHook: bool,
                    params: EngagementParams): float32 =
  ## Score using fixed thresholds for cross-video comparison
  ## Audio: 0-0.5 raw maps to 0-100
  ## Motion: 0-0.3 raw maps to 0-100

  # Fixed thresholds based on typical video ranges
  let audioThreshold = 0.5f
  let motionThreshold = 0.3f

  # Normalize to 0-100
  let audioNorm = min(audioRaw / audioThreshold, 1.0f) * 100.0f
  let motionNorm = min(motionRaw / motionThreshold, 1.0f) * 100.0f

  # Base score with signal weights
  var score = (audioNorm * params.audioWeight +
               motionNorm * params.motionWeight +
               speechScore * params.speechWeight)

  # Apply boosts
  if faceCount > 0:
    let faceBoost = min(faceCount.float32 * params.faceBoostPerFace, 10.0f)
    score += faceBoost

  if hasHook:
    score += params.hookBoost

  # Clamp to 0-100
  result = min(max(score, 0.0f), 100.0f)

# ===== Segment scoring =====

proc scoreSegment*(startMs, endMs: int64, text: string, words: seq[Word],
                   audioSignal, motionSignal: seq[float32],
                   audioNormBounds, motionNormBounds: tuple[low, high: float32],
                   faceFrames: seq[FrameFaces],
                   hookPatterns: seq[HookPattern],
                   avgAudioEnergy: float32,
                   tb: AVRational,
                   params: EngagementParams): EngagementSegment =
  ## Score a single segment combining all signals

  # Initialize result
  result = newEngagementSegment(startMs, endMs)
  result.text = text

  # Convert timestamps to indices
  let startIdx = msToIndex(startMs, tb)
  let endIdx = msToIndex(endMs, tb)

  # Get raw audio and motion averages for segment
  let audioRaw = averageSignal(audioSignal, startIdx, endIdx)
  let motionRaw = averageSignal(motionSignal, startIdx, endIdx)

  # Normalize to 0-100 using pre-computed bounds (relative scoring)
  result.audioScore = normalizeValue(audioRaw, audioNormBounds.low, audioNormBounds.high)
  result.motionScore = normalizeValue(motionRaw, motionNormBounds.low, motionNormBounds.high)

  # Score speech features from words
  result.speechScore = scoreSpeechFeatures(words)

  # Count faces in this segment
  result.faceCount = countFacesInRange(faceFrames, startMs, endMs)

  # Detect hooks (text + prosody)
  let audioSegment = getSignalRange(audioSignal, startIdx, endIdx)
  let hookResult = detectHook(text, audioSegment, avgAudioEnergy, hookPatterns)
  result.hasHook = hookResult.isHook

  # Calculate combined relative score
  var relativeScore = (result.audioScore * params.audioWeight +
                       result.motionScore * params.motionWeight +
                       result.speechScore * params.speechWeight)

  # Apply face boost
  if result.faceCount > 0:
    let faceBoost = min(result.faceCount.float32 * params.faceBoostPerFace, 10.0f)
    relativeScore += faceBoost

  # Apply hook boost
  if result.hasHook:
    relativeScore += params.hookBoost

  # Clamp to 0-100
  result.scoreRelative = min(max(relativeScore, 0.0f), 100.0f)

  # Calculate absolute score using fixed thresholds
  result.scoreAbsolute = scoreAbsolute(audioRaw, motionRaw, result.speechScore,
                                       result.faceCount, result.hasHook, params)

  # Use relative as primary score
  result.score = result.scoreRelative

# ===== Segment merging helper =====

proc mergeAdjacentSegments*(segments: seq[EngagementSegment],
                             threshold: float32): seq[EngagementSegment] =
  ## Merge adjacent segments with scores within threshold
  ## Preserves hook flags (merged segment is hook if either was)
  if segments.len == 0:
    return @[]

  result = @[segments[0]]

  for i in 1..<segments.len:
    let prev = result[^1]
    let curr = segments[i]

    # Check if adjacent and score difference within threshold
    if prev.endMs == curr.startMs and abs(prev.score - curr.score) <= threshold:
      # Merge: create weighted average
      let totalDuration = prev.durationMs + curr.durationMs
      let mergedScore = ((prev.score * prev.durationMs.float32) +
                         (curr.score * curr.durationMs.float32)) / totalDuration.float32

      var merged = newEngagementSegment(prev.startMs, curr.endMs)
      merged.text = if prev.text.len > 0 and curr.text.len > 0:
                      prev.text & " " & curr.text
                    elif prev.text.len > 0:
                      prev.text
                    else:
                      curr.text
      merged.score = mergedScore
      merged.scoreRelative = mergedScore
      merged.scoreAbsolute = ((prev.scoreAbsolute * prev.durationMs.float32) +
                              (curr.scoreAbsolute * curr.durationMs.float32)) / totalDuration.float32
      merged.audioScore = ((prev.audioScore * prev.durationMs.float32) +
                           (curr.audioScore * curr.durationMs.float32)) / totalDuration.float32
      merged.motionScore = ((prev.motionScore * prev.durationMs.float32) +
                            (curr.motionScore * curr.durationMs.float32)) / totalDuration.float32
      merged.speechScore = ((prev.speechScore * prev.durationMs.float32) +
                            (curr.speechScore * curr.durationMs.float32)) / totalDuration.float32
      merged.hasHook = prev.hasHook or curr.hasHook
      merged.faceCount = max(prev.faceCount, curr.faceCount)
      merged.speaker = if prev.speaker == curr.speaker: prev.speaker else: -1

      # Replace last segment with merged
      result[^1] = merged
    else:
      # Not mergeable, add current segment
      result.add(curr)

# ===== Non-speech segment creation =====

proc createNonSpeechSegments*(transcript: Transcript, duration: int64,
                               minGapMs: int64 = 2000): seq[tuple[startMs, endMs: int64]] =
  ## Find gaps in transcript > minGapMs for non-speech scoring
  result = @[]

  if transcript.segments.len == 0:
    # Entire video is non-speech
    result.add((0'i64, duration))
    return

  # Check gap at start
  if transcript.segments[0].startMs >= minGapMs:
    result.add((0'i64, transcript.segments[0].startMs))

  # Check gaps between segments
  for i in 0..<transcript.segments.len - 1:
    let gap = transcript.segments[i + 1].startMs - transcript.segments[i].endMs
    if gap >= minGapMs:
      result.add((transcript.segments[i].endMs, transcript.segments[i + 1].startMs))

  # Check gap at end
  let lastEndMs = transcript.segments[^1].endMs
  if duration - lastEndMs >= minGapMs:
    result.add((lastEndMs, duration))

# ===== Main engagement analysis API =====

proc analyzeEngagement*(bar: Bar, container: InputContainer, path: string,
                        transcript: Transcript, tb: AVRational,
                        params: EngagementParams = defaultEngagementParams(),
                        hookPatterns: seq[HookPattern] = loadBuiltinPatterns(),
                        useFaceDetection: bool = true): EngagementTimeline =
  ## Main engagement analysis API
  ## Combines audio, motion, speech, and face signals into engagement scores

  # 1. Get audio signal
  let audioSignal = audio(bar, container, path, tb, 0)

  # 2. Get motion signal
  let motionSignal = motion(bar, container, path, tb, 0, 160, 1)

  # 3. Get face frames (if enabled)
  var faceFrames: seq[FrameFaces] = @[]
  if useFaceDetection:
    # Use default FaceAnalysisParams
    faceFrames = faces(bar, container, path, tb)

  # 4. Compute normalization bounds for audio and motion
  let audioNormBounds = computePercentileBounds(audioSignal,
                                                 params.normalizeLowPct,
                                                 params.normalizeHighPct)
  let motionNormBounds = computePercentileBounds(motionSignal,
                                                  params.normalizeLowPct,
                                                  params.normalizeHighPct)

  # 5. Compute average audio energy for prosody detection
  var avgAudioEnergy: float32 = 0.0f
  if audioSignal.len > 0:
    var sum: float32 = 0.0f
    for v in audioSignal:
      sum += v
    avgAudioEnergy = sum / audioSignal.len.float32

  # 6. Build segments from transcript
  var segments: seq[EngagementSegment] = @[]

  # Score transcript segments (speech)
  for tseg in transcript.segments:
    let seg = scoreSegment(
      tseg.startMs, tseg.endMs, tseg.text, tseg.words,
      audioSignal, motionSignal,
      audioNormBounds, motionNormBounds,
      faceFrames, hookPatterns, avgAudioEnergy,
      tb, params
    )
    segments.add(seg)

  # Score non-speech segments
  let nonSpeechGaps = createNonSpeechSegments(transcript, transcript.duration, 2000)
  for gap in nonSpeechGaps:
    let seg = scoreSegment(
      gap.startMs, gap.endMs, "", @[],  # No text, no words
      audioSignal, motionSignal,
      audioNormBounds, motionNormBounds,
      faceFrames, hookPatterns, avgAudioEnergy,
      tb, params
    )
    segments.add(seg)

  # Sort segments by start time
  segments.sort(proc(a, b: EngagementSegment): int = cmp(a.startMs, b.startMs))

  # 7. Merge adjacent segments within threshold
  segments = mergeAdjacentSegments(segments, params.mergeThreshold)

  # 8. Rate limit hooks (max 3 per minute)
  var hookCandidates: seq[tuple[timestampMs: int64, result: HookResult]] = @[]
  for seg in segments:
    if seg.hasHook:
      # Create HookResult from segment
      let hookRes = HookResult(
        isHook: true,
        textMatches: @[],  # Already detected
        hasProsodyIndicator: true,
        confidence: 0.8f  # Default confidence for detected hooks
      )
      hookCandidates.add((seg.startMs, hookRes))

  let rateLimitedHooks = rateLimitHooks(hookCandidates, maxPerMinute = 3)

  # Update hook flags based on rate limiting
  for i, seg in segments:
    if seg.hasHook:
      if seg.startMs notin rateLimitedHooks:
        segments[i].hasHook = false

  # 9. Calculate timeline stats
  var avgScore: float32 = 0.0f
  var hookCount = 0
  for seg in segments:
    avgScore += seg.score * seg.durationMs.float32
    if seg.hasHook:
      hookCount += 1

  if transcript.duration > 0:
    avgScore = avgScore / transcript.duration.float32

  # 10. Return timeline
  result = EngagementTimeline(
    segments: segments,
    duration: transcript.duration,
    avgScore: avgScore,
    hookCount: hookCount,
    params: params
  )

# ===== Test block =====

when isMainModule:
  # Test signal alignment round-trip
  echo "Test 1: msToIndex/indexToMs round-trip"
  let tb = AVRational(num: 1, den: 1000)
  let ms = 1000'i64
  let idx = msToIndex(ms, tb)
  let msBack = indexToMs(idx, tb)
  echo "  Input: ", ms, "ms"
  echo "  Index: ", idx
  echo "  Back to ms: ", msBack
  echo "  Round-trip correct: ", msBack == ms

  # Test averageSignal
  echo "\nTest 2: averageSignal"
  let signal = @[1.0f, 2.0f, 3.0f]
  let avg = averageSignal(signal, 0, 3)
  echo "  Signal: ", signal
  echo "  Average: ", avg
  echo "  Correct (2.0): ", avg == 2.0f

  # Test speech scoring
  echo "\nTest 3: scoreSpeechFeatures range"
  let words = @[
    newWord("test", 0, 500, 0.9),
    newWord("words", 500, 1000, 0.8)
  ]
  let speechScore = scoreSpeechFeatures(words)
  echo "  Score: ", speechScore
  echo "  In range [0-100]: ", speechScore >= 0.0 and speechScore <= 100.0

  # Test segment scoring
  echo "\nTest 4: scoreSegment"
  let audioSig = @[0.2f, 0.3f, 0.4f, 0.3f]
  let motionSig = @[0.1f, 0.2f, 0.15f, 0.1f]
  let normBounds = (low: 0.0f, high: 1.0f)
  let faceFrames: seq[FrameFaces] = @[]
  let patterns = loadBuiltinPatterns()
  let params = defaultEngagementParams()

  let segment = scoreSegment(
    0, 1000, "test", words,
    audioSig, motionSig,
    normBounds, normBounds,
    faceFrames, patterns, 0.3f, tb, params
  )
  echo "  Segment score: ", segment.score
  echo "  Score in range [0-100]: ", segment.score >= 0.0 and segment.score <= 100.0
  echo "  Has audio/motion/speech scores: ",
    segment.audioScore > 0 or segment.motionScore > 0 or segment.speechScore > 0

  # Test main API signature (integration test would need real video)
  echo "\nTest 5: analyzeEngagement signature"
  echo "  API exports: analyzeEngagement, scoreSegment, mergeAdjacentSegments"
  echo "  Helper exports: msToIndex, indexToMs, averageSignal, countFacesInRange"
  echo "  All functions defined and accessible"
