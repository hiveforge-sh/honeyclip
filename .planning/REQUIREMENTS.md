# Requirements: Auto-Editor Engagement Analysis

**Defined:** 2026-02-01
**Core Value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Transcript

- [ ] **TRNS-01**: Extract full transcript with word-level timestamps
- [ ] **TRNS-02**: Export transcript in SRT format
- [ ] **TRNS-03**: Export transcript in VTT format
- [ ] **TRNS-04**: Identify and label speakers (speaker diarization)

### Captions

- [ ] **CAPT-01**: Generate auto-captions from transcript
- [ ] **CAPT-02**: Burn captions into video with styling
- [ ] **CAPT-03**: Export captions as separate editable track for NLEs

### Engagement Scoring

- [ ] **ENGR-01**: Analyze audio energy (RMS, dynamics, pace)
- [ ] **ENGR-02**: Analyze motion/visual activity (frame differences)
- [ ] **ENGR-03**: Analyze speech features (rate, pauses, hooks)
- [ ] **ENGR-04**: Combine signals into engagement score (0-100)
- [ ] **ENGR-05**: Detect scene boundaries for clip segmentation
- [ ] **ENGR-06**: Rank clips by engagement score

### Speaker Tracking

- [ ] **SPKR-01**: Detect faces in video frames
- [ ] **SPKR-02**: Track speaker across frames (persistent identity)
- [ ] **SPKR-03**: Auto-reframe video to center active speaker
- [ ] **SPKR-04**: Output vertical (9:16) video with speaker centered

### Export & Workflow

- [ ] **EXPRT-01**: Export in multiple aspect ratios (16:9, 9:16, 1:1)
- [ ] **EXPRT-02**: Batch export multiple clips from single video
- [ ] **EXPRT-03**: Generate preview thumbnails before full render
- [ ] **EXPRT-04**: Allow clip boundary adjustments after detection
- [ ] **EXPRT-05**: Analysis-only mode (export project, skip video render)

### NLE Integration

- [ ] **NLE-01**: Export to Adobe Premiere (FCP7 XML with markers)
- [ ] **NLE-02**: Export to After Effects (FCP7 XML or AAF)
- [ ] **NLE-03**: Export to DaVinci Resolve (FCP7 XML, AAF, or EDL)
- [ ] **NLE-04**: Export to Final Cut Pro (FCPXML with markers)
- [ ] **NLE-05**: Include engagement markers at scene boundaries and peaks
- [ ] **NLE-06**: Include speaker change markers
- [ ] **NLE-07**: Export engagement scores as text/graphic layer

### CLI & Interface

- [ ] **CLI-01**: New subcommand for engagement analysis workflow
- [ ] **CLI-02**: Integration with existing auto-editor edit workflow
- [ ] **CLI-03**: Progress reporting during analysis

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
| TRNS-01 | TBD | Pending |
| TRNS-02 | TBD | Pending |
| TRNS-03 | TBD | Pending |
| TRNS-04 | TBD | Pending |
| CAPT-01 | TBD | Pending |
| CAPT-02 | TBD | Pending |
| CAPT-03 | TBD | Pending |
| ENGR-01 | TBD | Pending |
| ENGR-02 | TBD | Pending |
| ENGR-03 | TBD | Pending |
| ENGR-04 | TBD | Pending |
| ENGR-05 | TBD | Pending |
| ENGR-06 | TBD | Pending |
| SPKR-01 | TBD | Pending |
| SPKR-02 | TBD | Pending |
| SPKR-03 | TBD | Pending |
| SPKR-04 | TBD | Pending |
| EXPRT-01 | TBD | Pending |
| EXPRT-02 | TBD | Pending |
| EXPRT-03 | TBD | Pending |
| EXPRT-04 | TBD | Pending |
| EXPRT-05 | TBD | Pending |
| NLE-01 | TBD | Pending |
| NLE-02 | TBD | Pending |
| NLE-03 | TBD | Pending |
| NLE-04 | TBD | Pending |
| NLE-05 | TBD | Pending |
| NLE-06 | TBD | Pending |
| NLE-07 | TBD | Pending |
| CLI-01 | TBD | Pending |
| CLI-02 | TBD | Pending |
| CLI-03 | TBD | Pending |

**Coverage:**
- v1 requirements: 32 total
- Mapped to phases: 0
- Unmapped: 32 (pending roadmap creation)

---
*Requirements defined: 2026-02-01*
*Last updated: 2026-02-01 after initial definition*
