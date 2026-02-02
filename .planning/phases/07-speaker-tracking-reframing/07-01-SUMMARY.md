---
phase: 07-speaker-tracking-reframing
plan: 01
subsystem: tracking
tags: [kalman-filter, face-tracking, tracking-types, deepsort, motion-prediction]

# Dependency graph
requires:
  - phase: 04-face-detection-infrastructure
    provides: FaceRect type from libfacedetection
provides:
  - Track object for persistent face identity across frames
  - TrackedFace extending FaceDetection with tracking context
  - TrackingState for managing active tracks
  - KalmanFilter for motion prediction during occlusion
  - EasingPreset enum for reframing transition speeds
  - CropRegion for reframing output
affects: [07-02-face-embedding, 07-03-tracker-core, 07-04-reframe-animation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DeepSORT-style tracking with identity persistence"
    - "Simplified Kalman filter with diagonal covariance"
    - "Constant velocity model for face motion prediction"

key-files:
  created:
    - src/tracking/types.nim
    - src/tracking/kalman.nim
  modified:
    - tests/unit.nim

key-decisions:
  - "Simplified Kalman filter with diagonal covariance for efficiency (full matrix operations not required per research)"
  - "Constant velocity model for face tracking (adequate for typical video frame rates)"
  - "Track age and hit streak determine stability (maxAge 90 frames = 3s @ 30fps, minHits 3)"
  - "Predicted bboxes have confidence 0.5 to distinguish from actual detections"

patterns-established:
  - "Track object combines identity (id), appearance (embedding), motion (Kalman filter state), and temporal metrics (age, hitStreak, timeSinceUpdate)"
  - "TrackedFace extends FaceDetection pattern from faces.nim with tracking context"
  - "Kalman filter predict-update cycle: predict increases uncertainty, update reduces it"

# Metrics
duration: 3min
completed: 2026-02-02
---

# Phase 7 Plan 1: Tracking Types and Kalman Filter Summary

**DeepSORT-style tracking types with simplified Kalman filter for face motion prediction during occlusion**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-02T20:20:18Z
- **Completed:** 2026-02-02T20:23:12Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Track type with persistent identity, appearance embedding, and temporal state
- TrackedFace extending FaceDetection with track ID and embedding fields
- TrackingState managing active tracks with configurable maxAge and minHits
- Simplified Kalman filter with diagonal covariance for computational efficiency
- Predict-update cycle for motion prediction during temporary occlusion
- Unit tests validating Kalman filter predict increases uncertainty, update reduces it

## Task Commits

Each task was committed atomically:

1. **Task 1: Create tracking types module** - `71c5f51` (feat)
2. **Task 2: Implement Kalman filter for motion prediction** - `1357ae5` (feat)

## Files Created/Modified
- `src/tracking/types.nim` - Track, TrackedFace, TrackingState, EasingPreset, CropRegion types
- `src/tracking/kalman.nim` - Kalman filter with predict/update cycle for motion prediction
- `tests/unit.nim` - Unit tests for Kalman filter predict-update cycle and velocity tracking

## Decisions Made
- Simplified Kalman filter with diagonal covariance instead of full matrix operations (sufficient for face tracking per RESEARCH.md, reduces computational overhead)
- Constant velocity model for motion prediction (adequate for typical video frame rates)
- Default maxAge 90 frames (3 seconds at 30fps) before track deletion, minHits 3 for track confirmation (standard DeepSORT parameters)
- Predicted bboxes assigned confidence 0.5 to distinguish from actual detections (0.9 typical)
- Track holds both FaceRect (current bbox) and embedding (512-dim ArcFace for re-identification)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - both modules compiled successfully on first attempt.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Track types ready for Plan 02 (face embedding extraction)
- Kalman filter ready for Plan 03 (tracker core implementation)
- TrackingState provides global tracker state management
- EasingPreset enum ready for Plan 04 (reframing animation)
- CropRegion type ready for Plan 05 (reframe output)
- Unit tests validate Kalman filter predict-update cycle
- All types compile and export correctly

---
*Phase: 07-speaker-tracking-reframing*
*Completed: 2026-02-02*
