---
phase: 04-face-detection-infrastructure
plan: 02
subsystem: video-analysis
tags: [face-detection, ffmpeg, scene-detection, adaptive-sampling, performance-optimization]

# Dependency graph
requires:
  - phase: 04-01
    provides: Face detection types, consensus algorithm, and binary cache
provides:
  - Adaptive frame sampling with 1fps baseline and 5fps spike rates
  - FFmpeg scdet filter integration for scene change detection
  - Face state change detection triggering high-rate sampling
  - Frame selection pipeline avoiding filter graph recreation overhead
affects: [04-03, engagement-scoring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Adaptive sampling with cooldown periods for performance optimization"
    - "FFmpeg filter metadata extraction via avdict_to_dict"
    - "Frame skipping strategy to avoid filter graph recreation"

key-files:
  created: []
  modified:
    - src/analyze/faces.nim

key-decisions:
  - "1fps baseline sampling for static scenes, 5fps during scene changes or face state changes"
  - "Scene change threshold 0.4 (per research on scdet filter)"
  - "1-second cooldown duration after spike events before returning to baseline"
  - "Frame skipping via shouldSampleFrame instead of filter graph recreation"
  - "Metadata extraction from frame.metadata for scene change scores"

patterns-established:
  - "Adaptive sampling pattern: constant maxFps pipeline with selective frame processing"
  - "SceneInfo type for scene change detection metadata"
  - "AdaptiveSampler state machine tracking spikes and cooldowns"

# Metrics
duration: 3min
completed: 2026-02-02
---

# Phase 04 Plan 02: Adaptive Sampling Implementation Summary

**Adaptive frame sampling with FFmpeg scdet filter, 1-5fps dynamic rate based on scene changes and face state**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-02T21:05:03Z
- **Completed:** 2026-02-02T21:08:28Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Adaptive frame sampling reduces CPU usage during static scenes (1fps baseline)
- Scene change detection via FFmpeg scdet filter triggers 5fps sampling spikes
- Face appearance/disappearance events also trigger high-rate sampling
- Efficient implementation avoids filter graph recreation overhead

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement adaptive sampling with scene change detection** - `d3bd5f2` (feat)

## Files Created/Modified
- `src/analyze/faces.nim` - Added SceneInfo, AdaptiveSampler types, facesPipeline iterator with scdet filter integration

## Decisions Made
- 1fps baseline sampling for static content to minimize CPU waste
- 5fps spike sampling triggered by scene changes (threshold 0.4) or face state changes
- 1-second cooldown duration maintains high rate after spike before returning to baseline
- Frame skipping strategy avoids expensive filter graph recreation (run at maxFps, skip frames adaptively)
- Scene scores extracted from frame metadata via `lavfi.scd.score` key

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation followed videoPipeline pattern from motion.nim successfully.

## Next Phase Readiness

Adaptive sampling infrastructure complete. Ready for 04-03 (Face Analyzer Command).

**Key exports for integration:**
- `AdaptiveSampler` - State machine for adaptive rate control
- `SceneInfo` - Scene change metadata type
- `facesPipeline` - Iterator yielding frames at adaptive rates with scene scores
- `newAdaptiveSampler` - Constructor with baseline/max FPS configuration
- `updateSamplingRate` - Sampling rate adjustment based on scene/face state
- `shouldSampleFrame` - Frame selection predicate for efficient skipping

**Performance characteristics:**
- Baseline: 1fps (60-frames/min at 60fps input)
- Spike: 5fps (300 frames/min at 60fps input)
- Cooldown: 1 second maintains high rate after change detection
- No filter graph recreation overhead (constant pipeline, selective processing)

---
*Phase: 04-face-detection-infrastructure*
*Completed: 2026-02-02*
