---
phase: 11-ml-library-size-optimization
plan: 01
subsystem: build
tags: [cmake, opencv, libfacedetection, size-optimization, MinSizeRel]

# Dependency graph
requires:
  - phase: 01-foundation-build-infrastructure
    provides: ML library build system (makeml task, cmakeBuild proc)
provides:
  - Size-optimized OpenCV build configuration (MinSizeRel, disabled modules)
  - Size-optimized libfacedetection build configuration (MinSizeRel)
  - Conditional CMAKE_BUILD_TYPE in cmakeBuild proc
affects: [11-02-dead-code-elimination, binary-size-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MinSizeRel for ML libraries (-Os optimization over -O3)"
    - "Explicit module disable flags in addition to BUILD_LIST"
    - "Conditional build type detection in cmakeBuild"

key-files:
  created: []
  modified:
    - honeyclip.nimble

key-decisions:
  - "MinSizeRel build type for OpenCV and libfacedetection (15-25% size reduction expected)"
  - "Explicitly disable 10 OpenCV modules even with BUILD_LIST (belt-and-suspenders approach)"
  - "Keep opencv_photo module for future image preprocessing"
  - "Disable 5 unused 3rdparty dependencies: CAROTENE, EIGEN, ADE, FLATBUFFERS, ITT"
  - "Conditional build type in cmakeBuild preserves Release for whisper, svtav1"

patterns-established:
  - "Package-specified CMAKE_BUILD_TYPE overrides cmakeBuild default"
  - "Comment markers for grouped CMake flags (e.g., # Disable unused 3rdparty dependencies)"

# Metrics
duration: 2min
completed: 2026-02-05
---

# Phase 11 Plan 01: ML Build Configuration Summary

**OpenCV and libfacedetection build configurations updated to MinSizeRel with explicit module disabling and 3rdparty dependency trimming**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-05T15:23:25Z
- **Completed:** 2026-02-05T15:25:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- OpenCV uses MinSizeRel (-Os) instead of Release (-O3) for smaller binary size
- Explicitly disabled 10 unwanted OpenCV modules (calib3d, features2d, flann, dnn, gapi, highgui, ml, video, stitching, videoio)
- Disabled 5 unused 3rdparty dependencies (CAROTENE, EIGEN, ADE, FLATBUFFERS, ITT)
- libfacedetection uses MinSizeRel for consistency
- cmakeBuild respects package-specified build types, preserving Release for other packages

## Task Commits

Each task was committed atomically:

1. **Task 1: Update OpenCV build configuration for size optimization** - `8a04e51` (feat)
2. **Task 2: Update libfacedetection build configuration for size optimization** - `6be4486` (feat)
3. **Task 3: Update cmakeBuild to respect package-specified build type** - `da9aaa6` (refactor)

## Files Created/Modified
- `honeyclip.nimble` - Updated OpenCV buildArguments with MinSizeRel, disabled modules, and 3rdparty deps; updated libfacedetectionBaseArgs with MinSizeRel; modified cmakeBuild to conditionally add build type

## Decisions Made
- MinSizeRel for ML libraries: Research indicates 15-25% size reduction from -Os vs -O3 optimization
- Keep opencv_photo module: Reserved for future image preprocessing capabilities
- Explicit module disabling: BUILD_LIST alone may not fully exclude modules in all OpenCV versions
- Conditional build type: Whisper and SVT-AV1 benefit from -O3 performance optimization for real-time processing

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Build configuration updated, ready for plan 11-02 (dead code elimination)
- Actual size reduction requires rebuilding ML libraries (`nimble makeml`)
- Size validation will occur after all optimization plans complete

---
*Phase: 11-ml-library-size-optimization*
*Completed: 2026-02-05*
