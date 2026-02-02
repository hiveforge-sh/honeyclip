# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Project:** honeyclip — Extract the sweetest moments from your video
**Core value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.
**Current focus:** Phase 4 - Face Detection Infrastructure

## Current Position

Phase: 4 of 10 (Face Detection Infrastructure) — In Progress
Plan: 1 of 3 in phase
Status: In Progress
Last activity: 2026-02-02 — Completed 04-01-PLAN.md

Progress: [████████████████░░░░░░░░░░░░░░░░░░░░░░░░] 41%

## Performance Metrics

**Velocity:**
- Total plans completed: 14
- Average duration: 3.6 min
- Total execution time: 0.85 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation-build-infrastructure | 4 | 17min | 4.3min |
| 02-transcript-foundation | 4 | 15min | 3.8min |
| 03-caption-rendering | 5 | 19.5min | 3.9min |
| 04-face-detection-infrastructure | 1 | 2.5min | 2.5min |

**Recent Trend:**
- Last 5 plans: 03-03 (4min), 03-04 (5min), 03-05 (4min), 04-01 (2.5min)
- Trend: Fast completion for infrastructure tasks

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
- Face detection false positive rate can reach 85% in production (Metropolitan Police finding) - ADDRESSED: Multi-frame consensus algorithm implemented (04-01)
- Adaptive frame sampling needed to avoid CPU waste - PENDING: Will be addressed in 04-02

**Phase 5 (Engagement Scoring):**
- No ground truth data for validating engagement scores without cloud platform metrics
- Must define scoring algorithm based on content features, not historical performance data

**Phase 7 (Speaker Reframing):**
- Falcon SDK integration (C API, commercial licensing unclear for free tier 250 min/month)
- Fallback strategy needed when free tier exceeded

## Session Continuity

Last session: 2026-02-02
Stopped at: Completed 04-01-PLAN.md
Resume file: None
Next: Execute 04-02-PLAN.md (Face Analyzer Implementation)
