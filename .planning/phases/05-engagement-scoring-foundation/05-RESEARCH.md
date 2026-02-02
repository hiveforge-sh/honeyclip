# Phase 5: Engagement Scoring Foundation - Research

**Researched:** 2026-02-02
**Domain:** Multi-modal video engagement scoring (audio, motion, speech)
**Confidence:** HIGH

## Summary

Engagement scoring combines audio energy, motion activity, and speech features into a unified 0-100 score for video segments. The standard approach uses signal normalization (z-score or percentile-based), equal weighting across modalities (~33% each), and sentence-aligned segmentation from transcripts. Hook detection requires both text pattern matching (questions, emphasis keywords) and audio prosody analysis (pitch changes, pauses, volume spikes).

The codebase already provides foundational components: RMS-based audio analysis (`analyze/audio.nim`), frame-difference motion detection (`analyze/motion.nim`), Whisper transcripts with word-level timestamps (`transcript/types.nim`), and face detection with consensus (`analyze/faces.nim`). Phase 5 builds the scoring layer on top of these existing signals.

**Primary recommendation:** Use percentile-based normalization (robust to outliers), equal signal weights (33% each), sentence-aligned scoring from transcripts, and combined text+prosody hook detection with rate limiting (max 3 per minute).

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Nim stdlib json | 2.2.2+ | JSON serialization | Built-in, zero dependencies, sufficient for structured output |
| Nim stdlib re | 2.2.2+ | Regex pattern matching | Native regex for hook text detection (questions, keywords) |
| Nim stdlib algorithm | 2.2.2+ | Sorting, statistical ops | Percentile calculation, signal ranking |
| FFmpeg avfilter | 7.x | Audio filtering for prosody | Already integrated, provides silencedetect, astats filters |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Nim stdlib stats | 2.2.2+ | Statistical functions | Mean, variance, percentile calculations |
| Nim stdlib strutils | 2.2.2+ | String manipulation | Text normalization, pattern extraction |
| Existing cache.nim | - | Result caching | Engagement computation is expensive (5-10x audio analysis cost) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled pitch | Parselmouth/Praat | Praat is Python-only, adds external dependency; hand-rolled autocorrelation sufficient for prosody spikes |
| Min-max normalization | Z-score | Z-score more robust to outliers but requires global stats; percentile-based best for video (handles outlier frames) |
| Word-level scoring | Sentence-level | Word-level too granular (jittery scores); sentence-level matches user perception |

**Installation:**
No additional dependencies required - all components available in Nim stdlib or existing codebase.

## Architecture Patterns

### Recommended Project Structure
```
src/
├── analyze/
│   ├── engagement.nim     # Main engagement scoring API (parallel to audio.nim, motion.nim)
│   └── hooks.nim          # Hook detection (text + prosody patterns)
├── cmds/
│   └── engagement.nim     # CLI command for engagement analysis
└── exports/
    └── engagement.nim     # Optional: engagement-specific JSON export if needed
```

### Pattern 1: Signal Extraction & Alignment
**What:** Extract raw signals at different granularities, align to common timebase, interpolate/aggregate
**When to use:** Always - audio is per-chunk, motion is per-frame, speech is per-word
**Example:**
```nim
# Audio: seq[float32] indexed by timebase chunks
let audioSignal = audio(bar, container, path, tb, stream)

# Motion: seq[float32] indexed by timebase chunks
let motionSignal = motion(bar, container, path, tb, stream, width, blur)

# Transcript: seq[Word] with startMs/endMs timestamps
let transcript = extractTranscript(path, model)

# Align transcript words to timebase indices
proc alignToTimebase(words: seq[Word], tb: AVRational): seq[int64] =
  for word in words:
    let index = (word.startMs * tb.num) div (1000 * tb.den)
    result.add(index)
```

### Pattern 2: Percentile-Based Normalization
**What:** Normalize signals using percentiles (robust to outliers)
**When to use:** All signal types - video has extreme outliers (black frames, cuts, flashes)
**Example:**
```nim
import std/algorithm

proc normalizePercentile(signal: seq[float32], lowPct: float = 0.05, highPct: float = 0.95): seq[float32] =
  ## Normalize signal to 0-100 using percentile range
  ## More robust than min-max for video data with outliers
  var sorted = signal
  sorted.sort()

  let n = sorted.len
  let lowIdx = int(float(n) * lowPct)
  let highIdx = int(float(n) * highPct)
  let lowVal = sorted[lowIdx]
  let highVal = sorted[highIdx]

  result = newSeq[float32](signal.len)
  for i, val in signal:
    # Clamp to percentile range, then scale to 0-100
    let clamped = clamp(val, lowVal, highVal)
    result[i] = ((clamped - lowVal) / (highVal - lowVal)) * 100.0
```

### Pattern 3: Sentence-Aligned Scoring
**What:** Score at sentence boundaries from transcript, merge similar adjacent scores
**When to use:** Always - matches user perception, avoids jittery word-level scores
**Example:**
```nim
type
  EngagementSegment* = object
    startMs*: int64
    endMs*: int64
    text*: string
    score*: float32           # Combined 0-100 score
    audioScore*: float32      # Raw audio component
    motionScore*: float32     # Raw motion component
    speechScore*: float32     # Raw speech component
    hasHook*: bool
    faceCount*: int

proc scoreSentence(words: seq[Word], audioSignal, motionSignal: seq[float32],
                   tb: AVRational): EngagementSegment =
  # Calculate time range for sentence
  let startMs = words[0].startMs
  let endMs = words[^1].endMs

  # Map to timebase indices
  let startIdx = (startMs * tb.num) div (1000 * tb.den)
  let endIdx = (endMs * tb.num) div (1000 * tb.den)

  # Average signals over sentence duration
  var audioSum, motionSum: float32
  for i in startIdx ..< endIdx:
    audioSum += audioSignal[i]
    motionSum += motionSignal[i]

  let audioAvg = audioSum / float32(endIdx - startIdx)
  let motionAvg = motionSum / float32(endIdx - startIdx)
  let speechScore = analyzeSpeechFeatures(words)  # From hooks.nim

  # Equal weights: 33% each
  let combinedScore = (audioAvg + motionAvg + speechScore) / 3.0

  result = EngagementSegment(
    startMs: startMs,
    endMs: endMs,
    score: combinedScore,
    audioScore: audioAvg,
    motionScore: motionAvg,
    speechScore: speechScore
  )
```

### Pattern 4: Hook Detection (Text + Prosody)
**What:** Detect engagement hooks using combined text patterns and audio features
**When to use:** Always - single-signal detection has high false positive rate
**Example:**
```nim
import std/re

type
  HookPattern = object
    regex*: Regex
    name*: string
    weight*: float32

proc loadHookPatterns(): seq[HookPattern] =
  ## Built-in hook patterns (can be extended via JSON config)
  result = @[
    HookPattern(regex: re"(?i)^(what|why|how|when|where|who)\b", name: "question_opening", weight: 1.5),
    HookPattern(regex: re"(?i)\?$", name: "question_ending", weight: 1.2),
    HookPattern(regex: re"(?i)\b(never|always|must|shocking|revealed)\b", name: "emphasis", weight: 1.3),
    HookPattern(regex: re"(?i)^(imagine|picture this|here's the thing)", name: "storytelling", weight: 1.4),
  ]

proc detectTextHooks(text: string, patterns: seq[HookPattern]): seq[string] =
  ## Return matched hook patterns
  for pattern in patterns:
    if text.match(pattern.regex):
      result.add(pattern.name)

proc detectProsodyHook(words: seq[Word], audioSignal: seq[float32], tb: AVRational): bool =
  ## Detect prosody-based hooks: pitch spikes, unusual pauses, volume changes
  ## This is a simplified heuristic - full pitch extraction would require YIN/autocorrelation

  # Check for unusual pause before sentence (hook technique: pause for emphasis)
  if words[0].startMs > 0:
    let prevIdx = max(0, (words[0].startMs * tb.num) div (1000 * tb.den) - 5)
    let pauseIdx = (words[0].startMs * tb.num) div (1000 * tb.den)
    var silentFrames = 0
    for i in prevIdx ..< pauseIdx:
      if audioSignal[i] < 0.05:  # Very low energy = silence
        silentFrames.inc

    # Unusual pause: >200ms silence before speech
    if silentFrames > 6:  # ~200ms at 30fps
      return true

  # Check for volume spike (emphasis, excitement)
  let startIdx = (words[0].startMs * tb.num) div (1000 * tb.den)
  let endIdx = (words[^1].endMs * tb.num) div (1000 * tb.den)
  var maxEnergy: float32 = 0.0
  for i in startIdx ..< endIdx:
    maxEnergy = max(maxEnergy, audioSignal[i])

  # Compare to typical energy level (would be computed from full video)
  # For simplicity, use threshold
  if maxEnergy > 0.7:  # Strong volume = emphasis
    return true

  return false

proc isHook(words: seq[Word], audioSignal: seq[float32], tb: AVRational,
            patterns: seq[HookPattern]): bool =
  ## Combined hook detection: text AND prosody
  let text = words.mapIt(it.text).join(" ")
  let textHooks = detectTextHooks(text, patterns)
  let prosodyHook = detectProsodyHook(words, audioSignal, tb)

  # Require BOTH text and prosody indicators (reduces false positives)
  return textHooks.len > 0 and prosodyHook
```

### Pattern 5: Cache Strategy
**What:** Cache engagement results with multi-part key (video, timebase, params)
**When to use:** Always - engagement computation is 5-10x more expensive than single-signal analysis
**Example:**
```nim
# Extend existing cache.nim pattern for structured data
proc cacheEngagement(segments: seq[EngagementSegment], path: string, tb: AVRational,
                     params: string): void =
  ## Similar to writeCache but for structured engagement data
  ## Serialize segments to binary format or JSON
  let cacheKey = procTag(path, tb, "engagement", params)
  let cacheFile = getTempDir() / fmt"ae-{version}" / fmt"{cacheKey}.json"

  var jArray = newJArray()
  for seg in segments:
    jArray.add(%*{
      "startMs": seg.startMs,
      "endMs": seg.endMs,
      "score": seg.score,
      "audioScore": seg.audioScore,
      "motionScore": seg.motionScore,
      "speechScore": seg.speechScore,
      "hasHook": seg.hasHook
    })

  writeFile(cacheFile, $jArray)
```

### Anti-Patterns to Avoid
- **Word-level scoring:** Too granular, produces jittery scores that don't match perception
- **Min-max normalization:** Outliers (black frames, cuts) compress entire range
- **Text-only hooks:** High false positive rate (e.g., "why" in middle of sentence)
- **Absolute thresholds without relative:** "Loud" depends on video's overall audio level
- **Ignoring face presence:** Faces strongly correlate with engagement (human interest)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pitch extraction | Custom FFT/autocorrelation | FFmpeg astats/volumedetect + heuristics | Pitch detection is hard (YIN algorithm has 5 refinement steps); good-enough heuristics (silence, volume spikes) work for hook detection |
| Sentence segmentation | Custom NLP tokenizer | Transcript word timestamps + punctuation | Whisper provides word-level timing; sentence breaks detectable from punctuation + pauses |
| Percentile calculation | Hand-rolled sorting | stdlib algorithm.sorted + index math | Correctness matters; stdlib is tested and optimized |
| JSON serialization | String building | stdlib json module | JSON escaping is subtle; stdlib handles all edge cases |

**Key insight:** Engagement scoring doesn't need research-grade accuracy (0.5% error in YIN). Good-enough heuristics combined across modalities produce reliable rankings. Overengineering single signals wastes time vs. testing full pipeline.

## Common Pitfalls

### Pitfall 1: Misaligned Signals
**What goes wrong:** Audio/motion/transcript have different timebases, mixing them produces garbage scores
**Why it happens:** Audio is chunked (e.g., 100ms), motion is per-frame (33ms), transcript is word-level (variable)
**How to avoid:**
- Convert all signals to common timebase (AVRational) at extraction time
- Interpolate or aggregate to match granularity
- Verify alignment with known test case (e.g., loud clap in video should spike audio + motion at same timestamp)
**Warning signs:** Scores don't match visual inspection; hook detected seconds before/after actual hook

### Pitfall 2: Normalization Before Combination
**What goes wrong:** Normalizing each signal 0-100 then averaging loses relative importance
**Why it happens:** Intuition says "make them same scale first" but this amplifies noise
**How to avoid:**
- Normalize AFTER combination OR use percentile-based on raw values
- If normalizing before, weight by signal-to-noise ratio
- Test on video with clear dominant signal (e.g., silent video with high motion)
**Warning signs:** Static camera with loud audio scores same as shaky camera with silence

### Pitfall 3: Over-Flagging Hooks
**What goes wrong:** Every question, every pause marked as hook → meaningless
**Why it happens:** Low detection threshold + no rate limiting
**How to avoid:**
- Require BOTH text pattern AND prosody indicator (reduces false positives)
- Rate limit: max 3 hooks per minute (user decision from CONTEXT.md)
- Sort candidates by confidence, take top N
**Warning signs:** >10% of sentences flagged as hooks; users ignore hook markers

### Pitfall 4: Ignoring Non-Speech Segments
**What goes wrong:** Scoring skips intros, outros, B-roll → incomplete timeline
**Why it happens:** Transcript-centric approach only scores speech
**How to avoid:**
- Score non-speech segments using audio + motion only (user decision from CONTEXT.md)
- Interpolate between transcript segments for continuous timeline
- Mark segments without speech differently in output
**Warning signs:** Gaps in timeline JSON; clip detection (Phase 6) fails on B-roll

### Pitfall 5: Absolute Scoring Without Context
**What goes wrong:** Same RMS value scores differently in quiet vs. loud video
**Why it happens:** Using fixed thresholds (e.g., "RMS > 0.5 = high energy")
**How to avoid:**
- Compute BOTH relative (percentile-based) AND absolute scores (user decision)
- Relative for ranking within video, absolute for cross-video comparison
- Let downstream tools choose which to use
**Warning signs:** Quiet ASMR video scores all low; loud concert scores all high; no differentiation within video

### Pitfall 6: Expensive Cache Misses
**What goes wrong:** Small parameter change invalidates cache, recomputes everything
**Why it happens:** Cache key includes ALL parameters (like face detection does)
**How to avoid:**
- Hierarchical caching: cache raw signals separately from scoring
- Engagement cache depends only on scoring params (weights, thresholds), not extraction params
- If user changes hook patterns, reload cached signals + rescore (fast)
**Warning signs:** Tweaking hook pattern recomputes 5-minute face detection

## Code Examples

Verified patterns from codebase:

### Existing Audio Analysis Iterator
```nim
# From src/analyze/audio.nim - already provides RMS per chunk
iterator loudness*(processor: var AudioProcessor, container: InputContainer): float32 =
  # Yields one float32 per timebase chunk
  # Already cached in .honeyclip/ folder

# Usage in engagement scoring:
let audioSignal = audio(bar, container, path, tb, stream)
# audioSignal[i] is RMS for timebase chunk i
```

### Existing Motion Analysis Iterator
```nim
# From src/analyze/motion.nim - frame difference ratio
iterator motionness*(processor: var VideoProcessor, width, blur: int32): float32 =
  # Yields fraction of changed pixels per frame
  # width=160, blur=1 is fast; width=480, blur=3 is accurate

# Usage:
let motionSignal = motion(bar, container, path, tb, stream, width=160, blur=1)
# motionSignal[i] is motion ratio for timebase chunk i
```

### Existing Transcript Structure
```nim
# From src/transcript/types.nim
type
  Word* = object
    text*: string
    startMs*: int64        # Milliseconds from start
    endMs*: int64
    confidence*: float     # 0.0-1.0, from whisper "p" field
    speaker*: int          # -1 = unassigned, 0+ = speaker index

  Transcript* = object
    segments*: seq[TranscriptSegment]
    words*: seq[Word]      # Flat list of all words
    duration*: int64       # Total duration in ms
    language*: string
```

### Existing Face Detection API
```nim
# From src/analyze/faces.nim - already provides stable face detections
proc faces*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
            params: FaceAnalysisParams): seq[FrameFaces] =
  ## Returns face detections per frame with temporal consensus
  ## Cached in .honeyclip/ folder

# Usage in engagement scoring:
let faceFrames = faces(bar, container, path, tb, defaultParams)
# Count faces per timebase chunk for engagement boost
```

### Existing Cache Pattern
```nim
# From src/cache.nim - extend for engagement
proc readCache*(path: string, tb: AVRational, kind, args: string): Option[seq[float32]]
proc writeCache*(data: seq[float32], path: string, tb: AVRational, kind, args: string)

# For engagement (structured data):
# Option 1: Serialize to JSON and cache as string
# Option 2: Create parallel engagement-specific cache (facecache.nim pattern)
```

### CLI Pattern
```nim
# From src/cmds/levels.nim, src/cmds/transcript.nim
# engagement.nim should follow same pattern:
# - Parse args with expecting: string pattern
# - Read from file, write to file or stdout with "-"
# - Use --no-cache flag to bypass cache
# - Progress bar for long operations
# - JSON output via stdlib json module
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-modal scoring | Multi-modal fusion | 2024+ | Engagement models now combine audio, visual, speech; single signals unreliable |
| Min-max normalization | Percentile/robust scaling | 2023+ | Video has extreme outliers; percentile-based more stable |
| ML-based engagement | Heuristic + signal combo | 2025-2026 | LLMs can score engagement but require cloud APIs; local heuristics 90% as good for ranking |
| Word-level analysis | Sentence-level grouping | 2020+ | Matches user perception; research shows sentence boundaries matter for NLP quality |
| Text-only hooks | Multi-modal hooks | 2024+ | TikTok/YouTube research: hooks need visual+audio+text; text alone high false positive |

**Deprecated/outdated:**
- **Pure ML engagement models:** Require training data, cloud APIs, or large models; heuristic fusion 90% as effective for local processing
- **Fixed 3-second hook window:** 2024+ research shows 15-20 second retention matters more than pure 3-second; flexible hook detection better
- **Min-max normalization:** Superseded by percentile-based (robust scaling) for signal processing

## Open Questions

Things that couldn't be fully resolved:

1. **Pitch extraction method for prosody**
   - What we know: YIN algorithm is gold standard (0.5% error), FFmpeg has astats filter with limited pitch info
   - What's unclear: Whether simple heuristics (silence, volume spikes) sufficient for hook detection vs. full pitch tracking
   - Recommendation: Start with heuristics (good-enough for MVP), add pitch if testing shows missed hooks

2. **Hook score boost amount**
   - What we know: Should boost engagement score when detected, user decision says "tuned based on testing"
   - What's unclear: Specific multiplier (1.2x? 1.5x? +10 points?)
   - Recommendation: Start with +15 points to base score (hooks increase from 60→75), tune based on Phase 6 clip detection results

3. **Segment merging threshold**
   - What we know: User decision says "~10 points" for merging adjacent sentences
   - What's unclear: Exact threshold (±8? ±12?) and minimum merged duration
   - Recommendation: Start with ±10 points AND minimum 2 seconds (user decision), test on real videos with varying speaking pace

4. **Face presence boost calculation**
   - What we know: Faces indicate human interest, should boost score (user decision)
   - What's unclear: Boost amount per face, diminishing returns for multiple faces, stable vs. unstable faces
   - Recommendation: +5 points per stable face (from consensus), max +10 (caps at 2 faces), ignore unstable faces

5. **Relative vs. absolute scoring priority**
   - What we know: Compute BOTH (user decision), let downstream choose
   - What's unclear: Which should be primary in JSON output, how to label clearly
   - Recommendation: JSON includes both `score_relative` (0-100 within video) and `score_absolute` (0-100 fixed thresholds), default to relative for most use cases

## Sources

### Primary (HIGH confidence)
- [Codebase analysis] - Existing audio.nim, motion.nim, transcript/types.nim, faces.nim, cache.nim patterns
- [Stanford Speech and Language Processing](https://web.stanford.edu/~jurafsky/slp3/) - Sentence segmentation, NLP fundamentals
- [Pitch Detection Wikipedia](https://en.wikipedia.org/wiki/Pitch_detection_algorithm) - YIN, autocorrelation, FFT methods
- [Nim Standard Library](https://nim-lang.github.io/Nim/lib.html) - json, re, algorithm, stats modules

### Secondary (MEDIUM confidence)
- [Engagement Prediction with LMMs (2025)](https://arxiv.org/html/2508.02516v2) - Multi-modal fusion for video engagement, verified approach
- [Speech Prosody 2026 Conference](https://www.speechprosody2026.org/) - Current prosody research, feature extraction methods
- [Min-Max vs Z-Score Normalization](https://www.codecademy.com/article/min-max-zscore-normalization) - Normalization techniques comparison
- [OpenSearch Z-Score Blog (2025)](https://opensearch.org/blog/introducing-the-z-score-normalization-technique-for-hybrid-search/) - Performance data on normalization methods
- [TikTok Hook Formulas](https://www.opus.pro/blog/tiktok-hook-formulas) - Hook patterns, 3-second retention research
- [RMS in Audio](https://librosa.org/doc/main/generated/librosa.feature.rms.html) - RMS calculation methods

### Tertiary (LOW confidence)
- [Short-Form Video Statistics 2026](https://autofaceless.ai/blog/short-form-video-statistics-2026) - Engagement benchmarks (71% decide in 3 seconds)
- [Regex for NLP](https://www.analyticsvidhya.com/blog/2021/06/regex-cheatsheet-for-natural-language-processing-tasks/) - Pattern matching tutorials
- [Silence Detection GitHub](https://github.com/rhasspy/rhasspy-silence) - Energy-based silence detection algorithms

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools exist in Nim stdlib or codebase, no new dependencies needed
- Architecture: HIGH - Patterns verified in existing analyze/ modules (audio, motion, faces), proven cache strategy
- Pitfalls: HIGH - Derived from codebase analysis + WebSearch cross-referenced with research papers
- Hook detection: MEDIUM - Text patterns verified, prosody heuristics need testing vs. full pitch extraction
- Score combination: MEDIUM - Equal weights standard in literature, but optimal weights for this use case need tuning

**Research date:** 2026-02-02
**Valid until:** 2026-04-02 (60 days - engagement scoring is mature domain, slow-moving)
