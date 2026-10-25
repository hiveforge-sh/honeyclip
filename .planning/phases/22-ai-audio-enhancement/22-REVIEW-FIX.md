---
phase: 22-ai-audio-enhancement
fixed_at: 2026-10-24T00:00:00Z
review_path: .planning/phases/22-ai-audio-enhancement/22-REVIEW.md
iteration: 1
findings_in_scope: 13
fixed: 13
skipped: 0
status: all_fixed
---

# Phase 22: Code Review Fix Report

**Fixed at:** 2026-10-24
**Source review:** .planning/phases/22-ai-audio-enhancement/22-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 13 (2 Critical + 11 Warning; Info IN-01..IN-07 excluded by request)
- Fixed: 13
- Skipped: 0

Some fixes change logic. They pass the tests below, but a human should still confirm the behaviour: WR-06 (chunk bounds), WR-09 (A/V offset) and WR-10 (auto fallback).

---

## Fixed Issues

### CR-01: DeepFilterNet output path is wrong, so the real `local` backend always fails

**Files modified:** `src/audio/deepfilter.nim`, `tests/test_audio.py`, `tests/unit_audio.nim`
**Commit:** f578745
**Applied fix:**
- `buildDeepFilterCmd` now passes `--no-suffix`.
- A new `resolveDeepFilterOutput` takes `outDir/<input name>` first. If that is missing, it falls back to the first `<stem>*.wav` in `outDir`, so a DeepFilterNet version that ignores the flag still works.
- The E2E stub now names its output the way the real tool does: `<stem>_DeepFilterNet3.wav` unless `--no-suffix` is given.
- Verified that the updated stub fails `test_enhance_local_path` against the pre-fix binary with the original "output ... missing" error, so the test now catches the bug.
- Added a unit test for the fallback resolution.

---

### CR-02: The FFmpeg binary is found relative to the current directory (binary planting)

**Files modified:** `src/analyze/audio_enhance.nim`, `src/audio/deepfilter.nim`, `src/audio/ffmpeg_chain.nim`, `src/cmds/enhance.nim`, `tests/unit_audio.nim`
**Commit:** 73581a5
**Applied fix:**
- Nim's `findExe` has no option to skip the CWD; on Windows it always checks it first. A new `findExeOnPath` therefore searches only absolute PATH entries, with `ExeExts` on Windows. It skips relative entries such as `.` and empty ones.
- `ffmpegBin()` order is now:
  1. `HONEYCLIP_FFMPEG`;
  2. `getAppDir()/{ffmpeg,build/ffmpeg,build/bin/ffmpeg}(.exe)`;
  3. `findExeOnPath("ffmpeg")`.
- `ffmpegBin()` returns `""` instead of a bare `"ffmpeg"`. A bare name would let `CreateProcess` search the CWD.
- `enhance` exits 1 with a clear message when no ffmpeg is found.
- `python3`/`python`/`deepFilter` are resolved the same way, and the subprocess is started with the quoted absolute path.
- New unit tests:
  - a planted `ffmpeg(.exe)` and `build/ffmpeg(.exe)` in the CWD are never picked;
  - `HONEYCLIP_FFMPEG` still wins.

---

### WR-01: The ElevenLabs cost gate fails open when the duration is unknown

**Files modified:** `src/audio/provider.nim`, `src/audio/elevenlabs.nim`, `tests/unit_audio.nim`
**Commit:** fc47c49
**Applied fix:**
- The gate now runs after `resampleTo48kMono`, which is local with no HTTP, so T-22-04 ordering holds.
- The duration comes from the resampled WAV: probed first, then `(size - 44) / 96000`, then the container value.
- In `confirmElevenlabsCost`, a duration of 0 or less is never auto-approved. On a non-TTY it is refused with a warning to pass `--yes`; on a TTY the user gets a prompt saying the cost cannot be estimated.
- The chunking trigger uses the same measured duration.

---

### WR-02: Auto mode uploads user audio to a third party without asking

**Files modified:** `src/audio/provider.nim`, `tests/test_audio.py`
**Commit:** 412d188 (the message moved into the `alwaysWarn` helper in 4bfce11)
**Applied fix:**
- As the user decided, which backend `auto` picks is unchanged.
- The `info` line is replaced by a `Warning!` written straight to stderr, which `-q` does not suppress. It says the audio will be uploaded to ElevenLabs, names the endpoint, and points at `--backend=ffmpeg`.
- The E2E auto-fallback test now runs with `-q` and asserts the warning is present.

---

### WR-03: The mux drops subtitle, data and attachment streams, and fails on audio-only containers

**Files modified:** `src/audio/render.nim`, `tests/unit_audio.nim`
**Commit:** 24916a0
**Applied fix:**
- Both mux paths now map `0:v?` and add `-map 0:s? -map 0:t? -c:s copy -c:t copy -map_chapters 0`.
- If the output container rejects those streams (for example ASS subtitles into .mp4), `muxEnhancedAudio` retries without them and prints a warning, so nothing is dropped silently.
- Data streams (`0:d`) are deliberately not mapped, because copying tmcd/data tracks fails in many containers.
- New unit tests: a mov_text subtitle survives the mux, and an audio-only `.mka` input muxes.

---

### WR-04: `writeAudioOnly` writes WAV bytes whatever the output extension

**Files modified:** `src/audio/render.nim`, `src/cmds/enhance.nim`, `tests/unit_audio.nim`
**Commit:** cb95fbf
**Applied fix:**
- A `.wav` output is still a plain copy. Any other extension is transcoded by ffmpeg (`buildAudioOnlyCmd`), so `-o clean.mp3` writes a real MP3.
- An extension ffmpeg cannot write fails with the existing "could not write output" error.
- The help text for `--audio-only` is updated.
- New unit test: an `.mp3` output is not RIFF and probes as mp3.

---

### WR-05: `--de-reverb` and `--voice-isolation` are accepted but do nothing (and `--backend=elevenlabs` can skip itself)

**Files modified:** `src/audio/provider.nim`, `src/analyze/audio_enhance.nim`, `src/cmds/enhance.nim`, `tests/test_audio.py`, `tests/unit_audio.nim`
**Commit:** 8cf4434
**Applied fix:**
- `--de-reverb=on` is now rejected with exit code 2, because no backend implements de-reverberation. `parseArgs` still accepts the syntax; `run` refuses it.
- A new `applyProviderStages` handles provider-driven stages:
  - with ElevenLabs, `--voice-isolation=auto` means on, so `--backend=elevenlabs` no longer skips the isolator and the cost gate on audio the heuristic calls clean;
  - with local/ffmpeg, `--voice-isolation=on` prints a warning that the backend ignores it.
- The help text and the `EnhancementFlags` field comments are updated.
- New unit and E2E tests cover this.

---

### WR-06: A tiny trailing chunk can break the crossfade reassembly

**Files modified:** `src/audio/ffmpeg_chain.nim`, `tests/unit_audio.nim`
**Commit:** a2c7c4c
**Applied fix:**
- Chunk boundaries now come from a pure `chunkBounds()`. When the remainder after a cut would be shorter than `max(1s, 4 x overlap)`, the cut limit moves earlier to `total - minTail`.
- Every chunk stays at or below `maxChunkSec`, and the tail is never tiny.
- Unit tests:
  - the review's 1200.02s/600s example;
  - a near-end silence that must not be chosen;
  - an unchanged ordinary case.
- **Status: fixed, requires human verification** (logic change).

---

### WR-07: Temp directories and files have predictable names in a shared temp dir

**Files modified:** `src/analyze/audio_enhance.nim`, `src/audio/ffmpeg_chain.nim`, `src/cmds/enhance.nim`, `tests/unit_audio.nim`
**Commit:** 3bb6a5d
**Applied fix:**
- A new `createPrivateTempDir(prefix)` builds a random name with `std/tempfiles.genTempPath` and creates the directory atomically. On POSIX it uses `mkdir(path, 0o700)` and retries on EEXIST. On Windows it uses `existsOrCreateDir`. An existing path is never reused.
- `std/tempfiles.createTempDir` was not used because it creates the directory with the default umask, not 0700.
- These all use the new helper: the enhance work dir, the probe `.raw` (now inside its own private directory), and the default chunk dir.
- POSIX compile checked with `nim check --os:linux`.

---

### WR-08: EOF at the cost prompt crashes with an unhandled exception

**Files modified:** `src/audio/elevenlabs.nim`, `tests/unit_audio.nim`
**Commit:** 11c049c
**Applied fix:**
- Both prompts read through a new `readAnswer()`, which maps `EOFError`/`IOError` to `""`. The gate then denies.
- New unit test: a `readLineFn` that raises `EOFError`.

---

### WR-09: A/V offset in the source is lost when the enhanced audio is muxed back

**Files modified:** `src/audio/ffmpeg_chain.nim`, `src/audio/render.nim`, `src/cmds/enhance.nim`, `tests/test_audio.py`, `tests/unit_audio.nim`
**Commit:** ceb889f
**Applied fix:**
- The FFmpeg banner prints only the container `start:` (plus a per-stream `start` on newer builds), not reliable per-stream start times. So the new `audioStartOffset(path, track)` measures the `pts_time` of the first decoded frame of the selected audio track with `ashowinfo`. That is the same audio the WAV extraction keeps, priming samples included.
- If `ashowinfo` is unavailable, it falls back to the banner's stream `start` minus the container start (`probeAudio` now records both).
- `buildMuxCmd`/`muxEnhancedAudio` take an `audioOffset` and emit `-itsoffset` before the enhanced input when |offset| >= 0.5 ms. Normal files get the same command as before.
- Unit test and E2E test (`test_audio_delay_survives_the_mux`) use a source with a 0.5s audio delay.
- **Not addressed:** per-chunk MP3 encoder priming in the ElevenLabs response. ffmpeg's mp3 decoder already honours LAME/Xing gapless headers, and there is no reliable way to detect priming when the header is absent.
- **Status: fixed, requires human verification** (sync logic).

---

### WR-10: Auto mode picks DeepFilterNet with a weaker check than the one used to run it, and does not fall back

**Files modified:** `src/audio/deepfilter.nim`, `src/audio/provider.nim`, `src/cmds/enhance.nim`, `tests/test_audio.py`, `tests/unit_audio.nim`
**Commit:** 4bfce11
**Applied fix:**
- `isDeepFilterAvailable()` now returns `whichDeepFilter() != ""`, the same check `runDeepFilter` uses.
- `AudioProvider` gains `fromAuto` and `AudioResult` gains `backendFailed`.
- **No backend at all:** with neither DeepFilterNet nor a key, auto now resolves to `apFfmpeg` instead of raising. A warning names both remediations; the E2E test for this case changed from "exit 1" to "succeeds with that warning".
- **Backend failure:** when the backend fails under auto, `run` retries once with the FFmpeg chain and warns first. A denied cost gate is not a backend failure and never falls back.
- **Explicit backends:** `--backend=local` and `--backend=elevenlabs` stay strict; there is an E2E test for local.
- Both fallback warnings use `alwaysWarn`, so `-q` cannot hide them.
- The help text now documents the auto order.
- **Status: fixed, requires human verification** (fallback logic).

---

### WR-11: Channel layouts with a suffix are parsed as stereo, so 5.1 sources get downmixed

**Files modified:** `src/audio/ffmpeg_chain.nim`, `src/audio/provider.nim`, `tests/unit_audio.nim`
**Commit:** 2e4be16
**Applied fix:**
- `parseChannels` (now exported) handles all FFmpeg layout notations:
  - it strips the `(...)` suffix;
  - it sums `X.Y` and `X.Y.Z` layouts (5.1, 7.1.4, 22.2);
  - it knows the named layouts (downmix, binaural, hexagonal, octagonal, cube, hexadecagonal);
  - it counts `FL+FR+...` lists;
  - it reads `N channels`.
- It returns 0 when unsure instead of guessing 2. `probeAudio` then falls back to `ashowinfo`'s decoded `channels:`. If the count is still unknown, `enhance` stops with "Could not determine the channel layout".
- The deliberate 48 kHz mono processing design is unchanged; only the restored channel count is fixed.
- New unit tests: 16 layout strings, plus a 5.1(side) WAV that comes back with 6 channels after `enhance`.

---

## Verification

- `tests/unit_audio`: **101 OK, 1 SKIPPED** (DeepFilterNet not installed), 0 failed. The baseline was 82 OK / 1 SKIPPED; the 19 new tests are listed under the findings above.
- `tests/unit_broll`: **62 OK, 1 SKIPPED**, 0 failed. Unchanged.
- `python tests/test_audio.py`: **19 OK**, 0 failed. The baseline was 14; there are 5 new tests, and one renamed and inverted for WR-10.
- `nimble make`: rebuilt `honeyclip.exe` (`[SuccessX]`). The E2E run used the rebuilt binary.
- Not run: `tests/unit` and `tests/test.py`. Both have known failures from before this phase that are unrelated to it.
- Not verified:
  - a real DeepFilterNet install (only the stub, which now mimics real naming);
  - the POSIX-only `mkdir 0700` path at runtime (checked at compile time only);
  - the ElevenLabs MP3 priming part of WR-09.

---

_Fixed: 2026-10-24_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
