# Phase 9 Plan 03: FCPXML Marker Export Summary

**One-liner:** FCPXML marker export with rational time format for Final Cut Pro X timeline markers

## Metadata

| Field | Value |
|-------|-------|
| Phase | 09-nle-integration-markers |
| Plan | 03 |
| Subsystem | exports |
| Tags | fcpxml, markers, fcp, nle, xml |
| Duration | 2.4 min |
| Completed | 2026-02-04 |

## Dependency Graph

| Type | Items |
|------|-------|
| Requires | 09-01 (markers.nim types) |
| Provides | FCPXML marker export functions |
| Affects | 09-04 (EDL marker export) |

## Tech Stack

| Category | Items |
|----------|-------|
| Added | None (uses existing xmltree stdlib) |
| Patterns | Rational time format for FCPXML, frame-based timing conversion |

## Key Files

| Status | Path | Purpose |
|--------|------|---------|
| Modified | src/exports/fcp11.nim | FCPXML marker export functions |
| Modified | tests/unit.nim | FCPXML marker test suite |

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Markers attach to asset-clip element | FCPXML markers belong to clip elements, not spine directly |
| Rational time format (frames*den/num)s | Matches existing FCPXML timing patterns in fcp11.nim |
| Note attribute for comment field | FCPXML uses `note` attribute for marker descriptions |
| No color attribute in FCPXML | FCPXML markers don't support custom colors in XML; FCP sets color by marker type |

## Artifacts Delivered

### Functions

| Function | Purpose |
|----------|---------|
| `addMarkerFCPXML*(parent: XmlNode, marker: Marker, tb: AVRational)` | Add single marker element to FCPXML |
| `addMarkersFCPXML*(parent: XmlNode, markers: seq[Marker], tb: AVRational)` | Add multiple markers to parent element |
| `writeMarkersFCPXML*(videoPath: string, markers: seq[Marker], outputPath: string)` | Write complete FCPXML file with markers |

### Test Suite

| Test | Verification |
|------|--------------|
| addMarkerFCPXML creates correct XML structure | Verifies tag, value, note attributes |
| addMarkerFCPXML rational time format | Validates NTSC 29.97fps rational time |
| addMarkerFCPXML simple 30fps timebase | Validates integer framerate conversion |
| addMarkerFCPXML note contains marker comment | Ensures engagement data in note |
| addMarkersFCPXML adds multiple markers | Bulk marker addition |
| addMarkerFCPXML zero timestamp | Edge case for 0s start |
| addMarkerFCPXML duration calculation | 1000ms default duration |

## Implementation Notes

### FCPXML Marker Format

FCPXML uses a simpler marker format than FCP7 XML:

```xml
<marker start="60/30s" duration="30/30s" value="Peak #1" note="Score: 85/100 (#1) - High engagement"/>
```

Key differences from FCP7:
- Self-closing element (no children)
- Timing in rational seconds format
- No color support in XML (FCP assigns colors by marker type)
- `value` attribute for name, `note` for comment

### Timing Conversion

The conversion from milliseconds to FCPXML rational time:

```nim
# ms -> frames: (ms * fps_num) / (fps_den * 1000)
let startFrame = (marker.timestampMs * tb.num.int64) div (tb.den.int64 * 1000)
# Rational format: frames * den / num "s"
result = &"{startFrame * tb.den.int}/{tb.num}s"
```

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

- `nim check src/exports/fcp11.nim`: Compiles without errors
- `nimble test`: All 7 new FCPXML marker tests pass
- Marker XML structure matches Apple FCPXML specification

## Next Phase Readiness

- FCPXML marker export ready for use in clips export command
- 09-04 (EDL marker export) can proceed
- Full marker export pipeline (FCP7 + FCPXML + EDL) nearing completion
