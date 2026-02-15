# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-05)

**Project:** honeyclip — Extract the sweetest moments from your video
**Core value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.
**Current focus:** v2.0 Workflow, Performance & AI Features

## Current Position

Phase: 19 - Brand Templates
Plan: 02/03
Status: In Progress
Last activity: 2026-02-15 — Plan 19-02 complete (brand pipeline integration)

Progress v1.0: [████████████████████████████████████████████████] 100%
Progress v1.1: [████████████████████████████████████████████████] 100%
Progress v2.0: [████████████████████                              ] 40% (4/10 phases)
Progress Phase 19: [████████████████████████████████                ] 67% (2/3 plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 72
- Average duration: 3.5 min
- Total execution time: ~4.5 hours

**Milestones:**

| Milestone | Phases | Plans | Duration | Shipped |
|-----------|--------|-------|----------|---------|
| v1.0 Engagement Analysis | 1-10 | 49 | 4 days | 2026-02-04 |
| v1.1 Polish | 11-14 | 10 | 1 day | 2026-02-05 |
| v2.0 Workflow, Performance & AI | 15-24 | 11 | In progress | TBD |
| **Total** | **24** | **70** | **5 days** | — |

**Recent Plans:**

| Phase-Plan | Duration | Tasks | Files | Completed |
|------------|----------|-------|-------|-----------|
| 15-03 | 253s | 1 | 2 | 2026-02-14 |
| 16-01 | 123s | 2 | 6 | 2026-02-14 |
| 16-01 | 123s | 2 | 6 | 2026-02-14 |
| 16-02 | 132s | 2 | 5 | 2026-02-14 |
| 16-03 | 55s | 1 | 1 | 2026-02-14 |
| 16-03 | 55s | 1 | 1 | 2026-02-14 |
| 17-01 | 859s | 2 | 6 | 2026-02-14 |
| 17-02 | 300s | 2 | 5 | 2026-02-14 |
| 17-03 | 584s | 1 | 2 | 2026-02-14 |
| 18-01 | 102s | 2 | 1 | 2026-02-15 |
| 18-02 | 313s | 2 | 2 | 2026-02-15 |
| 18-03 | 736s | 1 | 1 | 2026-02-15 |
| 19-01 | 122s | 2 | 4 | 2026-02-15 |
| 19-02 | 89s | 2 | 2 | 2026-02-15 |

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
- [Phase 17-03]: Export virality calculation procs for unit testing access
- [Phase 17-03]: Use checkApprox helper for float tolerance comparisons
- [Phase 18-01]: Default 30s minimum spacing between chapters for usable navigation
- [Phase 18-01]: Combined mode prefers engagement markers over scene markers during deduplication
- [Phase 18-01]: Chapter titles use engagement labels (High/Medium/Low) for context
- [Phase 18-02]: Auto-set --no-transcript for scene-only mode when no model specified
- [Phase 18-02]: Create dummy timeline with zero segments for scene-only mode
- [Phase 18-02]: Use execCmd for FFmpeg chapter embedding (simpler than libav process)
- [Phase 18-03]: Test fixture pattern with makeTimeline helper for clean test data creation
- [Phase 18-03]: Systematic edge case testing (empty, single, plateau, limits, spacing)
- [Phase 19]: Post-processing approach: Apply brand operations after main honeyclip subprocess completes
- [Phase 19]: Processing order: edit -> watermark -> intro/outro concat

### Pending Todos

None currently. Phase 19 in progress (plan 02/03 complete).

### Blockers/Concerns

None — all tech debt items from v1.0 addressed in v1.1.

**Note:** ML features (face detection) remain stubbed on Windows due to LTO issues with ML libraries. GPU acceleration (Phase 15) will maintain this limitation.

## Session Continuity

Last session: 2026-02-15
Stopped at: Completed 19-02-PLAN.md
Resume file: None
Next: Phase 19 Plan 03

**Project Status: v2.0 IN PROGRESS**

All 38 v2.0 requirements mapped to 10 phases (15-24). Phase 15, 16, 17, and 18 execution complete. Phase 19 in progress.
- Plan 15-01: Complete (GPU Runtime Detection) ✓
- Plan 15-02: Complete (Frame Buffer Pooling) ✓
- Plan 15-03: Complete (GPU Runtime & Buffer Pool Tests) ✓
- Plan 16-01: Complete (Template Parser and Discovery) ✓
- Plan 16-02: Complete (Checkpoint/Resume and Parallel Batch Runner) ✓
- Plan 16-03: Complete (Batch Processing Unit Tests) ✓
- Plan 17-01: Complete (Virality Scoring Core Logic) ✓
- Plan 17-02: Complete (Virality CLI Output and Exports) ✓
- Plan 17-03: Complete (Virality Scoring Unit Tests) ✓
- Plan 18-01: Complete (Chapter Detection Core) ✓
- Plan 18-02: Complete (Chapters CLI Command) ✓
- Plan 18-03: Complete (Chapter Detection Unit Tests) ✓
- Plan 19-01: Complete (Brand Template Core Types) ✓
- Plan 19-02: Complete (Brand Pipeline Integration) ✓

**Phase 16 COMPLETE** - Batch processing foundation fully operational and tested.

**Phase 17 COMPLETE** - Four-component virality scoring (hook, flow, value, trend) with research-backed weights integrated into clip detection and ranking pipeline. Clips ranked by virality score instead of raw engagement. CLI output displays virality scores with component breakdown. JSON/EDL exports include virality fields. Project files store virality scores. Comprehensive unit test coverage (18 tests) for all virality components.

**Phase 18 COMPLETE** - Chapter detection with local maxima peak detection, three-mode generation (scene/engagement/combined), and export to MP4 metadata and NLE markers. CLI integration via `honeyclip chapters` subcommand. Comprehensive unit test coverage (23 tests) for all chapter detection functionality.

**Phase 19 IN PROGRESS** - Brand template system for applying consistent watermarks, intro/outro clips, and caption styles across batch jobs. Plan 01 complete: BrandConfig type system and core brand modules. Plan 02 complete: Brand pipeline integration with FFmpeg post-processing (watermark overlay, intro/outro concat).

---
*Updated: 2026-02-15 after Phase 19 Plan 02 execution*
