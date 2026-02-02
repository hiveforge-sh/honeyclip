# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Project:** honeyclip — Extract the sweetest moments from your video
**Core value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.
**Current focus:** Phase 6 - Engagement Clip Detection

## Current Position

Phase: 6 of 10 (Engagement Clip Detection) — In Progress
Plan: 3 of 4 in phase
Status: In progress
Last activity: 2026-02-02 — Completed 06-03-PLAN.md

Progress: [███████████████████████████░░░░░░░░░░░░] 62.5%

## Performance Metrics

**Velocity:**
- Total plans completed: 25
- Average duration: 3.3 min
- Total execution time: 1.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation-build-infrastructure | 5 | 17min | 3.4min |
| 02-transcript-foundation | 4 | 15min | 3.8min |
| 03-caption-rendering | 5 | 19.5min | 3.9min |
| 04-face-detection-infrastructure | 4 | 11.2min | 2.8min |
| 05-engagement-scoring-foundation | 4 | 21min | 5.25min |
| 06-engagement-clip-detection | 3 | 6.75min | 2.25min |

**Recent Trend:**
- Last 5 plans: 05-04 (6min), 06-02 (1.5min), 06-01 (3min), 06-03 (2.25min)
- Trend: Phase 6 maintaining high efficiency with focused modules

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Local signals for engagement (no cloud dependencies, faster processing, works offline)
- SRT output format (standard format, works with all video editors)
- Face detection via ML (motion-only tracking insufficient for speaker centering)
- New subcommand + integration (flexibility for standalone use and pipeline integration)
- Build ML libraries from source for consistent cross-platform support (01-01)
- SHA256-based caching to avoid unnecessary rebuilds (01-01)
- OpenCV minimal build (core+imgproc+objdetect only) to reduce binary size (01-01)
- ONNX Runtime minimal build (extended mode, no ML ops) for size optimization (01-01)
- 50MB soft limit / 100MB hard limit for ML library size validation (01-01)
- Buffer-based API for libfacedetection (CNN weights static, no object state) (01-02)
- ONNX Runtime function table pattern via OrtGetApiBase (01-02)
- OpenCV via importcpp for direct C++ cv::Mat access (01-02)
- result.handle assignment to avoid Nim 2.x implicit destructor conflicts (01-02)
- ONNX Runtime cross-compilation deferred due to Windows SDK requirement (01-03)
- Separate ccache directories prevent false cache hits between targets (01-03)
- Explicit platform checks for CUDA/OpenCL in cross-compilation (01-03)
- Cache ML sources separately from built libraries for faster incremental builds (01-04)
- 50MB soft limit (warning) / 100MB hard limit (fail) for ML library size in CI (01-04)
- Auto-enable ML tests when libfacedetection.a exists (no manual flag) (01-04)
- Rebrand to honeyclip under hiveforge-sh organization (01-05)
- SRT uses comma separator, VTT uses period for timestamp milliseconds (02-01)
- Word-level timestamps via whisper filter format=json with max_len=1 (02-01)
- Speaker -1 = unassigned until diarization, 0+ = identified speakers (02-01)
- Template instead of nested proc to avoid Nim closure memory safety issues (02-02)
- 42-char default caption limit (standard readable line length) (02-02)
- Prefer sentence boundaries when within 20% of char limit (02-02)
- Never break before small words (a, the, to, of, etc.) (02-02)
- Speaker labels only on speaker change to reduce visual clutter (02-02)
- UTF-8 output without BOM for maximum player compatibility (02-02)
- Prompt for model download if missing (user-friendly) (02-04)
- Output all three formats by default (SRT, VTT, JSON) (02-04)
- Backup files use .bak extension (overwrite existing backup) (02-04)
- ASS subtitle format for caption rendering (supports advanced styling and karaoke tags) (03-01)
- 5-color speaker palette (cyan, red/pink, green, yellow, purple) (03-01)
- Traditional and Modern/TikTok caption style presets (03-01)
- FFmpeg ass filter for subtitle rendering (supports advanced styling and karaoke) (03-02)
- Temporary ASS file generation with cleanup pattern (03-02)
- Windows colon escaping (C: -> C\:) for FFmpeg filter paths (03-02)
- Exported filter builder functions for testing and reuse (03-02)
- FCP7 captions as text generator clips (editable in Premiere/Resolve) (03-03)
- FCPXML captions as title clips in gap element (non-destructive overlay) (03-03)
- Frame-based timing for NLE exports (frame-accurate positioning) (03-03)
- Speaker colors via effect parameters (visual differentiation in NLE) (03-03)
- CLI subcommands (burn, export) for different caption workflows (03-04)
- Style presets with CLI override flags for flexible customization (03-04)
- JSON transcript input (requires prior transcript extraction) (03-04)
- Exported parseCaptionStyle and loadTranscriptFromJSON for testability (03-04)
- Minimal XML structure for caption-only NLE exports (no audio tracks) (03-05)
- Video clip reference included in caption exports for NLE timeline context (03-05)
- Support stdout output with "-" path for piping (03-05)
- Multi-frame consensus with 3-frame window and 0.6 threshold for stability (04-01)
- IoU > 0.5 threshold for matching faces across frames (04-01)
- Default confidence filter 0.3 (higher than libfacedetection 0.02 default) (04-01)
- Cache location .honeyclip/ alongside video (not getTempDir) for persistence (04-01)
- 20 face cache file limit per directory (vs 10 for motion cache) (04-01)
- 1fps baseline sampling for static scenes, 5fps during scene changes or face state changes (04-02)
- Scene change threshold 0.4 via FFmpeg scdet filter (04-02)
- 1-second cooldown duration after spike events before returning to baseline (04-02)
- Frame skipping strategy avoids filter graph recreation overhead (04-02)
- All analysis parameters in cache key for proper invalidation (04-03)
- Conversion helpers in faces.nim to avoid circular dependency (04-03)
- Default FaceAnalysisParams: minConfidence 0.3, consensus 3@0.6, minFaceRatio 0.05, baseFps 1.0, maxFps 5.0, sceneThreshold 0.4 (04-03)
- --clear-faces flag operates on .honeyclip/ in current directory (04-04)
- --info flag shows both system and face caches (04-04)
- Face detection tests conditional on enable_ml to support incremental ML builds (04-04)
- Equal weights (33.3% each) for audio, motion, speech signals in engagement scoring (05-01)
- Percentile normalization (5th-95th) over min-max for outlier robustness (05-01)
- Dual scoring: relative (normalized to video) and absolute (fixed thresholds) (05-01)
- Hook boost default 15.0 points, face boost 5.0 per face (max 10.0 total) (05-01)
- Minimum segment duration 2000ms, merge threshold 10.0 points (05-01)
- Signal alignment via timebase conversion for precise timestamp mapping (05-03)
- Speech scoring: 120-180 wpm optimal, 60% rate + 40% confidence weighting (05-03)
- Face boost capped at +10 points (2 faces max contribution) (05-03)
- Adjacent segment merging via weighted average by duration (05-03)
- Non-speech segments (gaps > 2s) scored with audio+motion only (05-03)
- JSON engagement output includes both relative and absolute scores for flexibility (05-04)
- Summary mode shows top 5 segments and score distribution histogram (05-04)
- Timebase extracted from video stream (or audio if no video) for analyzeEngagement (05-04)
- EDLClip DTO for decoupled export (CLI converts Clip->EDLClip, export module stays simple) (06-02)
- Both EDL and JSON formats in same module (share EDLClip type, minimize duplication) (06-02)
- 30fps default for SMPTE timecode (maximum NLE compatibility, NTSC industry standard) (06-02)
- Reel names 8 char max, uppercase, alphanumeric (CMX3600 standard SMPTE 258M) (06-02)
- FFmpeg scdet filter with 0.4 threshold for scene change detection (06-01)
- EDLClip DTO for decoupled export (CLI converts Clip->EDLClip, export module stays simple) (06-02)
- Both EDL and JSON formats in same module (share EDLClip type, minimize duplication) (06-02)
- 30fps default for SMPTE timecode (maximum NLE compatibility, NTSC industry standard) (06-02)
- Reel names 8 char max, uppercase, alphanumeric (CMX3600 standard SMPTE 258M) (06-02)
- 2-second merge window for nearby boundaries to reduce fragmentation (06-01)
- Boundaries extend to sentence ends to avoid mid-sentence cuts (06-01)
- Clip duration targets: 15-60 seconds (30s optimal) for social media (06-01)
- Multi-signal boundary detection: scene changes + engagement drops + speech alignment (06-01)
- IoU threshold 0.3 triggers overlap penalty (30.0 points per overlap) (06-03)
- Top 5 clips by default with hook boost (+5.0 points) (06-03)
- Prefer longer clips when overlapping (extra 5.0 point penalty for shorter) (06-03)
- Parallel export with 4 concurrent FFmpeg processes by default (06-03)
- Frame-accurate clip extraction with libx264 re-encoding (06-03)
- Output directory defaults to subfolder next to source video (06-03)
- Timestamp-based filename format: video_00m30s-01m15s.mp4 (06-03)

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 1 (Foundation):**
- Cross-platform build complexity for ONNX Runtime and OpenCV (especially Windows cross-compile via MinGW) - PARTIALLY RESOLVED: Windows cross-compile works for libfacedetection and OpenCV (01-03), ONNX Runtime needs Windows SDK headers
- Binary size explosion risk (10MB → 100MB+ with ML libraries) - ACTIVE: Current ML libs total 114MB, exceeds 100MB hard limit
- Nim/C++ FFI memory management patterns must be established before adding multiple ML dependencies - RESOLVED: Patterns established in 01-02 (=destroy hooks, defer cleanup)
- ONNX Runtime build complexity may cause issues on different systems - RESOLVED: Eigen hash issue fixed in 01-05
- First ML library build takes 1-2 hours - DOCUMENTED: Users need to be aware

**Phase 2 (Transcript):**
- Unit tests require FFmpeg build (nimble makeff) to execute - currently only syntax-checked
- RESOLVED: All transcript components implemented and integrated

**Phase 4 (Face Detection):**
- PHASE COMPLETE: All deliverables implemented
- Face detection false positive rate - RESOLVED: Multi-frame consensus algorithm (04-01)
- Adaptive frame sampling - RESOLVED: 1-5fps dynamic rate based on scene changes (04-02)
- faces() API ready with caching, CLI tools, and comprehensive unit tests (04-01 through 04-04)

**Phase 5 (Engagement Scoring):**
- PHASE COMPLETE: All deliverables implemented
- No ground truth data for validating engagement scores - validation will require real-world video testing
- Scoring algorithm based on content features (audio, motion, speech, faces, hooks)

**Phase 7 (Speaker Reframing):**
- Falcon SDK integration (C API, commercial licensing unclear for free tier 250 min/month)
- Fallback strategy needed when free tier exceeded

## Session Continuity

Last session: 2026-02-02T20:09:23Z
Stopped at: Completed 06-03-PLAN.md
Resume file: None
Next: Continue Phase 6 - Plan 04 (CLI Integration)
