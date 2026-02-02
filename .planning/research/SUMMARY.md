# Project Research Summary

**Project:** Auto-Editor Video Engagement Analysis Features
**Domain:** Video engagement analysis and auto-clipping tools (local-first CLI)
**Researched:** 2026-02-01
**Confidence:** MEDIUM-HIGH

## Executive Summary

Auto-editor is adding video engagement analysis features to compete with cloud-based auto-clipping tools like OpusClip and Kapwing, while maintaining its local-first, privacy-focused architecture. The recommended approach leverages existing FFmpeg/whisper.cpp integration and adds face detection (libfacedetection or ONNX models), speaker diarization (Falcon SDK), and multi-modal engagement scoring. This enables automatic clip detection, virality scoring, auto-captions, and smart vertical reframing without cloud dependencies.

The core differentiator is local processing with open-source transparency. Cloud competitors require $29-99/month subscriptions and upload video to their servers. Auto-editor can provide comparable features (transcription, engagement scoring, auto-clipping, multi-aspect-ratio export) while running entirely offline. The recommended stack uses CPU-friendly libraries (libfacedetection, ONNX Runtime) with optional GPU acceleration, following honeyclip's existing build patterns (static linking, cross-platform compilation via nimble).

Key risks center on build complexity and performance. Adding ML libraries (OpenCV, ONNX Runtime) to the existing FFmpeg build system creates cross-platform compilation challenges, particularly for Windows cross-compile via MinGW. Binary size can balloon from 10MB to 100MB+ without careful dependency management. Face detection at 30fps consumes significant CPU, requiring adaptive frame sampling (1-5fps analysis rate) and aggressive caching. Memory management at the Nim/C++ FFI boundary must follow strict patterns (GC_ref/GC_unref, shared allocation) to prevent leaks and crashes. Mitigation: establish build architecture and FFI patterns in Phase 1 before adding multiple ML libraries.

## Key Findings

### Recommended Stack

The research identifies a pragmatic stack that builds on honeyclip's existing strengths (FFmpeg, whisper.cpp, Nim) while adding minimal new dependencies. All recommended libraries are open-source with permissive licenses (BSD, MIT, Apache 2.0) and provide C/C++ APIs compatible with Nim's FFI.

**Core technologies:**
- **libfacedetection v3.0**: Face detection — BSD-3 license, no dependencies, 1000 FPS on CPU, cross-platform including ARM
- **ONNX Runtime 1.23.2+**: Neural network inference — Industry standard, CPU/GPU support, C++ API, enables flexible model deployment
- **OpenCV 4.13+**: Video frame processing and tracking — Most mature option, extensive documentation, Apache 2.0 license
- **Falcon Speaker Diarization**: Speaker identification — Apache 2.0, C API, free tier 250 min/month, only viable local C++ diarization option
- **FFmpeg 8.0.1 (existing)**: Video decoding and audio processing — Already integrated and proven reliable
- **whisper.cpp 1.8.2 (existing)**: Speech-to-text transcription — Already integrated, provides foundation for transcript-based features

**What NOT to use:**
- MediaPipe (deprecated C++ support as of March 2023, Android/Python/Web only)
- Cloud APIs (violates local-first architecture)
- TensorFlow/PyTorch runtime (heavy dependencies vs lightweight ONNX Runtime)
- Python-based solutions like pyannote.audio directly (requires Python runtime; use Falcon SDK instead)

**Critical version compatibility:** ONNX Runtime 1.23+ supports ONNX opset 7-21, compatible with InsightFace models (opset 11). OpenCV 4.13+ requires C++11 minimum, compatible with Nim's C++ backend. All libraries confirmed cross-platform for Linux, macOS, Windows (MinGW), and ARM.

### Expected Features

Research shows auto-clipping tools have standardized on a core feature set. Missing any table stakes makes the product feel incomplete. Differentiators justify choosing honeyclip over cloud competitors.

**Must have (table stakes):**
- Automatic transcription with word-level timestamps (SRT/VTT export) — users expect this
- Auto-caption generation with stylized text overlay — required for social media
- Scene/moment detection for auto-clipping boundaries — defines "auto-clipping"
- Multi-platform export (16:9 YouTube, 9:16 TikTok/Reels, 1:1 Instagram) — users expect this
- Batch processing (one video → multiple ranked clips) — expected behavior

**Should have (competitive advantage):**
- Local processing with no cloud upload — MAJOR differentiator, privacy-conscious users can't use cloud tools
- Engagement scoring using local signals (audio energy, motion, speech rate, pauses) — matches OpusClip's Virality Score but transparent and local
- Speaker reframing for vertical conversion (face tracking + smart crop) — matches OpusClip's ReframeAnything premium feature
- Open-source and transparent algorithms — builds trust vs proprietary black boxes
- No subscription lock-in — free/donate model vs $29-99/month recurring payments

**Defer (v2+):**
- ClipAnything-style natural language search ("find all moments where speaker says X") — requires semantic embeddings, high complexity
- Advanced B-roll insertion points — suggests where to add B-roll but doesn't generate/fetch it
- Multi-speaker diarization with per-speaker clip export — valuable but niche, requires Falcon integration
- Emotion detection via facial expression or voice tone — experimental, requires additional ML models

**Anti-features (avoid):**
- Cloud virality scores connected to TikTok/YouTube data — violates privacy differentiator, creates false confidence
- Automatic B-roll from stock libraries — licensing complexity, generic results, users prefer their own B-roll
- AI-generated video content (Sora/Veo) — requires expensive cloud APIs, quality inconsistent, out of scope
- Social media auto-posting/scheduling — platform APIs unstable, not core editing functionality
- Real-time live stream processing — completely different architecture, niche use case

### Architecture Approach

The research validates extending honeyclip's existing pipeline architecture rather than building parallel systems. Face detection, speaker diarization, and engagement scoring integrate as new analyzers following the existing audio.nim/motion.nim pattern. All analyzers produce seq[bool] arrays that feed into the existing timeline builder, maintaining backward compatibility with exports and edit expressions.

**Major components:**
1. **Analysis Layer Extension** (analyze/face.nim, analyze/speaker.nim, analyze/engagement.nim) — New analyzers follow existing pattern, produce boolean arrays or scored regions, integrate with palet edit expression language
2. **Timeline Metadata** (optional side table) — Rich engagement data (face regions, speaker segments, scores) stored separately, referenced by clip index, preserves v3 timeline structure for backward compatibility
3. **Reframing Engine** (render/reframe.nim) — Face tracking with persistent IDs, ROI smoothing via exponential moving average, dynamic crop filter integrated with FFmpeg filter graphs
4. **Caching Layer** (extends existing cache.nim) — Mandatory for expensive operations (face detection 5-20 FPS, speaker diarization 10-60s per hour), cache keyed by input hash + detector version

**Key architectural patterns:**
- **Frame-by-frame analysis with buffering:** Process one frame at a time for memory efficiency, parallelize via FFmpeg filter graphs
- **Boolean array as common interface:** All detectors produce seq[bool] for timeline integration, enables composability with existing edit expressions
- **Two-stage pipeline (Detect → Score → Timeline):** Rich data structures (FaceRegion, SpeakerSegment) converted to boolean for timeline, metadata preserved for advanced features like reframing
- **Lazy evaluation:** Parse --edit expression first, only instantiate required analyzers (avoid running face detection if user only needs audio)

### Critical Pitfalls

Based on research, the top pitfalls that could derail implementation:

1. **Memory management at FFI boundaries (Nim/C ML libraries)** — Memory leaks or crashes at Nim GC / C++ manual memory boundary. Nim's GC runs unpredictably; ref types passed to C get garbage collected while still in use. **Avoid:** Use GC_ref/GC_unref to extend lifetimes, use shared allocation (createShared/deallocShared) for cross-thread usage, wrap FFI calls in RAII-style Nim objects. Establish patterns in Phase 1 before integrating multiple ML libraries.

2. **Binary size explosion from static linking ML libraries** — Adding ONNX Runtime and OpenCV via static linking can balloon binaries from 10MB to 100MB+ per platform. **Avoid:** Disable unnecessary ONNX Runtime backends during compilation, use aggressive optimization (-Os, LTO), strip debug symbols, consider dynamic linking on platforms where runtime is controlled. Establish build architecture in Phase 1.

3. **False positive rate in production video analysis** — Face detection produces 85% false positive rates in real-world deployments (Metropolitan Police finding) due to motion blur, occlusions, varying lighting. Default thresholds sacrifice specificity. **Avoid:** Implement multi-frame consensus (require face detection across N consecutive frames), calibrate thresholds on user video not benchmarks, use Scene Change Indicator to reduce temporal false positives. Address in Phase 2.

4. **Frame extraction rate vs detection accuracy tradeoff** — Processing 30fps (1800 frames/min) wastes CPU but skipping too many frames misses events. **Avoid:** Use adaptive frame selection based on scene changes and motion, target 1-5fps analysis rate for offline processing (not real-time 24fps), validate accuracy within 5% of all-frame processing. Optimize in Phase 2.

5. **Cross-platform ONNX/OpenCV build system complexity** — ONNX Runtime requires Visual Studio 2022+ on Windows, GCC 9+ on Linux. OpenCV CMake with ONNX support has version conflicts. Windows cross-compile via MinGW has limited ONNX Runtime support. Protobuf version conflicts between FFmpeg, ONNX Runtime, OpenCV. **Avoid:** Document minimum toolchain versions, test cross-compilation early, consider ONNX Runtime pre-built binaries for Windows, use opencv_lite (bundles compatible ONNX Runtime v1.14-1.22). Validate in Phase 1.

## Implications for Roadmap

Based on research, suggested phase structure prioritizes foundation (build system, FFI patterns) before adding ML features, validates each analyzer independently before integration, and defers complex features (reframing, NL search) until core auto-clipping works.

### Phase 1: Foundation & Build Infrastructure
**Rationale:** Must establish Nim/C++ FFI memory management patterns, cross-platform build system for ML libraries, and binary size optimization strategy before adding multiple ML dependencies. Research shows this is the #1 cause of project failure (memory leaks, cross-compile failures, 100MB+ binaries).

**Delivers:**
- Build system extensions for libfacedetection, ONNX Runtime, OpenCV (static linking with size optimization)
- FFI wrapper patterns with GC_ref/GC_unref and RAII lifetime management
- Cross-platform validation (Linux, macOS, Windows via MinGW)
- Binary size CI checks (fail if >50MB per platform)

**Addresses:**
- Pitfall #2 (Binary size explosion)
- Pitfall #5 (Cross-platform build complexity)
- Pitfall #9 (Memory management at FFI boundaries)

**Research flag:** Needs `/gsd:research-phase` for cross-compilation strategy (MinGW vs pre-built binaries for ONNX Runtime on Windows)

### Phase 2: Transcript & Auto-Captions (Table Stakes MVP)
**Rationale:** Leverages existing whisper.cpp integration (lowest risk), provides immediate user value (SRT/VTT export, captions for social media), no new ML dependencies. Table stakes features that competitors all provide.

**Delivers:**
- Word-level timestamp extraction from whisper.cpp output
- SRT/VTT export formats
- Auto-caption rendering with basic styling (FFmpeg subtitle filters)
- Multi-aspect-ratio export (16:9, 9:16, 1:1) via FFmpeg scale/crop

**Uses:**
- whisper.cpp (existing)
- FFmpeg subtitle filters (existing)

**Addresses:**
- FEATURES.md table stakes: transcription, auto-captions, multi-aspect-ratio export

**Research flag:** Standard patterns, no research needed (whisper integration exists, FFmpeg subtitle filters well-documented)

### Phase 3: Face Detection & Motion Analysis
**Rationale:** Face detection is foundation for engagement scoring and reframing. Must validate accuracy, performance, and false positive rate before building dependent features. Research shows adaptive frame sampling and multi-frame consensus are critical to avoid CPU waste and false positives.

**Delivers:**
- Face detection analyzer (analyze/face.nim) following audio/motion pattern
- Adaptive frame extraction (1-5fps based on scene changes)
- Multi-frame consensus to reduce false positives
- Cache layer for face detection results
- Integration with edit expressions: `--edit '(face :min-confidence 0.7)'`

**Uses:**
- libfacedetection v3.0 (CPU-first, 1000 FPS claim)
- OpenCV for tracking (optional)
- Existing FFmpeg scene detection

**Addresses:**
- Pitfall #1 (Face alignment and low-quality input)
- Pitfall #4 (False positive rate)
- Pitfall #7 (Frame extraction rate vs accuracy)

**Research flag:** Needs `/gsd:research-phase` for face detection model selection (libfacedetection vs ONNX models like SCRFD/RetinaFace) and quantization validation

### Phase 4: Engagement Scoring (Core Differentiator)
**Rationale:** Multi-modal engagement scoring is the killer feature (local alternative to OpusClip's Virality Score). Combines face presence, audio energy, motion, and transcript features. Must define domain-specific metrics before implementation to avoid metric misalignment (Pitfall #5).

**Delivers:**
- Engagement scorer combining audio energy (RMS), motion (frame diff), face presence, speech rate
- Heuristic scoring model with configurable weights
- Boolean conversion (threshold engagement scores) for timeline integration
- Batch auto-clipping: export top N clips ranked by engagement
- Scene detection + silence detection for clip boundaries

**Implements:**
- analyze/engagement.nim (multi-modal fusion)
- Timeline metadata with engagement scores
- Batch export workflow

**Addresses:**
- FEATURES.md differentiator: local engagement scoring
- Pitfall #6 (Engagement metric misalignment) — define metrics for screencast/tutorial domain
- Pitfall #8 (Cold start problem) — content-based features work without history

**Research flag:** Needs `/gsd:research-phase` for scoring algorithm validation (how to weight audio vs motion vs face without cloud data for ground truth)

### Phase 5: Speaker Reframing (Advanced Feature)
**Rationale:** Most complex feature (tracking + smoothing + rendering). Requires all previous phases (face detection, speaker diarization, rendering pipeline changes). Differentiator against cloud tools but not essential for MVP.

**Delivers:**
- Face tracking with persistent IDs across frames
- ROI smoothing via exponential moving average or Kalman filter
- Speaker-aware ROI selection (combine face detection + speaker diarization)
- Dynamic crop filter for vertical conversion (9:16)
- Fallback to center crop when no faces detected

**Uses:**
- analyze/face.nim (from Phase 3)
- Falcon speaker diarization SDK (new dependency)
- OpenCV tracking API (KCF/CSRT)
- FFmpeg crop filter with dynamic parameters

**Addresses:**
- FEATURES.md differentiator: speaker reframing (matches OpusClip ReframeAnything)
- Pitfall #11 (Reframing without tracking) — persistent IDs + smoothing prevents jitter

**Research flag:** Needs `/gsd:research-phase` for Falcon SDK integration (C API bindings, licensing for commercial use, fallback when over free tier limit)

### Phase 6: Advanced Features (v2+)
**Rationale:** Defer until core auto-clipping validated and user feedback gathered. High complexity features that aren't essential for competing with cloud tools.

**Delivers:**
- Natural language search (semantic embeddings via CLIP/sentence-transformers)
- Advanced motion analysis (GPU-accelerated optical flow)
- Emotion detection (facial expression or voice tone ML models)
- Custom scoring weight UI/config

**Research flag:** Needs `/gsd:research-phase` for each feature (experimental, sparse documentation for local C++ implementations)

### Phase Ordering Rationale

- **Foundation first:** Build system and FFI patterns are the most common cause of project failure. Must validate cross-platform builds and memory management before adding ML dependencies.
- **Incremental ML complexity:** Start with existing whisper.cpp (Phase 2), add single new analyzer (face detection, Phase 3), then combine into multi-modal scorer (Phase 4). Avoids "big bang" integration failures.
- **Validate each layer independently:** Transcript export (Phase 2) works without face detection. Face detection (Phase 3) works without engagement scoring. Engagement scoring (Phase 4) works without reframing. Each phase delivers user value independently.
- **Defer complex features:** Reframing (Phase 5) requires all previous components plus new dependencies (Falcon SDK, OpenCV tracking). NL search (Phase 6) requires embeddings models and vector search. Save until core validated.
- **Dependency-driven grouping:** Phases 2-4 use existing FFmpeg/whisper.cpp with minimal new dependencies. Phase 5 adds Falcon SDK. Phase 6 adds CLIP/transformers. Minimizes build system churn per phase.

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 1 (Foundation):** Cross-compilation strategy for ONNX Runtime on Windows (MinGW support unclear, may need pre-built binaries)
- **Phase 3 (Face Detection):** Model selection (libfacedetection vs ONNX models) and quantization validation (INT8 accuracy on real videos)
- **Phase 4 (Engagement Scoring):** Scoring algorithm validation without cloud data (how to weight signals, what metrics define "engaging" for screencast/tutorial videos)
- **Phase 5 (Speaker Reframing):** Falcon SDK C API bindings, commercial use licensing, fallback strategy when free tier exceeded (250 min/month)

Phases with standard patterns (skip research-phase):

- **Phase 2 (Transcript & Captions):** Whisper integration exists, FFmpeg subtitle filters well-documented, SRT/VTT formats are standard
- **Phase 6 (Advanced Features):** Defer until needed, research closer to implementation

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | libfacedetection, ONNX Runtime, OpenCV are proven cross-platform. Licenses verified (BSD, MIT, Apache). Only uncertainty: Falcon SDK integration (C API exists but no Nim examples). |
| Features | HIGH | Competitor analysis comprehensive (OpusClip, Kapwing, Reap). Table stakes vs differentiators clearly identified. Anti-features well-documented to prevent scope creep. |
| Architecture | HIGH | Extends existing honeyclip patterns (analyzer modules, boolean arrays, v3 timeline). Integration points well-defined. Two-stage pipeline (rich data → boolean) preserves backward compatibility. |
| Pitfalls | MEDIUM-HIGH | Critical pitfalls identified from ML deployment literature (face detection false positives, FFI memory leaks, binary size, build complexity). Some mitigations untested (multi-frame consensus accuracy, adaptive frame sampling rate). |

**Overall confidence:** MEDIUM-HIGH

Research validates feasibility but highlights execution risks (build system, memory management, performance). Mitigation strategies exist but require validation during implementation.

### Gaps to Address

Areas where research was inconclusive or needs validation during implementation:

- **Engagement scoring ground truth:** No clear methodology for validating engagement scores without cloud platform data. **Handle:** Define metrics based on content features (hooks, pacing, motion), gather user feedback, A/B test with "which clip is better" comparisons.

- **Falcon SDK commercial licensing:** Free tier is 250 min/month (Apache 2.0 license). Unclear if usage limits acceptable for production or if fallback VAD-based segmentation needed. **Handle:** Research during Phase 5 planning, implement fallback strategy (Voice Activity Detection without speaker labels).

- **ONNX model licensing for commercial use:** InsightFace models are "research-permissive" but commercial use unclear. **Handle:** Verify licenses during Phase 3 planning, consider training custom face detection model if needed.

- **Optimal frame sampling rate:** Research suggests 1-5fps for offline analysis but accuracy impact on face detection unknown. **Handle:** Benchmark during Phase 3 with adaptive sampling (scene changes = dense, static = sparse), validate <5% accuracy degradation vs all-frame processing.

- **Windows cross-compile for ONNX Runtime via MinGW:** ONNX Runtime has "limited MinGW support." Auto-editor cross-compiles Windows binaries from Linux via MinGW. Unclear if ONNX Runtime builds work. **Handle:** Test during Phase 1, fallback to pre-built Windows binaries if cross-compile fails, document Windows-specific build process.

## Sources

### Primary (HIGH confidence)

**Stack:**
- [libfacedetection GitHub](https://github.com/ShiqiYu/libfacedetection) — Face detection library, BSD-3 license, cross-platform validation
- [ONNX Runtime GitHub](https://github.com/microsoft/onnxruntime) — Inference engine releases, C++ API documentation
- [Falcon Speaker Diarization GitHub](https://github.com/Picovoice/falcon) — C API, Apache 2.0 license, cross-platform support

**Features:**
- [OpusClip Virality Score](https://help.opus.pro/docs/article/virality-score) — Official documentation of competitor's scoring feature
- [Kapwing AI Features](https://www.kapwing.com/ai/auto-speaker-focus) — Official feature documentation for auto-reframing
- [Top AI Clipping Tools 2026](https://www.reap.video/blog/top-ai-clipping-tools-in-2026) — Comprehensive feature comparison

**Architecture:**
- [FFmpeg Documentation](https://ffmpeg.org/ffmpeg.html) — Filter graph and pipeline design patterns
- [MediaPipe Face Detector](https://developers.google.com/mediapipe/solutions/vision/face_detector) — Official docs confirming C++ deprecation, batch processing modes
- [ONNX Runtime C++ Guide](https://onnxruntime.ai/docs/get-started/with-cpp.html) — Official integration patterns

**Pitfalls:**
- [Nim Memory Model](https://zevv.nl/nim-memory/) — GC behavior and FFI patterns
- [ONNX Runtime Build Docs](https://onnxruntime.ai/docs/build/inferencing.html) — Cross-platform build requirements
- [Face Recognition Challenges 2026](https://research.aimultiple.com/facial-recognition-challenges/) — False positive rates, quality issues

### Secondary (MEDIUM confidence)

**Stack:**
- [UniFace Library](https://yakhyo.github.io/uniface/) — Recent (Nov 2025) open-source face analysis, ONNX-optimized
- [Best Speaker Diarization Models 2026](https://brasstranscripts.com/blog/speaker-diarization-models-comparison) — Validates Falcon claims vs alternatives
- [nimffmpeg GitHub](https://github.com/mashingan/nimffmpeg) — Demonstrates FFmpeg binding pattern for Nim

**Features:**
- [OpusClip Reviews 2026](https://sendshort.ai/guides/opus-review/) — User feedback on feature quality and limitations
- [Advanced Retention Editing](https://air.io/en/youtube-hacks/advanced-retention-editing-cutting-patterns-that-keep-viewers-past-minute-8) — Engagement patterns for video editing

**Pitfalls:**
- [Binary Size: Static vs Dynamic Linking](https://www.sandordargo.com/blog/2024/09/25/dynamic-vs-static-linking-binary-size) — Quantifies size explosion (22KB → 8.7MB for C++ with static linking)
- [Efficient Video Face Recognition](https://pmc.ncbi.nlm.nih.gov/articles/PMC7959602/) — Frame selection strategies
- [Beyond Views: Engagement Prediction](https://arxiv.org/pdf/1709.02541) — Academic research on engagement metrics

### Tertiary (LOW confidence, needs validation)

- [Learner Engagement Analysis](https://arxiv.org/html/2412.00429v1) — Recent (Dec 2024) research on engagement detection, but focused on educational videos (may not generalize)
- [opencv_lite GitHub](https://github.com/zihaomu/opencv_lite) — Bundles compatible ONNX Runtime (v1.14-1.22) but unclear if maintained or production-ready
- [Delving Deep into Engagement Prediction](https://arxiv.org/html/2410.00289v1) — Short-form video engagement, cold start problem validation needed for honeyclip domain

---
*Research completed: 2026-02-01*
*Ready for roadmap: yes*
