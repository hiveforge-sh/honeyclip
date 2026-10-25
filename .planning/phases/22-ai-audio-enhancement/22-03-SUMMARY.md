---
phase: 22-ai-audio-enhancement
plan: 03
subsystem: audio
tags: [nim, ffmpeg, audio, subprocess, cli, loudnorm, chunking]
requires:
  - phase: 22-02
    provides: AudioProvider variant, DeepFilterNet and ElevenLabs backends, cost gate
provides:
  - src/audio/ffmpeg_chain.nim (hum, de-ess, two-pass loudnorm, resample, MP3 decode, chunking, crossfade)
  - src/audio/render.nim (video mux, audio-only writer)
  - AudioProvider.enhance() dispatch
  - honeyclip enhance subcommand (main.nim and cli.nim)
affects: [22-04]
tech-stack:
  added: []
  patterns: [pure command builders next to executors, FFmpeg banner parsing for probing, name-based subcommand dispatch]
key-files:
  created:
    - src/audio/ffmpeg_chain.nim
    - src/audio/render.nim
    - src/cmds/enhance.nim
    - tests/fixtures/audio_44k_stereo.wav
  modified:
    - src/audio/provider.nim
    - src/analyze/audio_enhance.nim
    - src/main.nim
    - src/cli.nim
    - tests/unit_audio.nim
key-decisions:
  - "Added an apFfmpeg provider kind (--backend=ffmpeg): afftdn + hum/de-ess + loudnorm, no neural model, so the chain works with no DeepFilterNet and no API key"
  - "ffmpegBin exported from audio_enhance and reused; probeAudio parses the ffmpeg banner because there is no ffprobe"
  - "Subcommand dispatch looks handlers up by name"
requirements-completed: []
duration: n/a
completed: 2026-10-24
---

# Phase 22 Plan 03: FFmpeg Chain, Dispatch and `honeyclip enhance` Summary

File-path FFmpeg chain (hum notch, de-ess, two-pass loudnorm, 48k mono resample and restore, MP3 decode, silence-bounded chunking with crossfade), `AudioProvider.enhance()` dispatch with cost-gate-before-HTTP, and the `honeyclip enhance` subcommand registered in main.nim and cli.nim.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 22-03-01 | 0137fc6 | ffmpeg_chain.nim (also covers chunkAtSilence/reassembleWithCrossfade from 22-03-02) |
| 22-03-02 and 22-03-03 | 63cb26f | render.nim, enhance() dispatch, apFfmpeg, 44.1k stereo fixture, dispatch + resample contract suites and chain tests |
| 22-03-04 | 8bda668 | enhance.nim, main.nim and cli.nim registration, dispatch fix, "cli enhance" suite |

Tests for tasks 01-03 share tests/unit_audio.nim and landed in 63cb26f.

## Test results

Built with the choosenim MinGW gcc.

- `tests/unit_audio`: 77 OK, 0 failed, 1 skipped (apLocal end-to-end, DeepFilterNet not installed).
- `tests/unit_broll`: 62 OK, 0 failed.
- `tests/unit` (built with the nimble feature flags `-d:enable_vpx -d:enable_svtav1 -d:enable_hevc -d:enable_whisper`; without them it fails to link x265): 409 OK, 1 FAILED, the pre-existing `generateChapters combined mode no deduplication`. The count differs from the 357 baseline given in the brief; I count `[OK]` lines in the output, and I did not investigate the difference. The only failure is the known one.
- `nimble test` was not run end to end (stops at the pre-existing unit failure).

## Binary build and smoke runs

- `nimble make`: exit 0, binary rebuilt twice (4m22s, then 8m24s while tests ran in parallel).
- `./honeyclip enhance --help`: prints help, exit 0. `./honeyclip --help` lists `enhance`.
- Fixture: `ffmpeg -f lavfi -i testsrc=duration=3:size=320x240:rate=15 -i tests/fixtures/audio_noisy.wav -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac smoke.mp4`
- `./honeyclip enhance smoke.mp4 --backend=ffmpeg` -> rc 0, `smoke.enhanced.mp4` with h264 video copied and AAC 48 kHz stereo audio.
- `./honeyclip enhance smoke.mp4 --backend=ffmpeg --audio-only -o a.wav -q` -> rc 0, 48 kHz stereo WAV, 2.99s, integrated loudness -16.0 LUFS (ebur128).
- `./honeyclip enhance smoke.mp4 --backend ffmpeg --denoise=on --hum-removal=on --de-ess=on` -> rc 0.
- `./honeyclip enhance tests/fixtures/audio_noisy.wav --backend=ffmpeg -o n.wav` -> rc 0 (audio input).
- `./honeyclip enhance smoke.mp4` (auto, nothing installed) -> rc 1 with the "No audio backend available" remediation text.
- Used the system ffmpeg 9.0 on PATH; there is no build/ffmpeg.

## Deviations from Plan

1. **[Rule 1] ffmpeg binary.** The plan hardcodes `./build/ffmpeg`. All code uses `ffmpegBin()` (HONEYCLIP_FFMPEG, build/ffmpeg(.exe), PATH), which I made public in audio_enhance.nim. Commands are built from `quoteShell(ffmpegBin())`.
2. **[Rule 3] apFfmpeg backend.** The orchestrator required an FFmpeg-chain-only path, but `resolveProvider("auto")` raises without DeepFilterNet or a key. Added `apFfmpeg` (selected only by `--backend=ffmpeg`; `auto` behavior and its error message are unchanged). It applies `afftdn=nf=-25` when denoise is on. Plan-listed help text gains the `ffmpeg` backend.
3. **[Rule 1] No ffprobe.** `probeAudio` parses the `ffmpeg -i` banner (rate, channels, duration). Tests use it instead of ffprobe greps.
4. **[Rule 1] Mux audio codec.** `-c:v copy` alone cannot put PCM into MP4. `buildMuxCmd` adds `-c:a aac -b:a 192k` for .mp4/.m4v/.mov/.m4a outputs; the `-c:v copy` and `-map 0:v -map 1:a` parts are as planned.
5. **[Rule 1] `main` signature.** Handlers in main.nim are `proc(args: seq[string])`, so `enhance.main` returns void and quits on nonzero; `run(args): int` holds the logic. `parseArgs` returns `(opts, code)` with an added `helpShown` flag so `--help` stops cleanly with code 0.
6. **[Rule 1] Option parsing.** `parseopt` did not take a separate value for `-o PATH`/`--flag value`; arguments for value-taking flags are joined to `flag=value` before parsing. Both forms work.
7. **[Rule 1] Pre-existing dispatch bug fixed.** main.nim paired `commands` (cli.nim, 16 entries) and `cmdHandlers` (18 entries, includes chapters and preview) positionally with `zip`, so `enhance` would have run the `engage` handler. Dispatch now iterates `commands` and finds the handler by name. This also corrects the pairing for the other commands after `caption`.
8. **Chunking parallelism.** Plan says chunks are processed in parallel; chunks run sequentially (simpler, shares one backend and avoids rate limits). Trigger is duration > 3600s or file > 500 MB, chunk length 600s; both overridable through `enhance()` parameters for tests. chunkAtSilence takes an optional `chunkDir`.
9. **Backend gating.** apLocal skips DeepFilterNet when denoise is off; apElevenlabs skips the API (and the cost gate) when neither denoise nor voiceIsolation is on. Hum/de-ess stages are skipped when both flags are off; loudnorm always runs. Silent input (loudnorm measures `-inf`) is copied through instead of failing.
10. **Extras.** `AudioResult` gained an `err` field. `runAfftdn` added. Default output is `{input}.enhanced.{ext}` (`.wav` for audio inputs or `--audio-only`). The CLI TTY check is `isatty(stdin) and isatty(stdout)`. The CLI removes its temp output dir on exit.
11. **Task merging.** chunkAtSilence/reassembleWithCrossfade were written in the 22-03-01 file (same module); task 22-03-03 needed no new code, only tests and the 44.1 kHz fixture. Test 4 of the resample contract uses the apFfmpeg backend with `keepTmp=true` rather than apLocal, so it runs without DeepFilterNet.
12. **Quirk, not fixed.** When tests/unit_audio output is redirected to a file the log truncates after the analyzer suite (exit code 0); counts above come from a pipe. Cause not investigated.

## Known Stubs

None.

## Threat checks

- T-22-03: every path and filter string in ffmpeg_chain.nim and render.nim goes through `quoteShell`; a unit test covers paths with spaces and `&`/`;`.
- T-22-04: `confirmElevenlabsCost` runs before any HTTP call; the denial test asserts zero mock calls. CLI plumbs `--yes` and TTY detection.
- T-22-05: temp dir `outDir.tmp` removed by `defer` unless `keepTmp`; the CLI also removes its output dir.
- T-22-02: the API key is only passed to `elevenlabsIsolate`; enhance.nim never prints it.

## Unverified

- DeepFilterNet path (apLocal) end to end: not installed here, test skipped.
- Real ElevenLabs request (mock only).
- Chunking on a genuinely long file (>1h); tested with 30s files and lowered thresholds.
- Linux/macOS build.
- Hum notch effectiveness is not measured; the hum/de-ess run is checked for success only.

## Self-Check: PASSED
