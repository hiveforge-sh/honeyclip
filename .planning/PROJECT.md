# honeyclip — Engagement Analysis

## What This Is

A content intelligence layer for honeyclip that extracts transcripts, scores engagement levels, detects optimal clip boundaries, and auto-reframes speakers for vertical output. Turns long-form videos into actionable insights and short-form-ready segments using local-only processing.

## Core Value

Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.

## Requirements

### Validated

<!-- Existing capabilities from current codebase -->

- ✓ Open and process media files via FFmpeg — existing
- ✓ Analyze audio levels for silence detection — existing
- ✓ Analyze video for motion/visual changes — existing
- ✓ Extract and process subtitles — existing
- ✓ Build timeline-based clip sequences — existing
- ✓ Export to NLE formats (FCP7, FCP11, Shotcut, Kdenlive, JSON) — existing
- ✓ Render processed video/audio — existing
- ✓ Speech-to-text via whisper.cpp — existing (detection, not full transcript)
- ✓ Cross-platform support (Linux, macOS, Windows) — existing

### Active

<!-- New capabilities to build -->

- [x] Extract full transcript with timestamps (SRT output) — `transcript` command
- [x] Score segments by engagement level (audio energy + motion + speech content) — `engage` command
- [x] Detect optimal clip boundaries for high-engagement segments — `clips` command
- [x] Track and identify speakers/faces via ML — face detection infrastructure complete
- [ ] Auto-reframe video to center active speaker (vertical output) — `reframe` command (Phase 7 in progress)
- [x] New subcommand for analysis workflow — `engage`, `clips`, `transcript`, `caption` commands
- [ ] Integration with existing edit workflow — Phase 10

### Out of Scope

- Cloud API calls for engagement scoring — want local-only processing
- Historical performance data / virality prediction — no training data available
- Real-time processing — batch processing is fine
- Mobile app — CLI tool only

## Context

honeyclip is a Nim CLI tool (forked from honeyclip) that builds FFmpeg from source and processes video to remove silent sections. The codebase already has:

- Whisper.cpp integration (currently used for speech detection, not transcript extraction)
- Audio analysis infrastructure (`src/analyze/audio.nim`)
- Motion detection infrastructure (`src/analyze/motion.nim`)
- Modular analysis pipeline with filter graphs
- Export system supporting multiple NLE formats

The engagement analysis features build on this foundation, extending whisper output to full transcripts, combining existing audio/motion analysis into engagement scores, and adding new face detection capability for speaker reframing.

Reference: OpusClip's feature set (transcript + virality scoring + auto-clipping + speaker reframing) as inspiration, but implemented with local-only signals.

## Constraints

- **Stack**: Must remain Nim + FFmpeg — no Node.js or Python in core runtime
- **Processing**: Local-only — no cloud API dependencies for core features
- **Output**: SRT format for transcript/engagement annotations
- **Face Detection**: Will require ML library integration (OpenCV, MediaPipe, or similar)
- **Platform**: Must maintain cross-platform support (Linux, macOS, Windows)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Local signals for engagement | No cloud dependencies, faster processing, works offline | Implemented in Phase 5 |
| SRT output format | Standard format, works with all video editors | Implemented in Phase 2 |
| Face detection via ML | Motion-only tracking insufficient for speaker centering | Implemented in Phase 4 |
| New subcommand + integration | Flexibility for standalone use and pipeline integration | Phases 2-6 complete |
| Percentile normalization | Outlier robustness for engagement scoring | Implemented in Phase 5 |
| Multi-frame consensus | Reduces face detection false positives | Implemented in Phase 4 |
| ASS subtitle format | Advanced styling and karaoke support for captions | Implemented in Phase 3 |

---
*Last updated: 2026-02-03 — Phases 1-6 complete, Phase 7 in progress*
