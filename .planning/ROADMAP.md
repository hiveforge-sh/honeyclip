# Roadmap: honeyclip Engagement Analysis

## Overview

This roadmap transforms honeyclip from a silence removal tool into a comprehensive video engagement platform. Over 10 phases, we'll add ML-powered transcript extraction, multi-modal engagement scoring, speaker tracking with auto-reframing, and multi-aspect-ratio export with NLE integration. The journey starts by establishing build infrastructure for ML libraries, then progressively layers transcript features, face detection, engagement analysis, speaker reframing, and workflow polish. Each phase delivers verifiable user value while maintaining honeyclip's local-first, privacy-focused architecture.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation & Build Infrastructure** - ML library integration, FFI patterns, cross-platform builds
- [x] **Phase 2: Transcript Foundation** - Word-level timestamps, SRT/VTT export, speaker diarization
- [x] **Phase 3: Caption Rendering** - Burn captions into video, styling, NLE caption tracks
- [x] **Phase 4: Face Detection Infrastructure** - Face detection, adaptive sampling, caching layer
- [x] **Phase 5: Engagement Scoring Foundation** - Audio/motion/speech analysis, scoring algorithm
- [x] **Phase 6: Engagement Clip Detection** - Scene boundaries, ranking, batch export
- [x] **Phase 7: Speaker Tracking & Reframing** - Face tracking, ROI smoothing, vertical output
- [x] **Phase 8: Multi-Aspect Export & Workflow** - 16:9/9:16/1:1 export, previews, adjustments
- [ ] **Phase 9: NLE Integration & Markers** - Engagement markers, speaker markers, multi-format export
- [ ] **Phase 10: CLI Integration** - New subcommand, existing workflow integration, progress reporting

## Phase Details

### Phase 1: Foundation & Build Infrastructure
**Goal**: Establish cross-platform build system for ML libraries with FFI memory management patterns
**Depends on**: Nothing (first phase)
**Requirements**: None (foundational infrastructure)
**Success Criteria** (what must be TRUE):
  1. libfacedetection, ONNX Runtime, and OpenCV build successfully on Linux, macOS, and Windows via MinGW
  2. Binary size stays under 50MB per platform with static linking optimizations
  3. Nim FFI wrapper patterns with GC_ref/GC_unref established and documented
  4. Cross-platform CI validates builds and binary size limits
**Plans**: 5 plans

Plans:
- [x] 01-01-PLAN.md: ML library build infrastructure (libfacedetection, OpenCV, ONNX Runtime with caching)
- [x] 01-02-PLAN.md: Nim FFI wrappers for ML libraries (facedetect.nim, onnx.nim, opencv.nim)
- [x] 01-03-PLAN.md: Windows cross-compilation support (makemlwin task)
- [x] 01-04-PLAN.md: CI integration and unit tests (build validation, size checks)
- [x] 01-05-PLAN.md: Gap closure - ONNX Runtime static linking fix and build validation

### Phase 2: Transcript Foundation
**Goal**: Extract full transcripts with word-level timestamps and speaker identification
**Depends on**: Phase 1
**Requirements**: TRNS-01, TRNS-02, TRNS-03, TRNS-04
**Success Criteria** (what must be TRUE):
  1. User can extract word-level timestamps from video using existing whisper.cpp integration
  2. User can export transcript in SRT format with timestamps
  3. User can export transcript in VTT format with timestamps
  4. User can identify and label speakers in multi-speaker videos (speaker diarization)
**Plans**: 4 plans

Plans:
- [x] 02-01-PLAN.md: Transcript types and word-level extraction from whisper.cpp
- [x] 02-02-PLAN.md: SRT/VTT/JSON format exporters with caption grouping
- [x] 02-03-PLAN.md: Speaker diarization via pyannote.audio and nimpy
- [x] 02-04-PLAN.md: CLI `transcript` command integration

### Phase 3: Caption Rendering
**Goal**: Generate and render captions from transcripts with styling and NLE export
**Depends on**: Phase 2
**Requirements**: CAPT-01, CAPT-02, CAPT-03
**Success Criteria** (what must be TRUE):
  1. User can auto-generate captions from transcript output
  2. User can burn captions into video with customizable styling (font, size, position, color)
  3. User can export captions as separate editable track for NLE import
**Plans**: 5 plans

Plans:
- [x] 03-01-PLAN.md: Caption styling types, presets, and ASS file generation
- [x] 03-02-PLAN.md: FFmpeg filter integration for caption burning
- [x] 03-03-PLAN.md: NLE caption track export (FCP7, FCPXML)
- [x] 03-04-PLAN.md: CLI `caption` command with burn and export subcommands
- [x] 03-05-PLAN.md: Gap closure - Wire NLE export functions to CLI command

### Phase 4: Face Detection Infrastructure
**Goal**: Detect faces in video with adaptive frame sampling and persistent caching
**Depends on**: Phase 1
**Requirements**: SPKR-01
**Success Criteria** (what must be TRUE):
  1. User can detect faces in video frames with configurable confidence threshold
  2. Face detection uses adaptive frame sampling (1-5fps) based on scene changes to optimize CPU usage
  3. Face detection results are cached and reused across runs when input hasn't changed
  4. Multi-frame consensus reduces false positive rate below 15% on real-world video
**Plans**: 4 plans

Plans:
- [x] 04-01-PLAN.md: Core face detection types, consensus algorithm, and binary cache module
- [x] 04-02-PLAN.md: Adaptive frame sampling with scene change detection
- [x] 04-03-PLAN.md: Main faces() analysis function with caching integration
- [x] 04-04-PLAN.md: CLI cache management and unit tests

### Phase 5: Engagement Scoring Foundation
**Goal**: Analyze and score video segments using multi-modal signals (audio, motion, speech)
**Depends on**: Phase 2, Phase 4
**Requirements**: ENGR-01, ENGR-02, ENGR-03, ENGR-04
**Success Criteria** (what must be TRUE):
  1. User can analyze audio energy levels (RMS, dynamics, speech rate/pauses) from video
  2. User can analyze motion/visual activity levels (frame differences, scene changes) from video
  3. User can analyze speech features (rate, pauses, hooks) from transcript
  4. User sees combined engagement score (0-100) for video segments based on multi-modal signals
**Plans**: 4 plans

Plans:
- [x] 05-01-PLAN.md: Engagement types and percentile-based normalization
- [x] 05-02-PLAN.md: Hook detection (text patterns + audio prosody)
- [x] 05-03-PLAN.md: Main engagement scoring with signal combination
- [x] 05-04-PLAN.md: CLI `engage` command with JSON output

### Phase 6: Engagement Clip Detection
**Goal**: Automatically detect optimal clip boundaries and rank clips by engagement score for batch export
**Depends on**: Phase 5
**Requirements**: ENGR-05, ENGR-06, EXPRT-02
**Success Criteria** (what must be TRUE):
  1. User can detect scene boundaries that define natural clip segmentation points
  2. User sees clips ranked by engagement score from highest to lowest
  3. User can batch export multiple clips from single video based on engagement ranking
**Plans**: 4 plans

Plans:
- [x] 06-01-PLAN.md: Clip types and multi-signal boundary detection
- [x] 06-02-PLAN.md: CMX3600 EDL and JSON metadata export
- [x] 06-03-PLAN.md: Overlap-aware ranking and parallel batch export
- [x] 06-04-PLAN.md: CLI `clips` command with preview and export modes

### Phase 7: Speaker Tracking & Reframing
**Goal**: Track speakers across frames and auto-reframe video to center active speaker
**Depends on**: Phase 4, Phase 6
**Requirements**: SPKR-02, SPKR-03, SPKR-04
**Success Criteria** (what must be TRUE):
  1. User can track speakers across frames with persistent identity (same speaker = same ID throughout video)
  2. User can auto-reframe video to center the active speaker in each frame
  3. User can output vertical (9:16) video with speaker-centered framing
  4. Speaker reframing degrades gracefully to center crop when no faces detected
**Plans**: 6 plans

Plans:
- [x] 07-01-PLAN.md: Tracking types and Kalman filter for motion prediction
- [x] 07-02-PLAN.md: Face embeddings via ArcFace ONNX for re-identification
- [x] 07-03-PLAN.md: Hungarian algorithm and DeepSORT-style tracker
- [x] 07-04-PLAN.md: Cubic-bezier easing and crop region calculation
- [x] 07-05-PLAN.md: FFmpeg compositor for speaker-centered rendering
- [x] 07-06-PLAN.md: CLI `reframe` command with speed presets

### Phase 8: Multi-Aspect Export & Workflow
**Goal**: Export in multiple aspect ratios with preview and adjustment capabilities
**Depends on**: Phase 7
**Requirements**: EXPRT-01, EXPRT-03, EXPRT-04, EXPRT-05
**Success Criteria** (what must be TRUE):
  1. User can export video in multiple aspect ratios (16:9, 9:16, 1:1) from single source
  2. User can generate preview thumbnails before committing to full render
  3. User can adjust detected clip boundaries before final export
  4. User can run analysis-only mode that exports project file without rendering video
**Plans**: 5 plans

Plans:
- [x] 08-01-PLAN.md: Platform presets and project file infrastructure
- [x] 08-02-PLAN.md: Preview generation (thumbnails and video snippets)
- [x] 08-03-PLAN.md: Multi-aspect parallel export
- [x] 08-04-PLAN.md: Clip boundary adjustment with version history
- [x] 08-05-PLAN.md: CLI `export` command integration

### Phase 9: NLE Integration & Markers
**Goal**: Export to NLE formats with engagement and speaker markers
**Depends on**: Phase 6, Phase 8
**Requirements**: NLE-01, NLE-02, NLE-03, NLE-04, NLE-05, NLE-06, NLE-07
**Success Criteria** (what must be TRUE):
  1. User can export to Adobe Premiere (FCP7 XML with markers)
  2. User can export to After Effects (FCP7 XML or AAF)
  3. User can export to DaVinci Resolve (FCP7 XML, AAF, or EDL)
  4. User can export to Final Cut Pro (FCPXML with markers)
  5. User sees engagement markers at scene boundaries and engagement peaks in NLE timeline
  6. User sees speaker change markers in NLE timeline
  7. User can export engagement scores as text/graphic layer in NLE project
**Plans**: 7 plans

Plans:
- [ ] 09-01-PLAN.md — Marker data structures and factory functions
- [ ] 09-02-PLAN.md — FCP7 XML marker export (Adobe Premiere)
- [ ] 09-03-PLAN.md — FCPXML marker export (Final Cut Pro X)
- [ ] 09-04-PLAN.md — EDL marker export (DaVinci Resolve)
- [ ] 09-05-PLAN.md — AAF export via pyaaf2 (After Effects)
- [ ] 09-06-PLAN.md — Score visualization rendering (graph + text overlays)
- [ ] 09-07-PLAN.md — CLI integration (--nle flag for export command)

### Phase 10: CLI Integration
**Goal**: Integrate engagement analysis into CLI with new subcommand and progress reporting
**Depends on**: Phase 9
**Requirements**: CLI-01, CLI-02, CLI-03
**Success Criteria** (what must be TRUE):
  1. User can invoke engagement analysis workflow via new subcommand (e.g., `honeyclip engage`)
  2. User can integrate engagement analysis with existing honeyclip edit workflow via flags
  3. User sees real-time progress reporting during analysis (transcript extraction, face detection, scoring)
**Plans**: TBD

Plans:
- [ ] 10-01-PLAN.md: TBD during phase planning

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Build Infrastructure | 5/5 | Complete | 2026-02-01 |
| 2. Transcript Foundation | 4/4 | Complete | 2026-02-02 |
| 3. Caption Rendering | 5/5 | Complete | 2026-02-02 |
| 4. Face Detection Infrastructure | 4/4 | Complete | 2026-02-02 |
| 5. Engagement Scoring Foundation | 4/4 | Complete | 2026-02-02 |
| 6. Engagement Clip Detection | 4/4 | Complete | 2026-02-02 |
| 7. Speaker Tracking & Reframing | 6/6 | Complete | 2026-02-03 |
| 8. Multi-Aspect Export & Workflow | 5/5 | Complete | 2026-02-03 |
| 9. NLE Integration & Markers | 0/7 | Planned | - |
| 10. CLI Integration | 0/TBD | Not started | - |
