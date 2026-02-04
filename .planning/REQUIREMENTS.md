# Requirements: honeyclip Engagement Analysis

**Defined:** 2026-02-01
**Core Value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Transcript

- [x] **TRNS-01**: Extract full transcript with word-level timestamps
- [x] **TRNS-02**: Export transcript in SRT format
- [x] **TRNS-03**: Export transcript in VTT format
- [x] **TRNS-04**: Identify and label speakers (speaker diarization)

### Captions

- [x] **CAPT-01**: Generate auto-captions from transcript
- [x] **CAPT-02**: Burn captions into video with styling
- [x] **CAPT-03**: Export captions as separate editable track for NLEs

### Engagement Scoring

- [x] **ENGR-01**: Analyze audio energy (RMS, dynamics, pace)
- [x] **ENGR-02**: Analyze motion/visual activity (frame differences)
- [x] **ENGR-03**: Analyze speech features (rate, pauses, hooks)
- [x] **ENGR-04**: Combine signals into engagement score (0-100)
- [x] **ENGR-05**: Detect scene boundaries for clip segmentation
- [x] **ENGR-06**: Rank clips by engagement score

### Speaker Tracking

- [x] **SPKR-01**: Detect faces in video frames
- [x] **SPKR-02**: Track speaker across frames (persistent identity)
- [x] **SPKR-03**: Auto-reframe video to center active speaker
- [x] **SPKR-04**: Output vertical (9:16) video with speaker centered

### Export & Workflow

- [x] **EXPRT-01**: Export in multiple aspect ratios (16:9, 9:16, 1:1)
- [x] **EXPRT-02**: Batch export multiple clips from single video
- [x] **EXPRT-03**: Generate preview thumbnails before full render
- [x] **EXPRT-04**: Allow clip boundary adjustments after detection
- [x] **EXPRT-05**: Analysis-only mode (export project, skip video render)

### NLE Integration

- [x] **NLE-01**: Export to Adobe Premiere (FCP7 XML with markers)
- [x] **NLE-02**: Export to After Effects (FCP7 XML or AAF)
- [x] **NLE-03**: Export to DaVinci Resolve (FCP7 XML, AAF, or EDL)
- [x] **NLE-04**: Export to Final Cut Pro (FCPXML with markers)
- [x] **NLE-05**: Include engagement markers at scene boundaries and peaks
- [x] **NLE-06**: Include speaker change markers
- [x] **NLE-07**: Export engagement scores as text/graphic layer

### CLI & Interface

- [x] **CLI-01**: New subcommand for engagement analysis workflow
- [x] **CLI-02**: Integration with existing honeyclip edit workflow
- [x] **CLI-03**: Progress reporting during analysis

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Analysis

- **ADV-01**: Natural language search ("find moments about topic X")
- **ADV-02**: Emotion detection from facial expressions
- **ADV-03**: Voice tone/sentiment analysis
- **ADV-04**: GPU-accelerated optical flow motion detection
- **ADV-05**: Custom engagement scoring weights (user-configurable)

### Enhanced Workflow

- **WKF-01**: Clip editing UI (visual adjustment interface)
- **WKF-02**: Export templates per platform (TikTok, YouTube Shorts, etc.)
- **WKF-03**: B-roll insertion point suggestions

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Cloud API calls for engagement scoring | Privacy-first, local-only processing is core differentiator |
| Virality prediction from platform data | No access to TikTok/YouTube performance data |
| B-roll generation/fetching | Requires stock library licensing, adds complexity |
| Social media auto-posting | Platform APIs unstable, dedicated tools exist |
| Real-time/live stream processing | Different architecture, niche use case |
| Collaborative/multi-user editing | Requires cloud infrastructure, kills local-first |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRNS-01 | Phase 2 | Complete |
| TRNS-02 | Phase 2 | Complete |
| TRNS-03 | Phase 2 | Complete |
| TRNS-04 | Phase 2 | Complete |
| CAPT-01 | Phase 3 | Complete |
| CAPT-02 | Phase 3 | Complete |
| CAPT-03 | Phase 3 | Complete |
| ENGR-01 | Phase 5 | Complete |
| ENGR-02 | Phase 5 | Complete |
| ENGR-03 | Phase 5 | Complete |
| ENGR-04 | Phase 5 | Complete |
| ENGR-05 | Phase 6 | Complete |
| ENGR-06 | Phase 6 | Complete |
| SPKR-01 | Phase 4 | Complete |
| SPKR-02 | Phase 7 | Complete |
| SPKR-03 | Phase 7 | Complete |
| SPKR-04 | Phase 7 | Complete |
| EXPRT-01 | Phase 8 | Complete |
| EXPRT-02 | Phase 6 | Complete |
| EXPRT-03 | Phase 8 | Complete |
| EXPRT-04 | Phase 8 | Complete |
| EXPRT-05 | Phase 8 | Complete |
| NLE-01 | Phase 9 | Complete |
| NLE-02 | Phase 9 | Complete |
| NLE-03 | Phase 9 | Complete |
| NLE-04 | Phase 9 | Complete |
| NLE-05 | Phase 9 | Complete |
| NLE-06 | Phase 9 | Complete |
| NLE-07 | Phase 9 | Complete |
| CLI-01 | Phase 10 | Complete |
| CLI-02 | Phase 10 | Complete |
| CLI-03 | Phase 10 | Complete |

**Coverage:**
- v1 requirements: 32 total
- Mapped to phases: 32
- Unmapped: 0 (100% coverage)

---
*Requirements defined: 2026-02-01*
*Last updated: 2026-02-04 after Phase 10 completion*
