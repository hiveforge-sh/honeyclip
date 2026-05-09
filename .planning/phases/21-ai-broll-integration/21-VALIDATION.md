---
phase: 21
slug: ai-broll-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-08
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Nim `unittest` (stdlib) + Python E2E (`tests/test.py`) |
| **Config file** | `honeyclip.nimble` (test target) |
| **Quick run command** | `nimble test` |
| **Full suite command** | `nimble test && python3 tests/test.py` |
| **Estimated runtime** | ~30 seconds (unit) / ~3 min (full) |

---

## Sampling Rate

- **After every task commit:** Run `nimble test`
- **After every plan wave:** Run `nimble test && python3 tests/test.py`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds for unit tests

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 0 | BROLL-01..04 | T-21-01 | HTTP client abstraction (HttpClientLike) — enables mocking, prevents real network calls in tests | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-01-02 | 01 | 0 | BROLL-01..04 | — | Transcript fixture + marker JSON snapshot harness | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-01-03 | 01 | 1 | BROLL-01 | — | Topic-shift detector (segment-boundary + pause + engagement-delta) | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-01-04 | 01 | 1 | BROLL-02..03 | T-21-02 | `src/config.nim` — TOML parse, env var override, never-log secret | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-01-05 | 01 | 1 | BROLL-01 | — | Insertion-point selection (density + min-spacing) | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-01 | 02 | 2 | BROLL-02 | T-21-03 | ComfyUI provider — workflow placeholder substitution + HTTP submit/poll | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-02 | 02 | 2 | BROLL-03 | T-21-04 | Veo provider — async LRO polling + 8s output handling + cost pre-flight | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-03 | 02 | 2 | BROLL-03 | — | Gemini Flash prompt-rewrite client | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-04 | 02 | 3 | BROLL-04 | — | Duration fitting (truncate / freeze-pad / speed-ramp) | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-05 | 02 | 3 | BROLL-02..03 | — | Provider selection + auto-fallback (ComfyUI unreachable → Veo) | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-06 | 02 | 3 | BROLL-04 | — | `--render` mux subprocess (concat demuxer + audio underlay) | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-02-07 | 02 | 3 | BROLL-01..04 | — | `honeyclip broll` CLI subcommand wiring | unit | `nimble test` | ❌ W0 | ⬜ pending |
| 21-03-01 | 03 | 4 | BROLL-01..04 | — | E2E marker JSON snapshot + audio-sync smoke check | e2e | `python3 tests/test.py` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/unit_broll.nim` — test module compiled into `nimble test` target
- [ ] `tests/fixtures/broll_transcript.json` — synthetic transcript with engagement scores + segment boundaries
- [ ] `tests/fixtures/comfyui_workflow.json` — minimal ComfyUI workflow with `{{PROMPT}}`/`{{SEED}}`/`{{LENGTH}}` placeholders
- [ ] `tests/fixtures/veo_lro_response.json` — captured Veo long-running-operation responses (in-progress + completed)
- [ ] `src/http_client.nim` — `HttpClientLike` interface (real impl + mock impl) so providers are testable without network
- [ ] `tests/test_broll.py` — Python E2E harness extending `tests/test.py` for marker-JSON output and audio-sync check

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real ComfyUI generation against running server | BROLL-02 | External service (user-running ComfyUI on 127.0.0.1:8188); not reproducible in CI | Run `honeyclip broll input.mp4 --backend comfyui --workflow workflow.json --render` against a known ComfyUI install; verify `out.mp4` plays with B-roll inserts at marker times |
| Real Veo generation via API | BROLL-03 | Costs real money (~$1.20-$3.20/clip); requires `GEMINI_API_KEY` | With `GEMINI_API_KEY` set: `honeyclip broll input.mp4 --backend veo --max-broll 1 --render`; confirm 8s clip, marker JSON, mux output |
| Auto-fallback (ComfyUI down → Veo) | BROLL-02..03 | Requires real network behavior with one provider unreachable | Set ComfyUI URL to closed port + valid GEMINI_API_KEY; run with default backend; confirm Veo fallback engages |
| Cost pre-flight prompt UX | BROLL-03 | Interactive TTY prompt; CI is non-TTY | Run Veo command interactively; confirm cost estimate displayed and accept/decline gate works (and `--yes` bypasses) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s for unit tests
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
