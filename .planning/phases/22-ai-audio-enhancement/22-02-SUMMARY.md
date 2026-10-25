---
phase: 22-ai-audio-enhancement
plan: 02
subsystem: audio
tags: [nim, audio, deepfilternet, elevenlabs, http, multipart, provider]
requires:
  - phase: 22-01
    provides: postMultipart seam, resolveElevenlabsKey, audio analyzer
provides:
  - src/audio/deepfilter.nim (detection, command builder, runDeepFilter)
  - src/audio/elevenlabs.nim (Voice Isolator client, cost gate)
  - src/audio/provider.nim (AudioProvider variant, resolveProvider with auto-fallback)
affects: [22-03, 22-04]
tech-stack:
  added: []
  patterns: [injectable availability flag for deterministic provider tests, pure command builder separated from execution]
key-files:
  created:
    - src/audio/deepfilter.nim
    - src/audio/elevenlabs.nim
    - src/audio/provider.nim
  modified:
    - tests/unit_audio.nim
key-decisions:
  - "resolveProvider has a 3-arg core overload taking dfAvailable so tests need no DeepFilterNet"
  - "Python interpreter chosen as python3 else python (Windows has no python3 by default)"
requirements-completed: []
duration: n/a
completed: 2026-10-24
---

# Phase 22 Plan 02: Providers and AudioProvider Summary

DeepFilterNet local provider, ElevenLabs Voice Isolator client with cost gate, and an AudioProvider variant with auto-fallback; enhance() dispatch is left to 22-03.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 22-02-01 | 330da49 | deepfilter.nim |
| 22-02-02 | a8755af | elevenlabs.nim |
| 22-02-03 | edb5495 | provider.nim plus all Wave 2 tests (shared tests/unit_audio.nim, so tests for all three tasks are in this commit) |

## Test results

- `tests/unit_audio`: 44/44 pass (22-01: 17; new: deepfilter 6, elevenlabs cost 7, elevenlabs provider 5, provider selection 9).
- `tests/unit_broll`: 62 OK, 0 failed.
- `tests/unit`: not re-run (pre-existing chapters failure per orchestrator).
- Built with the choosenim MinGW gcc (`--gcc.exe`), as the nimble task does; the default PATH gcc is broken on this machine.

## Deviations from Plan

1. **[Rule 1] Python interpreter.** Plan hardcodes `python3`; `deepfilter.nim` uses `python3` if found, else `python` (Windows).
2. **[Rule 1] Testability.** Added `buildDeepFilterCmd` (pure) so command quoting is tested without DeepFilterNet; added a `resolveProvider(force, key, dfAvailable)` overload so tests are deterministic instead of using `skip()`. The 2-arg form calls it with real detection.
3. **[Rule 1] Adapted to real HTTP API.** `postMultipart` returns `HttpResponse` tuple `(statusCode, body)`, called positionally with `extraHeaders`; mock `register(meth, substr, status, body)`; mock call body is `"audio:audio.wav"`.
4. **[Rule 1] Cost formatting.** Nim `{x:.0f}` prints `6000.`; messages use `int(durationSec)`. Cost threshold compares with a 1e-9 epsilon so exactly 600s (= $1.00) is auto-allowed despite float rounding.
5. `findExe` is checked before `execCmdEx("deepFilter --help")` to avoid shell errors when the script is absent.
6. Task commits: tests for all three tasks live in one file, so they landed in the third commit.

## Known Stubs

`enhance()` is not defined (planned for 22-03). `AudioResult` type is declared but unused until then.

## Unverified

- Real DeepFilterNet execution: `import df` fails on this machine (not installed). runDeepFilter success path and the python -m fallback against a real install are untested; only command construction and the not-installed error path are.
- Real ElevenLabs request (mock only).
- `nimble test` end to end (blocked by the pre-existing `unit` failure).

## Self-Check: PASSED
