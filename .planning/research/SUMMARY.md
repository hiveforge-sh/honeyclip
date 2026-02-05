# Project Research Summary

**Project:** honeyclip v1.2 - Workflow & Performance
**Domain:** Video processing CLI - batch processing, GPU acceleration, 4K optimization, chapter detection
**Researched:** 2026-02-05
**Confidence:** HIGH

## Executive Summary

honeyclip v1.2 extends an existing, validated video CLI tool with workflow and performance features. The research reveals that most requirements can be met with minimal new dependencies: only nim-toml for batch configuration files. GPU acceleration leverages existing CUDA/Metal support already integrated for whisper.cpp. 4K memory optimization is achieved through application-level patterns (downsampling frames before ML analysis) rather than new libraries. Chapter detection uses FFmpeg's built-in scene detection filter combined with transcript analysis. Preview generation already exists and needs only batch integration.

The recommended approach is to build workflow features first (batch processing, chapter detection) before performance optimizations (GPU acceleration, 4K memory optimization). This ordering allows users to gain immediate value from batch processing while the team validates GPU integration complexity on production workloads. Critical risk: GPU acceleration requires careful memory transfer management - frames must stay GPU-resident to avoid PCIe bandwidth bottlenecks that negate performance gains.

The architecture cleanly extends existing patterns: batch processing wraps the single-file pipeline, chapter detection follows the analyzer pattern established by audio/motion/engagement modules, and GPU acceleration adds backend selection to existing ML modules. No parallel systems needed. The main technical debt risk is Nim's garbage collector not tracking C-allocated FFmpeg frame buffers - migration to --gc:orc recommended for deterministic cleanup of 32MB 4K frames.

## Key Findings

### Recommended Stack

v1.2 builds on the validated v1.0-v1.1 stack without major changes. Only one new dependency: nim-toml (50 KB) for batch configuration files. GPU acceleration extends existing CUDA 12.8 (Linux) and Metal (macOS) support from whisper.cpp by enabling OpenCV CUDA module via cmake flags. No new runtime dependencies - just build configuration changes.

**Core technologies:**
- **nim-toml (NEW)**: Human-editable batch templates - chosen over JSON (no comments) and YAML (implicit typing bugs)
- **OpenCV CUDA module (build flag)**: GPU-accelerated face detection - already have CUDA 12.8 for whisper, just enable OpenCV integration
- **FFmpeg scdet filter (existing)**: Scene change detection for chapter boundaries - built-in, no new dependency
- **Memory-mapped I/O (existing)**: FFmpeg already uses this - 4K optimization is application-level frame management, not library changes
- **ONNX Runtime CoreML EP (optional)**: Enable via --use_coreml build flag on macOS for Apple Neural Engine acceleration

**What NOT to add:**
- TensorRT (NVIDIA): Overkill for v1.2, defer to Phase 3+ if needed
- OpenCL: Deprecated on macOS, inferior to CUDA on Linux
- Vulkan Compute: Immature video ecosystem
- SQLite job queue: Start with simple TOML, add only if 1000+ video batches become common

### Expected Features

**Must have (table stakes) - Users expect these from modern video CLI tools:**
- **Batch template/preset system**: Content creators process multiple videos with same settings - YAML/JSON config is standard (FFmpeg-batch, HandBrake presets)
- **Batch progress reporting**: Overall progress (N/M files, ETA), not just current file - GNU Parallel's --progress is expected
- **Batch error recovery**: One failure shouldn't stop 50-video overnight batch - job log with skip/resume capability
- **Parallel processing**: Use all CPU cores, not serial - GNU Parallel pattern
- **Chapter: Scene change detection**: Adobe/DaVinci/Final Cut all have this - FFmpeg filter provides parity
- **Chapter: Transcript-based markers**: When transcripts exist, users expect auto-chapters from topic changes (Descript, Sonix)
- **Preview: Low-res proxy generation**: 720p proxies for 4K+ source is standard NLE workflow
- **Preview: Fast preview mode**: Quick preview at 2-3x faster than realtime before full render
- **GPU: CUDA on Linux**: Linux users with NVIDIA expect CUDA for ML - 3-22x speedup for face detection
- **GPU: Metal on macOS**: Apple's GPU API since 2014 - CoreML + Metal Performance Shaders expected
- **Memory: Streaming decode**: 4K at 60fps = 1GB/sec uncompressed - frame-at-a-time is mandatory
- **Memory: Frame pooling**: Reuse buffers to prevent allocation churn and fragmentation

**Should have (differentiators) - Novel features that set honeyclip apart:**
- **Engagement-driven chapters**: Use existing engagement scores to set boundaries at high-engagement moments (novel in CLI space)
- **Hook pattern chapters**: Chapters at detected hooks from v1.1 (questions, cliffhangers) - "Chapter 1: How to optimize..."
- **Multi-modal boundaries**: Combine transcript + scene changes + engagement drops for smarter boundaries (most tools use single signal)
- **GPU automatic fallback**: Detect CUDA/Metal availability, gracefully fall back to CPU without user intervention
- **Hybrid CPU+GPU pipeline**: GPU for face detection, CPU for I/O and timeline - minimize data transfer overhead

**Defer (v2+) - High complexity or lower priority:**
- Folder watch mode (HIGH complexity, async monitoring)
- Adaptive resolution processing (HIGH complexity, auto-downscale based on available RAM)
- Progress checkpointing for 3hr+ videos (HIGH complexity)
- Multi-preview generation (multiple types in one pass)

### Architecture Approach

v1.2 features integrate cleanly with honeyclip's existing pipeline architecture. All new features extend existing components rather than creating parallel systems. Batch processing wraps the single-file workflow with job queue orchestration. Chapter detection follows the analyzer pattern (audio.nim, motion.nim, engagement.nim). Preview generation already exists. GPU acceleration extends ML modules with backend selection. 4K optimization touches frame decoding loop and analyzer buffering.

**Major components:**
1. **batch.nim (NEW)**: Job queue, worker pool, progress aggregation - wraps main() with batch orchestration, reuses existing editMedia() per file
2. **analyze/chapters.nim (NEW)**: Topic segmentation with sliding window + TF-IDF cosine similarity - follows analyzer pattern, consumes existing Transcript type
3. **render/previews.nim (EXISTING)**: Already has contact sheets, thumbnails, snippets - just needs batch wrapper and progress reporting
4. **ml/facedetect.nim (MODIFIED)**: Add AcceleratorBackend enum (CPU, CUDA, Metal) - backend dispatch transparent to callers
5. **av.nim (MODIFIED)**: Add downscale helper for 4K optimization - analyzers request 640x360 frames instead of 3840x2160 for face detection (36x memory reduction)

**Integration pattern:** Existing pipeline is decode → analyze → timeline → render → export. Batch wraps this as orchestrator. Chapter detection inserts between transcript and timeline. GPU acceleration is drop-in backend replacement in ML modules. 4K optimization is application-level buffering, not pipeline changes.

### Critical Pitfalls

1. **GPU memory round-trip bottleneck**: Missing `-hwaccel_output_format cuda` flag causes frames to copy from GPU to system RAM after decode, then back to GPU for encoding - PCIe bandwidth saturation defeats GPU acceleration (2x throughput loss). Prevention: Add platform-specific hwaccel flags, verify GPU-resident pipeline with nvidia-smi profiling.

2. **Thread count misconfiguration for hybrid workloads**: Using default thread_count=0 (all cores) with GPU encoding causes 100% CPU saturation while GPU sits at 20% utilization - cache thrashing, system unresponsiveness. Prevention: Dynamic thread allocation - limit to 4 threads when GPU available, use all cores for CPU-only fallback.

3. **4K frame buffer accumulation without backpressure**: Decode queue fills faster than encode drains - 30 frames × 32MB = 960MB spike, multiple files = OOM kill. Prevention: Bounded queue with max 8 frames for 4K (256MB ceiling), block decode when queue full, implement drain logic.

4. **Batch processing without checkpoint/resume**: Multi-hour batch fails at file 99/100 - entire batch restarts from file 1, wasting 50 hours. Prevention: Save checkpoint after EACH file completes, include batch ID (hash of inputs), install signal handler for graceful Ctrl+C shutdown.

5. **Chapter detection without speaker diarization**: Topic changes during conversation create 60 micro-chapters instead of 8 meaningful segments - splits mid-sentence during natural topic pivots. Prevention: Implement speaker diarization (whisper.cpp has tinydiarize support) before chapter algorithm, only create boundaries on speaker change + topic change.

## Implications for Roadmap

Based on research, suggested phase structure prioritizes user value and risk management:

### Phase 1: Batch Processing Foundation
**Rationale:** Lowest risk, highest immediate value. No new dependencies beyond nim-toml. Wraps existing pipeline without modifying analyzers. Validates orchestration patterns before adding GPU complexity.

**Delivers:**
- Process 10-100 videos without manual intervention
- TOML template system for preset configurations
- Parallel processing (N workers = CPU cores)
- Progress reporting with ETA calculation
- Checkpoint/resume capability

**Addresses:**
- Table stakes: batch template system, progress reporting, error recovery, parallel processing (FEATURES.md)
- User workflow: "Process folder like this file" pattern

**Avoids:**
- Pitfall 4: Checkpoint/resume from start (not retrofit)
- Pitfall 7: Per-file context isolation to prevent error cascade

**Research flag:** SKIP RESEARCH - Standard orchestration pattern, well-documented. Implement directly from ARCHITECTURE.md producer-consumer model.

### Phase 2: Chapter Detection & Export
**Rationale:** Builds on existing transcript pipeline (v1.1 whisper integration). Enables clip boundary improvements. FFmpeg scdet filter is built-in, no complex dependencies.

**Delivers:**
- Scene change detection via FFmpeg scdet filter
- Transcript-based topic segmentation (sliding window + TF-IDF)
- Engagement-driven chapter boundaries (novel differentiator)
- Export formats: YouTube chapters, EDL markers, FCPXML markers

**Uses:**
- Existing Transcript type (src/transcript/types.nim)
- Existing engagement scores (src/analyze/engagement.nim)
- FFmpeg scdet filter (built-in)

**Implements:**
- analyze/chapters.nim following analyzer pattern
- cmds/chapters.nim new subcommand

**Avoids:**
- Pitfall 5: Implement speaker diarization first (whisper.cpp tinydiarize)

**Research flag:** NEEDS RESEARCH for Phase 2b - Speaker diarization integration with whisper.cpp is experimental (2026 feature). Research: tinydiarize API, WhisperX alternative, Falcon integration options.

### Phase 3: Preview Enhancement & Batch Integration
**Rationale:** Builds on existing previews.nim (already implemented in v1.1). Low risk enhancement. Adds batch support and progress reporting.

**Delivers:**
- Batch preview generation (process multiple clips)
- Progress bars during preview generation
- 4K-aware preview (downscale before thumbnail extraction)
- Integration with batch command from Phase 1

**Uses:**
- Existing src/render/previews.nim
- Batch orchestrator from Phase 1
- FFmpeg thumbnail filter, tile filter

**Avoids:**
- Pitfall 9: Streaming preview generation (decode → thumbnail → discard, not accumulate frames)

**Research flag:** SKIP RESEARCH - Enhancement of existing feature, patterns established.

### Phase 4: GPU Acceleration (Optional Performance)
**Rationale:** Complex dependencies (CUDA toolkit), optional feature. Comes after core workflow features deliver user value. GPU reduces memory pressure for Phase 5's 4K optimization.

**Delivers:**
- CUDA backend for face detection (Linux, NVIDIA GPUs)
- CoreML backend for neural inference (macOS, Apple Silicon)
- Automatic fallback to CPU if GPU unavailable
- 5-10x speedup for face detection on supported hardware

**Uses:**
- Existing CUDA 12.8 from whisper.cpp build
- OpenCV CUDA module (enable via cmake flag)
- ONNX Runtime CoreML EP (rebuild with --use_coreml)

**Implements:**
- Modified src/ml/facedetect.nim (AcceleratorBackend enum)
- New src/gpu.nim (runtime capability detection)

**Avoids:**
- Pitfall 1: GPU memory round-trip (use -hwaccel_output_format cuda)
- Pitfall 2: Thread misconfiguration (limit to 4 threads when GPU active)
- Pitfall 6: macOS Metal assumption (detect at runtime, support pre-2017 Macs)
- Pitfall 12: GPU capability detection (query compute capability, graceful degradation)

**Research flag:** NEEDS RESEARCH for Phase 4a - CUDA integration specifics: OpenCV CUDA module build flags, compute capability requirements, memory transfer patterns. Research: nvidia-smi integration, pinned memory allocation, benchmark data transfer overhead.

### Phase 5: 4K Memory Optimization
**Rationale:** Optimization, not new feature. Benefits from Phase 4's GPU acceleration (less memory to transfer). Touches core decode loop and all analyzers - highest integration risk, goes last.

**Delivers:**
- Downsampled face detection (4K → 640x360 = 36x memory reduction)
- Bounded frame queue with backpressure (max 8 frames for 4K = 256MB ceiling)
- Sparse sampling for face detection (1 FPS instead of 30 FPS = 30x speedup)
- Memory budget enforcement across batch jobs

**Uses:**
- Modified src/av.nim (downscale helper, bounded decode queue)
- Modified src/analyze/faces.nim (request downscaled frames)
- Modified src/cache.nim (cache keys include downscale factor)

**Implements:**
- Frame pool with backpressure mechanism
- Resolution-based queue sizing (queueDepth = min(16, 256MB / frameSize))

**Avoids:**
- Pitfall 3: 4K frame buffer accumulation (bounded queue from start)
- Pitfall 8: Nim GC not tracking C buffers (migrate to --gc:orc for deterministic cleanup)

**Research flag:** SKIP RESEARCH for implementation, but ADD VALIDATION - Profile with valgrind, test with ulimit -v to simulate memory constraints, benchmark peak RSS with 4K 10-minute test videos.

### Phase Ordering Rationale

- **Workflow before performance**: Batch processing (Phase 1) delivers immediate user value. GPU acceleration (Phase 4) is optional enhancement - users without NVIDIA GPUs still get full functionality.
- **Simple before complex**: Chapter detection (Phase 2) uses built-in FFmpeg filter. GPU acceleration (Phase 4) requires CUDA toolkit and complex build configuration.
- **Foundation before optimization**: 4K optimization (Phase 5) goes last because it touches core decode loop and all analyzers - highest integration risk. GPU acceleration (Phase 4) reduces memory transfer needs for Phase 5.
- **Validation via usage**: Phases 1-3 deliver complete workflow features. Phases 4-5 are performance optimizations that can be validated with real user workloads from Phases 1-3.

**Dependency graph:**
- Phase 1 (Batch) → independent, can start immediately
- Phase 2 (Chapters) → depends on existing transcript pipeline (v1.1), independent of Phase 1
- Phase 3 (Previews) → depends on Phase 1 (batch wrapper), independent of Phase 2
- Phase 4 (GPU) → independent of Phases 1-3, but Phase 3 benefits from GPU speedup
- Phase 5 (4K) → benefits from Phase 4 (less GPU memory to transfer), touches all phases

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 2b (Speaker Diarization)**: Whisper.cpp tinydiarize is experimental 2026 feature. Need to research API stability, accuracy benchmarks, fallback options (WhisperX, Falcon). Estimated research: 2-4 hours.
- **Phase 4a (CUDA Integration)**: OpenCV CUDA module build process, compute capability detection, pinned memory patterns. Estimated research: 4-6 hours.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Batch Processing)**: Producer-consumer pattern, well-documented in GNU Parallel, FFmpeg-batch, AWS Batch. ARCHITECTURE.md provides sufficient detail.
- **Phase 3 (Preview Enhancement)**: Existing previews.nim established patterns. Extension, not net-new.
- **Phase 5 (4K Optimization)**: Application-level buffering, no new libraries. PITFALLS.md covers backpressure patterns. Needs profiling validation, not research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Minimal new dependencies (only nim-toml). GPU acceleration extends existing CUDA/Metal from whisper.cpp. Verified via official NVIDIA, Apple docs. |
| Features | MEDIUM | Table stakes verified across FFmpeg-batch, GNU Parallel, HandBrake patterns. Differentiators (engagement-driven chapters) are novel but build on existing v1.1 features. Speaker diarization tooling experimental. |
| Architecture | HIGH | Clean extension of existing patterns. Batch wraps pipeline, chapters follow analyzer pattern, GPU adds backend selection. No parallel systems. Validated via CVPR 2025 chaptering research, IMG.LY batch processing patterns. |
| Pitfalls | HIGH | GPU memory round-trip, thread misconfiguration, 4K OOM documented in NVIDIA official guides, FFmpeg 7.x release notes, Linux kernel docs. Checkpoint patterns from AWS/Azure/HTCondor. Speaker diarization gap from Auphonic, WhisperX sources. |

**Overall confidence:** HIGH

### Gaps to Address

**Speaker diarization accuracy:** Research shows whisper.cpp tinydiarize is experimental (2026). WhisperX provides production-ready alternative but requires Python dependency. Falcon Speaker Diarization is offline but integration unclear.

**How to handle:** Phase 2a implements topic-based chapters WITHOUT speaker diarization (accept micro-chapter risk for single-speaker content). Phase 2b adds speaker diarization after validating tinydiarize stability or selecting WhisperX/Falcon alternative. Flag Phase 2b for `/gsd:research-phase` during roadmap execution.

**GPU performance variability:** Research shows 3-22x speedup range for face detection depending on implementation. Data transfer overhead can negate gains if not managed carefully.

**How to handle:** Phase 4 must include profiling gates: measure GPU memory usage (nvidia-smi), verify frames stay GPU-resident (no system RAM spikes), benchmark throughput vs CPU baseline. If speedup <3x, revisit memory transfer patterns before declaring phase complete.

**Nim GC with C FFI:** Current codebase uses default refc GC. Research indicates ARC/ORC better for multimedia (deterministic cleanup, no GC pauses). Migration risk unclear.

**How to handle:** Phase 5 (4K optimization) tests --gc:orc on isolated module first (av.nim). If stable, migrate incrementally. Document fallback to manual av_frame_free() if ORC issues surface. Add memory leak tests with valgrind to validate cleanup.

## Sources

### Primary (HIGH confidence)
- [NVIDIA FFmpeg Transcoding Guide](https://developer.nvidia.com/blog/nvidia-ffmpeg-transcoding-guide/) - GPU acceleration patterns, hwaccel flags
- [OpenCV CUDA Module Documentation](https://docs.opencv.org/4.x/d2/dbc/cuda_intro.html) - CUDA integration for face detection
- [FFmpeg 7.x Release Notes](https://www.phoronix.com/news/FFmpeg-CLI-Multi-Threaded) - Multi-threaded pipeline architecture
- [IMG.LY FFmpeg Batch Processing](https://img.ly/blog/building-a-production-ready-batch-video-processing-server-with-ffmpeg/) - Producer-consumer patterns
- [Chapter-Llama CVPR 2025](https://openaccess.thecvf.com/content/CVPR2025/papers/Ventura_Chapter-Llama_Efficient_Chaptering_in_Hour-Long_Videos_with_LLMs_CVPR_2025_paper.pdf) - Video chaptering algorithms
- [Auphonic Automatic Chapters](https://auphonic.com/help/algorithms/speech_recognition.html) - Speaker diarization + chapters
- [AWS SageMaker Checkpoints](https://docs.aws.amazon.com/sagemaker/latest/dg/model-checkpoints.html) - Checkpoint/resume patterns
- [Linux Kernel V4L2 Decoder](https://docs.kernel.org/userspace-api/media/v4l/dev-stateless-decoder.html) - Buffer management

### Secondary (MEDIUM confidence)
- [FFmpeg Threads Performance Study](https://streaminglearningcenter.com/blogs/ffmpeg-command-threads-how-it-affects-quality-and-performance.html) - Thread count impact
- [WhisperX Pipeline Guide](https://vogla.com/whisperx-transcription-pipeline-guide/) - Speaker diarization options
- [Whisper.cpp Speaker Diarization](https://picovoice.ai/blog/whisper-cpp-speaker-diarization/) - Tinydiarize integration
- [NVIDIA RTX 4K AI Performance](https://blogs.nvidia.com/blog/rtx-ai-garage-ces-2026-open-models-video-generation/) - Memory optimization patterns
- [Nim ARC/ORC Documentation](https://nim-lang.org/araq/destructors.html) - GC alternatives for FFI
- [MuleSoft Batch Error Handling](https://mulesy.com/error-handling-in-batch-job/) - Error isolation patterns

### Tertiary (LOW confidence, needs validation)
- TOML vs YAML vs JSON comparison (dev.to) - Configuration format selection
- ComfyUI VRAM management (GitHub) - GPU memory patterns
- Video segmentation methods (DagShub blog) - ML-based segmentation options

---
*Research completed: 2026-02-05*
*Ready for roadmap: yes*
