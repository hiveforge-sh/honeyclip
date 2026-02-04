---
phase: 09-nle-integration-markers
plan: 01
subsystem: exports
tags: [markers, nle, timeline, engagement]
dependency-graph:
  requires: []
  provides: [Marker, MarkerType, createEngagementMarker, createSceneMarker, createSpeakerMarker]
  affects: [09-02, 09-03, 09-04]
tech-stack:
  added: []
  patterns: [factory-functions, enum-types]
key-files:
  created: [src/exports/markers.nim]
  modified: [tests/unit.nim]
decisions:
  - Green (#00FF00) for engagement peaks
  - Blue (#0066FF) for scene boundaries
  - Yellow (#FFCC00) for speaker changes
  - 30fps default for timecode calculation
metrics:
  duration: 3.4min
  completed: 2026-02-03
---

# Phase 9 Plan 1: NLE Marker Data Structures Summary

Unified marker types for engagement peaks, scene boundaries, and speaker changes with color coding and format-agnostic timing.

## What Was Built

### MarkerType Enum
Three marker types with semantic meaning:
- `mtEngagementPeak` - High engagement moment
- `mtSceneBoundary` - Visual scene change
- `mtSpeakerChange` - New speaker begins

### Marker Object
Format-agnostic marker with fields:
- `markerType` - Enum identifying the type
- `timestampMs` - Position in milliseconds
- `durationMs` - Default 1000ms
- `name` - Short display name
- `comment` - Detailed description
- `color` - Hex color string

### Factory Functions
- `createEngagementMarker(timestampMs, score, rank)` - Creates peak marker with "Peak #N" name and score/label comment
- `createSceneMarker(timestampMs)` - Creates scene boundary marker with timecode in comment
- `createSpeakerMarker(timestampMs, speakerId, speakerName)` - Creates speaker change marker with name or ID

### Utility Functions
- `getMarkerColor(mt)` - Returns hex color for marker type
- `msToTimecode(ms, fps)` - Formats milliseconds as HH:MM:SS:FF
- `labelForScore(score)` - Returns "High"/"Medium"/"Low" based on score threshold

## Design Rationale

**Color Coding:** Standard NLE conventions - green for positive (engagement), blue for structural (scenes), yellow for informational (speakers).

**Score Labels:** Three tiers (High 80+, Medium 50-79, Low <50) provide quick visual classification without needing exact numbers.

**Timecode Format:** HH:MM:SS:FF is standard NLE format, 30fps default matches NTSC industry standard.

**Factory Pattern:** Each marker type has a dedicated factory function that handles formatting, ensuring consistent output across the codebase.

## Commits

| Hash | Description |
|------|-------------|
| 5242508 | feat(09-01): add marker types module for NLE timeline markers |
| bd35bfb | test(09-01): add unit tests for NLE marker module |

## Tests Added

8 unit tests covering:
- `createEngagementMarker` format and score labels
- `createSceneMarker` format
- `createSpeakerMarker` with and without name
- `labelForScore` thresholds
- `msToTimecode` calculation
- `getMarkerColor` returns correct colors

## Deviations from Plan

None - plan executed exactly as written.

## Next Phase Readiness

**Dependencies provided for 09-02:**
- `Marker` type for FCP7 XML marker export
- `MarkerType` enum for type-specific rendering
- Color constants for NLE color formatting

**Integration points:**
- `src/exports/markers.nim` exports all types with `*`
- Factory functions accept standard timestamp format (milliseconds)
- Colors are hex strings compatible with FCP7/FCPXML color conversion
