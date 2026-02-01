# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Core value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.
**Current focus:** Phase 1 - Foundation & Build Infrastructure

## Current Position

Phase: 1 of 10 (Foundation & Build Infrastructure)
Plan: 04 of 4 in phase
Status: In progress
Last activity: 2026-02-01 — Completed 01-04-PLAN.md (CI/Testing Integration)

Progress: [████░░░░░░] 40%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 4 min
- Total execution time: 0.22 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation-build-infrastructure | 3 | 13min | 4min |

**Recent Trend:**
- Last 5 plans: 01-01 (5min), 01-02 (5min), 01-04 (3min)
- Trend: Improving velocity (getting faster)

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
- Cache ML sources separately from built libraries for faster incremental builds (01-04)
- 50MB soft limit (warning) / 100MB hard limit (fail) for ML library size in CI (01-04)
- Auto-enable ML tests when libfacedetection.a exists (no manual flag) (01-04)

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 1 (Foundation):**
- Cross-platform build complexity for ONNX Runtime and OpenCV (especially Windows cross-compile via MinGW) - ACTIVE: Windows not yet supported for ML libs
- Binary size explosion risk (10MB → 100MB+ with ML libraries) - MITIGATED: 50MB/100MB limits in place, minimal builds configured
- Nim/C++ FFI memory management patterns must be established before adding multiple ML dependencies - RESOLVED: Patterns established in 01-02 (=destroy hooks, defer cleanup)
- ONNX Runtime build complexity may cause issues on different systems - ACTIVE: build.sh integration untested
- First ML library build takes 1-2 hours - DOCUMENTED: Users need to be aware

**Phase 2 (Transcript):**
- Whisper.cpp currently used for speech detection, not full transcript extraction — need to extend output format

**Phase 4 (Face Detection):**
- Face detection false positive rate can reach 85% in production (Metropolitan Police finding)
- Multi-frame consensus and adaptive frame sampling critical to avoid CPU waste and accuracy issues

**Phase 5 (Engagement Scoring):**
- No ground truth data for validating engagement scores without cloud platform metrics
- Must define scoring algorithm based on content features, not historical performance data

**Phase 7 (Speaker Reframing):**
- Falcon SDK integration (C API, commercial licensing unclear for free tier 250 min/month)
- Fallback strategy needed when free tier exceeded

## Session Continuity

Last session: 2026-02-01 23:56:48Z
Stopped at: Completed 01-04-PLAN.md - CI/Testing Integration
Resume file: None
Next: Execute 01-03-PLAN.md or continue to next phase
