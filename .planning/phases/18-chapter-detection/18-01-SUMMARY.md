---
phase: 18-chapter-detection
plan: 01
subsystem: analyze
tags: [chapter-detection, engagement-peaks, scene-detection, metadata-export, nle-markers]
dependency-graph:
  requires:
    - src/analyze/engagement_types.nim (EngagementTimeline, EngagementSegment)
    - src/metadata/types.nim (ChapterMarker)
    - src/exports/markers.nim (Marker, MarkerType, getMarkerColor, labelForScore)
  provides:
    - src/analyze/chapters.nim (Chapter types, peak detection, chapter generation, export conversion)
  affects:
    - Future CLI command (honeyclip chapters)
    - MP4 metadata export pipeline
    - NLE marker export pipeline
tech-stack:
  added:
    - Chapter detection module with engagement peak analysis
  patterns:
    - Local maxima detection with greedy spacing selection
    - Multi-modal chapter generation (scene, engagement, combined)
    - Deduplication via sliding window for combined mode
    - FFmpeg ffmetadata spec compliance (endMs = next.startMs - 1)
key-files:
  created:
    - src/analyze/chapters.nim (318 lines, 11KB)
  modified: []
decisions:
  - Default 30s minimum spacing between chapters for usable navigation
  - Combined mode prefers engagement markers over scene markers during deduplication
  - Chapter titles use engagement labels (High/Medium/Low) for context
  - Export conversions reuse existing ChapterMarker and Marker types
metrics:
  duration: 102s
  tasks: 2
  files-created: 1
  commits: 2
  completed: 2026-02-15T02:35:55Z
---

# Phase 18 Plan 01: Chapter Detection Core Summary

**One-liner:** Local maxima engagement peak detection with scene/engagement/combined chapter generation and FFmpeg metadata export conversion.

## What Was Built

Implemented the core chapter detection module (`src/analyze/chapters.nim`) with:

1. **Type System:**
   - `ChapterSource` enum (scene/engagement)
   - `Chapter` object with start/end timestamps, title, source, score
   - `ChapterParams` with configurable mode, thresholds, spacing, limits

2. **Peak Detection:**
   - `detectEngagementPeaks`: Local maxima algorithm with greedy spacing selection
   - Finds segments where score > neighbors and >= minScore
   - Sorts candidates by score, applies minimum spacing constraint
   - Caps at maxPeaks, returns chronologically sorted timestamps

3. **Chapter Generation:**
   - `generateChapters`: Three modes (scene, engagement, combined)
   - **Scene mode:** Converts float64 timestamps to ms, filters by spacing, caps at max
   - **Engagement mode:** Looks up scores from timeline, generates descriptive titles
   - **Combined mode:** Merges sources, deduplicates within window, applies spacing
   - Implements FFmpeg spec: endMs = next.startMs - 1 (not equal)

4. **Export Conversion:**
   - `chaptersToMetadata`: Converts to ChapterMarker for MP4 metadata export
   - `chaptersToMarkers`: Converts to Marker for NLE export with proper types/colors

## Implementation Notes

### Peak Detection Algorithm

Per RESEARCH.md Pattern 2, used standard signal processing local maxima:
1. Iterate segments [1..len-2], check if score > neighbors
2. Sort candidates by score descending
3. Greedy selection: skip if within minSpacingMs of any selected peak
4. Cap at maxPeaks, return chronologically sorted

Edge cases handled:
- Empty timeline: return empty seq
- Single/two segments: return empty seq (can't compute local maxima)
- All scores below threshold: return empty seq

### Chapter Generation Modes

**Scene mode:** Scene boundaries only
- Convert seconds to milliseconds
- Filter consecutive scenes within minSpacingMs
- Cap at maxChapters (evenly distribute if too many)
- Title: "Scene N"

**Engagement mode:** Engagement peaks only
- Use peak timestamps directly
- Look up score from timeline segments
- Title: "Peak #N - {High/Medium/Low engagement}"

**Combined mode:** Merge both with deduplication
- Collect all markers with source tags
- Sort by timestamp
- Deduplicate: if within dedupeWindowMs, keep engagement over scene
- Apply minSpacing filter across merged list
- Cap at maxChapters
- Separate counters for engagement/scene in titles

### FFmpeg Metadata Compliance

Critical spec from RESEARCH.md Pitfall 4:
- Chapter END must be last frame before next START
- Implementation: `endMs = next.startMs - 1`
- Last chapter: `endMs = timeline.duration`

### Export Conversion Strategy

Reused existing types from Phase 9 (markers) and Phase 14 (metadata):
- `ChapterMarker` has startMs, endMs, title (for MP4 metadata)
- `Marker` has markerType, timestampMs, durationMs, name, comment, color (for NLE)
- Conversion is straightforward mapping with proper type selection

## Verification

1. Compilation: `nim check src/analyze/chapters.nim` passes
2. Module exports verified:
   - ChapterSource, Chapter, ChapterParams types
   - defaultChapterParams, detectEngagementPeaks procs
   - generateChapters, chaptersToMetadata, chaptersToMarkers procs
3. Edge cases handled: empty timeline, single segment, all scores below threshold
4. FFmpeg spec compliance: endMs = next.startMs - 1

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check

Verifying created files:

```bash
[ -f "src/analyze/chapters.nim" ] && echo "FOUND: src/analyze/chapters.nim" || echo "MISSING: src/analyze/chapters.nim"
```

Result: FOUND

Verifying commits:

```bash
git log --oneline --all | grep -q "1449e9a" && echo "FOUND: 1449e9a" || echo "MISSING: 1449e9a"
git log --oneline --all | grep -q "b8a8dde" && echo "FOUND: b8a8dde" || echo "MISSING: b8a8dde"
```

Result: FOUND (both commits)

## Self-Check: PASSED

All files created, all commits present, module compiles successfully.

## Next Steps

Phase 18 Plan 02 will implement:
- Scene detection via FFmpeg scdet filter
- extractSceneChanges proc to integrate with chapter generation
- CLI flag parsing for scene threshold

Phase 18 Plan 03 will implement:
- `honeyclip chapters` CLI command
- Integration with existing engagement analysis
- MP4 metadata and NLE marker export
- Unit tests for peak detection and chapter generation
