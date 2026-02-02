---
phase: 06-engagement-clip-detection
plan: 02
subsystem: exports
tags: [edl, cmx3600, nle, metadata, json, timecode]

dependency_graph:
  requires:
    - "Phase 5 (engagement scoring API)"
  provides:
    - "CMX3600 EDL export"
    - "JSON clip metadata export"
    - "SMPTE timecode formatting"
  affects:
    - "06-04 (clips CLI - will consume EDLClip type)"

tech_stack:
  added:
    - "CMX3600 EDL format support"
    - "SMPTE timecode utilities"
  patterns:
    - "DTO pattern (EDLClip for export decoupling)"
    - "Dual format export (EDL + JSON)"
    - "Round-trip timecode parsing for testing"

key_files:
  created:
    - path: "src/exports/edl.nim"
      lines: 173
      purpose: "CMX3600 EDL and JSON export for engagement clips"
  modified: []

decisions:
  - decision: "EDLClip DTO for decoupled export"
    rationale: "CLI handles Clip->EDLClip conversion; export module stays simple"
    alternatives: ["Export module converts Timeline Clips directly"]
    why_chosen: "Separation of concerns, testability, reusability"

  - decision: "Both EDL and JSON formats in same module"
    rationale: "CONTEXT.md specifies both formats needed; share EDLClip type"
    alternatives: ["Separate modules for EDL and JSON"]
    why_chosen: "Minimal code duplication, shared data structure"

  - decision: "30fps default for SMPTE timecode"
    rationale: "Maximum NLE compatibility (industry standard)"
    alternatives: ["25fps for PAL", "video framerate from source"]
    why_chosen: "NTSC 30fps most widely supported in professional NLEs"

  - decision: "Reel names: 8 char max, uppercase, alphanumeric"
    rationale: "CMX3600 standard requirement (SMPTE 258M)"
    alternatives: ["Full source filename"]
    why_chosen: "Standard compliance ensures NLE import compatibility"

metrics:
  duration: "1.5 min"
  completed: "2026-02-02"
---

# Phase 6 Plan 2: CMX3600 EDL Export Summary

## One-liner

Created CMX3600 EDL and JSON export for engagement clips with SMPTE timecode formatting.

## What Was Built

### EDL Export Module (`src/exports/edl.nim`)

**Core exports:**

1. **EDLClip DTO** - Self-contained data structure for export:
   - startMs, endMs: Clip boundaries in milliseconds
   - engagementScore: Score for metadata
   - text: Truncated transcript excerpt
   - rank: Clip rank (1 = best)

2. **formatTimecode()** - Convert milliseconds to SMPTE timecode:
   - Format: HH:MM:SS:FF
   - Default 30fps for maximum compatibility
   - Used in both EDL and JSON exports

3. **parseTimecode()** - Parse SMPTE timecode back to milliseconds:
   - Round-trip testing support
   - Format validation

4. **exportCMX3600EDL()** - Export clips as CMX3600 EDL:
   - TITLE line at top
   - Event lines with timecode and edit info
   - Comment lines for engagement scores and transcript
   - Proper reel name formatting (8 char, uppercase)
   - Record timeline tracking for sequential clips

5. **exportClipsJSON()** - Export clips as JSON:
   - Full engagement breakdown per clip
   - Timecodes for reference
   - Source file metadata
   - Optional params for reproducibility

### CMX3600 EDL Format

Follows SMPTE 258M standard:

```
TITLE: Engagement Clips

001  VIDEOSRC  V     C        00:00:30:00 00:01:00:00 00:00:00:00 00:00:30:00
* ENGAGEMENT_SCORE: 85.2
* RANK: 1
* TRANSCRIPT: This is an example clip...
```

**Key characteristics:**
- Fixed-width fields for compatibility
- Video-only (V) edit type
- Cut transition (C)
- Source timecode (original video position)
- Record timecode (concatenated timeline position)
- Comment lines (asterisk prefix) for metadata

### JSON Format

Richer metadata than EDL:

```json
{
  "source": "video.mp4",
  "clip_count": 5,
  "params": {...},
  "clips": [
    {
      "rank": 1,
      "start_ms": 30000,
      "end_ms": 60000,
      "duration_ms": 30000,
      "start_timecode": "00:00:30:00",
      "end_timecode": "00:01:00:00",
      "engagement_score": 85.2,
      "text": "..."
    }
  ]
}
```

## Integration Points

### From Phase 5 (Engagement Scoring)

- Engagement scores calculated by `analyzeEngagement()`
- CLI (06-04) will query engagement API to get scores
- CLI converts to EDLClip format before export

### To Phase 6 Plan 4 (Clips CLI)

- EDLClip DTO consumed by CLI
- Clip -> EDLClip conversion in 06-04
- Both formats (EDL + JSON) produced by default

### Pattern: DTO for Decoupling

```nim
# In CLI (06-04):
var edlClips: seq[EDLClip] = @[]
for clip in topClips:
  edlClips.add(EDLClip(
    startMs: clip.startMs,
    endMs: clip.endMs,
    engagementScore: clip.score,
    text: clip.transcript[0..60],
    rank: clip.rank
  ))

# Export both formats
exportCMX3600EDL(edlClips, "clips.edl", "video", fps=30.0)
exportClipsJSON(edlClips, "clips.json", "video.mp4")
```

## Testing Strategy

**Module compilation:**
- Nim syntax check passes
- C compilation succeeds (linker fails due to missing FFmpeg, expected)

**Round-trip timecode:**
- `parseTimecode()` validates `formatTimecode()` output
- Enables unit testing of timecode conversion

**Manual testing (after 06-04 CLI):**
- Export sample EDL
- Import into Premiere Pro / Resolve
- Verify clip boundaries and metadata

## Deviations from Plan

None - plan executed exactly as written.

Both Task 1 (EDL export) and Task 2 (JSON export) implemented together since they share the EDLClip data structure and fit naturally in the same module.

## Next Phase Readiness

**Ready for Phase 6 Plan 3 (Clip Detection Algorithm):**
- Export infrastructure complete
- EDLClip type defined and ready

**Ready for Phase 6 Plan 4 (Clips CLI):**
- Export API fully defined
- Both metadata formats available
- CLI just needs to convert Clip -> EDLClip and call export functions

**No blockers identified.**

## Key Learnings

**CMX3600 format quirks:**
- 8 character reel name limit requires truncation
- Must be uppercase and alphanumeric only
- Comment lines enable custom metadata
- Record timecode must track concatenated timeline position

**SMPTE timecode:**
- HH:MM:SS:FF format (frames, not milliseconds)
- 30fps most compatible across NLEs
- Round-trip parsing enables validation

**Export patterns:**
- DTO pattern decouples export from internal structures
- Both formats share same data structure
- CLI handles conversion logic, export module stays focused

## Files Modified

**Created:**
- `src/exports/edl.nim` (173 lines) - CMX3600 EDL and JSON export

**Total:** 1 file created, 173 lines added

## Commits

- `f507109` - feat(06-02): create CMX3600 EDL export module
