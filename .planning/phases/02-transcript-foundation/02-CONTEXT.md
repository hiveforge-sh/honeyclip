# Phase 2: Transcript Foundation - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract full transcripts with word-level timestamps and speaker identification from video using existing whisper.cpp integration. Export to SRT, VTT, and JSON formats. Identify and label speakers in multi-speaker videos via diarization.

Caption rendering and engagement scoring are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Output Format
- Generate both SRT and VTT by default (not separate exports)
- Also export JSON with word-level timestamps and confidence scores
- Millisecond precision for timestamps (00:01:23,456)
- Mark low-confidence words with [?] marker in output
- Mark non-speech audio as [music] or [noise]
- Mark significant pauses with [pause] marker
- Enforce maximum line length for captions (~42 chars broadcast standard), configurable via --max-chars
- Backup existing files to .bak before overwriting (no silent overwrite)
- Default output to same directory as input, -o flag to override
- --dry-run mode to preview transcript without writing files
- --stdout option to output to terminal (requires --format flag to specify type)
- --compact flag for minified JSON (default is pretty-printed)

### Speaker Labeling
- Speaker names can be remapped via JSON mapping file after transcription
- VTT speaker colors available via --speaker-colors flag (off by default)
- Speaker labels appear on speaker change only (not every line)

### Whisper Integration
- Auto-detect language by default, --language flag to override
- Support all model sizes (tiny, base, small, medium, large)
- Prompt user before downloading missing models ("Model not found, download? [y/n]")

### Multi-Speaker Handling
- Label uncertain speaker segments as "Unknown" when diarization fails
- --single-speaker flag to disable diarization for known single-speaker videos
- Support up to 10 speakers (panel discussions, meetings)

### Claude's Discretion
- Word grouping strategy for captions (sentence vs time window vs word count)
- Character encoding details (UTF-8 with/without BOM)
- File naming pattern (extension-only vs timestamped)
- VTT style hints inclusion
- JSON structure (flat word list vs hierarchical segments)
- Speaker label format (Speaker 1, SPEAKER_00, or letter codes)
- Exact position of speaker labels in caption text
- Overlapping speech handling strategy

</decisions>

<specifics>
## Specific Ideas

- JSON output should include per-word confidence scores for downstream engagement scoring
- Pause markers are important for engagement scoring (speech rate analysis)
- [music] markers help identify non-speech segments that might still be engaging

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-transcript-foundation*
*Context gathered: 2026-02-01*
