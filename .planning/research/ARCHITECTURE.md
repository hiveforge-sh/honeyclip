# Architecture Integration Patterns

**Milestone:** v1.2 Workflow & Performance
**Domain:** Batch processing, chapter detection, preview generation, GPU acceleration, 4K optimization
**Researched:** 2026-02-05
**Confidence:** HIGH

## Executive Summary

The v1.2 features integrate cleanly with honeyclip's existing pipeline architecture. Batch processing wraps the existing single-file workflow with job queue management. Chapter detection extends the transcript/engagement analyzer pattern with topic segmentation. Preview generation already exists and needs only batch support. GPU acceleration extends ML modules (face detection) with CUDA backend selection. 4K memory optimization touches the frame decoding loop in av.nim and analyzer buffering.

**Key integration pattern:** All new features extend existing components rather than creating parallel systems. Batch processing orchestrates, chapter detection analyzes, preview generation renders, GPU acceleration accelerates, and 4K optimization reduces memory footprint—but all operate within the established pipeline stages (decode → analyze → timeline → render).

## Recommended Architecture

### High-Level Integration Map

```
┌─────────────────────────────────────────────────────────────────┐
│                     NEW: Batch Orchestrator                     │
│  (src/batch.nim - job queue, progress aggregation, CLI wrapper) │
└──────────────────────┬──────────────────────────────────────────┘
                       │ spawns per-file →
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                   EXISTING: Single File Pipeline                │
├─────────────────────────────────────────────────────────────────┤
│  1. Decode (av.nim)  ← NEW: 4K frame buffer optimization        │
│  2. Analyze (analyze/*) ← NEW: chapter detection, GPU accel     │
│  3. Timeline (timeline.nim)                                     │
│  4. Render (render/*)  ← EXISTING: preview generation           │
│  5. Export (exports/*)                                          │
└─────────────────────────────────────────────────────────────────┘
```

### Component Integration Points

| New Feature | Integration Point | New vs Modified | Priority |
|-------------|------------------|-----------------|----------|
| Batch processing | Wraps main() with job queue | NEW: src/batch.nim, MODIFIED: src/main.nim (entry point detection) | HIGH (user value) |
| Chapter detection | Analyzer following audio.nim pattern | NEW: src/analyze/chapters.nim, NEW: src/cmds/chapters.nim | MEDIUM (builds on transcript) |
| Preview generation | **Already implemented!** | EXISTING: src/render/previews.nim (add batch wrapper) | MEDIUM (enhancement) |
| GPU acceleration | ML backend selection in existing modules | MODIFIED: src/ml/facedetect.nim, MODIFIED: build system | LOW (optional perf) |
| 4K memory optimization | Frame buffer management in decode loop | MODIFIED: src/av.nim (decode iterator), MODIFIED: analyze/* (buffering) | MEDIUM (enables 4K) |

## Component Details

### 1. Batch Processing (NEW: src/batch.nim)

**Purpose:** Process multiple videos sequentially or in parallel without restarting the binary for each file.

**Integration pattern:** Producer-consumer model where batch orchestrator produces jobs, worker pool consumes via FFmpeg pipeline.

```nim
# src/batch.nim
type
  BatchJob* = object
    inputPath*: string
    outputPath*: string
    args*: mainArgs  # Reuse existing args type
    status*: JobStatus
    startTime*: Time
    endTime*: Time
    error*: string

  JobQueue* = object
    jobs*: seq[BatchJob]
    maxWorkers*: int
    activeJobs*: int
    completed*: int
    failed*: int

proc processBatch*(inputPaths: seq[string], args: mainArgs,
                   maxWorkers: int = 4): BatchResult
```

**How it works:**
1. Parse batch input (glob pattern, directory, or file list)
2. Create JobQueue with one BatchJob per file
3. Spawn worker pool (threads or processes) calling existing `editMedia(args)` per job
4. Aggregate progress bars (show per-file + overall progress)
5. Generate batch summary report (successes, failures, total time)

**Integration with existing code:**
- **src/main.nim**: Detect batch mode via `--batch` flag or multiple positional args, delegate to `batch.processBatch()`
- **Reuses existing pipeline**: Each worker calls `editMedia(args)` from edit.nim with different input path
- **No changes to analyzers**: Audio, motion, engagement analyzers don't know they're in batch mode
- **Cache benefits batch**: First video caches engagement analysis, subsequent videos reuse if same timebase

**Research validation:**
Per [Automated Video Processing with FFmpeg and Docker](https://img.ly/blog/building-a-production-ready-batch-video-processing-server-with-ffmpeg/), Docker-based batch video processing uses producer-consumer model with FastAPI layer producing jobs and async workers consuming. For CLI tools, simpler approach: sequential processing with optional parallel workers (controlled by `--concurrent N` flag).

FFmpeg itself doesn't have built-in batch processing—tools wrap it. Honeyclip follows this pattern: `batch.nim` wraps the existing single-file `editMedia()` call.

**Build order:** Phase 1 (lowest risk, highest user value)

### 2. Chapter Detection (NEW: src/analyze/chapters.nim)

**Purpose:** Segment video into semantic chapters based on transcript topic boundaries.

**Integration pattern:** Analyzer following existing audio.nim/motion.nim/engagement.nim pattern, produces seq[ChapterSegment] consumed by timeline.

```nim
# src/analyze/chapters.nim
type
  ChapterSegment* = object
    startMs*: int64
    endMs*: int64
    title*: string        # Auto-generated from transcript
    confidence*: float32  # 0-1 confidence in boundary

proc detectChapters*(transcript: Transcript,
                     params: ChapterParams): seq[ChapterSegment]
```

**How it works:**
1. **Input:** Transcript with word-level timestamps and sentence boundaries (already available from existing whisper integration)
2. **Segmentation:** Apply text segmentation algorithm (sliding window + cosine similarity, or hierarchical clustering)
3. **Title generation:** Extract keywords from segment text or use first sentence as title
4. **Output:** seq[ChapterSegment] with timestamps and titles

**Integration with existing code:**
- **Input source:** Consumes `Transcript` from `src/transcript/types.nim` (already structured with segments and words)
- **Called by:** New subcommand `src/cmds/chapters.nim` or integrated into `analyze` workflow
- **Output format:** Export to YouTube chapters format (timestamp + title), EDL markers, or JSON
- **Timeline integration:** ChapterSegment boundaries can inform clip detection boundaries (don't split clips across chapters)

**Architectural pattern match:**
```nim
# Existing: src/analyze/audio.nim
proc audio*(bar: Bar, container: InputContainer, path: string,
            tb: AVRational, stream: int32): seq[float32]

# New: src/analyze/chapters.nim (same signature style)
proc chapters*(bar: Bar, transcript: Transcript,
               params: ChapterParams): seq[ChapterSegment]
```

**Research validation:**
Per [Chapter-Llama: Efficient Chaptering](https://openaccess.thecvf.com/content/CVPR2025/papers/Ventura_Chapter-Llama_Efficient_Chaptering_in_Hour-Long_Videos_with_LLMs_CVPR_2025_paper.pdf), recent research (2024-2026) uses LLMs (Chapter-Llama) or hierarchical text segmentation (MiniSeg on YTSeg benchmark) for video chaptering. These operate on transcripts, not raw video, which fits honeyclip's existing whisper → transcript pipeline perfectly.

Local implementation strategy:
1. **Phase 1 (MVP):** Simple sliding window with TF-IDF cosine similarity for topic shifts (no LLM required)
2. **Phase 2 (Advanced):** Optional LLM integration via ONNX Runtime (if user provides GGUF model path) for title generation

**Build order:** Phase 2 (after engagement scoring working, before GPU acceleration complexity)

### 3. Preview Generation (EXISTING: src/render/previews.nim)

**Status:** **Already implemented in v1.1!** Full preview generation module exists.

**Current capabilities:**
- Contact sheet generation (thumbnail grid)
- Best frame thumbnails (histogram-based selection)
- Video snippets (3-second start/middle/end previews)
- Side-by-side comparison (original vs reframed)
- Overview video (concatenated snippets)

**Integration points:**
- Used by `src/cmds/analyze.nim` for clip preview workflow
- Uses `findFFmpegPath()` to locate build/bin/ffmpeg (prefers honeyclip's built FFmpeg)
- Generates previews in `{video}_previews/` subdirectory
- Burns metadata (clip rank, timestamps) into previews

**What v1.2 needs to add:**
- Batch preview generation (apply to multiple clips at once)
- Progress reporting during preview generation (currently no progress bar)
- Preview optimization for 4K videos (downscale before thumbnail extraction)

**Modifications for batch context:**
```nim
# New: Batch wrapper in src/batch.nim
proc generateBatchPreviews*(jobs: seq[BatchJob],
                            mode: PreviewMode): seq[PreviewResult] =
  var results: seq[PreviewResult] = @[]
  for job in jobs:
    # Extract clips from job.outputPath or engagement data
    let clips = loadClipsFromEngagement(job.inputPath)
    let result = generatePreviews(job.inputPath, clips, mode)
    results.add(result)
  results
```

**Research validation:**
Per [Generating thumbnails 3.8x faster with FFmpeg seeking](https://sebi.io/posts/2024-12-21-faster-thumbnail-generation-with-ffmpeg-seeking/), input seeking (keyframe parsing) is 3.8x faster than fps filtering. The existing implementation already uses this pattern (`-ss` before `-i`).

Per [Extracting Thumbnails Faster with FFmpeg](https://wistia.com/learn/marketing/faster-thumbnail-extraction-ffmpeg), I-frame extraction is most efficient (select='eq(pict_type,I)'), and the existing thumbnail filter implements histogram-based selection.

**No architecture changes needed** — preview generation already structured for reuse.

**Build order:** Phase 3 (enhancement of existing feature)

### 4. GPU Acceleration (MODIFIED: src/ml/facedetect.nim, build system)

**Purpose:** Offload face detection to CUDA-capable GPU for 3-10x speedup on ML inference.

**Integration pattern:** Add GPU backend selection to existing ML modules, preserve CPU fallback.

```nim
# src/ml/facedetect.nim (modified)
type
  AcceleratorBackend* = enum
    CPU, CUDA, OpenCL

proc detect*(image: ptr uint8, width, height, step: int,
             backend: AcceleratorBackend = CPU): seq[FaceRect]
```

**How it works:**
1. **Build system** (honeyclip.nimble): Add CUDA build flags when `ENABLE_CUDA=1`
2. **Runtime detection**: Check for CUDA availability via library probe
3. **Backend dispatch**: Route inference calls to CUDA kernel if available, fallback to CPU
4. **Memory management**: Pin memory for GPU transfers (cudaMallocHost), reuse buffers across frames

**Integration with existing code:**
- **ML modules**: Modify `src/ml/facedetect.nim` and `src/ml/onnx.nim` to accept backend parameter
- **Analyzers**: `src/analyze/faces.nim` passes backend from CLI flag `--gpu` or env var `ENABLE_CUDA=1`
- **Cache invalidation**: Cache keys include backend (cache/face_detection_cpu.bin vs cache/face_detection_cuda.bin)

**Research validation:**
Per [Hardware-Accelerated Machine Learning | Immich](https://docs.immich.app/features/ml-hardware-acceleration/), CUDA is most reliable among hardware acceleration backends for face detection. OpenCV supports CUDA acceleration via `cuda` module. ONNX Runtime supports CUDA via `CUDAExecutionProvider`.

Per [Computer vision algorithms acceleration using CUDA](https://link.springer.com/article/10.1007/s10586-020-03090-6), face detection sees 1.2-13x speedup with CUDA depending on model.

**Critical constraints:**
- CUDA requires NVIDIA GPU (check via `nvidia-smi`)
- OpenCL more portable but slower than CUDA
- Build complexity: CUDA toolkit dependency, platform-specific compilation
- Memory overhead: GPU memory separate from system RAM

**Implementation stages:**
1. **Phase 1:** Add CUDA backend to libfacedetection (existing C++ library has CUDA support)
2. **Phase 2:** Add CUDA backend to ONNX Runtime inference (CUDAExecutionProvider)
3. **Phase 3:** Add OpenCL backend for AMD/Intel GPUs (broader compatibility)

**Build order:** Phase 4 (after core features working, before 4K optimization which reduces GPU load)

### 5. 4K Memory Optimization (MODIFIED: src/av.nim, src/analyze/*)

**Purpose:** Reduce memory footprint when processing 4K video (3840×2160 = 8.3MP per frame vs 1920×1080 = 2.1MP).

**Integration pattern:** Optimize frame buffer management and analyzer downsizing without changing API contracts.

**Current memory hotspots:**
1. **Frame decoding loop** (av.nim): Allocates full-resolution frame buffers
2. **Analyzer buffering** (analyze/audio.nim, analyze/motion.nim): Accumulates frames for batch processing
3. **ML inference** (analyze/faces.nim): Passes full-resolution frames to face detector

**Optimization strategies:**

#### Strategy 1: Adaptive downscaling in analyzers
```nim
# src/analyze/faces.nim (modified)
proc faces*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
            targetWidth: int = 640): seq[FrameFaces] =
  # Downscale to targetWidth before face detection
  # 4K (3840×2160) → 640×360 = 14x fewer pixels
  # Face detection accuracy impact: <5% (faces must be >32px wide)
```

**Where to apply:**
- Face detection: Downscale to 640×360 (minimal accuracy loss, faces still >32px)
- Motion detection: Already uses downscaling (see `analyze/motion.nim` — samples at `downsample: int = 160`)
- Engagement scoring: Uses downscaled signals from face/motion analyzers

**Memory savings:**
- 4K frame: 3840×2160×3 bytes (RGB) = 24.9 MB
- 640×360 frame: 640×360×3 bytes = 0.69 MB
- **36x reduction** in memory per frame for ML analysis

#### Strategy 2: Streaming decode (already implemented!)
```nim
# src/av.nim - decode iterator already streams frames
iterator decode*(container: InputContainer, index: cint,
                 codecCtx: ptr AVCodecContext, frame: ptr AVFrame): ptr AVFrame =
  # Only one frame in memory at a time - no buffering
  for decodedFrame in ...:
    yield frame  # Caller processes immediately, frame reused
```

**Current architecture already optimal** — frame-by-frame decode with immediate processing. No accumulation of full-resolution frames.

#### Strategy 3: Audio sample buffer limits
```nim
# src/analyze/audio.nim (modified AudioIterator)
type AudioIterator = ref object
  fifo: ptr AVAudioFifo
  maxBufferSize: int  # Already limits buffer size
```

**Current implementation already capped** — `maxBufferSize` prevents unbounded growth. For 4K videos with high audio bitrate, consider reducing fifo size from 1024 to 512 samples.

#### Strategy 4: Cache downsized analysis
```nim
# src/cache.nim (modified procTag)
proc procTag(path: string, tb: AVRational, kind, args: string): string =
  # Include downsample factor in cache key
  let key = fmt"{name}{ext}:{modTime:x}:{tb}:{args}:downscale={downscaleFactor}"
```

**Benefit:** First pass caches face detection at 640×360, subsequent renders reuse without re-analyzing 4K frames.

**Research validation:**
Per [NVIDIA RTX Accelerates 4K AI Video Gen](https://blogs.nvidia.com/blog/rtx-ai-garage-ces-2026-open-models-video-generation/), 4K AI video generation achieves 3x faster speeds and 60% less VRAM via PyTorch-CUDA optimizations and native precision support. The same principle applies: downscale for analysis, preserve original resolution for render.

Per [Buffer Count and Buffer Fill](https://www.fastpix.io/blog/buffer-count-and-buffer-fill-for-smooth-video-streaming), codec efficiency (VP9 vs H.264) affects buffering needs. Our approach: downscale before ML analysis, use original resolution for final render.

**Build order:** Phase 5 (after GPU acceleration, since downscaling reduces GPU load too)

## Data Flow: Existing vs New

### Existing Single-File Flow
```
CLI args → main() → editMedia() → Pipeline
  ↓
  av.open(video) → decode frames
  ↓
  analyze/audio → seq[float32]  ← caches to disk
  analyze/motion → seq[float32] ← caches to disk
  analyze/engagement → EngagementTimeline ← caches to disk
  ↓
  timeline.initLinearTimeline() → v3 (clips)
  ↓
  render/video → OutputContainer
  render/audio → OutputContainer
  ↓
  exports/* → .fcpxml / .edl / .json
```

### New Batch Flow
```
CLI args → main() → detectBatchMode()
  ↓ if batch mode
  batch.processBatch() → JobQueue
  ↓ per job
  ┌─────────────────────────────────┐
  │ editMedia(job.args)             │ ← reuses entire existing pipeline
  │   (same flow as single-file)    │
  └─────────────────────────────────┘
  ↓ aggregate
  BatchResult → report
```

**Key insight:** Batch processing is orchestration layer, not pipeline modification.

### New Chapter Detection Flow
```
Transcript (existing from whisper)
  ↓
  analyze/chapters.detectChapters()
    → segment by topic shifts (TF-IDF cosine similarity)
    → generate titles (keyword extraction or first sentence)
  ↓
  seq[ChapterSegment] → export formats
    → YouTube chapters (00:00:00 Title)
    → EDL markers
    → JSON metadata
```

**Integration with existing analyzers:**
```nim
# In analyze command or clips command
let transcript = extractTranscript(inputPath, model)
let chapters = detectChapters(transcript, params)
let clips = detectClips(timeline, chapters)  # Pass chapters as boundary hints
```

### New Preview Generation Flow (Already Exists)
```
Engagement timeline + clips
  ↓
  render/previews.generatePreviews()
    → Contact sheet (thumbnail grid)
    → Best frame per clip (histogram filter)
    → Video snippets (3s start/middle/end)
  ↓
  {video}_previews/*.jpg, *.mp4
```

**No architectural changes needed** — already integrated into analyze command.

### New GPU Acceleration Flow
```
Frame → analyze/faces.nim
  ↓ check backend
  if GPU available:
    ml/facedetect.nim (CUDA backend)
      → cudaMallocHost (pin memory)
      → launch CUDA kernel
      → cudaMemcpy results
  else:
    ml/facedetect.nim (CPU backend)
      → libfacedetection CPU inference
  ↓
  seq[FaceRect] (same output format)
```

**Key pattern:** Backend dispatch transparent to caller. Analyzer API unchanged.

### New 4K Optimization Flow
```
av.decode() → 4K frame (3840×2160)
  ↓
  if analysis (not render):
    render/video.reformat(frame, targetWidth=640)  ← downscale
    ↓ 640×360 frame
  ml/facedetect.nim
    ↓ cached result
  else (render):
    use full 4K frame
```

**Key pattern:** Downscale for analysis, preserve original resolution for render.

## Component Boundaries

| Component | Responsibility | Communicates With | New/Modified | Phase |
|-----------|---------------|-------------------|--------------|-------|
| **batch.nim** | Job queue, worker pool, progress aggregation | main.nim (entry), edit.nim (per-job processing) | NEW | 1 |
| **analyze/chapters.nim** | Topic segmentation, title generation | transcript/types (input), timeline.nim (boundary hints) | NEW | 2 |
| **render/previews.nim** | Thumbnail/snippet generation | av.nim (decode), FFmpeg CLI (encoding) | EXISTING (add batch wrapper) | 3 |
| **ml/facedetect.nim** | Face detection with backend dispatch | av.nim (frames), analyze/faces.nim (caller) | MODIFIED (add GPU) | 4 |
| **av.nim** | Frame decoding, format conversion | All analyzers, renderers | MODIFIED (4K downscale helper) | 5 |
| **cache.nim** | Disk caching for expensive operations | All analyzers | MODIFIED (cache key includes downscale factor) | 5 |

## Build Order & Dependencies

### Phase Structure Recommendation

**Phase 1: Batch Processing**
- **Why first:** Lowest risk, highest user value. No new dependencies, pure orchestration.
- **Dependencies:** None (wraps existing pipeline)
- **Delivers:** Process 10 videos without manual intervention
- **Build steps:**
  1. Implement batch.nim (job queue, worker pool)
  2. Modify main.nim (detect batch mode)
  3. Add progress aggregation
  4. Test with existing single-file pipeline (no changes to analyzers)

**Phase 2: Chapter Detection**
- **Why second:** Builds on existing transcript pipeline, enables clip boundary improvements.
- **Dependencies:** Existing whisper.cpp integration, transcript types
- **Delivers:** YouTube chapters, EDL markers, improved clip detection
- **Build steps:**
  1. Implement analyze/chapters.nim (text segmentation)
  2. Add cmds/chapters.nim (new subcommand)
  3. Integrate with clips command (boundary hints)
  4. Export formats (YouTube, EDL, JSON)

**Phase 3: Preview Enhancements**
- **Why third:** Builds on existing previews.nim, adds batch support.
- **Dependencies:** Existing render/previews.nim
- **Delivers:** Batch preview generation, progress reporting
- **Build steps:**
  1. Add batch wrapper (process multiple files)
  2. Add progress bars to preview generation
  3. Add 4K optimization (downscale before thumbnail)
  4. Integrate with batch command

**Phase 4: GPU Acceleration**
- **Why fourth:** Complex dependencies (CUDA toolkit), optional feature.
- **Dependencies:** CUDA toolkit (optional), modified build system
- **Delivers:** 3-10x speedup on face detection with NVIDIA GPU
- **Build steps:**
  1. Add CUDA backend to ml/facedetect.nim
  2. Add build flags (ENABLE_CUDA=1)
  3. Add runtime GPU detection
  4. Add fallback to CPU if CUDA unavailable

**Phase 5: 4K Memory Optimization**
- **Why last:** Optimization, not new feature. Benefits from GPU acceleration (less memory to transfer).
- **Dependencies:** All analyzers, av.nim
- **Delivers:** Reduced memory footprint for 4K videos
- **Build steps:**
  1. Add downscale helper to av.nim
  2. Modify analyzers (faces, motion) to request downscaled frames
  3. Update cache keys (include downscale factor)
  4. Benchmark memory usage (verify 36x reduction for face detection)

### Dependency Graph
```
Phase 1 (Batch Processing)
  ↓ no dependencies

Phase 2 (Chapter Detection)
  ↓ depends on: existing transcript pipeline

Phase 3 (Preview Enhancements)
  ↓ depends on: Phase 1 (batch wrapper), existing previews.nim

Phase 4 (GPU Acceleration)
  ↓ depends on: existing ML modules (facedetect.nim)

Phase 5 (4K Optimization)
  ↓ depends on: Phase 4 (GPU reduces memory transfer), all analyzers
```

**Critical path:** Phase 1 → Phase 2 → Phase 3 can proceed in parallel with Phase 4 → Phase 5.

## Scalability Considerations

| Concern | At 10 videos | At 100 videos | At 1000 videos |
|---------|--------------|---------------|----------------|
| **Batch processing** | Sequential (30 min) | Parallel 4 workers (2 hrs) | Parallel 16 workers + disk I/O bottleneck |
| **Cache disk usage** | 100 MB (10×10MB) | 1 GB (100×10MB) | 10 GB → implement cache eviction (LRU, keep 100 most recent) |
| **Preview storage** | 50 MB (10×5MB) | 500 MB | 5 GB → warn user, offer cleanup |
| **GPU memory** | 2 GB VRAM | 2 GB VRAM (same, processes sequentially) | 2 GB VRAM (no change) |
| **4K memory per video** | 8 GB RAM (one 4K frame + buffers) | 8 GB RAM (same, sequential) | 8 GB RAM (no change with optimization) |

**Bottlenecks:**
- **Disk I/O:** Reading 4K video at 100 Mbps = 12.5 MB/s. NVMe SSD can sustain 3000 MB/s → not bottleneck until 240 parallel workers.
- **Cache eviction:** After 100 videos, cache directory grows to 1 GB. Implement LRU eviction (already prototyped in cache.nim — keeps 10 most recent).
- **Preview cleanup:** Warn user when preview directories exceed 1 GB total, offer batch cleanup command.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Batch Processing with Shared State
**What:** Reusing decoder/encoder contexts across files without cleanup
**Why bad:** Memory leaks, corrupted state, crashes after 10th file
**Instead:** Each BatchJob gets isolated `editMedia()` call with fresh containers

### Anti-Pattern 2: Chapter Detection without Transcript
**What:** Implementing scene-based chaptering (detect visual transitions)
**Why bad:** Visual scenes ≠ semantic topics. YouTube users expect topic chapters, not shot changes.
**Instead:** Require transcript for chapter detection. Scene detection already exists for clip boundaries.

### Anti-Pattern 3: GPU Acceleration without CPU Fallback
**What:** Fail if CUDA unavailable
**Why bad:** Users without NVIDIA GPU can't use feature
**Instead:** Detect GPU at runtime, fallback to CPU silently

### Anti-Pattern 4: 4K Downscaling for All Operations
**What:** Downscale before rendering output
**Why bad:** User expects 4K output, not 640×360
**Instead:** Downscale only for analysis (face detection, motion), preserve original resolution for render

### Anti-Pattern 5: Batch Processing via Shell Script
**What:** `for video in *.mp4; do honeyclip "$video"; done`
**Why bad:** No progress aggregation, no failure recovery, restarts binary per file (cold start overhead)
**Instead:** Native batch support with job queue and worker pool

## Sources

### Architecture Patterns (HIGH confidence)

**Batch processing:**
- [Automated Video Processing with FFmpeg and Docker | IMG.LY Blog](https://img.ly/blog/building-a-production-ready-batch-video-processing-server-with-ffmpeg/) — Producer-consumer model, FastAPI + async workers, profile-based templates
- [Batch Processing Architecture | Swiftorial](https://www.swiftorial.com/swiftlessons/architecture-patterns_bkp/software-architecture-patterns/batch-processing-architecture) — Workflow orchestration, pipeline patterns
- [Batch Architectural Design Patterns | Medium](https://medium.com/@pandeyarpit88/batch-architectural-design-patterns-and-tools-for-seamless-implementation-5a6fa1e03eb7) — Apache Airflow patterns, controller-based execution

**Chapter detection:**
- [Chapter-Llama: Efficient Chaptering | CVPR 2025](https://openaccess.thecvf.com/content/CVPR2025/papers/Ventura_Chapter-Llama_Efficient_Chaptering_in_Hour-Long_Videos_with_LLMs_CVPR_2025_paper.pdf) — LLM-based chaptering, 45.3% F1 score on VidChapters-7M
- [From Text Segmentation to Smart Chaptering | EACL 2024](https://aclanthology.org/2024.eacl-long.25.pdf) — YTSeg benchmark, MiniSeg model, hierarchical segmentation
- [Automatically determine video sections with AI | AssemblyAI](https://www.assemblyai.com/blog/automatically-determine-video-sections-with-ai-using-python) — Practical implementation guide

**Preview generation:**
- [Generating thumbnails 3.8x faster with FFmpeg seeking | Sebastian Aigner](https://sebi.io/posts/2024-12-21-faster-thumbnail-generation-with-ffmpeg-seeking/) — Input seeking (keyframe parsing) 3.8x faster than fps filtering
- [Extracting Thumbnails Faster with FFmpeg | Wistia](https://wistia.com/learn/marketing/faster-thumbnail-extraction-ffmpeg) — I-frame extraction, -ss before -i optimization, 5x speedup
- [FFmpeg Mastery: Extracting Perfect Thumbnails | Medium](https://medium.com/@sergiu.savva/ffmpeg-mastery-extracting-perfect-thumbnails-from-videos-339a4229bb32) — Quality settings (-q:v 2), thumbnail filter

**GPU acceleration:**
- [Hardware-Accelerated Machine Learning | Immich](https://docs.immich.app/features/ml-hardware-acceleration/) — CUDA vs OpenCL for face detection, CUDAExecutionProvider reliability
- [CUDA - OpenCV](https://opencv.org/platforms/cuda/) — OpenCV CUDA module, GPU-accelerated computer vision
- [Computer vision algorithms acceleration using CUDA | Springer](https://link.springer.com/article/10.1007/s10586-020-03090-6) — Performance analysis, 1.2-13x speedup

**4K memory optimization:**
- [NVIDIA RTX Accelerates 4K AI Video Gen | NVIDIA Blog](https://blogs.nvidia.com/blog/rtx-ai-garage-ces-2026-open-models-video-generation/) — 3x faster 4K generation, 60% less VRAM via PyTorch-CUDA optimizations
- [Buffer Count and Buffer Fill | Fastpix](https://www.fastpix.io/blog/buffer-count-and-buffer-fill-for-smooth-video-streaming) — Codec efficiency (VP9 vs H.264), buffer size optimization
- [Low Quality for High Quality: 2K Frames for 4K Streaming | IEEE](https://ieeexplore.ieee.org/document/9345461/) — Upscaling approach, render at lower resolution

### Implementation Details (MEDIUM confidence)

- FFmpeg filter documentation — Verified thumbnail filter, drawtext filter, tile filter
- ONNX Runtime C++ API docs — Verified CUDAExecutionProvider usage
- OpenCV CUDA module docs — Verified GPU backend selection pattern

---

*Research completed: 2026-02-05*
*Architecture validation: Extends existing patterns, no parallel systems required*
*Ready for roadmap: Yes*
