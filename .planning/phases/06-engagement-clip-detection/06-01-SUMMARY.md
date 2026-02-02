---
phase: 06-engagement-clip-detection
plan: 01
subsystem: video-analysis
tags: [nim, ffmpeg, scdet, engagement, clip-detection]

# Dependency graph
requires:
  - phase: 05-engagement-scoring
    provides: EngagementTimeline with scored segments
provides:
  - Clip boundary detection combining scene changes, engagement drops, and speech alignment
  - Multi-signal approach for natural clip segmentation (15-60 second target)
  - FFmpeg scdet filter integration for scene change detection
  - Sentence boundary alignment to prevent mid-sentence cuts
affects: [06-02-clip-ranking, 06-03-batch-export, 06-04-clip-metadata]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Multi-signal boundary detection (scene changes + engagement drops + speech alignment)
    - FFmpeg scdet filter for scene change timestamps
    - Sentence boundary alignment via engagement segments

key-files:
  created:
    - src/analyze/clips.nim
  modified: []

key-decisions:
  - "Use FFmpeg scdet filter with 0.4 threshold for scene change detection"
  - "Merge nearby boundaries within 2-second window to reduce fragmentation"
  - "Extend boundaries to sentence ends to avoid mid-sentence cuts"
  - "Target 15-60 second clips (30s optimal) for social media"

patterns-established:
  - "Multi-signal boundary detection: Scene changes (primary) → engagement drops (secondary) → speech alignment (refinement)"
  - "Percentile-based normalization from Phase 5 used for engagement scores"
  - "Clip metadata includes all sub-scores (audio, motion, speech) plus hooks and face counts"

# Metrics
duration: 3min
completed: 2026-02-02
---

# Phase 6 Plan 1: Clip Boundary Detection Summary

**Multi-signal clip boundary detection using FFmpeg scdet for scene changes, engagement drop thresholds, and sentence alignment to produce 15-60 second natural clips**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-02T16:26:56Z
- **Completed:** 2026-02-02T16:29:53Z
- **Tasks:** 2 (implemented as single atomic module)
- **Files modified:** 1

## Accomplishments
- Created clips.nim module with Clip, ClipBoundary, BoundaryReason types and all detection functions
- Implemented scene change extraction via FFmpeg scdet filter (threshold 0.4)
- Multi-signal boundary detection combining visual cuts, engagement drops, and speech alignment
- Sentence boundary alignment prevents mid-sentence cuts per CONTEXT.md requirements
- Duration constraints (15-60s with 30s target) and intro/outro skip parameters

## Task Commits

Each task was committed atomically:

1. **Task 1 & 2: Create clip types and boundary detection module** - `3571fe9` (feat)

_Note: Task 2 requirements (sentence boundary alignment) were implemented as part of Task 1's detectBoundaries function, so both tasks are in a single commit._

## Files Created/Modified
- `src/analyze/clips.nim` - Clip boundary detection combining scene changes, engagement drops, and speech alignment

## Decisions Made

**1. Scene change detection threshold**
- Selected 0.4 as default threshold based on RESEARCH.md recommendation
- Balance between sensitivity (catching cuts) and noise (camera shake, lighting changes)
- Made configurable for different video types (handheld vs studio)

**2. Boundary merge window**
- 2-second window to merge nearby boundaries from different signals
- Prevents fragmentation from multiple triggers in same moment
- Prioritizes SceneChange > EngagementDrop > SpeechBoundary when merging

**3. Sentence alignment implementation**
- Boundaries within speech segments extend to segment.endMs
- Uses engagement timeline segment boundaries as sentence boundaries
- 2-second search window for finding nearest sentence end
- Aligns with CONTEXT.md: "avoid cutting mid-sentence; extend or trim slightly to complete thoughts"

**4. Clip score calculation**
- Weighted average of segment scores within clip time range
- Includes all sub-scores (audio, motion, speech) for later analysis
- Preserves hasHook flag and max face count for ranking

## Deviations from Plan

None - plan executed exactly as written. Task 2's sentence alignment functionality was naturally integrated into Task 1's detectBoundaries implementation.

## Issues Encountered

**1. FFmpeg process handling**
- **Issue:** Initial implementation used `startProcess` with stream reading, which had type errors
- **Resolution:** Switched to `execProcess` with {poStdErrToStdOut, poUsePath} options (pattern from main.nim)
- **Verification:** `nim check` passes without errors

**2. Build environment missing FFmpeg headers**
- **Issue:** Full `nimble make` failed with "libavutil/rational.h: No such file or directory"
- **Resolution:** This is pre-existing build environment issue unrelated to new code. Used `nim check` for syntax/type verification instead
- **Impact:** clips.nim module verified via `nim check` - compiles successfully

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for Phase 6 Plan 2 (Clip Ranking):**
- Clip type includes engagementScore and adjustedScore fields for ranking
- All segment metadata (hooks, faces, sub-scores) preserved for ranking algorithm
- detectClips returns seq[Clip] ready for overlap penalty and ranking

**Ready for Phase 6 Plan 3 (Batch Export):**
- Clip boundaries include startMs/endMs timestamps for FFmpeg extraction
- Text field preserves transcript for metadata export

**Blockers:**
None. All interfaces match RESEARCH.md patterns.

**Concerns:**
- Scene change detection via execProcess() runs synchronously - may be slow for long videos
- Consider caching scene change timestamps alongside face cache for performance

---
*Phase: 06-engagement-clip-detection*
*Plan: 01*
*Completed: 2026-02-02*
