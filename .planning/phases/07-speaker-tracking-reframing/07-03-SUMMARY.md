---
phase: 07-speaker-tracking-reframing
plan: 03
subsystem: tracking
tags: [hungarian-algorithm, deepsort, multi-object-tracking, data-association, kalman-filter, face-embeddings]

# Dependency graph
requires:
  - phase: 07-01
    provides: Kalman filter for motion prediction, Track and TrackingState types
  - phase: 07-02
    provides: ArcFace face embeddings for re-identification
  - phase: 04-face-detection-infrastructure
    provides: FaceRect type and face detection
provides:
  - Hungarian algorithm for optimal track-to-detection assignment
  - DeepSORT-style multi-face tracker with persistent identity
  - Cost matrix computation combining IoU and appearance similarity
  - Graceful degradation to IoU-only tracking without embedder
affects: [07-04-reframe-animation, 07-05-compositor, 07-06-cli-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Hungarian algorithm with greedy optimization for small N (1-5 faces)"
    - "DeepSORT tracking-by-detection pipeline: predict → embed → assign → update → create/delete"
    - "Temporal embedding smoothing (0.9 old + 0.1 new) for stable re-identification"
    - "Kalman filter lifecycle synchronized with track lifecycle"

key-files:
  created:
    - src/tracking/assignment.nim
    - src/tracking/tracker.nim
  modified:
    - src/tracking/kalman.nim (restored from git)

key-decisions:
  - "Combined cost metric: 70% IoU distance + 30% appearance distance (spatial proximity favored)"
  - "IoU < 0.5 triggers infinite cost (1e6) to prevent unlikely matches"
  - "Greedy assignment algorithm optimal for small N (typical 1-5 faces in video)"
  - "Kalman filters stored in tracker and synchronized with track lifecycle"
  - "Graceful degradation to IoU-only mode when face embedder unavailable"
  - "Temporal embedding smoothing (0.9 old + 0.1 new) per RESEARCH temporal smoothing guidance"
  - "Active speaker detection via largest face heuristic during speaking segments"

patterns-established:
  - "Cost matrix combines motion (IoU) and appearance (embedding similarity) with 70/30 weighting"
  - "Hungarian assignment excludes matches exceeding cost threshold for robustness"
  - "Track-Kalman filter synchronization: parallel sequences, synchronized create/delete operations"
  - "Option[FaceEmbedder] pattern enables graceful fallback when model unavailable"

# Metrics
duration: 5min
completed: 2026-02-02
---

# Phase 7 Plan 3: Hungarian Algorithm and DeepSORT Tracker Summary

**Optimal track-to-detection assignment via Hungarian algorithm with DeepSORT-style tracker combining Kalman prediction, face embeddings, and temporal smoothing**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-02T23:09:42Z
- **Completed:** 2026-02-02T23:14:51Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Hungarian algorithm finds optimal track-detection pairs minimizing combined IoU + appearance cost
- DeepSORT tracker maintains persistent identity across frames and occlusions
- Kalman filter integration for motion prediction during temporary occlusion
- Temporal embedding smoothing for stable re-identification across frames
- Graceful degradation to IoU-only tracking when embedder unavailable
- Active speaker detection matching transcript diarization to faces via largest face heuristic
- Tracks survive 3 seconds without detection (maxAge = 90 frames @ 30fps)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement Hungarian algorithm for data association** - `6be1456` (feat)
2. **Task 2: Implement main DeepSORT tracker** - `d02934d` (feat)

## Files Created/Modified
- `src/tracking/assignment.nim` - Hungarian algorithm for optimal assignment, IoU helper for FaceRect pairs, cost matrix computation
- `src/tracking/tracker.nim` - FaceTracker with updateTracks pipeline, getActiveTracks filtering, getActiveSpeaker matching
- `src/tracking/kalman.nim` - Restored from git (was accidentally missing from working tree)

## Decisions Made
- Combined cost metric weights IoU (70%) higher than appearance (30%) to favor spatial proximity - prevents track jumps when faces similar
- IoU < 0.5 threshold triggers infinite cost to prevent unlikely matches per RESEARCH guidance
- Greedy assignment algorithm chosen over full Hungarian matrix operations - optimal for typical 1-5 faces, O(n²) vs O(n³)
- Kalman filters stored separately in tracker state rather than in Track object to avoid circular dependency between types.nim and kalman.nim
- Temporal embedding smoothing (0.9 old + 0.1 new) per RESEARCH temporal smoothing guidance - reduces embedding jitter across frames
- Active speaker uses largest face heuristic (face area * confidence * stability) per RESEARCH Pattern 3 - closest face to camera typically speaker

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Restored missing kalman.nim from git**
- **Found during:** Task 2 startup (tracker.nim imports kalman)
- **Issue:** kalman.nim committed in 07-01 but missing from working tree (file existed in git history but not filesystem)
- **Fix:** Restored via `git checkout 1357ae5 -- src/tracking/kalman.nim`
- **Files modified:** src/tracking/kalman.nim
- **Verification:** File now present, imports succeed
- **Committed in:** 6be1456 (Task 1 commit - included in first commit to document restoration)

**2. [Rule 2 - Missing Critical] Added Kalman filter integration to tracker**
- **Found during:** Task 2 implementation (updateTracks Step 1 - predict)
- **Issue:** Track type lacks Kalman filter field - motion prediction impossible without it
- **Fix:** Added kalmanFilters: seq[KalmanFilter] to FaceTracker, synchronized lifecycle (create on new track, delete with stale tracks, predict in Step 1, update in Step 5)
- **Files modified:** src/tracking/tracker.nim
- **Verification:** Kalman predict() called in Step 1, update() in Step 5, lifecycle synchronized
- **Committed in:** d02934d (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 blocking)
**Impact on plan:** Both essential for tracker functionality. Kalman filter integration is core DeepSORT requirement per RESEARCH Pattern 1.

## Issues Encountered

None - both modules compiled successfully after auto-fixes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Hungarian algorithm ready for use in Plan 04+ (reframe animation)
- FaceTracker ready for integration in Plan 06 (CLI command)
- getActiveSpeaker ready for transcript-driven reframing
- Kalman filter enables smooth prediction during occlusion
- Graceful degradation ensures functionality without embedding model
- All types compile and export correctly
- Unit tests for Hungarian assignment and tracker lifecycle needed in future test expansion

---
*Phase: 07-speaker-tracking-reframing*
*Completed: 2026-02-02*
