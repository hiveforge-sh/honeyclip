---
phase: 08-multi-aspect-export-workflow
plan: 02
subsystem: render
tags: [ffmpeg, thumbnail, preview, tile-filter, hstack, contact-sheet]

# Dependency graph
requires:
  - phase: 08-01
    provides: AspectRatio, ReframeSettings foundation types
provides:
  - Preview generation using FFmpeg thumbnail and tile filters
  - Video snippet extraction (9s per clip: 3s start + 3s middle + 3s end)
  - Side-by-side comparison previews (original vs reframed)
  - Contact sheet grid generation
  - Overview video concatenation
affects: [08-03-boundary-adjustment, 08-05-export-command]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - FFmpeg thumbnail filter for best-frame selection (histogram analysis)
    - FFmpeg tile filter for contact sheet grid layout
    - FFmpeg hstack filter for side-by-side comparison
    - FFmpeg concat demuxer for overview video assembly
    - Preview directory pattern ({video}_previews/ subfolder)

key-files:
  created:
    - src/render/previews.nim
  modified: []

key-decisions:
  - "FFmpeg thumbnail filter batch size 100 for best-frame selection"
  - "Contact sheet uses concat+tile approach for reliable multi-input handling"
  - "Video snippets use fast preset + CRF 28 for preview quality (not final)"
  - "Metadata burned into previews via drawtext filter (clip rank + time range)"
  - "Side-by-side uses hstack filter with scale=iw/2:-1 for equal width"
  - "Overview video uses concat demuxer with generated list file"

patterns-established:
  - "findFFmpegPath checks build/bin first, then PATH (per reframe.nim pattern)"
  - "Preview files in dedicated {video}_previews/ subfolder"
  - "Snippet naming: clip_{rank:02}_{start|middle|end}.mp4"

# Metrics
duration: 2min
completed: 2026-02-03
---

# Phase 08 Plan 02: Preview Generation Summary

**FFmpeg-based preview generation with thumbnails, video snippets, contact sheets, and side-by-side comparison using tile/thumbnail/hstack filters**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-04T00:41:04Z
- **Completed:** 2026-02-04T00:43:30Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Preview module generates thumbnails using FFmpeg thumbnail filter (histogram-based best frame selection)
- Contact sheet creates thumbnail grid using tile filter with configurable columns
- Video snippets extract 9 seconds per clip (3s start + 3s middle + 3s end)
- Side-by-side comparison shows original vs reframed using hstack filter
- Overview video concatenates all snippets using concat demuxer
- Metadata burned into previews (clip rank + time range) via drawtext filter

## Task Commits

Each task was committed atomically:

1. **Task 1: Create preview generation module** - `fd6ec0e` (feat)
2. **Task 2: Add side-by-side comparison preview** - `e2f68fe` (feat)

## Files Created/Modified

- `src/render/previews.nim` - Preview generation using FFmpeg thumbnail, tile, and hstack filters

## Decisions Made

- **FFmpeg thumbnail filter batch size 100:** Standard batch for histogram analysis, selects most representative frame
- **Contact sheet concat+tile approach:** More reliable than complex select expressions for multi-input handling
- **CRF 28 for preview snippets:** Lower quality than final render (CRF 23) for faster generation
- **Drawtext metadata overlay:** Burns clip rank and time range into previews for easy identification
- **hstack with scale=iw/2:-1:** Equal width comparison panels that preserve aspect ratio

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Preview generation ready for integration with clips command
- generatePreviews() function ready for CLI exposure
- Side-by-side comparison ready for reframe verification workflow
- Contact sheet provides quick visual overview of all detected clips

---
*Phase: 08-multi-aspect-export-workflow*
*Completed: 2026-02-03*
