---
phase: 13-tracker-test-coverage
plan: 01
subsystem: testing
tags: [kalman, hungarian, iou, unit-tests, fixtures]

dependency-graph:
  requires: []
  provides:
    - "Test fixture utilities (checkApprox, checkBboxApprox)"
    - "Synthetic face data generators"
    - "Kalman filter unit tests"
    - "Assignment algorithm unit tests"
  affects:
    - "13-02 (tracker integration tests)"
    - "13-03 (test coverage reporting)"

tech-stack:
  added: []
  patterns:
    - "Include fixtures for test utilities"
    - "Tolerance-based float assertions with checkApprox"
    - "Seeded RNG for deterministic test data"

file-tracking:
  key-files:
    created:
      - tests/fixtures/test_utils.nim
      - tests/fixtures/synthetic_faces.nim
    modified:
      - tests/unit.nim
      - .gitignore

decisions:
  - id: "gitignore-fixtures"
    choice: "Add !tests/fixtures/*.nim to .gitignore"
    reason: "tests/* was gitignored, fixtures directory needed exception"

metrics:
  duration: "6min"
  completed: "2026-02-05"
---

# Phase 13 Plan 01: Kalman and Assignment Unit Tests Summary

**One-liner:** Tolerance-based unit tests for Kalman filter predict/update and Hungarian assignment algorithm with synthetic face generators.

## What Was Built

### Test Fixture Utilities

**tests/fixtures/test_utils.nim:**
- `checkApprox(a, b, epsilon)` - Float comparison with tolerance
- `checkBboxApprox(a, b, epsilon)` - FaceRect comparison with pixel tolerance
- `checkCovariancePositive(cov)` - Verify covariance diagonal > 0

**tests/fixtures/synthetic_faces.nim:**
- `generateStraightLineFace()` - Face moving in straight line
- `generateCrossingPaths()` - Two faces crossing paths
- `generateOcclusionScenario()` - Face with temporary occlusion
- `generateNoisyPath()` - Face with Gaussian noise on position

### Kalman Filter Tests (14 total)

Pre-existing tests:
1. newKalmanFilter initializes state
2. newKalmanFilter sets noise parameters
3. predict applies velocity
4. predict increases uncertainty
5. update reduces uncertainty
6. update moves state toward detection
7. getBbox returns current state

New tests added:
8. kalman-predict-zero-velocity
9. kalman-update-calculates-velocity
10. kalman-covariance-diagonal-initialized
11. kalman-covariance-stays-positive
12. kalman-multi-frame-tracking
13. kalman-handles-noisy-input

### Assignment Algorithm Tests (19 total)

Pre-existing tests:
1. iou no overlap
2. iou full overlap
3. iou partial overlap
4. iou edge touching
5. hungarianAssignment empty matrix
6. hungarianAssignment single element
7. hungarianAssignment respects threshold
8. hungarianAssignment optimal assignment

New tests added:
9. iou-one-inside-other
10. iou-symmetric
11. costMatrix-empty-tracks
12. costMatrix-empty-detections
13. costMatrix-sets-infinite-for-low-iou
14. costMatrix-calculates-valid-cost
15. hungarian-two-tracks-two-detections
16. hungarian-unbalanced-more-tracks
17. hungarian-unbalanced-more-detections
18. hungarian-all-high-cost
19. costMatrix-with-embeddings

## Verification Results

```
[Suite] Kalman Filter
  [OK] newKalmanFilter initializes state
  [OK] newKalmanFilter sets noise parameters
  [OK] predict applies velocity
  [OK] predict increases uncertainty
  [OK] update reduces uncertainty
  [OK] update moves state toward detection
  [OK] getBbox returns current state
  [OK] kalman-predict-zero-velocity
  [OK] kalman-update-calculates-velocity
  [OK] kalman-covariance-diagonal-initialized
  [OK] kalman-covariance-stays-positive
  [OK] kalman-multi-frame-tracking
  [OK] kalman-handles-noisy-input

[Suite] Hungarian Assignment
  [OK] iou no overlap
  [OK] iou full overlap
  [OK] iou partial overlap
  [OK] iou edge touching
  [OK] hungarianAssignment empty matrix
  [OK] hungarianAssignment single element
  [OK] hungarianAssignment respects threshold
  [OK] hungarianAssignment optimal assignment
  [OK] iou-one-inside-other
  [OK] iou-symmetric
  [OK] costMatrix-empty-tracks
  [OK] costMatrix-empty-detections
  [OK] costMatrix-sets-infinite-for-low-iou
  [OK] costMatrix-calculates-valid-cost
  [OK] hungarian-two-tracks-two-detections
  [OK] hungarian-unbalanced-more-tracks
  [OK] hungarian-unbalanced-more-detections
  [OK] hungarian-all-high-cost
  [OK] costMatrix-with-embeddings
```

Total tests: 300 (all passing)
New tests added: 17

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] .gitignore excluded tests/fixtures/**

- **Found during:** Task 1
- **Issue:** `tests/*` in .gitignore with `!tests/*.nim` exception did not allow subdirectories
- **Fix:** Added `!tests/fixtures/` and `!tests/fixtures/*.nim` exceptions
- **Files modified:** .gitignore
- **Commit:** 78e6893

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Velocity assertion in multi-frame test | Check direction only | Kalman filter with simplified diagonal covariance doesn't converge velocity to exact input value; checking positive direction validates correct behavior |

## Commits

| Hash | Message |
|------|---------|
| 78e6893 | test(13-01): create test fixture utilities |
| 646933b | test(13-01): add Kalman filter unit tests |
| 53cab48 | test(13-01): add assignment algorithm unit tests |

## Next Phase Readiness

**Prerequisites for 13-02:**
- Test fixtures available (test_utils.nim, synthetic_faces.nim)
- Kalman filter tests established as reference
- Assignment algorithm tests cover IoU, cost matrix, Hungarian assignment

**No blockers identified.**
