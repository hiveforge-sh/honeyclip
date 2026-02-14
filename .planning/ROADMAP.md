# Roadmap: honeyclip Engagement Analysis

## Overview

honeyclip transforms long-form video into engagement-analyzed content with transcript extraction, multi-modal scoring, speaker tracking, and auto-reframing. v1.0 delivered the core engagement platform (Phases 1-10), v1.1 closed tech debt (Phases 11-14), and v2.0 adds workflow automation, AI features, and social publishing (Phases 15-24).

## Milestones

- ✅ **v1.0 Engagement Analysis** — Phases 1-10 (shipped 2026-02-04)
- ✅ **v1.1 Polish** — Phases 11-14 (shipped 2026-02-05)
- 📋 **v2.0 Workflow, Performance & AI Features** — Phases 15-24 (in progress)

## Phases

<details>
<summary>✅ v1.0 Engagement Analysis (Phases 1-10) — SHIPPED 2026-02-04</summary>

- [x] Phase 1: Foundation & Build Infrastructure (5/5 plans) — completed 2026-02-01
- [x] Phase 2: Transcript Foundation (4/4 plans) — completed 2026-02-02
- [x] Phase 3: Caption Rendering (5/5 plans) — completed 2026-02-02
- [x] Phase 4: Face Detection Infrastructure (4/4 plans) — completed 2026-02-02
- [x] Phase 5: Engagement Scoring Foundation (4/4 plans) — completed 2026-02-02
- [x] Phase 6: Engagement Clip Detection (4/4 plans) — completed 2026-02-02
- [x] Phase 7: Speaker Tracking & Reframing (6/6 plans) — completed 2026-02-03
- [x] Phase 8: Multi-Aspect Export & Workflow (5/5 plans) — completed 2026-02-03
- [x] Phase 9: NLE Integration & Markers (7/7 plans) — completed 2026-02-03
- [x] Phase 10: CLI Integration (5/5 plans) — completed 2026-02-04

**Full details:** `.planning/milestones/v1.0-ROADMAP.md`

</details>

<details>
<summary>✅ v1.1 Polish (Phases 11-14) — SHIPPED 2026-02-05</summary>

- [x] Phase 11: ML Library Size Optimization (2/2 plans) — completed 2026-02-05
- [x] Phase 12: Custom Hook Patterns (2/2 plans) — completed 2026-02-05
- [x] Phase 13: Tracker Test Coverage (3/3 plans) — completed 2026-02-05
- [x] Phase 14: Media Metadata Management (3/3 plans) — completed 2026-02-05

**Full details:** `.planning/milestones/v1.1-ROADMAP.md`

</details>

### 📋 v2.0 Workflow, Performance & AI Features (Phases 15-24)

Batch processing, GPU acceleration, AI features, and social publishing.

---

#### Phase 15: Performance Foundation ✅

**Goal:** Users can process 4K+ videos with GPU acceleration without OOM crashes

**Dependencies:** None (foundational)

**Requirements:** GPU-01, GPU-02, GPU-03, MEM-01, MEM-02

**Plans:** 3/3 complete

Plans:
- [x] 15-01-PLAN.md -- GPU runtime detection + ONNX execution provider support
- [x] 15-02-PLAN.md -- Frame buffer pooling + bounded decode queue
- [x] 15-03-PLAN.md -- Unit tests for GPU runtime and buffer pool

**Completed:** 2026-02-13

**Success Criteria:**
1. ✓ User can run face detection with CUDA on Linux without manual configuration
2. ✓ User can run face detection with Metal on macOS without manual configuration
3. ✓ System automatically falls back to CPU when GPU is unavailable (no crashes)
4. ✓ User can process 4K videos without out-of-memory errors
5. ✓ Memory usage remains bounded regardless of input file size

---

#### Phase 16: Batch Processing Foundation ✅

**Goal:** Users can process entire folders with templates and resume failed jobs

**Dependencies:** None (but enables Phase 19)

**Requirements:** BATCH-01, BATCH-02, BATCH-03, BATCH-04, BATCH-05

**Plans:** 3/3 complete

Plans:
- [x] 16-01-PLAN.md -- TOML template parsing, file discovery, batch command skeleton
- [x] 16-02-PLAN.md -- Checkpoint/resume system, parallel runner, progress tracking
- [x] 16-03-PLAN.md -- Unit tests for batch processing modules

**Completed:** 2026-02-14

**Success Criteria:**
1. ✓ User can create TOML template file with processing settings
2. ✓ User can run single command to process entire folder with template
3. ✓ User sees progress reporting (file X/N, percentage, ETA) during batch processing
4. ✓ User can resume failed batch job without reprocessing completed files
5. ✓ Batch processing automatically utilizes multiple CPU cores in parallel

---

#### Phase 17: Virality Scoring ✅

**Goal:** Users see quantified virality scores for each detected clip

**Dependencies:** None (extends existing engagement analysis)

**Requirements:** VIRAL-01, VIRAL-02, VIRAL-03

**Plans:** 3/3 complete

Plans:
- [x] 17-01-PLAN.md -- Virality types, component calculation, and ranking by virality score
- [x] 17-02-PLAN.md -- CLI output, JSON/EDL export, and project file virality fields
- [x] 17-03-PLAN.md -- Unit tests for virality scoring calculations

**Completed:** 2026-02-14

**Success Criteria:**
1. ✓ User sees engagement score (0-100) for each detected clip in output
2. ✓ User sees score breakdown showing hook, flow, value, and trend components
3. ✓ Clips are automatically sorted by virality score in output (highest first)

---

#### Phase 18: Chapter Detection

**Goal:** Users can auto-generate chapters from scene changes and engagement peaks

**Dependencies:** Phase 17 (uses engagement scores for peak detection)

**Requirements:** CHAP-01, CHAP-02, CHAP-03, CHAP-04

**Success Criteria:**
1. User can auto-detect chapter boundaries from scene changes
2. User can generate chapters at high-engagement peaks
3. User can export chapters as MP4 metadata (FFmpeg format)
4. User can export chapters as NLE markers (FCP, Premiere, Resolve)

---

#### Phase 19: Brand Templates

**Goal:** Users can apply consistent branding across all batch-processed videos

**Dependencies:** Phase 16 (applies in batch processing)

**Requirements:** BRAND-01, BRAND-02, BRAND-03, BRAND-04

**Success Criteria:**
1. User can define brand template with logo watermark position
2. User can define intro/outro clips to prepend/append
3. User can save caption styling presets (font, color, position)
4. Brand template applies consistently across all files in batch processing

---

#### Phase 20: Preview Generation

**Goal:** Users can generate 720p proxy previews faster than realtime

**Dependencies:** None (independent utility)

**Requirements:** PREV-01, PREV-02

**Success Criteria:**
1. User can generate 720p proxy preview of any input video
2. Preview generation runs at 2-3x realtime speed (faster than playback)

---

#### Phase 21: AI B-Roll Integration

**Goal:** Users can auto-insert generated B-roll at detected timeline points

**Dependencies:** None (independent AI feature)

**Requirements:** BROLL-01, BROLL-02, BROLL-03, BROLL-04

**Success Criteria:**
1. User can auto-detect B-roll insertion points in timeline
2. User can generate B-roll locally via ComfyUI integration
3. User can generate B-roll via API (Gemini or similar) when configured
4. Generated B-roll automatically inserts at detected points without manual editing

---

#### Phase 22: AI Audio Enhancement

**Goal:** Users can enhance audio quality with local models or API fallback

**Dependencies:** None (independent AI feature)

**Requirements:** AUDIO-01, AUDIO-02, AUDIO-03

**Success Criteria:**
1. User can enhance audio quality (noise reduction, normalization) with single flag
2. Audio enhancement works with local models when available
3. Audio enhancement falls back to API (ElevenLabs/Artlist) when configured and local unavailable

---

#### Phase 23: AI Voice-over

**Goal:** Users can generate voice-over narration from transcript text

**Dependencies:** None (independent AI feature)

**Requirements:** VOICE-01, VOICE-02, VOICE-03

**Success Criteria:**
1. User can generate voice-over narration from text or transcript
2. Voice-over uses local TTS engine by default
3. User can select voice style/model for generation via CLI flag

---

#### Phase 24: Social Posting

**Goal:** Users can upload clips directly to social platforms with scheduling

**Dependencies:** All previous phases (operates on final output)

**Requirements:** SOCIAL-01, SOCIAL-02, SOCIAL-03, SOCIAL-04, SOCIAL-05

**Success Criteria:**
1. User can upload clips directly to YouTube via API authentication
2. User can upload clips directly to TikTok via API authentication
3. User can upload clips directly to Instagram Reels via API authentication
4. User can schedule posts for future publishing (date/time)
5. Upload includes metadata (title, description, tags) from batch template

---

## Progress

**Execution Order:**
- v1.0: Phases 1-10 (complete)
- v1.1: Phases 11-14 (complete)
- v2.0: Phases 15-24 (in progress)

| Milestone | Phases | Plans | Status | Shipped |
|-----------|--------|-------|--------|---------|
| v1.0 Engagement Analysis | 1-10 | 48 | Complete | 2026-02-04 |
| v1.1 Polish | 11-14 | 10 | Complete | 2026-02-05 |
| v2.0 Workflow, Performance & AI Features | 15-24 | 9 | Phase 17 complete | TBD |
| **Total** | **24** | **67** | **In Progress** | — |

---
*Roadmap updated: 2026-02-14 after Phase 17 execution*
