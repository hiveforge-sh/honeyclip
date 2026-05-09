---
phase: 22
slug: ai-audio-enhancement
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-09
---

# Phase 22 — Validation Strategy

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
| 22-01-01 | 01 | 0 | AUDIO-01..03 | T-22-00 | FFmpeg filter allowlist updated (deesser, highpass, equalizer, afftdn, astats, ametadata, anullsink); `nimble makeff` re-run; `nimble test` passes | manual+unit | `nimble makeff && nimble test` | ❌ W0 | ⬜ pending |
| 22-01-02 | 01 | 0 | AUDIO-01..03 | T-22-01 | `HttpClientLike.postMultipart` extension for ElevenLabs file upload | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-01-03 | 01 | 0 | AUDIO-01..03 | — | Audio fixtures + DeepFilterNet stub harness | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-01-04 | 01 | 1 | AUDIO-03 | T-22-02 | `src/config.nim` extended with `resolveElevenlabsKey` (env-first, TOML `[elevenlabs]` fallback, never log secret) | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-01-05 | 01 | 1 | AUDIO-01 | — | Auto-detect analyzer: hum (50/60Hz narrowband), de-ess (sibilance ratio), noise-floor (afftdn probe) | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-01 | 02 | 2 | AUDIO-02 | T-22-03 | DeepFilterNet local provider: `whichDeepFilter` detection + subprocess invocation contract | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-02 | 02 | 2 | AUDIO-03 | T-22-04 | ElevenLabs Voice Isolator client: multipart upload + sync response + cost gate | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-03 | 02 | 2 | AUDIO-02..03 | — | `AudioProvider` object variant + auto-fallback (DeepFilterNet absent → ElevenLabs when key set) | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-04 | 02 | 3 | AUDIO-01 | — | FFmpeg chain orchestrator: hum-removal · de-ess · loudnorm (file-path subprocess; not in-process) | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-05 | 02 | 3 | AUDIO-01 | — | Long-file chunking + crossfade reassembly for ElevenLabs (file-size limit) | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-06 | 02 | 3 | AUDIO-01 | — | Resample to 48kHz mono (DeepFilterNet input), restore source rate/channels for final mux | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-02-07 | 02 | 3 | AUDIO-01..03 | — | `honeyclip enhance` CLI: arg parsing, --backend/--{stage}/--audio-only/--yes flags, video out vs --audio-only | unit | `nim c -r --path:src tests/unit_audio.nim` | ❌ W0 | ⬜ pending |
| 22-03-01 | 03 | 4 | AUDIO-01..03 | — | E2E harness: enhance subcommand against fixture audio with DeepFilterNet stub + ElevenLabs HTTP mock | e2e | `python3 tests/test_audio.py` | ❌ W0 | ⬜ pending |
| 22-03-02 | 03 | 4 | AUDIO-01..03 | — | README "Audio Enhancement" section: setup, ElevenLabs cost, DeepFilterNet install, --audio-only docs | manual | `grep -cE "Audio Enhancement\|ELEVENLABS_API_KEY\|deepfilternet" README.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `honeyclip.nimble` FFmpeg filter allowlist updated (deesser, highpass, equalizer, afftdn, astats, ametadata, anullsink) AND `nimble makeff` re-run successfully
- [ ] `tests/unit_audio.nim` — test module compiled into `nimble test` target
- [ ] `tests/fixtures/audio_clean.wav` — clean speech, 48kHz mono PCM, ~5s
- [ ] `tests/fixtures/audio_noisy.wav` — speech + AC hum + keyboard, 48kHz stereo PCM, ~5s
- [ ] `tests/fixtures/audio_hum_50hz.wav` — speech + 50Hz tone, ~3s (for hum detection unit test)
- [ ] `tests/fixtures/audio_sibilant.wav` — speech with strong sibilance, ~3s (for de-ess detection)
- [ ] `tests/fixtures/elevenlabs_isolator_response.bin` — captured ElevenLabs API response bytes (success path)
- [ ] `src/http_client.nim` — extended with `postMultipart` proc on `HttpClientLike`
- [ ] `tests/test_audio.py` — Python E2E harness extending `tests/test.py`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real DeepFilterNet enhancement | AUDIO-02 | Requires `pip install deepfilternet`; CPU-bound, ~10s for 5s clip | `pip install deepfilternet; honeyclip enhance noisy.mp4 --backend local`; verify enhanced.mp4 is audibly cleaner |
| Real ElevenLabs API isolation | AUDIO-03 | Costs real money (~$0.10/min × audio duration); requires `ELEVENLABS_API_KEY` | With key set: `honeyclip enhance test.mp4 --backend elevenlabs --yes`; verify enhanced.mp4 has isolated speech |
| Auto-fallback (DeepFilterNet absent → ElevenLabs) | AUDIO-02..03 | Requires uninstalling deepfilternet + valid ELEVENLABS_API_KEY | Without `df` on path + with key set: `honeyclip enhance file.mp4`; confirm ElevenLabs path engages with cost prompt |
| Cost pre-flight prompt UX | AUDIO-03 | Interactive TTY; CI is non-TTY | Run on >5min file interactively (cost > $1); confirm prompt shown, accept/decline gate works, `--yes` bypasses |
| Auto-detect on real audio | AUDIO-01 | Heuristic thresholds need real-audio validation | Run on 3 fixtures (clean / noisy / hum-only); verify analyzer's stage selection matches expectations |
| Long-file chunking on >1hr input | AUDIO-01 | File-size limits trigger only on hour-long inputs | `honeyclip enhance hourlong.mp4 --backend elevenlabs --yes`; verify chunked uploads + clean reassembly without audible boundaries |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s for unit tests
- [ ] FFmpeg filter allowlist regression-tested (deesser etc. present in built binary)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
