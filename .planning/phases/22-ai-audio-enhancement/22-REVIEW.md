---
phase: 22-ai-audio-enhancement
reviewed: 2026-10-24T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - honeyclip.nimble
  - src/analyze/audio_enhance.nim
  - src/audio/deepfilter.nim
  - src/audio/elevenlabs.nim
  - src/audio/ffmpeg_chain.nim
  - src/audio/provider.nim
  - src/audio/render.nim
  - src/cli.nim
  - src/cmds/enhance.nim
  - src/config.nim
  - src/http_client.nim
  - src/main.nim
  - tests/test.py
  - tests/test_audio.py
  - tests/unit_audio.nim
findings:
  critical: 2
  warning: 11
  info: 7
  total: 20
status: issues_found
---

# Phase 22: Code Review Report

**Reviewed:** 2026-10-24
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

I reviewed the Phase 22 diff (`220ce23^..HEAD`) for the `enhance` subcommand, the audio provider, the FFmpeg chain, DeepFilterNet, ElevenLabs, mux/render, and the config, HTTP, CLI and dispatch changes.

What holds up:
- **Quoting (T-22-03):** every subprocess path and filter string goes through `quoteShell`.
- **API key (T-22-02):** the key never reaches a log call.
- **Cost gate order (T-22-04):** the gate runs before any HTTP traffic.
- **Dispatch fix:** the name-based lookup in `main.nim` fixes the old mis-dispatch.

What fails:
- **The local DeepFilterNet backend cannot work with the real DeepFilterNet.** It looks for the output under a filename the real tool never writes. The E2E stub copies that wrong assumption, so the tests pass.
- **The FFmpeg binary is looked up relative to the current directory.** That opens a binary-planting path.
- Several problems around the edges:
  - the cost gate fails open when the duration is unknown;
  - non-audio streams are dropped silently during the mux;
  - WAV bytes get written into files with any extension;
  - some stage flags are accepted but do nothing;
  - temp directories have predictable names;
  - a short tail chunk can break the crossfade reassembly.

## Critical Issues

### CR-01: DeepFilterNet output path is wrong, so the real `local` backend always fails

**File:** `src/audio/deepfilter.nim:39,53` (also `tests/test_audio.py:113-125`)
**Issue:** `runDeepFilter` expects the output at `outDir / extractFilename(inputWav)`. That comes from RESEARCH "Pitfall 7", which was never checked. Real DeepFilterNet (`df.enhance.save_audio`) adds the model name to the filename unless `--no-suffix` is passed. So `resampled.wav` comes out as `resampled_DeepFilterNet3.wav` (or `..._pf` with the post-filter). `fileExists(outFile)` is false, and every run returns `"DeepFilterNet finished (rc=0) but output ... missing"`. Auto mode prefers `local` whenever `import df` succeeds, so on any machine with DeepFilterNet installed both `--backend=local` and `--backend=auto` fail. The E2E stub `STUB_DF_ENHANCE` writes `out / src.name`, which hides the bug. The `else` branch of unit test `tests/unit_audio.nim:156` would fail against a real install.
**Fix:**
```nim
proc buildDeepFilterCmd*(cmdPrefix, inputWav, outDir: string): string =
  &"{cmdPrefix} --no-suffix -o {quoteShell(outDir)} {quoteShell(inputWav)}"
```
As a safety net, if `outDir / extractFilename(inputWav)` is missing, glob `outDir / (splitFile(inputWav).name & "*.wav")`. Update the stub to reject calls without `--no-suffix`, or to add the suffix when the flag is absent, so the test pins real behaviour.

### CR-02: The FFmpeg binary is found relative to the current directory (binary planting)

**File:** `src/analyze/audio_enhance.nim:29-36`
**Issue:** `ffmpegBin()` checks `build/ffmpeg.exe`, `build/ffmpeg`, `build/bin/ffmpeg(.exe)` relative to the **current working directory** before PATH. Run `honeyclip enhance x.mp4` from inside any downloaded repo or archive that has a `build/ffmpeg`, and honeyclip runs that file for every probe, filter and mux. On top of that, Nim's `findExe` checks the CWD before PATH, which compounds the problem for `ffmpeg`, `python3`/`python` and `deepFilter` (`deepfilter.nim:7-8,24`). It is also a correctness bug. The in-tree build (the only build guaranteed to have `deesser`/`afftdn`/`acrossfade` enabled) is only found when the user happens to be in the repo root. Anywhere else it quietly falls back to whatever `ffmpeg` is on PATH.
**Fix:**
```nim
let appDir = getAppDir()
for cand in [appDir / "ffmpeg.exe", appDir / "ffmpeg",
             appDir / "build" / "ffmpeg.exe", appDir / "build" / "ffmpeg",
             appDir / "build" / "bin" / "ffmpeg.exe", appDir / "build" / "bin" / "ffmpeg"]:
  if fileExists(cand): return cand
```
Also wrap the `findExe` lookups in a check that rejects results under `getCurrentDir()` (or use `findExe(..., followSymlinks=true)` and search the PATH entries yourself).

## Warnings

### WR-01: The ElevenLabs cost gate fails open when the duration is unknown

**File:** `src/audio/provider.nim:105-108`, `src/audio/ffmpeg_chain.nim:39-47,57-58`
**Issue:** `confirmElevenlabsCost` takes `probe.durationSec`. That value is 0.0 whenever the banner says `Duration: N/A` or can't be parsed (some MKV/WebM/streamed or damaged files). A cost of $0 is approved automatically (`cost <= 1.0`), so a file of any length gets uploaded with no prompt and no `--yes`. That undoes T-22-04 for exactly the inputs whose length nobody knows.
**Fix:** Run the gate after `resampleTo48kMono` and get the duration from the resampled WAV (probe it, or use `(fileSize - 44) / 96000`). If it is still `<= 0`, require `--yes` or a TTY prompt:
```nim
if dur <= 0.0 and not autoYes:
  result.err = "Cannot determine duration for ElevenLabs cost estimate; pass --yes"
  return
```

### WR-02: Auto mode uploads user audio to a third party without asking

**File:** `src/audio/provider.nim:36-41`, `src/audio/elevenlabs.nim:25`
**Issue:** With `--backend=auto` (the default), no DeepFilterNet, and `ELEVENLABS_API_KEY` set (for example from another tool's env), any clip of 10 minutes or less is sent to ElevenLabs. The only signal is an `info` line, which `-q` hides. A user who never named a cloud backend gets their audio uploaded.
**Fix:** In auto mode, fall back to `apFfmpeg`. Use ElevenLabs only when the user asks for it with `--backend=elevenlabs`. If auto must stay able to pick ElevenLabs, show the confirmation prompt whatever the cost, and print a `warning` (not `info`) that `-q` can't hide.

### WR-03: The mux drops subtitle, data and attachment streams, and fails on audio-only containers

**File:** `src/audio/render.nim:18,21`
**Issue:** Both mux paths map only `0:v` plus audio. Subtitle tracks (mov_text, SRT/ASS in MKV), timecode/data tracks, MKV font attachments and chapters-as-streams are dropped from the output with no warning. Also, `-map 0:v` (not `0:v?`) is a hard error when the input has no video stream but its extension isn't on the audio list in `enhance.nim:150`. That covers `.mka`, `.wma`, `.aiff`, `.wv`, `.m4b`, and `.mkv`/`.mp4` files that hold only audio.
**Fix:** Use `-map 0:v? -map 0:s? -map 0:t? -c:s copy -c:t copy` (or `-map 0 -map -0:a` followed by the audio maps), and `-map_chapters 0`.

### WR-04: `writeAudioOnly` writes WAV bytes whatever the output extension

**File:** `src/audio/render.nim:33-38`, `src/cmds/enhance.nim:197-201`
**Issue:** With `--audio-only -o out.mp3`, or an audio input with `-o clean.m4a`, `copyFile` puts a RIFF/WAV file under a `.mp3`/`.m4a` name. Many players and NLEs reject it or misidentify it. Nothing reports the problem.
**Fix:** When `finalOut`'s extension isn't `.wav`, transcode with `"-i " & quoteShell(src) & " " & quoteShell(dst)` through `runFf`, or refuse non-`.wav` paths with `--audio-only`.

### WR-05: `--de-reverb` and `--voice-isolation` are accepted but do nothing (and `--backend=elevenlabs` can skip itself)

**File:** `src/audio/provider.nim:65,69,78`, `src/analyze/audio_enhance.nim:172-173`
**Issue:**
- `flags.deReverb` is never read by any backend, so `--de-reverb=on` is a silent no-op.
- `voiceIsolation` is only honoured by ElevenLabs and is never set in auto mode, despite the "set by the API provider" comment.
- So `--backend=elevenlabs` on audio the noise heuristic calls clean (`denoise=false`) skips the ElevenLabs call entirely. The user explicitly chose the isolator, yet the cost gate and the upload are both bypassed with no message.
- `--voice-isolation=on` with `local`/`ffmpeg` is ignored without a word.

**Fix:**
- When the provider is `apElevenlabs` and `voiceIsolation` is `smAuto`, set `voiceIsolation = true`.
- Either implement de-reverb (DeepFilterNet does not de-reverb, so drop the flag) or reject `--de-reverb=on`.
- Warn when a stage you forced on is unsupported by the chosen backend.

### WR-06: A tiny trailing chunk can break the crossfade reassembly

**File:** `src/audio/ffmpeg_chain.nim:176-197,199-218`
**Issue:** The bounds loop only guarantees that chunks other than the last are at least 10% of `maxChunkSec`. The last chunk is `total - cur` and can be any length above 0. For example, `total = 1200.02` and `maxChunkSec = 600` with no silences gives a 0.02s last chunk, shorter than the 50 ms `acrossfade`. `acrossfade` then fails or shortens the output, which breaks the length invariant that the 49d06d8 fix relies on. DeepFilterNet/ElevenLabs may also reject a sub-100 ms clip.
**Fix:** After building `bounds`, if `total - bounds[^2] < max(1.0, 4 * overlap)`, drop `bounds[^2]` so the short tail joins the previous chunk (that chunk can go slightly over `maxChunkSec`, or cap it earlier by choosing a cut up to `maxChunkSec - minTail`).

### WR-07: Temp directories and files have predictable names in a shared temp dir

**File:** `src/cmds/enhance.nim:166`, `src/analyze/audio_enhance.nim:79`, `src/audio/ffmpeg_chain.nim:156`
**Issue:** `getTempDir() / "honeyclip_enhance_<pid>"`, `honeyclip_probe_<pid>.raw` and `honeyclip_chunks_<pid>` can be guessed. `createDir` succeeds silently on a directory that already exists. On Linux, where `/tmp` is shared, another local user can pre-create the directory, or place a symlink at `work/enhanced.wav` or similar. That lets them read the victim's audio, or make `ffmpeg -y` overwrite files the victim owns through the symlink. Collisions from PID reuse also affect `removeDir`.
**Fix:** Create a unique 0700 directory atomically with `createTempDir("honeyclip_enhance_", "")` (std/tempfiles, Nim ≥ 1.6), and put every intermediate file inside it, including the probe `.raw` and the chunks.

### WR-08: EOF at the cost prompt crashes with an unhandled exception

**File:** `src/audio/elevenlabs.nim:30`
**Issue:** `stdin.readLine()` raises `EOFError` on Ctrl-D/Ctrl-Z, or when stdin closes after the TTY check. Neither `confirmElevenlabsCost`, `enhance` nor `run` catches it, so the user gets a Nim traceback and the temp dir may not be cleaned up the way the code intends.
**Fix:**
```nim
let line = try: (if readLineFn != nil: readLineFn() else: stdin.readLine())
           except EOFError, IOError: ""
```

### WR-09: A/V offset in the source is lost when the enhanced audio is muxed back

**File:** `src/audio/ffmpeg_chain.nim:133-136`, `src/audio/render.nim:6-25`
**Issue:** `resampleTo48kMono` / `extractAudioTrack` write a WAV that starts at t=0, which throws away the audio stream's `start_time` relative to video. MP4 edit lists, audio delay and cameras with an initial audio offset all set that. `buildMuxCmd` then lines the enhanced WAV up at 0, so the output drifts by the original offset, often tens to hundreds of ms. The ElevenLabs MP3 round trip can add encoder priming per chunk if the response has no gapless header.
**Fix:** In `probeAudio`, read the `start:` value from the banner for the video and audio streams, and pass `-itsoffset <audio_start - video_start>` before `-i enhancedAudio` in `buildMuxCmd`. Add an E2E fixture with an audio delay to confirm the sync.

### WR-10: Auto mode picks DeepFilterNet with a weaker check than the one used to run it, and does not fall back

**File:** `src/audio/deepfilter.nim:11-19,21-35`, `src/audio/provider.nim:36-38,65-67`
**Issue:**
- `isDeepFilterAvailable` checks `import df`, but `whichDeepFilter` needs `deepFilter --help` or `import df.enhance`, and `df.enhance` pulls in torch/torchaudio.
- A broken or partial install (`df` present, torch missing) makes auto choose `local`, and then every run fails late with "DeepFilterNet not installed".
- No backend falls back on a runtime failure: auto never tries ElevenLabs or the always-available FFmpeg chain.
- Auto with neither DF nor a key is a hard error even though `apFfmpeg` always works.

**Fix:** Make `isDeepFilterAvailable` return `whichDeepFilter() != ""`. In auto mode, on a `local` failure, retry with `apFfmpeg` (and log a warning). Use `apFfmpeg` as the last resort in auto mode instead of raising.

### WR-11: Channel layouts with a suffix are parsed as stereo, so 5.1 sources get downmixed

**File:** `src/audio/ffmpeg_chain.nim:26-37`
**Issue:** FFmpeg prints layouts such as `5.1(side)`, `7.1(wide)`, `5.0(side)`, `downmix` and `hexagonal`. The `t.len == 3` check only handles bare `5.1`/`7.1`, so all of these default to 2. `resampleFromWav(..., channels = 2)` then makes a stereo track, and the mux puts that stereo track where a 5.1 track was, without a word.
**Fix:** Remove any `(...)` suffix before parsing (`t = t.split('(')[0]`). Better still, ask ffmpeg for the channel count directly (`-af ashowinfo`, or parse `ch_layout` from `-f ffmetadata`). Warn when the count can't be determined, and don't guess 2.

## Info

### IN-01: Test-only endpoint override ships in production with no HTTPS check

**File:** `src/audio/elevenlabs.nim:11-15`
**Issue:** `HONEYCLIP_ELEVENLABS_URL` points the `xi-api-key` header at any URL, including `http://`, so the key travels in cleartext.
**Fix:** Accept only `https://` or `http://127.0.0.1`/`localhost` overrides, or compile the override in only with `-d:honeyclipTest`.

### IN-02: ElevenLabs error bodies are discarded

**File:** `src/audio/elevenlabs.nim:43-44`
**Issue:** Only `HTTP {code}` is reported, so quota, invalid-key and file-too-long reasons are lost.
**Fix:** Add the first ~200 chars of `body` when it's JSON (it never contains the key).

### IN-03: Hum removal always notches both 50 and 60 Hz, and no harmonics

**File:** `src/audio/ffmpeg_chain.nim:82-85`
**Issue:** The detector knows which band fired, but both notches are always applied, and 100/120/150/180 Hz harmonics (often the most audible part of a ground-loop buzz) are left in.
**Fix:** Pass `detect50`/`detect60` through `EnhancementFlags`, and add notches at 2f and 3f.

### IN-04: The Goertzel hum detector is extremely narrowband

**File:** `src/analyze/audio_enhance.nim:93-108`
**Issue:** Over 30s, the Hann main lobe is about ±0.07 Hz. Hum just a few tenths of a Hz off nominal (generator power, off-speed tape or film transfers) falls about 30 dB below the threshold and isn't detected.
**Fix:** Take the max over a small sweep (for example f ± 0.5 Hz in 0.05 Hz steps), or use shorter analysis blocks.

### IN-05: The default output for an input with no extension has no format

**File:** `src/cmds/enhance.nim:197-200`
**Issue:** For an input with no extension, `inExt == ""`, so the output is `name.enhanced` and ffmpeg can't pick a muxer.
**Fix:** Fall back to `.mp4` (or `.wav`) when `inExt == ""`.

### IN-06: Value flags given without a value silently fall back to defaults

**File:** `src/cmds/enhance.nim:75-86,95-100`
**Issue:** A trailing `--backend` or `--denoise` with no value gives `p.val == ""`, which turns into `auto`/`smAuto` without an error.
**Fix:** In `parseArgs`, treat an empty value for the flags in `valueFlags` as a usage error (exit 2).

### IN-07: A chunking failure silently falls back to processing the whole file

**File:** `src/audio/ffmpeg_chain.nim:194-196`
**Issue:** If any chunk extraction fails, the code returns `@[inputPath]` with no log line. The over-long input then goes to the backend in one piece, including a multi-hour upload to ElevenLabs, and the half-written chunks are left behind.
**Fix:** Log a `warning`, or return an empty seq so `enhance` stops with an error.

---

_Reviewed: 2026-10-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
