---
phase: 22-ai-audio-enhancement
plan: 01
subsystem: audio
tags: [nim, ffmpeg, audio, http, multipart, toml, auto-detect]
requires:
  - phase: 21-ai-broll-integration
    provides: HttpClientLike/MockHttpClient seam, config.nim resolver pattern
provides:
  - FFmpeg allowlist with 9 Phase 22 audio filters (rebuilt)
  - HttpClientLike.postMultipart (base, Real, Mock)
  - resolveElevenlabsKey (env > TOML, never logged)
  - analyzeAudioForEnhancement with StageMode overrides
  - 6 audio fixtures and tests/unit_audio.nim wired into nimble test
affects: [22-02, 22-03, 22-04]
tech-stack:
  added: []
  patterns: [Goertzel band-level probe on FFmpeg-decoded PCM, mode-override-then-heuristic]
key-files:
  created:
    - src/analyze/audio_enhance.nim
    - tests/unit_audio.nim
    - tests/fixtures/audio_clean.wav
    - tests/fixtures/audio_noisy.wav
    - tests/fixtures/audio_hum_50hz.wav
    - tests/fixtures/audio_sibilant.wav
    - tests/fixtures/elevenlabs_isolator_response.bin
    - tests/fixtures/audio_stats.json
  modified:
    - honeyclip.nimble
    - src/http_client.nim
    - src/config.nim
key-decisions:
  - "Hum band levels via Goertzel on decoded PCM; noise floor via >8 kHz residual RMS (afftdn emits no metadata)"
  - "ffmpeg resolved from HONEYCLIP_FFMPEG, then build/ffmpeg(.exe), then PATH"
requirements-completed: [AUDIO-01, AUDIO-02, AUDIO-03]
duration: n/a
completed: 2026-10-24
---

# Phase 22 Plan 01: Audio Enhancement Foundations Summary

FFmpeg filter allowlist rebuilt with the 9 audio filters, plus a multipart HTTP seam, ElevenLabs key resolver, fixtures, and an auto-detect analyzer for hum, sibilance and noise.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 22-01-01 | 220ce23 | Filter allowlist (checkpoint, completed by orchestrator) |
| 22-01-02 | c69ace4 | postMultipart on HttpClientLike/Real/Mock, unit_audio wired into nimble test |
| 22-01-03 | 8c4d258 | 6 fixtures |
| 22-01-04 | 6bf6e2c | ElevenlabsSection + resolveElevenlabsKey |
| 22-01-05 | 058365b | audio_enhance.nim analyzer (also retunes the hum fixture) |

## Test results

- `tests/unit_audio`: 17/17 pass (http multipart 4, config 5, audio analyzer 8).
- `tests/unit_broll`: 62 OK, 0 failed.
- `tests/unit`: 357 OK, 1 FAILED: `generateChapters combined mode no deduplication`. Chapters code is untouched by this plan, so this looks pre-existing, but I did not confirm it against a clean checkout. Because `unit` runs first, `nimble test` exits non-zero before reaching unit_broll/unit_audio; those were run directly.

## Deviations from Plan

1. **[Task 1 verify] No ffmpeg CLI.** FFmpeg is configured with `--disable-programs`, so `./build/ffmpeg -filters` cannot work. All 9 filters were verified as symbols in `build/lib/libavfilter.a` via MinGW `nm` (9 matches).
2. **[Task 1 build fixes, outside plan]** x264 STRINGS pinned to MinGW binutils in honeyclip.nimble (Sysinternals strings.exe shadowed it). FFmpeg's Makefile and 7 ffbuild files had been deleted from ffmpeg_sources/ffmpeg and were restored from the 8.0.1 tarball. mingw32-make silently fails to write archive response files over cmd.exe's 8191-char limit, so libavcodec.a/libavformat.a were archived manually. **Follow-up:** not fixed in the nimble file.
3. **[Rule 3] Fixtures and analyzer use system ffmpeg, not `./build/ffmpeg`.** The winget ffmpeg 9.0 (gyan full build) generated fixtures. The analyzer resolves the binary from `HONEYCLIP_FFMPEG`, then `build/ffmpeg(.exe)`, then PATH. Since the in-tree build has no CLI, analyzer probes need a system ffmpeg at runtime until a later plan decides how audio processing is invoked (libav bindings vs. subprocess).
4. **[Rule 1] Existing http API differs from the plan interface.** `HttpResponse` is `(statusCode, body)` and `get`/`post` take no extraHeaders. Only `postMultipart` got `extraHeaders`; get/post were left alone. RealHttpClient clears headers after the call so the API key does not leak to later requests.
5. **[Rule 1] `.gitignore` ignores `*.bin`.** `elevenlabs_isolator_response.bin` was force-added (`git add -f`).
6. **[Rule 1] Analyzer probing redesigned.** The plan's `ametadata=print:file=<tmp>` path-with-colon is fragile on Windows, so `file=-` is used. astats exposes no 50/60 Hz band levels and `afftdn` emits no noise-floor metadata, so: hum band levels come from a Hann-windowed Goertzel on FFmpeg-decoded PCM; noise floor is the RMS of the >8 kHz residual (proxy), stored under `afftdn_noise_floor_dbfs`; sibilance uses `highpass=f=4000` RMS. Numeric stats are read from JSON numbers or strings (fixture file holds numbers).
7. **[Rule 1] Hum fixture retuned.** The plan's `volume=-30dB` hum landed at about -57 dBFS (lavfi `sine` default amplitude is 1/8), below the -50 dBFS detection threshold. Regenerated with `volume=-15dB` (about -42 dBFS) in commit 058365b.
8. `audio_clean.wav` is a fixed 440 Hz tone rather than a sweep; fixtures total about 2 MB, not under 200 KB. `elevenlabs_isolator_response.bin` is 8.6 KB MP3.
9. Task 22-01-02 test 3 asserts `lastHeaders` on the mock; test 1 uses inline bytes rather than the .bin fixture (created later in 22-01-03).

## Known Stubs

None. `deReverb` and `voiceIsolation` heuristics intentionally return false in the analyzer (provider-driven, Wave 2).

## Unverified

- `nimble test` end to end (blocked by the one failing `unit` test above).
- Linux/macOS branch of the nimble test task (only edited, not run).
- Real ElevenLabs multipart upload (RealHttpClient.postMultipart only compiled, never exercised against a server).

## Self-Check: PASSED
