---
phase: 02-transcript-foundation
plan: 02
subsystem: transcript
tags: [subtitle, srt, vtt, json, caption, word-grouping, sentence-boundary]

# Dependency graph
requires:
  - phase: 02-01
    provides: Word and Transcript types with timestamp formatting
provides:
  - Caption grouping algorithm with sentence boundary detection
  - SRT export with comma milliseconds and speaker labels
  - VTT export with period milliseconds and WEBVTT header
  - JSON export with word-level confidence and caption metadata
affects: [02-03, 02-04, transcript-cli]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Caption grouping with sentence boundary preference
    - Speaker change detection between captions
    - Template-based caption building to avoid closure issues

key-files:
  created:
    - src/transcript/grouping.nim
    - src/transcript/formats.nim
  modified:
    - tests/unit.nim

key-decisions:
  - "Template instead of nested proc to avoid Nim closure memory safety issues"
  - "42-char default caption limit (standard readable line length)"
  - "5-second default caption duration (typical subtitle timing)"
  - "Prefer sentence boundaries when within 20% of char limit"
  - "Never break before small words (a, the, to, of, etc.)"
  - "Speaker labels only on speaker change to reduce visual clutter"
  - "UTF-8 output without BOM for maximum player compatibility"

patterns-established:
  - "Caption grouping balances char limit, duration limit, sentence boundaries, and speaker changes"
  - "Abbreviation detection prevents false sentence ends (Dr., Mr., etc.)"
  - "Low-confidence marking via [?] suffix for user review"
  - "Stdout support via '-' path for pipeline integration"

# Metrics
duration: 4min
completed: 2026-02-02
---

# Phase 02 Plan 02: Subtitle Format Export Summary

**SRT, VTT, and JSON subtitle exporters with intelligent caption grouping that respects 42-char limits, sentence boundaries, and speaker changes**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-02T07:45:46Z
- **Completed:** 2026-02-02T07:50:10Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Caption grouping algorithm that balances readability (sentence boundaries) with constraints (char/duration limits)
- SRT format export with comma milliseconds and contextual speaker labels
- VTT format export with period milliseconds, WEBVTT header, and optional color styling
- JSON format export with full word-level data and grouped captions
- Comprehensive test suite verifying format correctness and speaker label placement

## Task Commits

Each task was committed atomically:

1. **Task 1: Create caption grouping module** - `0fee729` (feat)
2. **Task 2: Create subtitle format exporters** - `a4e3880` (feat)
3. **Task 3: Add format output tests** - `4a45dbc` (test)

## Files Created/Modified
- `src/transcript/grouping.nim` - Caption grouping with sentence boundary detection and speaker change tracking
- `src/transcript/formats.nim` - SRT, VTT, and JSON export functions with speaker labels and confidence markers
- `tests/unit.nim` - Format tests verifying timestamp formats, caption grouping, and speaker label placement

## Decisions Made

**Template instead of nested proc:** Initial implementation used nested `proc finishCaption()` which triggered Nim 2.x closure memory safety error. Switched to `template finishCaption()` to avoid closure capture while maintaining clean code organization.

**42-char default caption limit:** Standard readable line length for subtitles, widely supported by video players and editors.

**Prefer sentence boundaries:** When within 20% of char limit and a sentence end exists in recent words, break at sentence rather than mid-sentence for better readability.

**Speaker labels on change only:** Reduces visual clutter - labels only appear when speaker transitions, not on every caption.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed Nim closure memory safety issue**
- **Found during:** Task 3 (running unit tests)
- **Issue:** Nested `proc finishCaption()` captured `result` seq, triggering Nim 2.x memory safety error: "cannot be captured as it would violate memory safety"
- **Fix:** Changed `proc finishCaption()` to `template finishCaption()` which expands inline without capturing variables
- **Files modified:** src/transcript/grouping.nim
- **Verification:** Compilation succeeds without errors
- **Committed in:** 4a45dbc (Task 3 commit)

**2. [Rule 3 - Blocking] Added strutils import to test file**
- **Found during:** Task 3 (running unit tests)
- **Issue:** Test code used `.contains()` method on string but strutils not imported, causing type mismatch error
- **Fix:** Added `import std/[os, tempfiles, strutils]` to tests/unit.nim
- **Files modified:** tests/unit.nim
- **Verification:** Tests compile and run successfully
- **Committed in:** 4a45dbc (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes were necessary to unblock compilation and testing. No scope creep.

## Issues Encountered

**Full test suite requires FFmpeg:** The `nimble test` command requires FFmpeg headers which aren't built yet (documented blocker in STATE.md: "Unit tests require FFmpeg build to execute"). Created standalone format tests using `--skipParentCfg` flag to verify functionality without FFmpeg dependency. All format-specific tests pass successfully.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

**Ready for:**
- Speaker diarization integration (02-03) - caption speaker field ready for assignment
- Subtitle command implementation (02-04) - exporters ready for CLI integration
- Timeline integration - captions can drive video segmentation

**Technical foundation:**
- Caption type with speaker tracking and change detection
- Three standard export formats (SRT, VTT, JSON)
- Sentence boundary detection and smart line breaking
- Low-confidence word marking for quality review

---
*Phase: 02-transcript-foundation*
*Completed: 2026-02-02*
