# honeyclip — Engagement Analysis

## What This Is

A content intelligence layer for honeyclip that extracts transcripts, scores engagement levels, detects optimal clip boundaries, and auto-reframes speakers for vertical output. Turns long-form videos into actionable insights and short-form-ready segments using local-only processing.

## Core Value

Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.

## Requirements

### Validated

<!-- v1.0 Engagement Analysis (shipped 2026-02-04) -->

- ✓ Extract full transcript with timestamps (SRT output) — v1.0
- ✓ Score segments by engagement level (audio energy + motion + speech content) — v1.0
- ✓ Detect optimal clip boundaries for high-engagement segments — v1.0
- ✓ Track and identify speakers/faces via ML — v1.0
- ✓ Auto-reframe video to center active speaker (vertical output) — v1.0
- ✓ New subcommands for analysis workflow (engage, clips, transcript, caption, reframe) — v1.0
- ✓ Integration with existing edit workflow via --engage flag — v1.0
- ✓ Export to NLE formats (FCP7, FCPXML, EDL, AAF with markers) — v1.0
- ✓ Multi-aspect export (16:9, 9:16, 1:1) with platform presets — v1.0
- ✓ Progress reporting during analysis — v1.0

<!-- v1.1 Polish (shipped 2026-02-05) -->

- ✓ ML library size optimization (MinSizeRel, stripping) — v1.1
- ✓ Custom hook patterns via JSON schema — v1.1
- ✓ Tracker test coverage (80% per-module threshold) — v1.1
- ✓ Media metadata management (templates, standalone command) — v1.1

<!-- Existing capabilities from original codebase -->

- ✓ Open and process media files via FFmpeg — existing
- ✓ Analyze audio levels for silence detection — existing
- ✓ Analyze video for motion/visual changes — existing
- ✓ Extract and process subtitles — existing
- ✓ Build timeline-based clip sequences — existing
- ✓ Export to NLE formats (FCP7, FCP11, Shotcut, Kdenlive, JSON) — existing
- ✓ Render processed video/audio — existing
- ✓ Speech-to-text via whisper.cpp — existing
- ✓ Cross-platform support (Linux, macOS, Windows) — existing

### Active

<!-- Next milestone scope TBD -->

(None — all v1.x requirements shipped. Define new requirements for v2.0.)

### Out of Scope

- Cloud API calls for engagement scoring — want local-only processing
- Historical performance data / virality prediction — no training data available
- Real-time processing — batch processing is fine
- Mobile app — CLI tool only
- Natural language search — requires embedding infrastructure
- Emotion detection from facial expressions — model complexity
- Voice tone/sentiment analysis — model complexity

## Context

**Current State (v1.1 shipped 2026-02-05):**

honeyclip is a Nim CLI tool that builds FFmpeg from source and processes video. The engagement analysis milestone (v1.0) added:

- ML library build infrastructure (libfacedetection, OpenCV, ONNX Runtime)
- Full transcript extraction with word-level timestamps
- Multi-modal engagement scoring (audio, motion, speech, faces, hooks)
- Speaker tracking with Kalman filter + Hungarian algorithm
- Auto-reframing with cubic-bezier easing
- Multi-aspect export with platform presets
- NLE integration with engagement/speaker markers

The polish milestone (v1.1) addressed tech debt:

- ML library size optimization (MinSizeRel, symbol stripping)
- Custom hook patterns via JSON schema
- Tracker test coverage (62 tests, 80% enforcement)
- Media metadata management (templates, standalone command)

**Codebase:**
- ~21,500 lines of Nim
- 58 plans executed across 14 phases
- Cross-platform: Linux, macOS, Windows (ML features stubbed on Windows)

## Constraints

- **Stack**: Must remain Nim + FFmpeg — no Node.js or Python in core runtime
- **Processing**: Local-only — no cloud API dependencies for core features
- **Output**: SRT format for transcript/engagement annotations
- **Face Detection**: ML libraries (libfacedetection, OpenCV, ONNX Runtime)
- **Platform**: Must maintain cross-platform support (Linux, macOS, Windows)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Local signals for engagement | No cloud dependencies, faster processing, works offline | ✓ Good — shipped in v1.0 |
| SRT output format | Standard format, works with all video editors | ✓ Good — shipped in v1.0 |
| Face detection via ML | Motion-only tracking insufficient for speaker centering | ✓ Good — shipped in v1.0 |
| Percentile normalization | Outlier robustness for engagement scoring | ✓ Good — shipped in v1.0 |
| Multi-frame consensus | Reduces face detection false positives | ✓ Good — shipped in v1.0 |
| ASS subtitle format | Advanced styling and karaoke support for captions | ✓ Good — shipped in v1.0 |
| Kalman + Hungarian tracking | DeepSORT-style tracking without neural network overhead | ✓ Good — shipped in v1.0 |
| MinSizeRel for ML libs | Reduces binary size 15-25% vs Release | ✓ Good — shipped in v1.1 |
| JSON schema for hooks | User extensibility without code changes | ✓ Good — shipped in v1.1 |
| Per-module coverage threshold | Ensures no module drags down average | ✓ Good — shipped in v1.1 |

---
*Last updated: 2026-02-05 after v1.1 milestone*
