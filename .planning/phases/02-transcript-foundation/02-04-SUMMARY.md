---
phase: 02
plan: 04
subsystem: transcript-cli
tags: [cli, command, transcript, whisper, diarization, srt, vtt, json]
requires:
  - 02-01 (types, extract)
  - 02-02 (grouping, formats)
  - 02-03 (diarization)
provides:
  - transcript CLI command
  - full transcript extraction workflow
affects:
  - phase 03 (engagement scoring may use transcript output)
  - phase 10 (pipeline integration will use transcript command)
tech-stack:
  added: []
  patterns: [command-subcommand-pattern]
key-files:
  created:
    - src/cmds/transcript.nim
  modified:
    - src/main.nim
    - src/cli.nim
    - tests/unit.nim
decisions:
  - Prompt for model download if missing (user-friendly)
  - Output all three formats by default (SRT, VTT, JSON)
  - Backup files use .bak extension (overwrite existing backup)
  - countSpeakers uses int8 set for efficiency
metrics:
  duration: 4min
  completed: 2026-02-02
---

# Phase 02 Plan 04: Transcript Command Summary

**One-liner:** CLI command integrating extraction, diarization, grouping, and export into unified workflow

## What Was Built

### src/cmds/transcript.nim (263 lines)
The main transcript command implementation providing user-facing CLI.

**CLI Options:**
- `-o, --output DIR` - Output directory (default: same as input)
- `--format FORMAT` - Output format for --stdout (srt, vtt, json)
- `--max-chars NUM` - Max characters per caption line (default: 42)
- `--single-speaker` - Skip speaker diarization
- `--speaker-map FILE` - JSON file mapping speaker IDs to names
- `--speaker-colors` - Enable VTT speaker colors
- `--language LANG` - Override language detection
- `--vad-model PATH` - VAD model for whisper
- `--confidence NUM` - Confidence threshold for [?] markers (default: 0.5)
- `--compact` - Minified JSON output
- `--dry-run` - Preview transcript without writing files
- `--stdout` - Output to terminal (requires --format)
- `--no-backup` - Don't create .bak files when overwriting

**Workflow:**
1. Parse arguments and validate inputs
2. Check if model exists, prompt for download if missing
3. Load speaker map if provided
4. Extract transcript via whisper with word timestamps
5. Run diarization unless --single-speaker
6. Group into captions with char limit
7. Export to SRT/VTT/JSON or stdout

**Helper Functions:**
- `countSpeakers(transcript)` - Count unique speakers (excluding -1)
- `createBackup(filePath)` - Create .bak backup before overwriting
- `generateOutputPath(input, outputDir, ext)` - Build output file path

### src/main.nim Changes
- Added transcript import: `import cmds/[..., transcript, ...]`
- Registered handler: `("transcript", transcript.main)`

### src/cli.nim Changes
- Added command description: `("transcript", "Extract transcript with word timestamps, speaker diarization, export to SRT/VTT/JSON")`

### tests/unit.nim Additions (91 lines)
- `transcript-countSpeakers` - Test with multiple speakers
- `transcript-countSpeakers-unassigned` - Test with all -1
- `transcript-createBackup` - Test backup creation and overwrite
- `transcript-createBackup-nonexistent` - Test with missing file
- `transcript-generateOutputPath` - Test path generation

## Key Links Verified

| From | To | Via | Pattern |
|------|----|-----|---------|
| src/cmds/transcript.nim | src/transcript/extract.nim | extractTranscript call | extractTranscript |
| src/cmds/transcript.nim | src/transcript/formats.nim | export calls | exportSRT, exportVTT, exportJSON |
| src/cmds/transcript.nim | src/transcript/diarization.nim | diarizeAudio call | diarizeAudio |
| src/main.nim | src/cmds/transcript.nim | command registration | transcript.main |

## Decisions Made

1. **Model download prompt** - When model file not found, prompt user with download URL rather than silently failing
2. **Default output = all formats** - Without --stdout, generate SRT + VTT + JSON simultaneously for maximum compatibility
3. **Backup with .bak extension** - Simple one-level backup, overwrite existing .bak on subsequent runs
4. **countSpeakers uses int8 set** - Efficient for up to 128 speakers (more than enough for any realistic use case)

## Deviations from Plan

None - plan executed exactly as written.

## Test Results

All syntax checks pass:
- `nim check --hints:off -d:nimpy src/cmds/transcript.nim` - OK
- `nim check --hints:off -d:nimpy src/main.nim` - OK (with unrelated deprecation warning)
- `nim check --hints:off -d:nimpy tests/unit.nim` - OK

Note: Full E2E testing requires FFmpeg build which is documented in STATE.md as existing blocker.

## Artifacts

| Artifact | Location |
|----------|----------|
| Transcript command | src/cmds/transcript.nim |
| Command registration | src/main.nim |
| CLI description | src/cli.nim |
| Unit tests | tests/unit.nim |

## Next Phase Readiness

Phase 02 (Transcript Foundation) is now complete with all 4 plans executed:
- 02-01: Types and extraction
- 02-02: Grouping and formats
- 02-03: Speaker diarization
- 02-04: CLI command (this plan)

The transcript system is ready for integration with engagement scoring (Phase 03).
