---
phase: 22-ai-audio-enhancement
plan: 04
subsystem: audio
tags: [python, e2e, docs, audio, http-mock]
requires:
  - phase: 22-03
    provides: honeyclip enhance subcommand, ffmpeg chain, providers
provides:
  - tests/test_audio.py (14-test standalone E2E, no PyAV needed)
  - tests/test.py runs test_audio.py after the B-roll E2E
  - README "Audio Enhancement" section
  - HONEYCLIP_ELEVENLABS_URL endpoint override
  - fix for postMultipart sending bytes as a file path
affects: [phase-22-verification]
tech-stack:
  added: []
  patterns: [localhost HTTP mock via env endpoint override, stub df.enhance module on PYTHONPATH plus python3 shim on PATH]
key-files:
  created:
    - tests/test_audio.py
  modified:
    - tests/test.py
    - README.md
    - src/audio/elevenlabs.nim
    - src/http_client.nim
key-decisions:
  - "E2E probes outputs with ffmpeg banner parsing instead of PyAV, so it runs with no pip packages"
  - "ElevenLabs endpoint overridable via HONEYCLIP_ELEVENLABS_URL (default unchanged)"
requirements-completed: []
duration: n/a
completed: 2026-10-24
---

# Phase 22 Plan 04: E2E Harness and README Summary

Standalone E2E for `honeyclip enhance` (stubbed DeepFilterNet, localhost ElevenLabs mock, cost gate enforced from outside), wired into tests/test.py, plus the README Audio Enhancement section; the E2E exposed and fixed a real multipart upload bug.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| fix | aaa7fff | postMultipart: `useStream = false` |
| feat | c2d6991 | `HONEYCLIP_ELEVENLABS_URL` override |
| 22-04-01 | e765ed3 | tests/test_audio.py (14 tests), wired into tests/test.py |
| 22-04-02 | dc6e234 | README Audio Enhancement section, Features bullet |

## Test results

- `python tests/test_audio.py`: Ran 14 tests, OK (0 skipped). Covers help, unknown flag, bad stage mode, missing input, `--backend=local` with stub DeepFilterNet (default `.enhanced.mp4`, video kept, 48 kHz audio), `--audio-only`, `--backend=elevenlabs` against the mock (checks path `/v1/audio-isolation/stream`, `xi-api-key`, key not echoed), auto prefers local when available, auto fallback to ElevenLabs, no-backend error text, `--backend=ffmpeg`, cost-gate denial on an 11-minute input (exit non-zero, zero mock requests, no output file), `--yes` bypass (one request), `--denoise=off --voice-isolation=off` (zero requests).
- `tests/test.py`: PyAV is not installed on the system Python, so it cannot import. I created a throwaway venv outside the repo (`pip install av`, 19.0.2) and ran `python tests/test.py --no-failfast` from the repo root: main suite Completed 40/50; 10 failures: test_backwards_range, test_example, test_cut_out, test_audio_norm_ebu, test_to_mono, test_scale, test_wav_output, test_video_to_mp3, test_margin, test_resolution. These exercise non-enhance commands; I did not confirm whether they fail on a clean pre-Phase-22 checkout. Without `--no-failfast` the run stops at test_backwards_range ("Timeline is empty") and never reaches the Phase 21/22 steps. With `--no-failfast` the B-roll E2E (4 tests, 1 skipped) and the Phase 22 E2E (14 tests) both ran and passed, and the script exited 0.
- Nim sources changed, so `nimble make` was re-run twice (about 4.5 min each); both succeeded. Nim unit suites were not re-run.

## Deviations from Plan

1. **[Rule 1] PyAV not used in test_audio.py.** Not installed here; output properties (rate, duration, video present) come from parsing `ffmpeg -i`, with the same ffmpeg resolution as the binary. Runs standalone.
2. **[Rule 1/3] HTTP mock needs an endpoint override.** elevenlabs.nim hardcoded the base URL. Added `elevenlabsBaseUrl()` reading `HONEYCLIP_ELEVENLABS_URL` (trailing slashes trimmed); default is the real API. The override is undocumented in the README by design (test seam).
3. **[Rule 1] Bug found by the E2E: multipart upload.** `RealHttpClient.postMultipart` used `MultipartData.add(..., filename)` with the default `useStream = true`, which makes Nim treat the content as a file path; the real upload failed with a Windows "filename syntax" error carrying the WAV bytes. It only passed before because tests used the mock client. Fixed with `useStream = false` (commit aaa7fff). This was the first real HTTP exercise of 22-01's postMultipart.
4. **[Rule 1] Stub DeepFilterNet.** The binary picks `python3` first, which on this machine is the Windows Store alias. The test prepends a temp dir with a `python3` shim (`.cmd` on Windows) to PATH and puts a stub `df/enhance.py` on PYTHONPATH; `python -m df.enhance -o DIR FILE` copies the input. Real DeepFilterNet is still untested here.
5. **Tests pass `--denoise=on` for API/local cases.** With `auto`, the analyzer judges a clean tone as not needing denoise and the backend is skipped (documented in 22-03 deviation 9), so a bare `--backend=elevenlabs` makes no call. The README states this.
6. **Plan tests adjusted.** Plan's `test_audio_only_local_path`/`test_video_default_output_path` skipped without DeepFilterNet; they now run via the stub. `test_cost_gate_non_tty` uses a 660 s 16 kHz sine instead of `anullsrc` (silence skips the backend's work). The plan's 5-stage "voice-isolation → de-reverb" prose in the README was replaced with what is implemented (voice isolation/de-reverb are never auto-selected; chain is denoise, hum, de-ess, loudnorm).
7. The README documents the system-ffmpeg requirement, the `ffmpeg` backend, exit codes, and that `HONEYCLIP_ELEVENLABS_URL` is not part of the public interface. It does not list DeepFilterNet "~10 s per minute" (unmeasured).

## Known Stubs

None.

## Threat checks

- T-22-04: cost gate verified from outside the Nim seam: no request reaches the mock when denied; `--yes` sends exactly one.
- T-22-02: README recommends `chmod 600` for config.toml and shows no real key; E2E asserts the key is not printed.

## Unverified

- Real DeepFilterNet run and real ElevenLabs API (mock only; the mock returns the 8.6 KB MP3 fixture).
- Whether the 10 main-suite failures in tests/test.py pre-date Phase 22.
- Linux/macOS: the `python3` shim branch of test_audio.py was not run.
- `nimble test` and Nim unit suites after the http_client/elevenlabs edits.

## Self-Check: PASSED
