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
