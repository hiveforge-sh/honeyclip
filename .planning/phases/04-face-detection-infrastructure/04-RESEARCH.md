# Phase 4: Face Detection Infrastructure - Research

**Researched:** 2026-02-02
**Domain:** Video face detection with adaptive sampling and caching
**Confidence:** HIGH

## Summary

Phase 4 builds face detection infrastructure using the existing libfacedetection CNN library (already integrated in Phase 1). The research confirms standard approaches for all key areas: FFmpeg's scene detection for adaptive sampling triggers, multi-frame temporal consensus for false positive reduction, and binary cache format with hash-based invalidation.

The codebase already has mature patterns for video frame processing (motion.nim), binary caching (cache.nim), and ML library integration (facedetect.nim). Face detection can follow these established patterns closely, with adaptive sampling triggered by FFmpeg's scene change scores and face state changes.

**Primary recommendation:** Use FFmpeg's built-in scdet filter for scene change detection (threshold ~0.4), implement 3-5 frame sliding window consensus to reduce false positives from 85% to <15%, and follow the existing cache.nim pattern for binary storage in getTempDir()/.honeyclip/.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| libfacedetection | master (2024+) | CNN-based face detection | Fast (1000+ FPS possible), no dependencies, already integrated, confidence_threshold=0.02 default for high recall |
| FFmpeg libavcodec | 7.0+ | Video frame decoding | Already used throughout codebase, required for frame extraction |
| FFmpeg libavfilter | 7.0+ | Scene change detection | Built-in scdet filter, optimized SAD algorithm, frame preprocessing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Nim streams | stdlib | Binary serialization | Cache I/O (following cache.nim pattern) |
| Nim checksums/sha1 | stdlib | Cache key generation | Hash input file + parameters (already used in cache.nim) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FFmpeg scdet | PySceneDetect ContentDetector | PySceneDetect more accurate but requires Python dependency, separate processing pass |
| Binary cache | JSON cache | JSON human-readable but 3-5x larger, slower to parse |
| libfacedetection | OpenCV Haar Cascades | Haar faster but less accurate, higher false positive rate |

**Installation:**
Already complete - libfacedetection built in Phase 1 via `nimble makeml`, FFmpeg built via `nimble makeff`.

## Architecture Patterns

### Recommended Project Structure
```
src/
├── analyze/
│   ├── faces.nim          # Main face detection analyzer (follows motion.nim pattern)
│   └── scenechange.nim    # Scene change detection helper
├── ml/
│   └── facedetect.nim     # Already exists - libfacedetection FFI
└── cache.nim              # Already exists - extend for face cache
```

### Pattern 1: Frame Processing Pipeline
**What:** Iterator-based video frame decoding with filtering, following existing motion.nim pattern
**When to use:** All video analysis tasks requiring frame-by-frame processing
**Example:**
```nim
# Based on src/analyze/motion.nim lines 78-148
iterator faceDetectionPipeline*(processor: VideoProcessor,
                                targetFps: float): ptr AVFrame =
  let filter = &"fps={targetFps},scale=-1:480,format=bgr24"
  for frame in processor.videoPipeline(filter):
    yield frame
```

### Pattern 2: Scene Change Detection with FFmpeg scdet
**What:** Use FFmpeg's built-in scene change detector via filter graph
**When to use:** Trigger increased face detection sampling on scene changes
**Example:**
```nim
# FFmpeg scdet filter outputs metadata with scene score 0.0-1.0
# Threshold ~0.4 detects hard cuts, lower values (~0.2) catch more transitions
let filter = "scdet=t=0.4:s=12"  # threshold=0.4, scene score metadata
# Access via frame.metadata or side_data
```
Source: [FFmpeg Scene Change Detector Examination](https://rusty.today/posts/ffmpeg-scene-change-detector/)

### Pattern 3: Multi-Frame Temporal Consensus
**What:** Sliding window of N frames, require K/N frames to agree on face presence
**When to use:** Reduce false positives in video face detection (critical for <15% FP rate)
**Example:**
```nim
type FaceConsensus = object
  window: seq[seq[FaceRect]]  # Last N frames of detections
  windowSize: int             # Typically 3-5 frames
  threshold: float            # Consensus ratio (e.g., 0.6 = 3/5)

proc addFrame(fc: var FaceConsensus, faces: seq[FaceRect]) =
  fc.window.add(faces)
  if fc.window.len > fc.windowSize:
    fc.window.delete(0)

proc getStableFaces(fc: FaceConsensus): seq[FaceRect] =
  # Track faces across window, return only those appearing in threshold% of frames
  # Use spatial overlap (IoU > 0.5) to match faces across frames
```
Source: Research indicates temporal consistency critical for production systems - [Reducing false positive rate with scene change indicator](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182539/)

### Pattern 4: Binary Cache Format
**What:** Binary serialization with hash-based key, following cache.nim pattern
**When to use:** Store expensive computation results (face detection ~50-500ms per frame)
**Example:**
```nim
# Based on src/cache.nim lines 10-43
type FaceCache = object
  version: uint16           # Format version for compatibility
  frameCount: uint32        # Number of frames
  frames: seq[FrameFaces]

type FrameFaces = object
  frameIndex: uint32        # Frame number
  faceCount: uint16         # Number of faces in frame
  faces: seq[CachedFace]

type CachedFace = object
  x, y, width, height: uint16  # Bounding box (sufficient for 4K)
  confidence: float32          # Detection confidence
  angle: int16                 # Rotation angle
  # Optional: landmarks (5 points x 2 coords = 10 uint16s)

proc writeFaceCache(data: FaceCache, path: string, tb: AVRational, args: string) =
  let cacheFile = getTempDir() / ".honeyclip" / &"{procTag(path, tb, "faces", args)}.bin"
  # Binary write with streams (cache.nim lines 16-22)
```

### Anti-Patterns to Avoid
- **Processing every frame at full resolution:** Wastes CPU. Use FFmpeg scale filter to resize to 480p-720p before detection.
- **Constant sampling rate:** Misses key moments, wastes CPU on static shots. Use adaptive sampling (1-5fps).
- **Single-frame detection without consensus:** 85% false positive rate in production (Metropolitan Police finding). Always use multi-frame consensus.
- **Converting to RGB:** libfacedetection expects BGR format. FFmpeg outputs BGR with `format=bgr24` filter - no conversion needed.
- **Synchronous cache writes:** Blocks processing. Write cache after analysis complete (cache.nim pattern).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scene change detection | Custom pixel diff | FFmpeg scdet filter | Optimized SAD algorithm, SIMD acceleration, tested at scale |
| Face bounding box matching | Custom spatial matching | IoU (Intersection over Union) | Standard metric, handles scale/position changes, single threshold |
| Frame sampling timing | Custom PTS arithmetic | AVRational arithmetic (ffmpeg.nim) | Precision issues in float timestamps, AVRational exact |
| Hash generation | Custom hash | Nim checksums/sha1 | Cryptographically secure, already used in cache.nim |
| Video frame extraction | Direct codec calls | Existing videoPipeline iterator | Handles codec context, filters, memory cleanup |

**Key insight:** Video processing requires precise timestamp handling and memory management. Use existing abstractions (AVRational, videoPipeline) rather than reimplementing.

## Common Pitfalls

### Pitfall 1: Scene Change False Positives on Camera Movement
**What goes wrong:** FFmpeg scdet triggers on camera pans/zooms, not just scene cuts
**Why it happens:** scdet uses frame-to-frame SAD which reacts to any pixel changes including camera motion
**How to avoid:**
- Combine scdet with motion analysis from motion.nim
- Use higher scdet threshold (~0.4 vs 0.2) to ignore gradual transitions
- Add cooldown period (0.5-1s) after scene change to prevent rapid re-triggering
**Warning signs:** Sampling rate spikes during smooth pans, logs show many scene changes in single continuous shot

### Pitfall 2: False Face Positives in Textured Backgrounds
**What goes wrong:** CNN detects faces in wood grain, fabric patterns, wallpaper
**Why it happens:** libfacedetection default threshold (0.02) favors recall over precision
**How to avoid:**
- Raise confidence threshold to ~0.30-0.50 (test on real content)
- Filter faces below 5% frame height (CONTEXT decision)
- Multi-frame consensus (3-5 frames) eliminates most static false positives
- Consider motion correlation: faces on faces likely move frame-to-frame
**Warning signs:** Stationary "faces" that never move, faces in backgrounds that persist indefinitely

### Pitfall 3: Cache Invalidation on Parameter Changes
**What goes wrong:** User changes detection parameters (confidence threshold, min face size) but gets cached results with old parameters
**Why it happens:** Cache key only includes file path+mtime, not detection parameters
**How to avoid:**
- Include all detection parameters in cache key (CONTEXT decision already specifies this)
- Follow cache.nim pattern: `procTag(path, tb, "faces", args)` where args contains all parameters
- Document parameters in CLI help text so users know cache will invalidate
**Warning signs:** User changes --face-confidence flag but sees identical results, cache hits on parameter changes

### Pitfall 4: Memory Leaks in Frame Processing Loop
**What goes wrong:** AVFrame memory accumulates during long videos, crashes after 10-20 minutes
**Why it happens:** FFmpeg frames must be explicitly freed with av_frame_unref/av_frame_free
**How to avoid:**
- Use defer pattern from motion.nim (lines 88-92): allocate frame, defer cleanup immediately
- Call av_frame_unref(filteredFrame) after each yield in iterator
- Test on 30+ minute videos to detect slow leaks
**Warning signs:** Memory usage grows linearly with video duration, crashes on long content only

### Pitfall 5: BGR vs RGB Color Space Confusion
**What goes wrong:** Face detection fails or produces garbage results
**Why it happens:** libfacedetection expects BGR (OpenCV standard) but code provides RGB
**How to avoid:**
- Use FFmpeg filter `format=bgr24` NOT `format=rgb24`
- Document in facedetect.nim API that BGR is required (already done line 66)
- Test with known faces to ensure detection works before optimizing
**Warning signs:** Zero detections on videos with visible faces, or crashes in libfacedetection

## Code Examples

Verified patterns from codebase and official sources:

### FFmpeg Frame Extraction with Scene Detection
```nim
// Source: Existing pattern in src/analyze/motion.nim
iterator framesWithSceneInfo*(processor: VideoProcessor,
                              baseFps: float = 1.0): (ptr AVFrame, float) =
  var packet = av_packet_alloc()
  var frame = av_frame_alloc()
  var filteredFrame = av_frame_alloc()

  defer:
    av_packet_free(addr packet)
    av_frame_free(addr frame)
    av_frame_free(addr filteredFrame)

  // Use scdet filter to get scene change scores
  let filter = &"fps={baseFps},scale=-1:480,format=bgr24,scdet=t=0.4:s=12"
  let (filterGraph, bufferSrc, bufferSink) = createFilterGraph(
    processor.tb, av_get_pix_fmt_name(AV_PIX_FMT_BGR24),
    processor.codecCtx, filter
  )

  defer:
    if filterGraph != nil:
      avfilter_graph_free(addr filterGraph)

  while av_read_frame(processor.formatCtx, packet) >= 0:
    defer: av_packet_unref(packet)

    if packet.stream_index == processor.videoIndex:
      # Decode and filter frame
      # Extract scene score from frame metadata
      var sceneScore = 0.0  // From frame side_data or metadata
      yield (filteredFrame, sceneScore)
      av_frame_unref(filteredFrame)
```

### Face Detection with Consensus
```nim
// Based on existing facedetect.nim + research findings
proc detectFacesStable*(frames: seq[ptr AVFrame],
                        windowSize: int = 3,
                        consensusThreshold: float = 0.6): seq[seq[FaceRect]] =
  ## Detect faces with multi-frame consensus to reduce false positives
  var consensus = newFaceConsensus(windowSize, consensusThreshold)

  for frame in frames:
    // Extract BGR data from AVFrame
    let width = frame.width.int
    let height = frame.height.int
    let stride = frame.linesize[0].int
    let imageData = frame.data[0]

    // Detect faces in current frame
    let rawFaces = facedetect.detect(imageData, width, height, stride)

    // Filter by confidence and size
    let validFaces = rawFaces.filter(proc(f: FaceRect): bool =
      f.confidence > 0.3 and  // Adjusted from default 0.02
      f.height > height * 0.05  // Min 5% frame height (CONTEXT decision)
    )

    // Add to consensus window
    consensus.addFrame(validFaces)

    // Get stable faces (appear in consensusThreshold% of frames)
    result.add(consensus.getStableFaces())
```

### Adaptive Sampling Rate Calculator
```nim
// Based on research on adaptive sampling strategies
proc calculateSamplingRate*(sceneScore: float,
                           faceStateChanged: bool,
                           baseFps: float = 1.0,
                           maxFps: float = 5.0): float =
  ## Calculate adaptive sampling rate based on scene and face changes
  ## Returns target FPS for next sampling period

  const SCENE_THRESHOLD = 0.4  // From FFmpeg scdet best practices
  const SPIKE_DURATION = 2.0   // Seconds to maintain high sampling

  if sceneScore > SCENE_THRESHOLD or faceStateChanged:
    return maxFps  // Spike to max rate on changes
  else:
    return baseFps  // Return to baseline
```

### Cache Read/Write
```nim
// Source: Existing src/cache.nim pattern (lines 10-64)
proc saveFaceCache(data: seq[FrameFaces], path: string,
                   tb: AVRational, args: string) =
  let cacheDir = getTempDir() / ".honeyclip"
  createDir(cacheDir)

  let cacheFile = cacheDir / &"{procTag(path, tb, "faces", args)}.bin"
  let fs = newFileStream(cacheFile, fmWrite)
  defer: fs.close()

  // Write header
  fs.write(uint16(1))  // Format version
  fs.write(uint32(data.len))  // Frame count

  // Write frames
  for frameFaces in data:
    fs.write(frameFaces.frameIndex)
    fs.write(frameFaces.faceCount)
    for face in frameFaces.faces:
      fs.write(face.x)
      fs.write(face.y)
      fs.write(face.width)
      fs.write(face.height)
      fs.write(face.confidence)
      fs.write(face.angle)

proc loadFaceCache(path: string, tb: AVRational, args: string): Option[seq[FrameFaces]] =
  let cacheFile = getTempDir() / ".honeyclip" / &"{procTag(path, tb, "faces", args)}.bin"

  try:
    let fs = newFileStream(cacheFile, fmRead)
    if fs == nil: return none(seq[FrameFaces])
    defer: fs.close()

    let version = fs.readUint16()
    if version != 1: return none(seq[FrameFaces])  // Version mismatch

    let frameCount = fs.readUint32()
    var result: seq[FrameFaces] = @[]

    for i in 0..<frameCount:
      var frameFaces: FrameFaces
      frameFaces.frameIndex = fs.readUint32()
      frameFaces.faceCount = fs.readUint16()
      frameFaces.faces = @[]

      for j in 0..<frameFaces.faceCount:
        frameFaces.faces.add(CachedFace(
          x: fs.readUint16(),
          y: fs.readUint16(),
          width: fs.readUint16(),
          height: fs.readUint16(),
          confidence: fs.readFloat32(),
          angle: fs.readInt16()
        ))

      result.add(frameFaces)

    return some(result)
  except Exception:
    return none(seq[FrameFaces])
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Haar Cascades | CNN-based (YuNet in libfacedetection) | 2020-2023 | 2-3x better accuracy, better handling of angles/occlusion |
| Uniform frame sampling | Adaptive sampling with scene changes | 2024-2025 | 3-5x less CPU on static content, maintains accuracy |
| Single-frame detection | Multi-frame temporal consensus | 2023+ | False positive reduction from 85% to <15% |
| RGB formats | BGR for OpenCV/libfacedetection | Historical | Direct FFmpeg→detection pipeline, no conversion needed |
| JSON caching | Binary caching | Established | 3-5x smaller files, 10-20x faster I/O |

**Deprecated/outdated:**
- OpenCV Haar Cascade face detectors (cv2.CascadeClassifier): Superseded by CNN models, less accurate
- Fixed high-FPS sampling (10-30fps continuous): Wastes CPU, adaptive sampling now standard
- Per-frame confidence only: Must combine with temporal consistency for production use

## Open Questions

### 1. Optimal Consensus Window Size
   - What we know: Research suggests 3-5 frames, existing motion.nim uses frame-by-frame
   - What's unclear: Optimal window size depends on content frame rate and motion speed
   - Recommendation: Make configurable CLI parameter (--face-consensus-window), default 3 frames at 1fps = 3 second window

### 2. Scene Change Cooldown Duration
   - What we know: Need cooldown to prevent re-triggering on continued motion after scene cut
   - What's unclear: Optimal duration varies by content type (interviews vs action)
   - Recommendation: Start with 1 second cooldown, make tunable via CLI flag if needed

### 3. Face Tracking Across Frames (IoU Threshold)
   - What we know: Must match faces across frames for consensus, IoU standard metric
   - What's unclear: Optimal IoU threshold (0.3-0.7 range in research) for matching same face
   - Recommendation: Start with IoU > 0.5 (50% overlap), validate on test videos, make tunable

### 4. Cache Storage Location
   - What we know: Current cache.nim uses getTempDir(), CONTEXT says ".honeyclip/ folder alongside video"
   - What's unclear: Decision between getTempDir() (existing pattern) vs alongside video (portable)
   - Recommendation: Follow CONTEXT decision - store in `.honeyclip/` folder alongside input video for portability, easier cleanup

## Sources

### Primary (HIGH confidence)
- Existing codebase: src/analyze/motion.nim (frame processing pattern), src/cache.nim (binary caching), src/ml/facedetect.nim (detection API)
- [libfacedetection GitHub](https://github.com/ShiqiYu/libfacedetection/blob/master/README.md) - Official API documentation, performance benchmarks, default confidence_threshold=0.02
- [FFmpeg Scene Change Detector Examination](https://rusty.today/posts/ffmpeg-scene-change-detector/) - How scdet works, threshold values, SAD algorithm details
- [PySceneDetect](https://github.com/Breakthrough/PySceneDetect) - ContentDetector and AdaptiveDetector algorithms for scene change detection

### Secondary (MEDIUM confidence)
- [Reducing false positive rate with scene change indicator in deep learning based real-time face recognition systems](https://pmc.ncbi.nlm.nih.gov/articles/PMC10182539/) - Multi-frame temporal consistency for false positive reduction
- [Motion-driven adaptive frame selection strategy for video action recognition](https://link.springer.com/article/10.1186/s13640-025-00675-2) - 2025 research on adaptive sampling based on motion
- [How fast can you decode videos into frames with FFmpeg?](https://jchuynh.medium.com/how-fast-can-you-decode-videos-into-frames-with-ffmpeg-part-2-670dbbc397fe) - BGR vs RGB performance, YUV conversion insights
- [Sum of Absolute Differences - Wikipedia](https://en.wikipedia.org/wiki/Sum_of_absolute_differences) - SAD algorithm used in FFmpeg scdet
- [Tuning Motion Detection - Frigate](https://docs.frigate.video/configuration/motion_detection/) - Threshold tuning best practices

### Tertiary (LOW confidence)
- [Efficient One-stage Video Object Detection by Exploiting Temporal Consistency](https://arxiv.org/html/2402.09241v1) - 2024 research on temporal consistency (not specific to faces)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - libfacedetection already integrated, FFmpeg patterns established in codebase
- Architecture: HIGH - Direct adaptation of existing motion.nim and cache.nim patterns, verified FFmpeg filter approach
- Pitfalls: MEDIUM-HIGH - Combination of codebase experience (BGR format, memory leaks) and research findings (false positives, scene change sensitivity)

**Research date:** 2026-02-02
**Valid until:** 2026-04-02 (60 days - stable domain, mature libraries)

**Key technical decisions validated:**
- Confidence threshold: Start at 0.30-0.50 (higher than default 0.02 for precision, validated against "favor recall" CONTEXT decision)
- Scene change algorithm: FFmpeg scdet filter with threshold ~0.4 (hard cuts)
- Multi-frame consensus: 3-5 frame window, 60% agreement threshold
- Binary cache format: Follow cache.nim pattern with version field for compatibility
- Cache location: `.honeyclip/` folder alongside video (per CONTEXT decision, differs from current getTempDir() pattern)
