# Requirements: honeyclip v2.0

**Defined:** 2026-02-05
**Core Value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.

## v2.0 Requirements

Requirements for v2.0 major release. Full OpusClip feature parity with local-first AI and optional social publishing.

### Batch Processing

- [ ] **BATCH-01**: User can create TOML template files defining processing settings
- [ ] **BATCH-02**: User can process entire folder with single command using template
- [ ] **BATCH-03**: User sees progress reporting (file X/N, percentage, ETA)
- [ ] **BATCH-04**: User can resume failed batch jobs without reprocessing completed files
- [ ] **BATCH-05**: Batch processing utilizes multiple CPU cores in parallel

### Chapter Detection

- [ ] **CHAP-01**: User can auto-detect chapter boundaries from scene changes
- [ ] **CHAP-02**: User can generate chapters at high-engagement peaks
- [ ] **CHAP-03**: User can export chapters as MP4 metadata
- [ ] **CHAP-04**: User can export chapters as NLE markers (FCP, Premiere, etc.)

### Preview Generation

- [ ] **PREV-01**: User can generate 720p proxy preview of any video
- [ ] **PREV-02**: Preview generation runs 2-3x faster than realtime

### GPU Acceleration

- [ ] **GPU-01**: Face detection uses CUDA on Linux when available
- [ ] **GPU-02**: Face detection uses Metal on macOS when available
- [ ] **GPU-03**: System automatically falls back to CPU when GPU unavailable

### Memory Optimization

- [ ] **MEM-01**: Frame buffer pooling prevents allocation overhead for 4K+ content
- [ ] **MEM-02**: Bounded decode queue prevents OOM on large files

### Virality Score

- [ ] **VIRAL-01**: User sees engagement score (0-100) for each detected clip
- [ ] **VIRAL-02**: Score breakdown shows hook, flow, value, trend components
- [ ] **VIRAL-03**: Clips are sorted/ranked by virality score in output

### Brand Templates

- [ ] **BRAND-01**: User can define brand template with logo watermark position
- [ ] **BRAND-02**: User can define intro/outro clips to prepend/append
- [ ] **BRAND-03**: User can save caption styling presets (font, color, position)
- [ ] **BRAND-04**: Brand template applies consistently across batch processing

### AI B-Roll

- [ ] **BROLL-01**: User can auto-detect B-roll insertion points in timeline
- [ ] **BROLL-02**: User can generate B-roll locally via ComfyUI integration
- [ ] **BROLL-03**: User can generate B-roll via API (Gemini or similar)
- [ ] **BROLL-04**: Generated B-roll auto-inserts at detected points

### AI Audio Enhancement

- [ ] **AUDIO-01**: User can enhance audio quality (noise reduction, normalization)
- [ ] **AUDIO-02**: Audio enhancement works with local models when available
- [ ] **AUDIO-03**: Audio enhancement falls back to API (ElevenLabs/Artlist) when configured

### AI Voice-over

- [ ] **VOICE-01**: User can generate voice-over narration from text/transcript
- [ ] **VOICE-02**: Voice-over uses local TTS engine
- [ ] **VOICE-03**: User can select voice style/model for generation

### Social Posting

- [ ] **SOCIAL-01**: User can upload clips directly to YouTube via API
- [ ] **SOCIAL-02**: User can upload clips directly to TikTok via API
- [ ] **SOCIAL-03**: User can upload clips directly to Instagram Reels via API
- [ ] **SOCIAL-04**: User can schedule posts for future publishing
- [ ] **SOCIAL-05**: Upload includes metadata (title, description, tags) from template

## Future Requirements

Deferred to post-v2.0. Tracked but not in current roadmap.

### Advanced AI

- **ADV-01**: Natural language clip search ("find moments where speaker mentions X")
- **ADV-02**: Emotion detection from facial expressions
- **ADV-03**: Voice tone/sentiment analysis
- **ADV-04**: Folder watch mode (auto-process new files)

### Collaboration

- **COLLAB-01**: Team workspace for shared projects
- **COLLAB-02**: Project sharing/export

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Cloud engagement scoring | Core analysis must remain local-only |
| Historical virality prediction | No training data available |
| Real-time processing | Batch processing sufficient |
| Mobile app | CLI tool only |
| GUI wrapper | CLI-first, users wanting GUI use NLEs |
| Distributed batch processing | Single-machine only, users can orchestrate externally |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BATCH-01 | TBD | Pending |
| BATCH-02 | TBD | Pending |
| BATCH-03 | TBD | Pending |
| BATCH-04 | TBD | Pending |
| BATCH-05 | TBD | Pending |
| CHAP-01 | TBD | Pending |
| CHAP-02 | TBD | Pending |
| CHAP-03 | TBD | Pending |
| CHAP-04 | TBD | Pending |
| PREV-01 | TBD | Pending |
| PREV-02 | TBD | Pending |
| GPU-01 | TBD | Pending |
| GPU-02 | TBD | Pending |
| GPU-03 | TBD | Pending |
| MEM-01 | TBD | Pending |
| MEM-02 | TBD | Pending |
| VIRAL-01 | TBD | Pending |
| VIRAL-02 | TBD | Pending |
| VIRAL-03 | TBD | Pending |
| BRAND-01 | TBD | Pending |
| BRAND-02 | TBD | Pending |
| BRAND-03 | TBD | Pending |
| BRAND-04 | TBD | Pending |
| BROLL-01 | TBD | Pending |
| BROLL-02 | TBD | Pending |
| BROLL-03 | TBD | Pending |
| BROLL-04 | TBD | Pending |
| AUDIO-01 | TBD | Pending |
| AUDIO-02 | TBD | Pending |
| AUDIO-03 | TBD | Pending |
| VOICE-01 | TBD | Pending |
| VOICE-02 | TBD | Pending |
| VOICE-03 | TBD | Pending |
| SOCIAL-01 | TBD | Pending |
| SOCIAL-02 | TBD | Pending |
| SOCIAL-03 | TBD | Pending |
| SOCIAL-04 | TBD | Pending |
| SOCIAL-05 | TBD | Pending |

**Coverage:**
- v2.0 requirements: 38 total
- Mapped to phases: 0
- Unmapped: 38

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-05 after initial definition*
