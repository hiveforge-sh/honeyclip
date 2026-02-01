# Architecture Research

**Domain:** Video Engagement Analysis for FFmpeg-based Processing Pipelines
**Researched:** 2026-02-01
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    CLI & Input Layer                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │  FFmpeg  │  │  Media   │  │  Input   │                       │
│  │  Decode  │  │  Metadata│  │  Args    │                       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                       │
│       │             │             │                              │
├───────┴─────────────┴─────────────┴──────────────────────────────┤
│                    Analysis Layer                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐         │
│  │  Audio   │  │  Motion  │  │ Subtitle │  │   Face   │         │
│  │ Silence  │  │ Detection│  │  Match   │  │ Detection│         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘         │
│       │             │             │             │                │
│       └─────────────┴─────────────┴─────────────┘                │
│                      │                                           │
│              ┌───────▼───────┐                                   │
│              │  Engagement   │  [NEW: Scoring & Integration]     │
│              │    Scorer     │                                   │
│              └───────┬───────┘                                   │
│                      │                                           │
├──────────────────────┴───────────────────────────────────────────┤
│                 Timeline Construction Layer                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Boolean Array → Action Index → Clip Sequence           │    │
│  │  [TTTFFFFTTTTT] → [1,1,1,0,0,0,0,1,...] → Clips w/Effects│    │
│  └─────────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│                    Output Layer                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │  Render  │  │  Export  │  │ Reframe  │  [NEW: Smart Crop]    │
│  │  (FFmpeg)│  │  (JSON)  │  │ (ROI)    │                       │
│  └──────────┘  └──────────┘  └──────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **FFmpeg Decode** | Extract frames/audio from media containers | libavformat demuxer + libavcodec decoder |
| **Media Metadata** | Parse stream info (codecs, dimensions, duration) | `MediaInfo` struct from container inspection |
| **Analysis Processors** | Detect features in decoded frames/audio | Filter graphs + threshold-based detection |
| **Engagement Scorer** | Combine multi-modal signals into engagement score | Weighted scoring model combining face, audio, transcript |
| **Timeline Builder** | Convert boolean arrays to timestamped clip sequences | Chunkify boolean regions into `Clip` objects with effects |
| **Render Pipeline** | Encode timeline back to video/audio | libavcodec encoder + muxer via filter graphs |
| **Export Pipeline** | Serialize timeline to NLE formats | JSON/XML serializers for Premiere, Final Cut, etc. |
| **Reframing Engine** | Dynamic crop based on ROI tracking | Frame-by-frame crop filter with face/speaker position |

## Recommended Project Structure

```
src/
├── analyze/
│   ├── audio.nim           # Existing: Audio level analysis
│   ├── motion.nim          # Existing: Pixel diff motion detection
│   ├── subtitle.nim        # Existing: Text pattern matching
│   ├── face.nim            # NEW: Face detection via MediaPipe/OpenCV
│   ├── speaker.nim         # NEW: Speaker diarization via pyannote
│   └── engagement.nim      # NEW: Multi-modal engagement scoring
├── palet/
│   ├── lexer.nim           # Existing: Edit expression tokenizer
│   └── edit.nim            # EXTEND: Add face(), speaker(), engage() functions
├── timeline.nim            # EXTEND: Add engagement metadata to Clip type
├── render/
│   ├── format.nim          # Existing: Encoder setup
│   ├── video.nim           # EXTEND: ROI-based reframing filter
│   └── reframe.nim         # NEW: Dynamic crop logic
├── exports/
│   └── json.nim            # EXTEND: Serialize engagement scores
├── cache.nim               # EXTEND: Cache face/speaker detection results
└── edit.nim                # EXTEND: Wire engagement analysis into main flow
```

### Structure Rationale

- **analyze/**: Modular detectors following existing pattern (audio, motion, subtitle)
  - Each analyzer produces `seq[bool]` or scored regions
  - Face/speaker detection integrate like existing analyzers
  - Engagement scorer combines signals from multiple analyzers

- **palet/**: Edit expression language extended with new detection primitives
  - Users write `--edit '(engage :threshold 0.7)'`
  - Composable with existing operators: `(or (audio) (face))`

- **timeline.nim**: Clip objects annotated with engagement metadata
  - Preserves existing v3 timeline structure
  - Optional engagement scores in metadata for advanced workflows

- **render/**: Reframing as optional post-process on video clips
  - Integrates with existing filter graph architecture
  - ROI data flows from face/speaker detection → reframe filter

## Architectural Patterns

### Pattern 1: Frame-by-Frame Analysis with Buffering

**What:** Decode media in chunks, analyze each frame, aggregate results into boolean arrays or scored segments

**When to use:** All analysis modules (audio, motion, face, speaker)

**Trade-offs:**
- ✅ Memory efficient (process one frame at a time)
- ✅ Parallelizable (FFmpeg filter graphs auto-parallelize)
- ❌ Requires buffering for temporal features (e.g., speaker change detection)

**Example:**
```nim
# Existing pattern in auto-editor
type AudioProcessor = object
  iterator: AudioIterator
  codecCtx: ptr AVCodecContext
  audioIndex: cint
  chunkDuration: float64

proc analyzeAudio(processor: AudioProcessor, threshold: float32): seq[bool] =
  var result: seq[bool] = @[]
  for audioChunk in processor.iterator:
    let isLoud = calcRMS(audioChunk) > threshold
    result.add(isLoud)
  return result

# NEW: Face detection follows same pattern
type FaceProcessor = object
  iterator: VideoFrameIterator
  detector: FaceDetector  # MediaPipe or OpenCV
  frameIndex: int

proc analyzeFaces(processor: FaceProcessor, minConfidence: float32): seq[FaceRegion] =
  var result: seq[FaceRegion] = @[]
  for frame in processor.iterator:
    let faces = processor.detector.detect(frame, minConfidence)
    result.add(FaceRegion(frameIndex: processor.frameIndex, faces: faces))
    processor.frameIndex += 1
  return result
```

### Pattern 2: Boolean Array as Common Interface

**What:** All detectors produce `seq[bool]` arrays where index = time chunk, value = detected/not detected

**When to use:** Integration with existing timeline builder (`initLinearTimeline`)

**Trade-offs:**
- ✅ Simple, composable (supports `or`, `and`, `not` operators)
- ✅ Already implemented in auto-editor
- ❌ Loses granular scores (must threshold engagement to boolean)
- ❌ Fixed time resolution (chunk duration)

**Example:**
```nim
# Existing flow in auto-editor
proc interpretEdit(args: mainArgs, container: InputContainer,
                   tb: AVRational, bar: Bar): seq[bool] =
  # Audio analysis produces seq[bool]
  let audioLoud = analyzeAudio(...)

  # Motion analysis produces seq[bool]
  let motionActive = analyzeMotion(...)

  # Combine via boolean operators
  return audioLoud or motionActive

# NEW: Engagement extends this pattern
proc analyzeEngagement(container: InputContainer, threshold: float32): seq[bool] =
  let faces = analyzeFaces(...)       # seq[FaceRegion]
  let speakers = analyzeSpeakers(...) # seq[SpeakerSegment]
  let audio = analyzeAudio(...)       # seq[bool]

  # Convert to engagement scores
  var scores: seq[float32] = combineSignals(faces, speakers, audio)

  # Threshold to boolean
  return scores.map(proc(s: float32): bool = s >= threshold)
```

### Pattern 3: Two-Stage Pipeline (Detect → Score → Timeline)

**What:** Analysis produces rich data structures first, then converts to boolean/timeline format

**When to use:** When downstream consumers need both boolean cuts AND rich metadata (e.g., reframing)

**Trade-offs:**
- ✅ Preserves granular data for advanced features (reframing, annotations)
- ✅ Backward compatible (still produces seq[bool] for timeline)
- ❌ More complex data flow
- ❌ Requires caching intermediate results

**Example:**
```nim
# Stage 1: Detection produces rich data
type EngagementData = object
  faces: seq[FaceRegion]        # Per-frame face boxes
  speakers: seq[SpeakerSegment] # Speaker change timestamps
  scores: seq[float32]          # Per-chunk engagement scores

proc detectAll(container: InputContainer): EngagementData =
  result.faces = analyzeFaces(container)
  result.speakers = analyzeSpeakers(container)
  result.scores = combineSignals(result.faces, result.speakers, ...)

# Stage 2: Convert to boolean for timeline
proc toBoolean(data: EngagementData, threshold: float32): seq[bool] =
  return data.scores.map(proc(s: float32): bool = s >= threshold)

# Stage 3: Timeline builder (existing)
let engagementData = detectAll(container)
let hasHighEngagement = toBoolean(engagementData, 0.7)
let timeline = initLinearTimeline(..., hasHighEngagement, ...)

# Stage 4: Reframing uses rich data (NEW)
if args.reframe:
  applyDynamicCrop(timeline, engagementData.faces)
```

## Data Flow

### Request Flow

```
User CLI Input
    ↓
Parse Args → Open Media (FFmpeg demux)
    ↓
Decode Frames/Audio
    ↓
┌──────────────────────────────────────────┐
│         Analysis Layer (Parallel)        │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐ │
│  │Audio │  │Motion│  │ Face │  │Speaker│ │
│  │ RMS  │  │ Diff │  │Detect│  │Diariz │ │
│  └──┬───┘  └──┬───┘  └──┬───┘  └──┬────┘ │
│     │         │         │         │      │
│     └─────────┴─────────┴─────────┘      │
│                  ↓                        │
│         Engagement Scorer                 │
│       (Weighted Combination)              │
└──────────────────┬───────────────────────┘
                   ↓
         ┌─────────────────┐
         │  Boolean Array  │  [TTTFFFFTTTTT...]
         │  (per chunk)    │
         └────────┬────────┘
                  ↓
         ┌─────────────────┐
         │ Timeline Builder│
         │ (chunkify bool  │
         │  → Clip objects)│
         └────────┬────────┘
                  ↓
         ┌─────────────────┐
         │  Apply Effects  │
         │ (cut/speed/vol) │
         └────────┬────────┘
                  ↓
      ┌───────────┴──────────┐
      ↓                      ↓
   Render                Export
 (FFmpeg encode)        (JSON/XML)
      ↓                      ↓
  Output.mp4         timeline.json
```

### Engagement Analysis Data Flow (NEW)

```
Video Input
    ↓
FFmpeg Decode
    ↓
┌────────────────────────────────────────────┐
│          Frame-by-Frame Analysis           │
├────────────────────────────────────────────┤
│                                            │
│  Video Frames → MediaPipe/OpenCV           │
│                 ↓                          │
│          Face Detection                    │
│          (faces/frame)                     │
│                 ↓                          │
│          Track ROI positions               │
│                                            │
│  Audio Stream → FFmpeg Filter Graph        │
│                 ↓                          │
│          RMS Calculation                   │
│          (loudness/chunk)                  │
│                                            │
│  Audio File → Pyannote Diarization         │
│                 ↓                          │
│          Speaker Segments                  │
│          (who speaks when)                 │
│                                            │
│  Audio + Transcript → Whisper              │
│                 ↓                          │
│          Text Transcript                   │
│          (words + timestamps)              │
│                                            │
└──────────────┬─────────────────────────────┘
               ↓
┌──────────────────────────────────────────┐
│       Engagement Scoring Engine          │
├──────────────────────────────────────────┤
│                                          │
│  Inputs:                                 │
│  - Face count & confidence per frame     │
│  - Audio RMS level per chunk             │
│  - Speaker change frequency              │
│  - Transcript word rate                  │
│                                          │
│  Scoring Formula:                        │
│    engagement_score =                    │
│      w1 * face_score +                   │
│      w2 * audio_score +                  │
│      w3 * speaker_score +                │
│      w4 * transcript_score               │
│                                          │
│  Output: seq[float32] (per chunk)        │
│                                          │
└──────────────┬───────────────────────────┘
               ↓
        Threshold to Boolean
               ↓
        Timeline Builder
               ↓
        Clip Sequence with Effects
```

### State Management

- **Immutable detection results**: Face regions, speaker segments cached per input file
- **Mutable timeline construction**: Boolean arrays modified by margin/smoothing operations
- **Persistent metadata**: Engagement scores stored in Clip metadata for export
- **Frame-level ROI tracking**: Face positions accumulated for reframing decision

## Key Data Structures

### Existing Auto-Editor Structures (Reused)

**InputContainer:**
```nim
type InputContainer = object
  formatContext: ptr AVFormatContext
  video: seq[VideoStream]
  audio: seq[AudioStream]
  subtitle: seq[SubtitleStream]
```

**Timeline v3:**
```nim
type v3 = object
  tb: AVRational              # Time base
  bg: RGBColor                # Background color
  v: seq[seq[Clip]]           # Video tracks
  a: seq[seq[Clip]]           # Audio tracks
  effects: seq[seq[Action]]   # Global effect pool

type Clip = object
  src: ptr string             # Source file
  start: int64                # Timeline start
  dur: int64                  # Duration
  offset: int64               # Source offset
  effects: uint32             # Effect index
  stream: int32               # Stream index
```

### NEW: Engagement Analysis Structures

**FaceRegion:**
```nim
type FaceRegion = object
  frameIndex: int             # Frame number
  boxes: seq[BoundingBox]     # Detected face boxes
  confidence: seq[float32]    # Detection confidence per face
  landmarks: seq[FaceLandmarks] # Optional: 68-point landmarks

type BoundingBox = object
  x, y, w, h: int             # Pixel coordinates

type FaceLandmarks = object
  points: array[68, (int, int)] # MediaPipe 68-point model
```

**SpeakerSegment:**
```nim
type SpeakerSegment = object
  start: float64              # Start time (seconds)
  end: float64                # End time (seconds)
  speaker: string             # Speaker ID (e.g., "SPEAKER_00")
  confidence: float32         # Diarization confidence
```

**TranscriptWord:**
```nim
type TranscriptWord = object
  word: string                # Transcribed text
  start: float64              # Word start time
  end: float64                # Word end time
  speaker: Option[string]     # Speaker if diarized
  confidence: float32         # ASR confidence
```

**EngagementScore:**
```nim
type EngagementScore = object
  chunkIndex: int             # Time chunk index
  score: float32              # Composite 0.0-1.0
  components: EngagementComponents

type EngagementComponents = object
  faceScore: float32          # Face presence/count contribution
  audioScore: float32         # Audio energy contribution
  speakerScore: float32       # Speaker variation contribution
  transcriptScore: float32    # Speech rate contribution
```

**EngagementMetadata (extends Clip):**
```nim
# Option 1: Extend Clip directly
type ClipWithEngagement = object
  clip: Clip                  # Existing clip structure
  engagementScore: float32    # Average engagement for this clip
  faceRegions: seq[FaceRegion] # Face data for reframing

# Option 2: Side table (cleaner, backward compatible)
type EngagementTable = Table[int, EngagementMetadata]
  # Key = clip index, Value = engagement data

type EngagementMetadata = object
  avgScore: float32
  maxScore: float32
  faceRegions: seq[FaceRegion]
  speakerSegments: seq[SpeakerSegment]
```

## Integration Points with Existing Auto-Editor

### 1. Analysis Layer Integration

**Existing Pattern:**
```nim
# src/analyze/audio.nim
proc analyzeAudio*(container: InputContainer, threshold: float32): seq[bool]

# src/analyze/motion.nim
proc analyzeMotion*(container: InputContainer, threshold: float32): seq[bool]

# src/analyze/subtitle.nim
proc analyzeSubtitle*(container: InputContainer, pattern: string): seq[bool]
```

**NEW Pattern (follows same signature):**
```nim
# src/analyze/face.nim
proc analyzeFaces*(container: InputContainer, minConfidence: float32): seq[FaceRegion]

# src/analyze/speaker.nim
proc analyzeSpeakers*(container: InputContainer): seq[SpeakerSegment]

# src/analyze/engagement.nim
proc analyzeEngagement*(container: InputContainer, weights: EngagementWeights): seq[float32]
```

**Integration Point:** `src/palet/edit.nim` - Add new detection functions to edit expression evaluator

```nim
# Existing in editEval():
of "audio":
  return analyzeAudio(container, threshold)
of "motion":
  return analyzeMotion(container, threshold)

# NEW additions:
of "face":
  let faceRegions = analyzeFaces(container, minConfidence)
  return faceRegionsToBoolean(faceRegions, chunkDuration)

of "speaker":
  let segments = analyzeSpeakers(container)
  return speakerSegmentsToBoolean(segments, chunkDuration)

of "engage":
  let scores = analyzeEngagement(container, weights)
  return scores.map(proc(s: float32): bool = s >= threshold)
```

### 2. Timeline Construction Integration

**Existing Flow:**
```nim
# src/edit.nim
var hasLoud = interpretEdit(args, container, tb, bar)  # seq[bool]
mutMargin(hasLoud, startMargin, endMargin)             # Apply margins
var actionIndex = hasLoud.map(toInt)                   # Convert to indices
tlV3 = initLinearTimeline(src, tb, bg, mi, actionMap, actionIndex)
```

**Extended Flow (backward compatible):**
```nim
# src/edit.nim
var hasLoud = interpretEdit(args, container, tb, bar)  # seq[bool]
mutMargin(hasLoud, startMargin, endMargin)
var actionIndex = hasLoud.map(toInt)

# NEW: Optionally compute engagement metadata
var engagementTable: EngagementTable
if args.analyzeEngagement:
  engagementTable = buildEngagementTable(container, args, tb)

tlV3 = initLinearTimeline(src, tb, bg, mi, actionMap, actionIndex)

# NEW: Attach engagement metadata to timeline
if args.analyzeEngagement:
  attachEngagementMetadata(tlV3, engagementTable)
```

### 3. Export Integration

**Existing Export (JSON):**
```nim
# src/exports/json.nim
proc exportJsonTl*(tl: v3, version: string, output: string) =
  # Serialize timeline to JSON
  writeFile(output, toJson(tl))
```

**Extended Export (with engagement scores):**
```nim
# src/exports/json.nim
proc exportJsonTl*(tl: v3, version: string, output: string,
                   engagement: Option[EngagementTable] = none(EngagementTable)) =
  var json = toJson(tl)

  if engagement.isSome:
    # Add engagement metadata to JSON
    json["engagement"] = toJson(engagement.get)

  writeFile(output, json)
```

### 4. Cache Integration

**Existing Cache:**
```nim
# src/cache.nim
proc getCachedAnalysis(inputPath: string, analysisType: string): Option[seq[bool]]
proc setCachedAnalysis(inputPath: string, analysisType: string, data: seq[bool])
```

**Extended Cache (for expensive operations):**
```nim
# src/cache.nim
proc getCachedFaces(inputPath: string): Option[seq[FaceRegion]]
proc setCachedFaces(inputPath: string, data: seq[FaceRegion])

proc getCachedSpeakers(inputPath: string): Option[seq[SpeakerSegment]]
proc setCachedSpeakers(inputPath: string, data: seq[SpeakerSegment])

# Cache key based on input hash + detector version
proc makeCacheKey(inputPath: string, detectorType: string, version: string): string
```

**Why caching matters:**
- Face detection: ~5-20 FPS on CPU (slow for long videos)
- Speaker diarization: ~10-60 seconds for 1hr audio (expensive)
- Audio RMS: Fast, cache optional
- Motion detection: Moderate, cache optional

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **Short clips (< 5 min)** | Process inline, no caching needed. Single-threaded analysis OK. |
| **Medium videos (5-60 min)** | Cache expensive detections (face, speaker). Parallelize analysis using FFmpeg filter threading. |
| **Long videos (1hr+)** | Mandatory caching. Batch process frames (e.g., 1 FPS sampling for face detection). Consider GPU acceleration for face detection. |
| **Batch processing** | Pre-compute all analysis, store in cache. Separate analysis + edit phases. Use persistent cache (SQLite or file-based). |

### Scaling Priorities

1. **First bottleneck: Face detection CPU cost**
   - **Symptom:** Processing takes >10x realtime (e.g., 1hr video takes 10hr)
   - **Fix:**
     - Reduce sampling rate (analyze every Nth frame, interpolate between)
     - Use GPU acceleration (CUDA for MediaPipe, if available)
     - Cache detection results aggressively
     - Use faster models (MediaPipe Lite vs Full)

2. **Second bottleneck: Speaker diarization latency**
   - **Symptom:** 5+ minute startup time for diarization model loading
   - **Fix:**
     - Lazy load pyannote model (only when `--edit` uses `speaker()`)
     - Keep model in memory across multiple files (batch mode)
     - Use quantized models (INT8 vs FP32)
     - Cache speaker segments permanently

3. **Third bottleneck: Memory for long videos**
   - **Symptom:** OOM when loading entire face detection results
   - **Fix:**
     - Stream-based processing (don't load all frames into memory)
     - Chunk-based aggregation (process 10min segments independently)
     - Lazy evaluation (compute engagement only for visible timeline regions)

## Anti-Patterns

### Anti-Pattern 1: Running All Detectors Unconditionally

**What people do:** Run face detection, speaker diarization, and transcript generation for every video

**Why it's wrong:**
- Wastes 10-100x processing time if user only needs audio detection
- User runs `--edit '(audio)'` but face detector still runs

**Do this instead:**
- Parse `--edit` expression first, determine which detectors are needed
- Only instantiate required analyzers
- Use lazy evaluation pattern

```nim
# BAD: Always run everything
let faces = analyzeFaces(container)
let speakers = analyzeSpeakers(container)
let engagement = analyzeEngagement(container)
let hasLoud = interpretEdit(args, container)  # Might only use audio!

# GOOD: Parse edit expression first
let requiredAnalyzers = parseEditExpression(args.edit)
var faces: seq[FaceRegion]
if "face" in requiredAnalyzers or "engage" in requiredAnalyzers:
  faces = analyzeFaces(container)
# Only compute what's needed
```

### Anti-Pattern 2: Per-Frame Engagement Scoring

**What people do:** Compute engagement score independently for every frame

**Why it's wrong:**
- Engagement is temporal (requires context from nearby frames)
- Speaker changes matter, but single frame doesn't show speaker context
- Noisy frame-level scores → unstable timeline cuts

**Do this instead:**
- Use chunk-based scoring (align with audio chunk duration, e.g., 0.1s)
- Apply temporal smoothing (moving average over 1-3 seconds)
- Aggregate features within chunks before scoring

```nim
# BAD: Per-frame scoring
for frame in videoFrames:
  let faces = detectFaces(frame)
  let score = if faces.len > 0: 1.0 else: 0.0
  scores.add(score)

# GOOD: Chunk-based with temporal context
for chunk in timeChunks:
  let frames = chunk.frames  # e.g., 3 frames @ 30fps = 0.1s
  let avgFaces = frames.map(detectFaces).map(len).sum / frames.len
  let faceScore = min(avgFaces / 2.0, 1.0)  # Normalize

  let audioRMS = calcChunkRMS(chunk.audio)
  let audioScore = if audioRMS > threshold: 1.0 else: 0.0

  let compositeScore = 0.6 * faceScore + 0.4 * audioScore
  scores.add(compositeScore)
```

### Anti-Pattern 3: Ignoring Existing Timeline Structure

**What people do:** Build parallel data structures for engagement, bypass timeline system

**Why it's wrong:**
- Breaks compatibility with exports (Premiere, Final Cut, etc.)
- Duplicates logic for clip merging, effect application
- Hard to compose engagement with existing `--edit` expressions

**Do this instead:**
- Convert engagement scores to boolean arrays (threshold)
- Feed into existing timeline builder
- Store rich metadata as side table, reference by clip index

```nim
# BAD: Separate engagement timeline
type EngagementTimeline = object
  segments: seq[EngagementSegment]  # Parallel to v3 timeline

proc buildEngagementTimeline(...): EngagementTimeline  # Doesn't use v3!

# GOOD: Integrate with v3 timeline
proc analyzeEngagement(...): seq[float32]  # Scores per chunk

# Convert to boolean for timeline
let hasHighEngagement = scores.map(proc(s: float32): bool = s >= threshold)

# Build v3 timeline (existing code path)
let tl = initLinearTimeline(..., hasHighEngagement, ...)

# Attach engagement metadata as side table
let metadata = buildEngagementMetadata(scores, faces, speakers)
tl.engagementMetadata = some(metadata)  # Optional field in v3
```

### Anti-Pattern 4: Reframing Without Face Tracking

**What people do:** Crop video to first detected face per frame

**Why it's wrong:**
- Face jumps between people → jittery output
- No temporal consistency (camera whips around)
- Breaks on multi-person scenes (arbitrary choice)

**Do this instead:**
- Track faces across frames (assign persistent IDs)
- Smooth ROI positions (exponential moving average)
- Prioritize primary speaker (combine with diarization)
- Fallback to centered crop when no faces

```nim
# BAD: Per-frame independent crop
for frame in frames:
  let faces = detectFaces(frame)
  if faces.len > 0:
    let cropBox = faces[0].box  # Arbitrary first face
    applyCrop(frame, cropBox)

# GOOD: Tracked ROI with smoothing
var tracker = initFaceTracker()
var smoothedROI = CenterROI  # Start at center

for frame in frames:
  let faces = detectFaces(frame)
  let trackedFaces = tracker.update(faces)  # Persistent IDs

  let primaryFace = selectPrimarySpeaker(trackedFaces, speakerSegments)
  if primaryFace.isSome:
    smoothedROI = smoothROI(smoothedROI, primaryFace.get.box, alpha=0.1)

  applyCrop(frame, smoothedROI)
```

## Build Order & Dependencies

### Phase 1: Core Analysis Components (Foundation)

**Components:**
1. Face detection module (`analyze/face.nim`)
2. Speaker diarization module (`analyze/speaker.nim`)
3. Engagement scoring module (`analyze/engagement.nim`)

**Dependencies:**
- External: MediaPipe/OpenCV (face detection)
- External: Pyannote (speaker diarization)
- Internal: Existing FFmpeg decode pipeline

**Build Order Rationale:**
- Face detection is independent, build first
- Speaker diarization is independent, build in parallel
- Engagement scorer depends on both → build last

**Integration Complexity:** LOW
- Follows existing analyzer pattern (audio.nim, motion.nim)
- No changes to core timeline structure yet

### Phase 2: Edit Expression Integration

**Components:**
1. Add `face()`, `speaker()`, `engage()` to palet/edit.nim
2. Boolean conversion utilities (FaceRegion → seq[bool])
3. Caching layer for expensive detections

**Dependencies:**
- Internal: Phase 1 analyzers
- Internal: Existing edit expression parser

**Build Order Rationale:**
- Can't test via CLI until edit expressions support new functions
- Caching needed before integration (avoid re-computation during testing)

**Integration Complexity:** MEDIUM
- Extends existing parser (well-defined extension point)
- Requires careful handling of chunk duration alignment

### Phase 3: Timeline Metadata Extension

**Components:**
1. EngagementMetadata data structures
2. Side table storage in v3 timeline
3. JSON export with engagement scores

**Dependencies:**
- Internal: Phase 2 (need engagement data to store)
- Internal: Existing v3 timeline structure

**Build Order Rationale:**
- Optional enhancement (doesn't break backward compatibility)
- Enables advanced workflows (segment-level engagement in exports)

**Integration Complexity:** LOW
- Side table approach avoids modifying core Clip structure
- JSON export already extensible

### Phase 4: Reframing Engine

**Components:**
1. Face tracking (persistent IDs across frames)
2. ROI smoothing (temporal stabilization)
3. Dynamic crop filter integration
4. Speaker-aware ROI selection

**Dependencies:**
- Internal: Phase 1 face detection
- Internal: Phase 1 speaker diarization
- Internal: Existing FFmpeg filter graph system

**Build Order Rationale:**
- Most complex component (tracking + smoothing + rendering)
- Depends on all previous phases for input data
- Can be built independently (doesn't block other features)

**Integration Complexity:** HIGH
- Modifies render pipeline (video.nim)
- Requires new filter graph (crop with dynamic parameters)
- Needs careful testing (visual quality, performance)

### Dependency Graph

```
┌──────────────┐     ┌──────────────┐
│     Face     │     │   Speaker    │
│  Detection   │     │ Diarization  │
│(analyze/face)│     │(analyze/spkr)│
└──────┬───────┘     └──────┬───────┘
       │                    │
       └─────────┬──────────┘
                 ↓
          ┌──────────────┐
          │ Engagement   │
          │   Scorer     │
          │(analyze/eng) │
          └──────┬───────┘
                 ↓
          ┌──────────────┐
          │    Cache     │
          │   Layer      │
          └──────┬───────┘
                 ↓
          ┌──────────────┐
          │  Edit Expr   │
          │ Integration  │
          │(palet/edit)  │
          └──────┬───────┘
                 ↓
          ┌──────────────┐
          │  Timeline    │
          │  Metadata    │
          └──────┬───────┘
                 ↓
          ┌──────────────┐
          │  Reframing   │
          │   Engine     │
          │(render/refr) │
          └──────────────┘
```

**Critical Path:** Face Detection → Engagement → Edit Expressions → Timeline
**Parallel Tracks:**
- Speaker Diarization (independent until Engagement)
- Reframing (independent until render phase)

## Sources

### FFmpeg Pipeline Architecture
- [Extend the FFmpeg Framework to Analyze Media Content](https://arxiv.org/pdf/2103.03539) - FFVA extension architecture
- [FFmpeg Documentation](https://ffmpeg.org/ffmpeg.html) - Filtergraph and pipeline design
- [Automate Video Analysis with Azure ML](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/analyze-video-computer-vision-machine-learning) - Cloud-based video analysis patterns

### Face Detection Integration
- [How to Process Live Video Stream Using FFMPEG and OpenCV](https://lembergsolutions.com/blog/how-process-live-video-stream-using-ffmpeg-and-opencv) - Integration patterns
- [Face Detection Guide | MediaPipe](https://developers.google.com/mediapipe/solutions/vision/face_detector) - MediaPipe batch/video processing modes
- [Efficient video face recognition based on frame selection](https://pmc.ncbi.nlm.nih.gov/articles/PMC7959602/) - Pipeline architecture with detection, tracking, recognition stages

### Speaker Diarization
- [pyannote/speaker-diarization](https://huggingface.co/pyannote/speaker-diarization-3.1) - Pyannote 3.1 architecture
- [Best Speaker Diarization Models Compared 2026](https://brasstranscripts.com/blog/speaker-diarization-models-comparison) - Architecture comparison
- [Deploy PyAnnote on Amazon SageMaker](https://aws.amazon.com/blogs/machine-learning/deploy-a-hugging-face-pyannote-speaker-diarization-model-on-amazon-sagemaker-as-an-asynchronous-endpoint/) - Integration patterns

### Engagement Analysis
- [24 Automated Transcription Statistics 2026](https://sonix.ai/resources/automated-transcription-statistics/) - Engagement metrics (91% completion with subtitles)
- [Video Engagement Metrics](https://mindstamp.com/blog/video-engagement-metrics) - Measurement patterns
- [Video Big Data Analytics Architecture Survey](https://www.mdpi.com/2076-3417/15/14/8089) - Centralized, cloud, edge, hybrid architectures

### Segment Annotation
- [Segment Anything Model 3 (SAM 3)](https://encord.com/blog/segment-anything-model-3/) - Data annotation pipeline architecture
- [SAM 3 in CVAT](https://www.cvat.ai/resources/blog/sam-3-image-segmentation) - Integration patterns
- [How to Build Data Pipelines for Media Industry](https://www.integrate.io/blog/data-pipelines-media-industry/) - Media pipeline patterns

---
*Architecture research for: Video Engagement Analysis in FFmpeg Pipelines*
*Researched: 2026-02-01*
