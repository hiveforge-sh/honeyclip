# Phase 22: AI Audio Enhancement - Research

**Researched:** 2026-05-09
**Domain:** Audio signal analysis, DeepFilterNet Python subprocess, ElevenLabs Voice Isolator API, FFmpeg audio filter graphs, multi-stage enhancement chain
**Confidence:** HIGH (architecture, code patterns, FFmpeg filter availability) / MEDIUM (DeepFilterNet de-reverb confidence) / LOW (ElevenLabs response codec, exact pricing tier lock-in)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Enhancement chain:** 5 stages: noise reduction → voice isolation → de-reverb → de-ess → hum removal → loudness normalization (6 steps total; loudnorm is the final stage always applied)
- **Default behavior:** auto-detect; per-stage `--{stage}=on|off|auto` flags; default all stages `auto`
- **Local backend:** DeepFilterNet via Python subprocess (`deep-filter` CLI or `deepFilter` command installed by `pip install deepfilternet`). Detection: `python3 -c "import df"` exit-0 check. No Python bundling.
- **What DeepFilterNet covers:** denoise + de-reverb
- **What FFmpeg covers locally:** hum removal, de-ess, loudnorm (already in src/render/audio.nim)
- **Voice isolation locally:** researcher to confirm if viable local model exists OR document that voice isolation forces API path
- **API backend:** ElevenLabs Voice Isolator API covering voice isolation + denoise
- **API+FFmpeg chain:** ElevenLabs (voice isolation + denoise) → FFmpeg (hum removal + de-ess + loudnorm)
- **Provider:** `AudioProvider` object variant (`apLocal | apElevenlabs`) mirroring `BrollProvider`
- **Provider selection:** local-first; auto-fallback to ElevenLabs when DeepFilterNet absent and key configured; forced via `--backend local|elevenlabs|auto`
- **Auth/config:** `ELEVENLABS_API_KEY` env first, then TOML `[elevenlabs]` section; reuse `src/config.nim`, add `resolveElevenlabsKey`
- **Cost gate:** auto-allow ≤ $1.00; prompt confirm > $1.00 on TTY; default-deny non-TTY > $1.00; `--yes` bypasses
- **CLI:** new `honeyclip enhance` subcommand; mirrors `broll` exactly
- **Output:** video (audio replaced) by default; `--audio-only` for cleaned audio file
- **Audio handling:** resample to 48kHz mono for DeepFilterNet; restore source rate/channels for final mux
- **Loudnorm:** reuse `src/render/audio.nim` — do NOT reimplement
- **Infrastructure reuse:** `src/http_client.nim` (HttpClientLike), `src/config.nim`, cost-gate philosophy

### Claude's Discretion

- Auto-detect signal-extraction algorithm per stage (highest-risk decision — researcher must give confidence verdict)
- Whether voice isolation uses a local model or is API-only
- `AudioResult` type shape (mirrors `ClipResult`)
- `src/audio/` module layout (mirrors `src/broll/`)
- Multipart upload extension to `src/http_client.nim` if needed for ElevenLabs

### Deferred Ideas (OUT OF SCOPE)

- Adobe Enhance Speech, Artlist, Krisp providers
- Real-time/streaming enhancement
- User-supplied DSP chain
- AI-generated background music removal
- Per-segment enhancement
- `--enhance-audio` on main edit command
- Saving/loading enhancement profiles
- Bundled Python distribution for Windows
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AUDIO-01 | User can enhance audio quality (noise reduction, normalization) with single flag | "Enhancement Chain" section: 5-stage chain triggered by `honeyclip enhance video.mp4`; auto-detect selects applicable stages; loudnorm always final |
| AUDIO-02 | Audio enhancement works with local models when available | "Local Backend — DeepFilterNet" section: `deepFilter` CLI covers denoise+de-reverb; FFmpeg covers hum/de-ess/loudnorm; detection via `python3 -c "import df"` |
| AUDIO-03 | Audio enhancement falls back to API (ElevenLabs/Artlist) when configured | "API Backend — ElevenLabs" section: `POST /v1/audio-isolation/stream`; multipart upload; synchronous; `xi-api-key` header; auto-fallback when DeepFilterNet absent |
</phase_requirements>

---

## Summary

Phase 22 introduces a 5-stage audio enhancement chain exposed via `honeyclip enhance`. The architecture mirrors Phase 21 almost exactly: a new `src/audio/` module group containing an `AudioProvider` object variant (`apLocal | apElevenlabs`), a pure analyzer `src/analyze/audio_enhance.nim` that decides which stages to apply, and a CLI in `src/cmds/enhance.nim`.

**Critical finding 1 — FFmpeg filter allowlist gap.** The honeyclip FFmpeg build uses `--disable-filters` with an explicit allowlist (`honeyclip.nimble` line 927). The current allowlist is: `whisper, scale, pad, format, gblur, aformat, abuffer, abuffersink, aresample, atempo, anull, anullsrc, volume, loudnorm, asetrate`. The filters needed for Phase 22 (`deesser`, `highpass`, `equalizer`, `afftdn`, `astats`) are ALL absent. The planner MUST add these to the filter allowlist as a Wave 0 task. This is a one-line change in `honeyclip.nimble` followed by `nimble makeff` (1-2 hours), but it gates everything else. [VERIFIED: codebase grep + FFmpeg documentation]

**Critical finding 2 — Auto-detect feasibility verdict.** See dedicated section below. Verdict: **MEDIUM confidence; downgrade to "full chain minus opt-outs" if planner prefers zero risk.** A pure-FFmpeg `astats`-based heuristic is viable for three of the five stages; the reverb T60 measurement and voice-isolation detection are less reliable. The recommended approach is a pragmatic mixed-signal approach documented below.

**Critical finding 3 — Voice isolation is API-only.** Demucs (Meta, the standard for local voice isolation) requires GPU to run in practical time (~15 min/track on CPU vs <90s on GPU). Introducing a GPU-required second subprocess dependency would gate voice isolation for most users on API path anyway. The recommended decision: voice isolation in local mode is **skipped** — DeepFilterNet handles denoise+de-reverb; voice isolation only runs when `--backend elevenlabs` or auto-selects the API. The auto-detect signal for voice isolation still runs even in local mode so that `auto` mode silently skips it rather than failing.

**Critical finding 4 — ElevenLabs API is synchronous, multipart.** `POST https://api.elevenlabs.io/v1/audio-isolation/stream` returns audio bytes directly (no LRO polling needed — much simpler than Veo). Auth via `xi-api-key` header. Pricing: ~$0.10/min (1,000 credits/min). File limit: 500MB or 1 hour. This means the ElevenLabs provider is a simple `post()` call; no `asyncdispatch` required.

**Primary recommendation:** Use Phase 21's entire infrastructure verbatim. Mirror `src/broll/` as `src/audio/`. The only novel work is the auto-detect analyzer and the DeepFilterNet subprocess. Invest the most care in the FFmpeg filter allowlist fix and the DeepFilterNet WAV pipeline (resample → subprocess → resample back).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Auto-detect signal analysis | Analysis Layer (`src/analyze/audio_enhance.nim`) | — | Pure FFmpeg analysis via subprocess (astats/afftdn); no external I/O; mirrors `src/analyze/broll.nim` pattern |
| AudioProvider variant (local/ElevenLabs) | `src/audio/provider.nim` | — | External boundary; same object-variant pattern as BrollProvider |
| DeepFilterNet subprocess invocation | `src/audio/deepfilter.nim` | — | One external process; isolated module for testability |
| ElevenLabs HTTP call | `src/audio/elevenlabs.nim` | `src/http_client.nim` | HttpClientLike injection for mock testability (T-22-01) |
| FFmpeg enhancement chain (hum/de-ess/loudnorm) | `src/audio/ffmpeg_chain.nim` | `src/render/audio.nim` (reused loudnorm) | execCmdEx subprocess pattern from Phase 19-02 |
| Config / API key resolution | `src/config.nim` (extend) | — | Add `ElevenlabsSection` + `resolveElevenlabsKey` proc; no new file |
| Audio mux (enhanced audio back into video) | `src/audio/render.nim` | — | `-c:v copy` video passthrough + re-encode audio; execCmdEx FFmpeg subprocess |
| CLI surface | `src/cmds/enhance.nim` | `src/main.nim` (registration) | Mirrors `src/cmds/broll.nim` exactly |
| Cost gate | `src/audio/elevenlabs.nim` | `src/cmds/enhance.nim` | estimateElevenlabsCost + confirmElevenlabsCost; mirrors confirmVeoCost |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Nim stdlib | 2.2.2+ | `std/osproc`, `std/os`, `std/json`, `std/strformat` | `[VERIFIED: codebase grep]` Project requirement |
| `std/osproc.execCmdEx` | stdlib | DeepFilterNet subprocess, FFmpeg filter chain subprocess | `[VERIFIED: src/batch/runner.nim, src/broll/fitting.nim already use it]` |
| `std/httpclient` (sync) | stdlib | ElevenLabs POST — synchronous, no LRO polling needed | `[CITED: elevenlabs.io/docs]` ElevenLabs audio-isolation is synchronous; no async required unlike Veo |
| `src/http_client.nim` | Phase 21 | HttpClientLike abstraction for testable ElevenLabs calls | `[VERIFIED: src/http_client.nim exists]` |
| `src/config.nim` | Phase 21 | env-first TOML key resolution; extend with resolveElevenlabsKey | `[VERIFIED: src/config.nim exists]` |
| `toml_serialization` | already required | Extend HoneyclipConfig with ElevenlabsSection | `[VERIFIED: honeyclip.nimble line 14]` |
| FFmpeg filters (built-in) | 8.0.1 | astats (analysis), afftdn (noise reduction probe), highpass/equalizer (hum), deesser (sibilance), loudnorm (already wired) | `[VERIFIED: honeyclip.nimble line 927 — all MISSING from current allowlist except loudnorm; require nimble.nimble change]` |
| DeepFilterNet | 0.5.6 (latest) | denoise + de-reverb via Python subprocess | `[CITED: github.com/Rikorose/DeepFilterNet]` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `src/log.nim` | current | `info()`, `warning()`, `error()` | All status output; NEVER log API key |
| `src/util/bar.nim` | current | Progress bar during analysis + enhancement | All stages that take significant time |
| `src/av.nim` | current | `av.open()` to probe input for sample rate, channels, duration | Analyzer + cost estimator |
| existing `src/render/audio.nim` | current | Two-pass loudnorm — reuse nkEbu path | Final loudnorm stage ONLY; do NOT copy |
| `std/terminal.isatty` | stdlib | TTY detection for cost gate | Cost gate same as broll |

### FFmpeg Filters That Must Be Added to allowlist (honeyclip.nimble)

| Filter | Covers | Notes |
|--------|--------|-------|
| `astats` | Per-channel RMS, peak stats output to metadata | Used for noise-floor measurement |
| `afftdn` | FFT-based noise estimation probe | Used to probe noise floor dB |
| `highpass` | Hum removal (≥80Hz high-pass, attenuates 50/60Hz) | Part of `biquads` module in FFmpeg source |
| `equalizer` | Parametric EQ notch at 50Hz and/or 60Hz | Part of `biquads` module; same C file as highpass |
| `deesser` | De-essing — reduce sibilance (4-9 kHz) | Separate `af_deesser.c` in FFmpeg |
| `ametadata` | Write frame metadata to pipe (for astats readback) | Required for subprocess-based stats capture |
| `anullsink` | Discard output when only metadata is needed | Analysis-only pass |

`[VERIFIED: honeyclip.nimble grep]` — The current filter list (line 927) contains NONE of these. One-line addition required. All these filters exist in FFmpeg 8.0.1. [CITED: ffmpeg.org/ffmpeg-filters.html + ayosec.github.io/ffmpeg-filters-docs/8.0]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| afftdn probe subprocess | astats + custom threshold logic only | afftdn exports noise floor estimate directly; astats gives RMS but not per-band |
| equalizer notch at 50+60Hz | highpass=f=80 only | highpass removes everything below 80Hz; equalizer notch is more surgical — attenuates only ±5Hz around 50/60Hz |
| confirmVeoCost clone | shared helper in src/util | Not worth abstracting yet; only two callers |
| synchronous httpclient | asyncdispatch | ElevenLabs is synchronous (verified); no polling loop needed unlike Veo |

**Installation:**
No new `nimble` dependencies. All new libraries are either FFmpeg built-in, Python-external (DeepFilterNet), or extend existing modules.

```bash
# Users install DeepFilterNet themselves:
pip install deepfilternet

# FFmpeg rebuild with added filters (Wave 0 task — takes 1-2 hours):
# Edit honeyclip.nimble line ~927 to add new filters, then:
nimble makeff
```

---

## Architecture Patterns

### System Architecture Diagram

```
[honeyclip enhance video.mp4]
         |
    [arg parse / config]
         |
    [av.open() probe] → duration, sample_rate, channels
         |
    [Auto-detect Analyzer]  ← FFmpeg subprocess: astats/afftdn stats
    analyzeAudioForEnhancement()
    → EnhancementFlags { denoise, voiceIsolation, deReverb, deEss, humRemoval }
         |
    [AudioProvider.resolveProvider()]
    apLocal?  ─────────────────────────┐
    apElevenlabs?                      │
         |                             │
    [apElevenlabs path]                │  [apLocal path]
         |                             │
  [cost gate]               [DeepFilterNet subprocess]
  confirmElevenlabsCost()   deepFilter input.wav -o out/
         |                  (denoise + de-reverb)
  [elevenlabs.post()]                  │
  multipart audio upload               │
  ← raw audio bytes                   │
         |                             │
    [FFmpeg hum+deess chain]    [FFmpeg hum+deess chain]
    highpass + equalizer        highpass + equalizer
    + deesser                   + deesser
         |                             │
    [loudnorm two-pass]────────────────┘
    (reuse src/render/audio.nim nkEbu path or new subprocess)
         |
    [audio/render.nim]
    ffmpeg -i video -i enhanced_audio -c:v copy -map 0:v -map 1:a -y out.mp4
    (or --audio-only: write WAV directly)
         |
    [output: video.enhanced.mp4 | enhanced.wav]
```

### Recommended Project Structure

```
src/audio/
├── provider.nim        # AudioProvider variant (apLocal|apElevenlabs), resolveProvider
├── deepfilter.nim      # DeepFilterNet subprocess wrapper; detectDeepFilter; runDeepFilter
├── elevenlabs.nim      # ElevenLabs POST /v1/audio-isolation/stream; cost gate
├── ffmpeg_chain.nim    # FFmpeg hum/deess subprocess (execCmdEx); pure command builders
└── render.nim          # Final audio→video mux: -c:v copy or --audio-only WAV write

src/analyze/
└── audio_enhance.nim   # Pure analyzer: EnhancementFlags; per-stage signal extraction

src/config.nim          # EXTEND: add ElevenlabsSection + resolveElevenlabsKey
src/cmds/enhance.nim    # CLI: mirrors src/cmds/broll.nim exactly
tests/unit_audio.nim    # Mirrors tests/unit_broll.nim; MockHttpClient + fixture audio
tests/fixtures/
├── audio_elevenlabs_response.wav  # 100ms silence WAV for mock response
└── audio_stats.json               # astats/afftdn sample JSON output for analyzer tests
```

### Pattern 1: AudioProvider Object Variant

Mirror BrollProvider exactly.

```nim
# Source: src/broll/provider.nim (verified in repo)
type
  AudioProviderKind* = enum
    apLocal
    apElevenlabs

  AudioProvider* = object
    case kind*: AudioProviderKind
    of apLocal:
      discard  # no config needed; DeepFilterNet found via PATH
    of apElevenlabs:
      apiKey*: string

proc resolveProvider*(forceBackend, apiKey: string,
                      http: HttpClientLike): AudioProvider =
  case forceBackend.toLowerAscii
  of "local":
    if not isDeepFilterAvailable():
      raise newException(ValueError,
        "Backend 'local' requires deepfilternet: pip install deepfilternet")
    return AudioProvider(kind: apLocal)
  of "elevenlabs":
    if apiKey == "":
      raise newException(ValueError,
        "Backend 'elevenlabs' requires ELEVENLABS_API_KEY env var or config.toml [elevenlabs]")
    return AudioProvider(kind: apElevenlabs, apiKey: apiKey)
  of "auto", "":
    if isDeepFilterAvailable():
      return AudioProvider(kind: apLocal)
    if apiKey != "":
      info "DeepFilterNet not found; falling back to ElevenLabs"
      return AudioProvider(kind: apElevenlabs, apiKey: apiKey)
    raise newException(ValueError,
      "No audio backend available.\n" &
      "Install DeepFilterNet: pip install deepfilternet\n" &
      "Or set ELEVENLABS_API_KEY for the ElevenLabs API path.")
  else:
    raise newException(ValueError, &"Unknown --backend: {forceBackend}")
```

### Pattern 2: DeepFilterNet Subprocess Contract

```nim
# Source: [CITED: github.com/Rikorose/DeepFilterNet README]
# CLI installed by: pip install deepfilternet
# Command: deepFilter path/to/noisy_audio.wav
# OR:      python3 -m df.enhance path/to/noisy_audio.wav  (fallback)
# Output:  written to ./out/noisy_audio.wav (default output dir "out")
# With -o: deepFilter -o /tmp/output_dir input.wav
# Sample rate: 48kHz WAV ONLY — caller must resample before calling
# Channels: stereo accepted (model handles both mono and stereo)
# Exit 0 = success; nonzero = failure (message to stderr)

proc isDeepFilterAvailable*(): bool =
  ## Detect DeepFilterNet installation by importing the 'df' Python module.
  ## Uses exit-0 check per CONTEXT.md.
  let (_, code) = execCmdEx("python3 -c \"import df\"")
  return code == 0

proc runDeepFilter*(inputWav, outDir: string): tuple[ok: bool, outputPath: string, err: string] =
  ## Run deepFilter subprocess on a 48kHz mono/stereo WAV.
  ## inputWav must already be 48kHz (resample before calling).
  ## Output written to outDir/basename(inputWav).
  let cmd = &"deepFilter -o {quoteShell(outDir)} {quoteShell(inputWav)}"
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    return (false, "", output)
  let outFile = outDir / extractFilename(inputWav)
  if not fileExists(outFile):
    # Fallback: try python3 -m df.enhance (module entrypoint)
    let cmd2 = &"python3 -m df.enhance -o {quoteShell(outDir)} {quoteShell(inputWav)}"
    let (out2, code2) = execCmdEx(cmd2)
    if code2 != 0:
      return (false, "", out2)
  return (true, outFile, "")
```

**DeepFilterNet resampling contract:**
1. Extract audio from input to temp WAV via FFmpeg subprocess: `ffmpeg -i input -ar 48000 -ac 1 -f wav temp_48k.wav`
2. Run `deepFilter -o outDir temp_48k.wav` → `outDir/temp_48k.wav`
3. Resample back to source rate/channels: `ffmpeg -i enhanced_48k.wav -ar {srcRate} -ac {srcChannels} enhanced_final.wav`

Steps 1 and 3 require `aresample` (already in allowlist) and channel manipulation (use `aformat` — already in allowlist).

### Pattern 3: ElevenLabs Multipart Upload

The current `HttpClientLike` only supports `post(url, body, contentType)` with a string body. ElevenLabs requires `multipart/form-data` with a binary file field. This requires extending `src/http_client.nim` with a `postMultipart` method.

```nim
# Extension needed in src/http_client.nim
# Source: [CITED: elevenlabs.io/docs/api-reference/audio-isolation/stream]
# Endpoint: POST https://api.elevenlabs.io/v1/audio-isolation/stream
# Auth: xi-api-key: <key>  (header, not query string)
# Body: multipart/form-data
#   Field "audio": binary file bytes
#   Field "file_format": "other" (default; covers WAV, MP3, etc.)
# Response: 200 = raw audio bytes (MP3 or PCM depending on input hint)
# File limit: 500MB or 1 hour duration
# Cost: ~$0.10/min (~1000 credits/min)

proc postMultipart*(c: HttpClientLike, url: string,
                    fieldName: string, fileBytes: string,
                    filename: string,
                    headers: openArray[tuple[key, val: string]] = []): HttpResponse {.base.} =
  raise newException(CatchableError, "abstract")
```

**Boundary construction** uses Nim stdlib `std/httpclient` multipart support:

```nim
# Source: [ASSUMED] — Nim httpclient.MultipartData
method postMultipart*(c: RealHttpClient, url: string, fieldName, fileBytes, filename: string,
                      headers: openArray[tuple[key, val: string]] = []): HttpResponse =
  var mpData = newMultipartData()
  mpData.add(fieldName, fileBytes, filename, "audio/wav")
  for (k, v) in headers:
    c.inner.headers[k] = v
  let resp = c.inner.postContent(url, multipart = mpData)
  result = (200, resp)  # postContent raises on non-2xx
```

**MockHttpClient** extends to stub `postMultipart` via existing `register` mechanism — register on `"POST"` + `"/audio-isolation"` URL substring, return a 100ms silence WAV fixture.

### Pattern 4: Auto-Detect Analyzer

**CONFIDENCE VERDICT: MEDIUM.** See dedicated section below for full reasoning.

```nim
# Source: [ASSUMED] — heuristic thresholds derived from DSP literature + FFmpeg filter behavior
type
  EnhancementFlags* = object
    denoise*: bool        # detected steady-state noise above threshold
    voiceIsolation*: bool # detected music-band energy concurrent with speech
    deReverb*: bool       # detected reverb tail (proxy: high RMS in 50-300ms post-speech)
    deEss*: bool          # detected sibilance band energy peaks
    humRemoval*: bool     # detected 50Hz or 60Hz narrowband energy above threshold
    # loudnorm always true — not a flag

proc analyzeAudioForEnhancement*(inputPath: string): EnhancementFlags =
  ## Run FFmpeg analysis pass and extract per-stage signals.
  ## Uses execCmdEx with astats/afftdn; pure function (no I/O side effects).
  result = EnhancementFlags()
  let stats = runAstatsProbe(inputPath)         # noise floor + RMS
  let fftStats = runAfftdnProbe(inputPath)      # per-band noise estimate
  result.humRemoval = detectHum(fftStats)       # narrowband 50/60Hz energy
  result.deEss = detectSibilance(stats)         # 4-9kHz RMS vs broadband ratio
  result.denoise = detectNoise(fftStats)        # noise floor above -55dBFS
  result.deReverb = detectReverb(stats)         # proxy: high RMS in tail windows
  result.voiceIsolation = detectMusicPresence(fftStats)  # music-band concurrent energy
```

**Stage-by-stage signal extraction (concrete algorithms):**

| Stage | Measurement | Tool | Threshold | Confidence |
|-------|------------|------|-----------|------------|
| Noise reduction | Estimate non-speech noise floor via `afftdn` analysis-only pass (`tn=1:output=noise_floor_dBFS`) | FFmpeg subprocess afftdn | > -55 dBFS noise floor → apply | MEDIUM — afftdn noise floor export requires afftdn + ametadata chain; tested approach but parsing is brittle |
| Voice isolation | Energy ratio in 200-4000 Hz band outside speech segments vs total RMS | FFmpeg astats on segmented regions | energy ratio > 0.35 in "silence" gaps → music present | LOW — heuristic doesn't distinguish music from ambient; prone to false positives |
| De-reverb | RMS level in 50-300ms windows immediately after peak transients (reverb tail proxy) | FFmpeg astats with `length=0.05` window, scan peak-following windows | RMS_trough > -40 dBFS in post-transient window → reverb | LOW — T60 measurement needs dedicated IR tool; this is a proxy |
| De-ess | Ratio of 4-9kHz band RMS to 1-4kHz band RMS measured via afftdn multi-band or astats | FFmpeg astats + equalizer bandpass pre-filter probe | ratio > 1.5 → sibilance | MEDIUM — FFmpeg equalizer can pre-filter for targeted measurement |
| Hum removal | Direct RMS probe of 45-65Hz band (two runs: one bandpass 45-55Hz, one 55-65Hz) | FFmpeg equalizer bandpass probe → astats | absolute RMS > -50 dBFS in either band → notch that band | HIGH — narrowband measurement is reliable; simple to implement |

**Revised auto-detect confidence verdict:**

Hum detection (HIGH) and de-ess detection (MEDIUM) are reliable. Noise floor (MEDIUM) is workable. Voice isolation (LOW) and de-reverb (LOW via proxy) are unreliable with FFmpeg-only analysis.

**Planner recommendation:** Use auto-detect for hum + de-ess + denoise (HIGH/MEDIUM). For voice isolation and de-reverb, default to `auto` behavior that runs them unless `--voice-isolation=off` / `--de-reverb=off`, since DeepFilterNet de-reverb is free with the model and ElevenLabs always does voice isolation. This avoids the LOW-confidence detection being a gate for operations that are essentially free once you're in the chain anyway.

In other words: for local mode, DeepFilterNet runs as a single call that covers denoise+de-reverb unconditionally (the model does both); for API mode, ElevenLabs does voice isolation+denoise unconditionally. The auto-detect signal primarily guards whether to run DeepFilterNet (local) or call ElevenLabs (API) at all.

### Pattern 5: FFmpeg Hum+Deess Subprocess Chain

```nim
# Source: [VERIFIED: FFmpeg filter docs + honeyclip broll/fitting.nim execCmdEx pattern]
proc buildHumDeessCmd*(inputPath, outputPath: string,
                       notch50Hz, notch60Hz, deEss: bool): string =
  ## Build FFmpeg filter chain command for hum removal + de-essing.
  ## All path args must be quoteShell'd by caller.
  var filters: seq[string] = @[]
  if notch50Hz:
    filters.add "equalizer=f=50:t=h:w=10:g=-40"   # -40dB notch at 50Hz, 10Hz wide
  if notch60Hz:
    filters.add "equalizer=f=60:t=h:w=10:g=-40"   # -40dB notch at 60Hz, 10Hz wide
  if deEss:
    filters.add "deesser=i=0.5:m=0.5:f=0.5"       # moderate de-essing defaults
  if filters.len == 0:
    filters.add "anull"
  result = &"ffmpeg -y -i {quoteShell(inputPath)} -af {quoteShell(filters.join(','))} {quoteShell(outputPath)}"
```

**Note on loudnorm:** The existing `src/render/audio.nim` `nkEbu` path is an in-process two-pass FFmpeg filter graph — it operates on a `v3` timeline, not on a file path. For `honeyclip enhance`, we need a file-in, file-out loudnorm that does not touch the timeline internals. The plan must include a new `ffmpeg_chain.nim` proc `runLoudnormSubprocess(inputPath, outputPath: string)` that does the same two-pass `loudnorm` via `execCmdEx`. This is NOT reinventing `src/render/audio.nim`; it is a different entry point (file-path based vs. frame-iterator based). [ASSUMED — the distinction is significant; planner should verify this decision is acceptable]

### Pattern 6: CLI Structure (mirrors src/cmds/broll.nim)

```nim
# Source: src/cmds/broll.nim (verified in repo)
const helpText = """usage: honeyclip enhance file [options]

Enhance audio quality with AI-powered noise reduction and normalization.

Arguments:
  file                    Input video or audio file

Options:
  --backend BACKEND       local | elevenlabs | auto (default: auto -- local first)
  --denoise VALUE         on | off | auto (default: auto)
  --voice-isolation VALUE on | off | auto (default: auto)
  --de-reverb VALUE       on | off | auto (default: auto)
  --de-ess VALUE          on | off | auto (default: auto)
  --hum-removal VALUE     on | off | auto (default: auto)
  --audio-only            Output cleaned audio file instead of video
  -o, --output PATH       Output path (default: {input}.enhanced.{ext})
  --yes                   Skip cost-confirmation prompt (ElevenLabs)
  -q, --quiet             Suppress progress output
  --debug                 Show debug information
  --help                  Show this help
"""
```

**main.nim registration** (mirrors broll pattern exactly):
- `src/main.nim`: add `("enhance", enhanceCmd.main)` to `cmdHandlers`
- `src/cli.nim`: add `("enhance", "Enhance audio quality with noise reduction and normalization")`

**A known deviation from Phase 21:** Phase 21 discovered that `src/cli.nim` must be updated alongside `src/main.nim` or dispatch breaks (21-02 deviation #2). Phase 22 planner must list BOTH files in the task.

### Anti-Patterns to Avoid

- **Forgetting the FFmpeg filter allowlist.** All `deesser`, `highpass`, `equalizer`, `afftdn`, `astats`, `ametadata` filters are missing from the current build. Calling them from Nim will silently produce `filter 'X' not found` stderr from FFmpeg and a nonzero exit code. This is a build-time fix, not runtime.
- **Using the internal loudnorm from `src/render/audio.nim` directly.** That proc takes a `v3` timeline and `Norm` record. It cannot be reused for file-path-based enhancement. Write a new `runLoudnormSubprocess` that invokes FFmpeg externally. Do not copy or import the in-process implementation.
- **Calling deepFilter on non-48kHz input.** DeepFilterNet only supports 48kHz WAV. Passing a 44.1kHz file produces either silence or distorted output without error. Always resample first.
- **Logging the ElevenLabs API key.** Carry T-21-02 forward as T-22-02: `apiKey` variable is NEVER passed to `info()`, `warning()`, `error()`, or `debug()`. The URL passed to `post()` is not logged either. Use a grep gate in the threat check.
- **Treating ElevenLabs `/v1/audio-isolation/stream` as async/polling.** It returns audio bytes synchronously. No LRO, no operation name, no polling loop. Response body IS the audio.
- **Using _ as loop variable.** Nim 2.2.2 does not allow `_` as a variable name (21-02 deviation #3). Use named variable + `discard`.
- **Using `out` as a variable name.** Reserved keyword in Nim (21-02 deviation #4).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| EBU R128 loudness normalization | Custom two-pass analysis | `ffmpeg loudnorm` filter via subprocess | EBU R128 spec compliance requires look-ahead true peak limiting; hand-roll is wrong |
| Noise reduction | Custom spectral subtraction | DeepFilterNet (local) or ElevenLabs (API) | DNN models eliminate hiss, transient noise, fan noise that spectral subtraction leaves behind |
| Vocal separation | Custom harmonic-percussive separation | ElevenLabs (API only; Demucs is not viable without GPU) | Demucs takes 10-15 min/track on CPU; not acceptable for end users |
| Multipart HTTP | Manual boundary construction | Nim stdlib `newMultipartData()` | Boundary escaping and MIME type headers are error-prone |
| Audio sample rate detection | Header parsing | `av.open()` + `stream.codecpar.sample_rate` | Already available from existing FFmpeg wrappers |
| De-essing | Compressor + sidechain | `deesser` FFmpeg filter | Purpose-built; no sidechain routing needed |

---

## Auto-Detect Feasibility — Full Analysis

**CONFIDENCE VERDICT: MEDIUM for overall auto-detect. Recommended planner action: proceed with auto-detect but treat voice-isolation and de-reverb detection as "run unless explicitly opted out" rather than "run if detected."**

### Stage-by-stage confidence

**Hum removal (HIGH confidence):**
Detection approach: Two narrow FFmpeg subprocess runs, each with `equalizer` bandpass centering at 50Hz and 60Hz respectively → `astats` → parse `RMS_level` from metadata. If RMS_level in either band > -50 dBFS, apply notch for that band. This is reliable because electrical hum is narrowband and consistent. False positive risk is low (a voice with fundamental at 50Hz is unusual). [ASSUMED — threshold -50 dBFS derived from DSP literature; should be verified empirically on test samples]

**De-ess (MEDIUM confidence):**
Detection approach: Two `astats` runs — one on full signal, one after `highpass=f=4000` (passes 4kHz+ only). If the ratio (4kHz+ RMS) / (full RMS) > 0.15, sibilance is likely present. Common speech has this ratio at ~0.05-0.08; sibilant recordings push 0.15-0.25. False positive: cymbals or bright instruments also trigger. Mitigation: only relevant for voice-heavy content. [ASSUMED — ratio threshold 0.15; should be verified empirically]

**Noise reduction (MEDIUM confidence):**
Detection approach: `afftdn` analysis pass with `tn=1` (track noise) and capture the noise floor estimate. FFmpeg's `afftdn` filter can output noise floor to metadata via `ametadata`. If noise floor > -55 dBFS in the median estimate, denoise is warranted. More reliable than a simple RMS check because afftdn adapts across speech/non-speech regions. [ASSUMED — -55 dBFS threshold; afftdn metadata output format requires verification against FFmpeg 8.0.1 docs]

**De-reverb (LOW confidence):**
True T60 measurement (the industry standard) requires exciting the room with a signal and measuring the decay — not possible on captured audio. A proxy is to measure RMS in 50ms windows following transient peaks and checking if it stays above noise floor for too long. This proxy is noisy and affected by music accompaniment. Recommendation: **default de-reverb to `on` in local mode** (DeepFilterNet does it for free with the denoise model) and `off` in API mode (ElevenLabs does not offer it; users explicitly opt in with `--de-reverb=on`). This sidesteps the detection problem entirely.

**Voice isolation (LOW confidence for detection; N/A for local execution):**
Even if we detect music presence (high RMS in 200-4000 Hz band during speech), this could be any ambient sound. More critically: in local mode, we have no voice isolation capability anyway (DeepFilterNet does not separate vocals from music). So the detection only matters to decide whether to route to ElevenLabs in `auto` mode. Recommendation: in `auto` mode + local backend, voice isolation is **always skipped** (local path never has this). In `auto` mode + API backend (ElevenLabs), voice isolation **always runs** because it is what ElevenLabs does by definition. Therefore the auto-detect signal for voice isolation only matters as a "should I use ElevenLabs at all" decision — which is handled by the provider selection logic, not the stage flags.

### Function signatures (for planner)

```nim
# src/analyze/audio_enhance.nim
type
  StageMode* = enum smAuto, smOn, smOff
  EnhancementFlags* = object
    denoise*: bool
    voiceIsolation*: bool   # always false in local mode
    deReverb*: bool         # always true in local mode (free with DeepFilterNet)
    deEss*: bool
    humRemoval*: bool

proc analyzeAudioForEnhancement*(inputPath: string,
                                 modes: tuple[
                                   denoise, voiceIsolation, deReverb,
                                   deEss, humRemoval: StageMode]
                                ): EnhancementFlags
  ## Returns per-stage booleans after applying mode overrides.
  ## smOn -> force true; smOff -> force false; smAuto -> run heuristic.
  ## This proc only runs FFmpeg analysis; no external model calls.

proc runAstatsProbe*(inputPath: string): JsonNode
  ## Run ffmpeg -i input -af astats=metadata=1,ametadata=print:file=- -f null -
  ## Parse output and return key statistics as JSON.

proc runAfftdnProbe*(inputPath: string): JsonNode
  ## Run ffmpeg -i input -af afftdn=tn=1,ametadata=print:file=- -f null -
  ## Parse noise floor estimate. Requires afftdn + ametadata in allowlist.

proc detectHum*(stats: JsonNode): bool
  ## Returns true if 50Hz or 60Hz narrowband energy > -50 dBFS.

proc detectSibilance*(stats: JsonNode): bool
  ## Returns true if 4kHz+ / broadband RMS ratio > 0.15.

proc detectNoise*(stats: JsonNode): bool
  ## Returns true if estimated noise floor > -55 dBFS.
```

---

## ElevenLabs Voice Isolator API — Complete Contract

**Source:** [CITED: elevenlabs.io/docs/api-reference/audio-isolation/stream] + [CITED: community search results]

| Property | Value |
|----------|-------|
| Endpoint | `POST https://api.elevenlabs.io/v1/audio-isolation/stream` |
| Auth header | `xi-api-key: <ELEVENLABS_API_KEY>` |
| Request format | `multipart/form-data` |
| Required field | `audio` (binary file bytes) |
| Optional field | `file_format` = `"other"` (default; also accepts `"pcm_s16le_16"` for 16kHz mono PCM low-latency mode) |
| Response | Raw audio bytes (synchronous — NOT an LRO) |
| Response codec | MP3 default; can be PCM if `file_format=pcm_s16le_16` used |
| HTTP 200 | Audio bytes in body |
| HTTP 422 | Validation error JSON |
| File size limit | 500 MB |
| Duration limit | 1 hour per upload |
| Cost | ~$0.10/minute (~1,000 credits/min) |
| Min plan | Any paid plan (Starter and above); free tier gets 10 min/month |

**Cost gate calculation:**
```nim
# Source: [CITED: help.elevenlabs.io Voice Isolator pricing]
const elevenlabsCostPerMin* = 0.10  # USD

proc estimateElevenlabsCost*(durationSec: float): float =
  result = (durationSec / 60.0) * elevenlabsCostPerMin

proc confirmElevenlabsCost*(durationSec: float,
                             isTty: bool, autoYes: bool,
                             readLineFn: proc(): string = nil): bool =
  ## Mirror of confirmVeoCost from src/broll/veo.nim.
  ## Auto-allow ≤ $1.00; prompt > $1.00 on TTY; deny non-TTY without --yes.
  if autoYes: return true
  let cost = estimateElevenlabsCost(durationSec)
  if cost <= 1.0: return true   # auto-allow ≤ $1.00 (10 minutes)
  if not isTty:
    warning &"ElevenLabs would cost ~${cost:.2f} for {durationSec:.0f}s; refusing without --yes on non-TTY"
    return false
  echo &"ElevenLabs audio isolation: {durationSec:.0f}s audio, ~${cost:.2f} USD. Continue? [y/N]"
  let line = if readLineFn != nil: readLineFn() else: stdin.readLine()
  return line.strip.toLowerAscii in ["y", "yes"]
```

**Chunking strategy for long files (>1hr or >500MB):**
ElevenLabs accepts up to 1 hour per request. For inputs over 1 hour (edge case), split at silence boundaries using `silencedetect` filter (requires adding to allowlist), submit sequentially, concatenate with 50ms crossfade. This is an edge case; the planner may defer chunking to a deferred idea if the base implementation has enough scope.

---

## Loudnorm Two-Pass Decision

**Recommendation: file-path subprocess, not src/render/audio.nim reuse.**

`src/render/audio.nim`'s `nkEbu` path is a frame-iterator that processes a `v3` timeline via in-process FFmpeg filter graphs. It cannot be called with just a file path. For `honeyclip enhance`, the enhancement pipeline operates at the file level (input WAV → enhanced WAV → mux into video). The planner should implement `runLoudnormTwoPassSubprocess(inputPath, outputPath: string)` in `src/audio/ffmpeg_chain.nim` using `execCmdEx`:

```
# Pass 1: measure
ffmpeg -i input.wav -af loudnorm=I=-16:LRA=11:TP=-1.5:print_format=json -f null -
# Parse JSON from stderr
# Pass 2: apply
ffmpeg -i input.wav -af "loudnorm=I=-16:LRA=11:TP=-1.5:linear=true:measured_I=...:..." output.wav
```

This is NOT reinventing src/render/audio.nim. It is an independent file-path entry point. The `src/render/audio.nim` in-process path continues to serve the main edit pipeline unchanged. [ASSUMED — this is the correct interpretation of "reuse loudnorm" from CONTEXT.md: reuse the pattern and parameters, not the code path]

---

## Hum Detection: 50Hz vs 60Hz

**Recommendation: probe both bands separately, notch only the detected band(s).**

Always notching both is safe but slightly degrades audio content with strong bass fundamentals at 50 or 60 Hz (rare in voice content, common in music). Region detection (power grid frequency) is not feasible without user metadata. Instead:

- Run two spectral probes: `equalizer=f=50:t=h:w=5:g=0,astats` and `equalizer=f=60:t=h:w=5:g=0,astats`
- If either probe shows RMS > -50 dBFS, notch that specific band
- The narrowband energy at 50Hz vs 60Hz is typically 20-30 dB higher than adjacent bands when hum is present
- This costs one extra FFmpeg subprocess but avoids over-processing

[ASSUMED — -50 dBFS threshold; behavior of equalizer as bandpass probe needs verification]

---

## Config Extension

```nim
# Extend src/config.nim (verified existing file structure)
type
  ElevenlabsSection* = object
    apiKey*: string

  HoneyclipConfig* = object
    api*: ApiSection
    elevenlabs*: ElevenlabsSection  # ADD THIS

proc resolveElevenlabsKey*(pathOverride: string = ""): string =
  ## Return ELEVENLABS_API_KEY from env first, then TOML [elevenlabs] apiKey.
  ## Returns "" when neither source provides a key.
  result = getEnv("ELEVENLABS_API_KEY")
  if result == "":
    result = loadConfig(pathOverride).elevenlabs.apiKey
```

The `[elevenlabs]` TOML section in `config.toml` coexists with `[api]` (Gemini). No schema conflict.

---

## HttpClientLike Multipart Extension

`src/http_client.nim` currently only supports `get` and `post(url, body, contentType)`. ElevenLabs requires multipart/form-data. The minimal extension is:

```nim
method postMultipart*(c: HttpClientLike, url: string,
                      fieldName: string, fileBytes: string,
                      filename: string,
                      extraHeaders: seq[tuple[key, val: string]] = @[]): HttpResponse {.base.} =
  raise newException(CatchableError, "abstract")

method postMultipart*(c: RealHttpClient, ...): HttpResponse =
  # Use std/httpclient newMultipartData
  ...

method postMultipart*(c: MockHttpClient, ...): HttpResponse =
  c.calls.add (meth: "POST_MULTIPART", url: url, body: fieldName & ":" & filename)
  result = c.lookup("POST", url)
```

`MockHttpClient.register` works unchanged — register on `"POST"` + URL substring.

---

## Common Pitfalls

### Pitfall 1: FFmpeg Filter Not Found at Runtime
**What goes wrong:** honeyclip calls `deesser` or `highpass` via filter graph; FFmpeg silently reports `Filter deesser not found` to stderr and returns nonzero exit code; Nim gets empty output.
**Why it happens:** The honeyclip.nimble filter allowlist uses `--disable-filters` + explicit `--enable-filter=...`. New filters are not available until added and `nimble makeff` is rerun (1-2 hours).
**How to avoid:** Wave 0 task: add `astats,afftdn,highpass,equalizer,deesser,ametadata,anullsink` to `filters.add` in honeyclip.nimble line ~927. Verify with `ffmpeg -filters | grep deesser` output from the rebuilt binary.
**Warning signs:** `execCmdEx` returns nonzero for a filter-graph command; stderr contains "not found".

### Pitfall 2: DeepFilterNet on Non-48kHz Input
**What goes wrong:** DeepFilterNet silently accepts the file but produces distorted or silent output if the sample rate is not 48kHz.
**Why it happens:** The `deepFilter` CLI has no automatic resampling.
**How to avoid:** Always resample to 48kHz mono before calling `deepFilter`. Use `ffmpeg -i input -ar 48000 -ac 1`. Resample back after enhancement.
**Warning signs:** Output WAV has 48kHz sample rate but sounds wrong at target playback rate.

### Pitfall 3: ElevenLabs Key Leakage (T-22-02)
**What goes wrong:** `ELEVENLABS_API_KEY` ends up in a log message; visible in CI logs or stdout.
**Why it happens:** Copying Veo patterns without checking whether the key is in a URL query string (Veo puts key in URL; ElevenLabs puts it in a header).
**How to avoid:** ElevenLabs key goes only in the `xi-api-key` header, never in the URL or log. Add grep gate: `grep -r "apiKey\|api_key" src/audio/ | grep -E "info|warning|error|debug"` must return 0 matches.
**Warning signs:** grep gate fails.

### Pitfall 4: Cost Surprise on Long Files
**What goes wrong:** User runs `honeyclip enhance 3h-conference.mp4` and is charged $18 without confirmation.
**Why it happens:** Auto-allow threshold is $1.00 (10 minutes). 3 hours = $18.
**How to avoid:** Cost gate prompt on TTY; auto-deny on non-TTY above $1.00. Gate is based on audio duration (probe with `av.open()`), not file size.
**Warning signs:** Missing cost gate call before ElevenLabs HTTP submission.

### Pitfall 5: ElevenLabs Response Body Treated as Text
**What goes wrong:** The 200 response body is raw binary audio bytes. Treating it as a UTF-8 string causes Nim string conversion issues.
**Why it happens:** Nim `httpclient` returns `string` (byte container); standard handling is fine, but if the code tries to parse it as JSON or UTF-8 text, it will fail or corrupt.
**How to avoid:** Write response body directly to a temp file with `writeFile(tmpPath, responseBody)`. Do not pass through `$` or string parsing.
**Warning signs:** Output WAV/MP3 plays as noise or truncated; file size much smaller than expected.

### Pitfall 6: _ Variable Name in Nim 2.2.2
**What goes wrong:** Compiler error `Error: invalid token: _ (\95)`.
**Why it happens:** Nim 2.2.2 does not allow `_` as a variable name in `for _ in` loops (21-02 deviation #3 verbatim).
**How to avoid:** Name the variable (e.g., `attempt`) and add `discard attempt`.

### Pitfall 7: deepFilter Output Path Mismatch
**What goes wrong:** `deepFilter -o /tmp/dir input.wav` writes to `/tmp/dir/input.wav`. If the caller looks for the output at a different path, it thinks the run failed.
**Why it happens:** deepFilter preserves the input filename in the output directory.
**How to avoid:** Output path = `outDir / extractFilename(inputWav)`. Explicitly check `fileExists(outPath)` after the subprocess.

---

## Code Examples

### Run astats probe and parse output

```nim
# Source: [ASSUMED — FFmpeg astats metadata output format; verify against FFmpeg 8.0.1]
proc runAstatsProbe*(inputPath: string): JsonNode =
  ## Run ffmpeg -af astats=metadata=1,ametadata=print:file=- to get per-channel stats.
  let cmd = &"ffmpeg -y -i {quoteShell(inputPath)} " &
            "-af \"astats=metadata=1,ametadata=print:file=pipe:1:file=metadata.txt\" " &
            "-f null -"
  let (output, code) = execCmdEx(cmd)
  # astats metadata appears in the output as key=value lines
  # Parse RMS_level, Peak_level per channel
  result = newJObject()
  for line in output.splitLines:
    if "=" in line:
      let parts = line.split("=", 1)
      if parts.len == 2:
        result[parts[0].strip] = newJString(parts[1].strip)
```

### ElevenLabs upload

```nim
# Source: [CITED: elevenlabs.io/docs/api-reference/audio-isolation/stream]
const elevenlabsBase* = "https://api.elevenlabs.io/v1"

proc elevenlabsIsolate*(http: HttpClientLike, apiKey: string,
                        inputWavPath: string, outPath: string): tuple[ok: bool, err: string] =
  if apiKey == "":
    return (false, "ElevenLabs requires ELEVENLABS_API_KEY")
  let audioBytes = readFile(inputWavPath)
  try:
    let (code, body) = http.postMultipart(
      &"{elevenlabsBase}/audio-isolation/stream",
      fieldName = "audio",
      fileBytes = audioBytes,
      filename = "audio.wav",
      extraHeaders = @[("xi-api-key", apiKey)]  # key in header only, never logged
    )
    if code notin 200 .. 299:
      return (false, &"ElevenLabs returned {code}")
    writeFile(outPath & ".tmp", body)
    moveFile(outPath & ".tmp", outPath)
    return (true, "")
  except CatchableError as e:
    return (false, e.msg)
```

### honeyclip.nimble filter allowlist addition (Wave 0)

```nim
# In honeyclip.nimble around line 927, change:
filters.add "scale,pad,format,gblur,aformat,abuffer,abuffersink,aresample,atempo,anull,anullsrc,volume,loudnorm,asetrate".split(",")
# TO:
filters.add "scale,pad,format,gblur,aformat,abuffer,abuffersink,aresample,atempo,anull,anullsrc,volume,loudnorm,asetrate,astats,afftdn,highpass,equalizer,deesser,ametadata,anullsink".split(",")
```

[VERIFIED: honeyclip.nimble line 927 — current content confirmed; new filters listed are valid FFmpeg 8.0.1 filter names per CITED docs]

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual noise reduction (iZotope, Audacity) | AI-based DNN (DeepFilterNet, ElevenLabs) | 2022-2024 | 5-15 dB DNSMOS improvement over spectral subtraction |
| FFmpeg afftdn only | DeepFilterNet for noise + de-reverb | 2022 | DNN handles non-stationary noise (keyboard, fan patterns) that afftdn misses |
| Long-form polling for audio APIs | ElevenLabs synchronous response | Current | Simpler than Veo's LRO; no asyncdispatch required |
| Demucs for voice isolation (local) | GPU-required; ElevenLabs as practical path | 2023 | CPU Demucs is 10-15 min/track; not viable for a CLI tool |

**Deprecated/outdated for this phase:**
- Using `afftdn` alone as the noise reduction output (not just analysis): DeepFilterNet is significantly better quality for perceptual noise removal.
- LRO polling pattern from Phase 21: ElevenLabs is synchronous; no polling code needed.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Nim unittest (stdlib) |
| Config file | honeyclip.nimble `task test` |
| Quick run command | `nim c --path:src -r tests/unit_audio.nim` |
| Full suite command | `nimble test` (runs both `tests/unit.nim` and `tests/unit_audio.nim`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUDIO-01 | Auto-detect flags correct stages from fixture audio stats | unit | `nim c --path:src -r tests/unit_audio.nim` (suite "audio analyzer") | ❌ Wave 0 |
| AUDIO-01 | Loudnorm subprocess builds correct two-pass FFmpeg command | unit | same | ❌ Wave 0 |
| AUDIO-02 | DeepFilterNet detection returns false when not installed | unit | same (suite "deepfilter provider") | ❌ Wave 0 |
| AUDIO-02 | DeepFilterNet subprocess command correctly assembled with 48kHz input path | unit | same | ❌ Wave 0 |
| AUDIO-02 | resolveProvider returns apLocal when DeepFilterNet available | unit | same (suite "provider selection") | ❌ Wave 0 |
| AUDIO-03 | elevenlabsIsolate calls postMultipart with xi-api-key header | unit | same (suite "elevenlabs provider") | ❌ Wave 0 |
| AUDIO-03 | confirmElevenlabsCost auto-allows ≤ $1 and prompts > $1 | unit | same (suite "elevenlabs cost") | ❌ Wave 0 |
| AUDIO-03 | resolveProvider returns apElevenlabs when DFN absent + key set | unit | same | ❌ Wave 0 |
| AUDIO-03 | resolveElevenlabsKey reads env first, TOML fallback | unit | same (suite "config") | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `nim c --path:src -r tests/unit_audio.nim`
- **Per wave merge:** `nimble test`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `tests/unit_audio.nim` — main test binary for Phase 22 (9 suites listed above)
- [ ] `tests/fixtures/audio_elevenlabs_response.wav` — minimal valid WAV (1 second silence, 44.1kHz stereo) for mock ElevenLabs response
- [ ] `tests/fixtures/audio_stats.json` — sample astats/afftdn output fixture for analyzer tests
- [ ] Add `unit_audio` to `nimble test` task in `honeyclip.nimble`
- [ ] FFmpeg filter allowlist update in `honeyclip.nimble` + `nimble makeff` (Wave 0 build task)

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | Input file path validated via `fileExists`; API response written to temp path before final rename |
| V6 Cryptography | no | API key transmitted over HTTPS; no local crypto needed |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| API key logged in error messages (T-22-02) | Information disclosure | Never pass `apiKey` to log procs; grep gate in threat check |
| Path traversal in output file path | Tampering | Validate `-o` flag; `extractFilename` for deepFilter output path construction |
| Temp file not cleaned on error | Denial of service (disk) | `defer: try: removeFile(tmpPath) except: discard` on all temp files |
| ElevenLabs response written as text (garbled binary) | Tampering | `writeFile` (byte-exact), not string parsing |
| Cost bypass on non-TTY | Elevation of privilege | Default-deny > $1 on non-TTY unless `--yes` passed |

---

## Open Questions for Planner / User

### OQ-1: Two deepFilter command variants — which to prefer?

`pip install deepfilternet` installs both `deepFilter` (Python script entry point) and `python3 -m df.enhance` (module invocation). The GitHub README shows `deepFilter path/to/audio.wav` as the primary command. However, on some systems (especially Windows via Git Bash), the Python script entry point may not be in PATH after pip install. Recommendation: try `deepFilter` first; if it fails (nonzero exit / command not found), fall back to `python3 -m df.enhance`. The detection check `python3 -c "import df"` only confirms the module exists, not that the script is in PATH.

**Planner action:** Include a `whichDeepFilter(): string` proc that returns the working command variant, or document the fallback order.

### OQ-2: ametadata filter availability in FFmpeg subprocess for astats readback

The `astats` + `ametadata` combination (used to read audio statistics to stdout/file) requires that FFmpeg was built with both `astats` and `ametadata` in the filter allowlist. This is being added in Wave 0. However, the `ametadata` filter's `print` mode outputs to a file path, not stdout, unless `file=pipe:1` is used. The `pipe:1` protocol (`--disable-protocols` + `--enable-protocol=file` in the FFmpeg build — line 942 of honeyclip.nimble) may block `pipe:` protocol. If `pipe:` is disabled, stats must be written to a temp file and read back.

**Planner action:** Wave 0 verification task — confirm `ametadata=print:file=pipe:1` works in the built FFmpeg, or provide a temp-file fallback path.

### OQ-3: ElevenLabs response audio codec and post-processing

ElevenLabs `/v1/audio-isolation/stream` returns "raw audio bytes." Based on search results, the default output appears to be MP3 (44.1kHz). Before the subsequent FFmpeg hum+deess chain, this needs to be decoded. If the response is MP3, write it to `tmp_isolated.mp3`, run FFmpeg `ffmpeg -i tmp_isolated.mp3 -f wav tmp_isolated.wav` (decode), then apply hum/deess chain. The planner should account for this decode step.

**Planner action:** Document the intermediate format conversion step in the ElevenLabs → FFmpeg chain. [LOW confidence — response format not explicitly confirmed from official docs; treat as MP3 decode needed unless testing shows otherwise]

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Python 3.x | DeepFilterNet subprocess | ✓ | 3.11.9 | ElevenLabs API path |
| DeepFilterNet (`df` module) | Local backend | ✗ | — | ElevenLabs API path (per CONTEXT.md) |
| FFmpeg (built-in) | Analysis + hum/deess chain | ✓ (build present) | 8.0.1 | — |
| `deesser` filter | De-ess stage | ✗ (not in allowlist) | 8.0.1 | Add to allowlist + rebuild (Wave 0) |
| `highpass`/`equalizer` filters | Hum removal | ✗ (not in allowlist) | 8.0.1 | Add to allowlist + rebuild (Wave 0) |
| `afftdn`/`astats` filters | Auto-detect analyzer | ✗ (not in allowlist) | 8.0.1 | Add to allowlist + rebuild (Wave 0) |
| ElevenLabs API key | API backend | ✗ (not configured) | — | Local backend (if DeepFilterNet installed) |

**Missing dependencies with no fallback:**
- FFmpeg filter allowlist additions (`deesser`, `highpass`, `equalizer`, `afftdn`, `astats`, `ametadata`, `anullsink`) — must be added in Wave 0 before any audio enhancement code can be tested end-to-end.

**Missing dependencies with fallback:**
- DeepFilterNet: Python installed (3.11.9) but `df` module not installed. Users install via `pip install deepfilternet`. Auto-fallback to ElevenLabs if not present.
- ElevenLabs key: not configured in this environment. Local path via DeepFilterNet is the fallback (once installed).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `deepFilter -o outDir input.wav` writes output to `outDir/basename(input.wav)` | DeepFilterNet subprocess contract | Wrong output path → process thinks run failed; easy to fix |
| A2 | Noise floor threshold for denoise detection is -55 dBFS | Auto-detect stage thresholds | Too aggressive or too lenient; tuning required on real samples |
| A3 | De-ess ratio threshold 4kHz+/broadband RMS > 0.15 | Auto-detect stage thresholds | False positives on bright music; false negatives on light sibilance |
| A4 | Hum detection threshold -50 dBFS in 45-65Hz band | Auto-detect stage thresholds | False positives with bass content; adjust to -45 dBFS if needed |
| A5 | `ametadata=print:file=pipe:1` works in honeyclip's built FFmpeg | OQ-2 | Must fall back to temp file if pipe: protocol is disabled |
| A6 | ElevenLabs response is MP3 format (not WAV PCM) by default | OQ-3 | If WAV PCM, skip decode step; if other format, add appropriate ffmpeg decode |
| A7 | `runLoudnormTwoPassSubprocess` in ffmpeg_chain.nim is the correct approach vs reusing src/render/audio.nim | Loudnorm Two-Pass Decision | If reuse is feasible, reduces code; but framing as separate proc is safer |
| A8 | Demucs is not viable for local voice isolation (CPU too slow) | Voice Isolation | If user has GPU and is willing to wait, Demucs is viable; out of scope for Phase 22 per deferred ideas |

---

## Sources

### Primary (HIGH confidence)
- `src/broll/provider.nim`, `src/broll/veo.nim`, `src/cmds/broll.nim`, `src/http_client.nim`, `src/config.nim` — verified in codebase
- `honeyclip.nimble` lines 924-944 — verified filter allowlist and FFmpeg build configuration
- `src/render/audio.nim` — verified loudnorm two-pass implementation (in-process, not file-path based)
- [CITED: elevenlabs.io/docs/api-reference/audio-isolation/stream] — endpoint URL, auth header, multipart format, synchronous behavior
- [CITED: github.com/Rikorose/DeepFilterNet README] — CLI command `deepFilter`, 48kHz WAV requirement, Python module import `df`

### Secondary (MEDIUM confidence)
- [CITED: help.elevenlabs.io Voice Isolator pricing search results] — $0.10/min, 500MB / 1hr limit, 10 min free
- [CITED: ffmpeg.org/ffmpeg-filters.html + ayosec.github.io/ffmpeg-filters-docs/8.0] — deesser, highpass, equalizer, afftdn, astats filter documentation
- [CITED: DeepFilterNet GitHub — August 2023 latest release v0.5.6] — version stability
- [CITED: Demucs performance data from search results] — 10-15 min/track CPU, <90s GPU

### Tertiary (LOW confidence)
- ElevenLabs response codec (MP3 default) — inferred from output format documentation; not confirmed for audio-isolation endpoint specifically
- Auto-detect heuristic thresholds — derived from DSP literature; require empirical validation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all reusing verified Phase 21 infrastructure; only FFmpeg filters are new
- Architecture: HIGH — direct mirror of Phase 21 patterns; AudioProvider variant shape is clear
- Auto-detect analyzer: MEDIUM — hum and de-ess HIGH; noise MEDIUM; reverb and voice isolation LOW (but routing around them)
- ElevenLabs API: MEDIUM — endpoint and auth confirmed; response codec LOW
- FFmpeg filter availability: HIGH — confirmed missing from allowlist; confirmed to exist in FFmpeg 8.0.1

**Research date:** 2026-05-09
**Valid until:** 2026-06-08 (ElevenLabs pricing subject to change; DeepFilterNet stable)

---

## RESEARCH COMPLETE

**Phase:** 22 - AI Audio Enhancement
**Confidence:** MEDIUM-HIGH (architecture HIGH; auto-detect MEDIUM; API specifics MEDIUM)

### Key Findings

- **FFmpeg filter allowlist blocks everything.** The honeyclip FFmpeg build disables all filters except an explicit allowlist (line 927, honeyclip.nimble). `deesser`, `highpass`, `equalizer`, `afftdn`, `astats`, `ametadata`, and `anullsink` are ALL missing. Wave 0 must add these and rebuild (1-2 hours for `nimble makeff`).
- **ElevenLabs is synchronous (no LRO).** `POST /v1/audio-isolation/stream` returns audio bytes directly. Simpler than Veo; no `asyncdispatch` needed. Auth via `xi-api-key` header; multipart form upload with `audio` binary field.
- **Voice isolation is API-only.** Demucs (GPU-required) is not viable for a CLI tool on CPU. Local path (DeepFilterNet) handles denoise+de-reverb only; voice isolation silently skips in local mode and always runs in ElevenLabs mode.
- **Auto-detect verdict: MEDIUM confidence.** Hum and de-ess detection are reliable via narrowband FFmpeg probes. Noise floor detection via afftdn is workable. De-reverb and voice isolation detection are LOW confidence; route around them by making de-reverb free-with-DeepFilterNet and voice isolation free-with-ElevenLabs.
- **ElevenLabs cost: ~$0.10/min** ($1 auto-allow threshold covers 10 minutes; cost gate needed for longer content).
- **DeepFilterNet subprocess:** `deepFilter -o outDir input.wav` (48kHz WAV only); detection via `python3 -c "import df"` exit-0 check; output at `outDir/basename(inputWav)`.

### File Created
`.planning/phases/22-ai-audio-enhancement/22-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | All Phase 21 infrastructure verified in codebase; new FFmpeg filters confirmed in FFmpeg 8.0.1 docs |
| Architecture | HIGH | Direct mirror of Phase 21 patterns; AudioProvider shape clear; all module paths defined |
| Auto-detect analyzer | MEDIUM | Hum/de-ess HIGH; noise floor MEDIUM; reverb/voice isolation LOW but routed around |
| ElevenLabs API | MEDIUM | Endpoint/auth/format confirmed; response codec LOW confidence |
| FFmpeg filter allowlist | HIGH | Confirmed missing; confirmed valid in FFmpeg 8.0.1 |
| DeepFilterNet subprocess | MEDIUM | CLI command confirmed; exit codes and fallback command path assumed |

### Open Questions Remaining

1. **OQ-1:** `deepFilter` vs `python3 -m df.enhance` — which is more reliable on Windows PATH?
2. **OQ-2:** Does `ametadata=print:file=pipe:1` work in honeyclip's FFmpeg build (`--disable-protocols` except `file`)? If not, temp-file fallback needed.
3. **OQ-3:** ElevenLabs response audio codec — MP3 (assumed) or PCM WAV? Affects whether intermediate decode step is needed.

### Ready for Planning

Research complete. Planner can create PLAN.md files. Wave 0 has two gates: (1) FFmpeg allowlist update + rebuild, (2) test scaffolding (`tests/unit_audio.nim`). All other waves can proceed in parallel once those gates clear.
