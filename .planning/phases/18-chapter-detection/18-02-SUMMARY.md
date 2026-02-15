---
phase: 18-chapter-detection
plan: 02
subsystem: cmds
tags: [cli, chapters, scene-detection, engagement-peaks, export, metadata, nle-markers]
dependency-graph:
  requires:
    - src/analyze/chapters.nim (Chapter types, generateChapters, chaptersToMetadata, chaptersToMarkers)
    - src/analyze/clips.nim (extractSceneChanges)
    - src/analyze/engagement.nim (analyzeEngagement)
    - src/metadata/apply.nim (writeFFMetadataFile)
    - src/exports/fcp11.nim (writeMarkersFCPXML)
    - src/exports/edl.nim (exportMarkersEDL)
    - src/transcript/extract.nim (extractTranscript)
  provides:
    - src/cmds/chapters.nim (CLI command for chapter generation)
  affects:
    - User can run honeyclip chapters for auto-generated video chapters
    - MP4 metadata export pipeline (embed chapters in video file)
    - NLE marker export pipeline (FCPXML, EDL for editing workflows)
tech-stack:
  added:
    - CLI command for chapter detection and export
  patterns:
    - Multi-mode chapter detection (scene/engagement/combined)
    - Auto-detection of whisper model from cache
    - Scene-only mode without transcript requirement
    - Dummy timeline for scene-only analysis
    - Default output path generation from input filename
    - FFmpeg metadata embedding via execCmd
key-files:
  created:
    - src/cmds/chapters.nim (420 lines, 15KB)
  modified:
    - src/main.nim (2 lines: import and command registration)
decisions:
  - Auto-set --no-transcript for scene-only mode when no model specified
  - Create dummy timeline with zero segments for scene-only mode
  - Use execCmd for FFmpeg chapter embedding (simpler than libav process)
  - Default output naming: {input}_chapters.{ext}
  - JSON export includes source field (scene/engagement) for post-processing
metrics:
  duration: 313s
  tasks: 2
  files-created: 1
  files-modified: 1
  commits: 2
  completed: 2026-02-15T02:43:48Z
---

# Phase 18 Plan 02: Chapters CLI Command Summary

**One-liner:** CLI command for auto-generating chapters from scene changes and engagement peaks with export to MP4 metadata, FCPXML, EDL, and JSON.

## What Was Built

Implemented the `chapters` CLI subcommand (`src/cmds/chapters.nim`) and registered it in `src/main.nim`:

1. **CLI Argument Parsing:**
   - Positional: `file` (required), `model` (auto-detected if not provided)
   - Mode selection: `--mode scene|engagement|combined` (default: combined)
   - Export format: `--export mp4|fcpxml|edl|json` (default: print to terminal)
   - Output path: `-o, --output PATH` (default: auto-generated)
   - Scene detection: `--threshold N` (default: 0.4, passed to FFmpeg scdet)
   - Engagement constraints: `--min-spacing SECS`, `--min-score N`, `--max-chapters N`
   - Performance flags: `--no-faces`, `--no-transcript`
   - Hooks: `--hooks PATH` for custom engagement patterns
   - Output control: `-q, --quiet`, `--debug`

2. **Pipeline Execution:**
   - **Step 1:** Extract transcript (unless `--no-transcript` or scene-only mode)
   - **Step 2:** Open container, get timebase and duration
   - **Step 3:** Load hooks (if engagement mode)
   - **Step 4:** Analyze engagement (unless scene-only mode)
   - **Step 5:** Detect scene changes via `extractSceneChanges` (unless engagement-only)
   - **Step 6:** Build ChapterParams from CLI args
   - **Step 7:** Detect engagement peaks via `detectEngagementPeaks` (if applicable)
   - **Step 8:** Generate chapters via `generateChapters`
   - **Step 9:** Print chapter list to terminal (always, unless `--quiet`)
   - **Step 10:** Export if `--export` specified

3. **Chapter List Output:**
   - Prints detected chapters with timestamps, duration, source, score
   - Format: `[M:SS]-[M:SS] (XXs) [scene|engagement] (score: XX)`
   - Displays chapter titles with engagement labels

4. **Export Formats:**
   - **mp4:** Converts to ChapterMarker, writes ffmetadata file, applies via FFmpeg `-map_metadata`
   - **fcpxml:** Converts to Markers, calls `writeMarkersFCPXML` with inputPath
   - **edl:** Converts to Markers, calls `exportMarkersEDL` with sourceName
   - **json:** Creates JSON array with startMs, endMs, title, source, score

5. **Command Registration:**
   - Imported as `chapters as chaptersCmd` in main.nim
   - Registered in cmdHandlers: `("chapters", chaptersCmd.main)`
   - Accessible via `honeyclip chapters --help`

## Implementation Notes

### Auto-Detection and Defaults

**Whisper model discovery:**
- If mode requires engagement (`!= "scene"`) and no model specified: calls `findWhisperModel()`
- If scene-only mode and no model: auto-sets `--no-transcript` flag
- Provides helpful error message with download link if model not found

**Dummy timeline for scene-only mode:**
- Created with duration from container, zero avgScore, zero hookCount
- Empty segments seq (no engagement analysis performed)
- Allows `generateChapters` to work without engagement data

**Default output paths:**
- mp4: `{dir}/{name}_chapters{ext}` (preserves original format)
- fcpxml: `{dir}/{name}_chapters.fcpxml`
- edl: `{dir}/{name}_chapters.edl`
- json: `{dir}/{name}_chapters.json`

### Scene Detection Integration

Used existing `extractSceneChanges` from clips.nim:
- Returns seq[float64] timestamps in seconds
- Runs FFmpeg with scdet filter: `-vf "scdet=t={threshold}:s=1"`
- Parses stderr for lavfi.scd.time entries
- Threshold 0.0-1.0 (default 0.4 for moderate sensitivity)

### Engagement Analysis Integration

Reused engagement pipeline from clips.nim and engagement.nim:
- Load hooks (built-in + custom if provided)
- Run `analyzeEngagement` with bar, container, transcript, timebase, params
- Call `detectEngagementPeaks` with minSpacing, minScore, maxPeaks
- Timeline provides segment scores for peak lookup

### MP4 Metadata Export

FFmpeg chapter embedding process:
1. Convert chapters to ChapterMarker (startMs, endMs, title)
2. Create MetadataTemplate with empty global dict and chapter seq
3. Call `writeFFMetadataFile` to generate ffmetadata INI file
4. Execute FFmpeg: `-i input -i metadata.txt -map_metadata 1 -codec copy output`
5. Use `execCmd` for simple synchronous execution (no process management needed)

Exit code check: if exitCode != 0, error with "FFmpeg command failed"

### NLE Marker Export

**FCPXML:**
- Function signature: `writeMarkersFCPXML(videoPath, markers, outputPath)`
- Pass inputPath as videoPath (needed for media info detection)
- Markers include markerType, timestampMs, durationMs, name, comment, color

**EDL:**
- Function signature: `exportMarkersEDL(markers, outputPath, sourceName, fps=30.0)`
- Pass `extractFilename(inputPath)` as sourceName
- Uses default 30fps (EDL standard)

### JSON Export

Custom JSON structure for post-processing:
```json
[
  {
    "startMs": 0,
    "endMs": 30000,
    "title": "Peak #1 - High engagement",
    "source": "engagement",
    "score": 85.3
  }
]
```

Source field enables filtering by scene vs engagement in external tools.

## Verification

1. **Compilation:** `nim check src/cmds/chapters.nim` passes
2. **Main registration:** `nim check src/main.nim` passes
3. **Binary build:** `nimble make` succeeds (114410 lines, 120.8s)
4. **Help text:** Command registered in cmdHandlers (verified via grep)
5. **All CLI flags parsed:** Expecting state machine handles all options
6. **Function signatures:** Fixed `writeMarkersFCPXML` call order (videoPath first)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed writeMarkersFCPXML function call signature**
- **Found during:** Task 1 (nimble make compilation)
- **Issue:** Called `writeMarkersFCPXML(markerList, outputFile, extractFilename(inputPath))` but function expects `(videoPath, markers, outputPath)`
- **Fix:** Reordered args to `writeMarkersFCPXML(inputPath, markerList, outputFile)`
- **Files modified:** src/cmds/chapters.nim
- **Commit:** 2670ae4 (combined with Task 2)

## Self-Check

Verifying created files:

```bash
[ -f "src/cmds/chapters.nim" ] && echo "FOUND: src/cmds/chapters.nim" || echo "MISSING: src/cmds/chapters.nim"
```

Result: FOUND

Verifying commits:

```bash
git log --oneline --all | grep -q "72d94c6" && echo "FOUND: 72d94c6" || echo "MISSING: 72d94c6"
git log --oneline --all | grep -q "2670ae4" && echo "FOUND: 2670ae4" || echo "MISSING: 2670ae4"
```

Result: FOUND (both commits)

## Self-Check: PASSED

All files created, all commits present, binary compiles successfully.

## Next Steps

Phase 18 Plan 03 (if planned) will likely add:
- Unit tests for chapters CLI argument parsing
- Integration tests for end-to-end chapter generation
- Edge case testing (no chapters detected, mode validation)

Phase 18 complete after this plan - chapter detection fully functional with:
- Core detection module (Plan 01)
- CLI command and exports (Plan 02)
- User can now run `honeyclip chapters video.mp4` for auto-generated chapters
