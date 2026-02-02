---
phase: 07-speaker-tracking-reframing
plan: 04
subsystem: reframing
tags: [easing, bezier-curves, crop-calculation, speaker-framing, nim]

# Dependency graph
requires:
  - phase: 07-01
    provides: "Tracking types (EasingPreset, CropRegion, FaceRect)"
provides:
  - "Cubic-bezier easing curves with Slow/Medium/Fast presets"
  - "Crop region calculation with medium shot framing"
  - "Smooth interpolation between crop targets"
affects: [07-05, 07-06, reframe-cli]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Cubic-bezier easing for cinematic motion", "Medium shot framing (face * 2.5 padding)"]

key-files:
  created: ["src/reframe/easing.nim", "src/reframe/crop.nim"]
  modified: []

key-decisions:
  - "Easing presets: Slow=1.5s, Medium=0.75s, Fast=0.35s matching CONTEXT speed requirements"
  - "Medium shot padding formula: face height * 2.5 for head and shoulders visible"
  - "Debouncing threshold: 20 pixels minimum distance to trigger crop switch"

patterns-established:
  - "Cubic-bezier curves: Slow(0.25,0.25), Medium(0.42,0.58), Fast(0.55,1.0) for distinct feels"
  - "Constraint-first approach: crop calculation constrains to frame boundaries before returning"

# Metrics
duration: 2min
completed: 2026-02-02
---

# Phase 7 Plan 4: Easing Curves and Crop Calculation Summary

**Cubic-bezier easing with three speed presets and crop region calculation with medium shot framing for cinematic speaker reframing**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-02T23:01:15Z
- **Completed:** 2026-02-02T23:03:16Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Cubic-bezier easing curves with Slow (1.5s), Medium (0.75s), Fast (0.35s) presets
- Crop region calculation centered on faces with medium shot padding (head + shoulders)
- Smooth interpolation between crop targets using bezier easing
- Graceful fallback to center-crop when no face detected
- Edge case handling: faces at boundaries, oversized crops

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement cubic-bezier easing curves** - `7bf5978` (feat)
2. **Task 2: Implement crop region calculation** - `29e3ce3` (feat)

## Files Created/Modified
- `src/reframe/easing.nim` - Cubic-bezier easing curves with speed presets, getDuration, lerp helper
- `src/reframe/crop.nim` - Crop region calculation with AspectRatio enum, calculateCrop, calculateFallbackCrop, interpolateCrop, shouldSwitchTarget

## Decisions Made

**1. Easing preset durations**
- Slow: 1.5s (centered in 1-2s range from CONTEXT)
- Medium: 0.75s (centered in 0.5-1s range)
- Fast: 0.35s (centered in 0.2-0.5s range)
- Rationale: Centered values provide balanced default behavior

**2. Medium shot padding formula**
- Formula: `faceHeight * 2.5` for total crop height
- Rationale: RESEARCH specified "bbox.height * 2.5 for head + shoulders" - standard interview/podcast framing

**3. Debouncing spatial threshold**
- Default: 20 pixels minimum distance between crop centers
- Rationale: Prevents flicker in rapid dialogue, complements 0.5s temporal hold (caller's responsibility)

**4. Cubic-bezier control points**
- Slow: (0.0, 0.25, 0.25, 1.0) - gradual acceleration/deceleration
- Medium: (0.0, 0.42, 0.58, 1.0) - balanced ease-in-out
- Fast: (0.0, 0.55, 1.0, 1.0) - quick motion
- Rationale: RESEARCH code examples provided these industry-standard curves

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - implementation straightforward following RESEARCH specifications.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for next plan (07-05: reframe compositor or tracking integration):
- Easing functions produce smooth curves in [0, 1] range
- Crop calculation handles edge cases (boundaries, oversized faces)
- All types properly exported and documented
- Module compiles without errors (`nim check` passed)

No blockers. Awaiting integration with face tracking and FFmpeg crop filter application.

---
*Phase: 07-speaker-tracking-reframing*
*Completed: 2026-02-02*
