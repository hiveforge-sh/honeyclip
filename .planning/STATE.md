# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Project:** honeyclip — Extract the sweetest moments from your video
**Core value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.
**Current focus:** v2.0 Workflow, Performance & AI Features

## Current Position

Phase: 17 - Virality Scoring
Plan: 01/03
Status: In Progress
Last activity: 2026-02-14 — Plan 17-01 complete (virality scoring core logic)

Progress v1.0: [████████████████████████████████████████████████] 100%
Progress v1.1: [████████████████████████████████████████████████] 100%
Progress v2.0: [████████████                                    ] 24% (2.33/10 phases)
Progress Phase 17: [████████████████                                ] 33% (1/3 plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 66
- Average duration: 3.3 min
- Total execution time: ~4.2 hours

**Milestones:**

| Milestone | Phases | Plans | Duration | Shipped |
|-----------|--------|-------|----------|---------|
| v1.0 Engagement Analysis | 1-10 | 49 | 4 days | 2026-02-04 |
| v1.1 Polish | 11-14 | 10 | 1 day | 2026-02-05 |
| v2.0 Workflow, Performance & AI | 15-24 | 7 | In progress | TBD |
| **Total** | **24** | **65** | **5 days** | — |

**Recent Plans:**

| Phase-Plan | Duration | Tasks | Files | Completed |
|------------|----------|-------|-------|-----------|
| 15-02 | 108s | 2 | 2 | 2026-02-13 |
| 15-03 | 253s | 1 | 2 | 2026-02-14 |
| 16-01 | 123s | 2 | 6 | 2026-02-14 |
| 16-01 | 123s | 2 | 6 | 2026-02-14 |
| 16-02 | 132s | 2 | 5 | 2026-02-14 |
| 16-03 | 55s | 1 | 1 | 2026-02-14 |
| 17-01 | 859s | 2 | 6 | 2026-02-14 |

## Accumulated Context

### Decisions

All decisions logged in PROJECT.md Key Decisions table.
Major architectural decisions across milestones:

**v1.0:**
- Local signals for engagement (no cloud dependencies)
- SRT output format (standard, editor compatible)
- Face detection via ML (libfacedetection, OpenCV, ONNX)
- Kalman + Hungarian tracking (DeepSORT-style without neural overhead)
- ASS subtitle format (advanced styling)

**v1.1:**
- MinSizeRel for ML libraries (size optimization)
- JSON schema for custom hooks (user extensibility)
- Per-module coverage threshold (test quality)
- FFmetadata format (FFmpeg native metadata)

**v2.0:**
- TOML templates for batch processing (16-01: template-based configuration with type-safe field mapping)
- GPU acceleration via CUDA/Metal (emerging decision)
- Local-first AI with API fallback (emerging decision)
- Runtime GPU detection with CPU fallback (15-01: file existence check for CUDA, platform-aware detection)
- Execution provider support for ONNX Runtime (15-01: backend parameter, graceful fallback)
- Backend parameter as string vs enum (15-01: string for simplicity, no module dependency)
- Frame buffer pooling for memory efficiency (15-02: pre-allocated buffers, acquire/release semantics)
- Bounded decode queue for OOM prevention (15-02: maxQueueFrames parameter)
- Template to CLI args conversion (16-01: defer validation to existing CLI parsing, avoid duplication)
- [Phase 15]: Added info() logging proc to log.nim for consistency with debug/warning/error pattern
- [Phase 16]: Subprocess-based parallel execution for process isolation
- [Phase 16]: Chunk-based checkpoint saves for resume granularity
- [Phase 17]: Four-component virality model (hook, flow, value, trend) with research-backed weights

### Pending Todos

None currently. Plan 17-01 complete. Ready for Plan 17-02.

### Blockers/Concerns

None — all tech debt items from v1.0 addressed in v1.1.

**Note:** ML features (face detection) remain stubbed on Windows due to LTO issues with ML libraries. GPU acceleration (Phase 15) will maintain this limitation.

## Session Continuity

Last session: 2026-02-14
Stopped at: Completed 17-01-PLAN.md
Resume file: None
Next: Plan 17-02 (Virality CLI Output)

**Project Status: v2.0 IN PROGRESS**

All 38 v2.0 requirements mapped to 10 phases (15-24). Phase 15 and Phase 16 execution complete. Phase 17 in progress.
- Plan 15-01: Complete (GPU Runtime Detection) ✓
- Plan 15-02: Complete (Frame Buffer Pooling) ✓
- Plan 15-03: Complete (GPU Runtime & Buffer Pool Tests) ✓
- Plan 16-01: Complete (Template Parser and Discovery) ✓
- Plan 16-02: Complete (Checkpoint/Resume and Parallel Batch Runner) ✓
- Plan 16-03: Complete (Batch Processing Unit Tests) ✓
- Plan 17-01: Complete (Virality Scoring Core Logic) ✓

**Phase 16 COMPLETE** - Batch processing foundation fully operational and tested.

**Phase 17 IN PROGRESS** - Plan 17-01 complete. Four-component virality scoring (hook, flow, value, trend) with research-backed weights integrated into clip detection and ranking pipeline. Clips now ranked by virality score instead of raw engagement score.

---
*Updated: 2026-02-14 after Plan 17-01 execution*
