# Phase 22 Context: AI Audio Enhancement

**Created:** 2026-05-09
**Phase:** 22 — AI Audio Enhancement
**Goal:** Users can enhance audio quality with local models or API fallback
**Requirements:** AUDIO-01, AUDIO-02, AUDIO-03

## Domain

Phase 22 introduces honeyclip's first **audio-quality** AI feature and its second network-dependent capability (after Phase 21's B-roll). The feature scope is a multi-stage enhancement chain (denoise → de-reverb → de-ess → hum removal → loudness normalization) plus voice isolation, exposed via a new `honeyclip enhance` subcommand. Phase 22 inherits the Phase 21 infrastructure (HttpClientLike abstraction, src/config.nim env+TOML loader, Provider object-variant pattern, cost-gate philosophy) wholesale — the novel work is the enhancement chain itself, the **auto-detect analyzer** that decides which stages to apply, and the DeepFilterNet Python-subprocess integration.

## Canonical refs

Downstream agents (researcher, planner) MUST read these before acting:

- `.planning/ROADMAP.md` — Phase 22 entry
- `.planning/REQUIREMENTS.md` — AUDIO-01..03 requirements
- `.planning/PROJECT.md` — "Local-first AI with API fallback"
- `.planning/codebase/ARCHITECTURE.md` — multi-stage CLI pipeline
- `.planning/codebase/INTEGRATIONS.md` — confirm and update for ElevenLabs
- `.planning/phases/21-ai-broll-integration/21-CONTEXT.md` — locked decisions to mirror (Provider pattern, cost-gate, --yes, config.toml location)
- `.planning/phases/21-ai-broll-integration/21-01-SUMMARY.md` — what's already built (HttpClientLike, src/config.nim, src/http_client.nim)
- `.planning/phases/21-ai-broll-integration/21-02-SUMMARY.md` — provider variant pattern, cost-gate impl, subcommand pattern
- `src/render/audio.nim` — existing loudnorm capture infrastructure to reuse, NOT reinvent
- `src/cmds/broll.nim` — closest CLI analog for `honeyclip enhance`
- `src/broll/provider.nim` — closest analog for `AudioProvider` object variant
- `src/config.nim` — env-first then TOML resolver (extend with ElevenLabs key)
- `src/http_client.nim` — HttpClientLike abstraction (reuse for ElevenLabs)
- `src/cli.nim`, `src/main.nim` — subcommand registration pattern

## Decisions

### Enhancement chain (scope of "enhance audio quality")

The enhancement chain has **5 stages**, all in scope for this phase:

1. **Noise reduction** — background hiss, AC, keyboard, fan noise
2. **Voice isolation** — separate speaker from BGM/music (more aggressive than denoise)
3. **De-reverb** — reduce room/echo
4. **De-ess** — reduce sibilance
5. **Hum removal** — 50/60Hz electrical hum, AC line noise
6. **Loudness normalization** — EBU R128 to -16 LUFS (already partially in `src/render/audio.nim`, expose as final stage)

### Default behavior — auto-detect

When user runs `honeyclip enhance video.mp4` with no other flags, the tool **analyzes the audio first** and only applies stages whose target is detected. Stages and their detection signals (researcher confirms heuristics):

- Noise reduction → detect via spectral noise floor in non-speech regions
- Voice isolation → detect via spectral content in the music-typical band when speech is also present
- De-reverb → detect via reverb-tail decay measurement (T60-style heuristic)
- De-ess → detect via sibilance band (4-9 kHz) energy peaks
- Hum removal → detect via narrowband 50/60Hz energy
- Loudness normalization → always run as final stage

**Researcher must specify** the analyzer's signal-extraction approach for each stage. This is the single highest-risk decision: auto-detect is harder than a fixed chain. If research shows the analyzer is too costly or unreliable, the planner may downgrade to "full chain by default with `--no-{stage}` opt-outs" (the second-place option from discussion).

**Per-stage opt-in / opt-out flags:** `--{stage}=on|off|auto` (e.g., `--denoise=off`, `--voice-isolation=on`). Default for every stage is `auto`. `auto` = run if detected; `on` = always run; `off` = never run.

### Local backend

- **Local backend:** DeepFilterNet via Python subprocess. We do NOT bundle Python; users `pip install deepfilternet` themselves. Detection: `python3 -c "import df"` exit-0 check.
- **What DeepFilterNet covers:** denoise + de-reverb (its model produces both)
- **What FFmpeg covers locally** (no extra deps, ships in honeyclip's FFmpeg build):
  - Hum removal — FFmpeg `highpass=f=80` or `equalizer` notches at 50/60Hz
  - De-ess — FFmpeg `deesser` filter
  - Loudness normalization — FFmpeg `loudnorm` (already wired in `src/render/audio.nim`)
- **Voice isolation locally** — DeepFilterNet does not isolate vocals from music. The local pipeline either skips voice-isolation when running locally, OR (researcher to confirm) uses a second model. **Researcher must answer:** is there a local voice-isolation model worth integrating, or does voice isolation force the API path?

### API backend

- **Provider:** ElevenLabs Voice Isolator API
- **Architecture:** `AudioProvider` object variant with `apLocal` and `apElevenlabs` kinds, designed so future providers (Adobe Enhance Speech if API ever ships, Krisp, Artlist) can drop in. Mirror Phase 21's `BrollProvider`.
- **What ElevenLabs covers:** voice isolation + denoise (combined). Not de-ess, not de-reverb, not hum, not loudnorm.
- **API+FFmpeg chain:** ElevenLabs (voice isolation + denoise) → FFmpeg (hum removal + de-ess + loudnorm) — chained locally after the API call

### Provider selection

Mirror Phase 21:
- **Local-first** when DeepFilterNet is detected
- **Auto-fallback to ElevenLabs API** when DeepFilterNet is not installed AND `ELEVENLABS_API_KEY` is configured (env or TOML)
- **Forced via `--backend local|elevenlabs|auto`** (default `auto`)
- **Hard error** when `auto` and neither path is available, with concrete remediation (install DeepFilterNet OR set ELEVENLABS_API_KEY)

### Windows behavior

- Windows users without Python/DeepFilterNet hit the API path automatically when `ELEVENLABS_API_KEY` is set, OR get a clean error pointing to both remediation options. **Do NOT** bundle Python with the Windows build. **Do NOT** silently downgrade to FFmpeg-only on Windows (would hide quality regression).
- The auto-detect analyzer must work on Windows even when DeepFilterNet is absent — analyzer is a pure-FFmpeg signal-extraction step, not dependent on the local enhancement model.

### Auth / config

- **API key:** `ELEVENLABS_API_KEY` env var first, fallback to TOML `[elevenlabs]` section in `$XDG_CONFIG_HOME/honeyclip/config.toml` (Linux/macOS) or `%APPDATA%\honeyclip\config.toml` (Windows). Reuse `src/config.nim` from Phase 21; add `resolveElevenlabsKey` proc.
- The same config.toml hosts `[gemini]` (Phase 21) and `[elevenlabs]` (Phase 22). No schema change beyond adding a section.

### Cost gate

ElevenLabs Voice Isolator is per-minute (~$0.20-1.00/min depending on tier). Pre-flight cost gate:

- **Estimate cost** before submitting (audio duration × per-minute rate)
- **Auto-allow** when estimated cost ≤ **$1.00**
- **Prompt confirm on TTY** when estimated cost > $1.00; show estimate and accept/decline
- **Default-deny on non-TTY** when cost > $1.00, unless `--yes` is passed
- `--yes` always bypasses (mirrors Phase 21's `confirmVeoCost`)

### CLI / output

- **Command:** new `honeyclip enhance` subcommand. Mirror Phase 21's `broll` exactly.
- **Default input:** any FFmpeg-readable file (video or audio). Detection via probe.
- **Default output:** **video** with enhanced audio replacing original audio. Video stream copied (`-c:v copy`), audio re-encoded. Default output path `{input}.enhanced.{ext}` or `-o`.
- **`--audio-only` flag:** emit a cleaned audio file (WAV by default, format selectable later). No video re-mux.
- **NOT modifying** the main `honeyclip video.mp4` edit command. Subcommand-only mirrors Phase 21.

### Audio sample rate / channel handling

- DeepFilterNet expects 48kHz mono. Source can be any rate/channel.
- The pipeline resamples to 48kHz mono before DeepFilterNet, processes, then resamples back to source rate/channel layout for the final mux.
- ElevenLabs accepts wider input. Researcher to confirm exact requirements (typical: 16-bit PCM WAV up to some MB limit).

## Open questions for researcher

These were surfaced during discussion but require codebase + external-doc investigation before planning:

1. **Auto-detect signal extraction per stage** — concrete algorithm + threshold for noise / reverb / sibilance / hum. Output: function signatures + defended heuristic thresholds. HIGHEST RISK: if these are unreliable, the user gets surprising behavior. If too expensive, scan time dominates.

2. **DeepFilterNet subprocess invocation contract** — command-line args, input/output file format, sample-rate/channel requirements, exit codes, error format. Confirm the `df` Python module's CLI shape and version stability.

3. **Voice isolation locally** — is there a viable local model (Spleeter? Demucs? a DeepFilterNet variant)? OR is voice isolation API-only? If local-only path lacks voice-isolation, document that the analyzer should never trigger voice-isolation when running local.

4. **ElevenLabs Voice Isolator API specifics** — auth header, sync vs async, request body format (multipart? JSON+base64?), response format, max input duration/size, pricing tier (which tier maps to "voice isolator" specifically). Document per-minute cost.

5. **FFmpeg de-ess filter availability** — is `deesser` available in honeyclip's FFmpeg build? If not, document the workaround (multiband compressor + sibilance-band sidechain) or recommend enabling.

6. **Loudnorm two-pass integration** — `src/render/audio.nim` already does single-pass loudnorm capture. For Phase 22, two-pass is more accurate. Decide: reuse the existing single-pass infra and accept slight inaccuracy, or extend to two-pass for the enhance pipeline.

7. **Long-file chunking** — ElevenLabs may have file-size limits. Strategy for hour-long inputs: chunk → submit in parallel → reassemble (with care at chunk boundaries to avoid clicks). Researcher proposes chunk size + crossfade strategy.

8. **Hum frequency detection** — 50Hz vs 60Hz varies by region. Researcher: detect via narrowband FFT bin energy and apply targeted notch, OR always notch both (cheaper, mild high-pass side effect).

## Deferred ideas

Captured here so they aren't lost — out of scope for Phase 22:

- Adobe Enhance Speech provider (no public API as of writing)
- Artlist / Krisp / other API providers
- Real-time enhancement (streaming) — Phase 22 is offline-only
- User-supplied DSP chain (free-form filter graph)
- AI-generated background music removal (separate from voice isolation)
- Per-segment enhancement (different settings per timeline segment)
- `--enhance-audio` flag on the main edit command (subcommand-only this phase)
- Saving / loading enhancement profiles to TOML
- Bundled Python distribution for Windows

## Code context

Reusable patterns / assets the researcher should plan to leverage:

- `src/config.nim` — extend with `resolveElevenlabsKey`; add `[elevenlabs]` TOML section parsing
- `src/http_client.nim` — reuse `HttpClientLike` for ElevenLabs HTTP calls (multipart upload may need extension)
- `src/broll/provider.nim` — pattern for `src/audio/provider.nim` `AudioProvider` object variant
- `src/cmds/broll.nim` — pattern for `src/cmds/enhance.nim` (arg parsing, error handling via `try/except ValueError`, cost gate)
- `src/render/audio.nim` — existing loudnorm infrastructure; do NOT reimplement
- `src/log.nim` `info()` / `warning()` / `error()` — standard logging
- `tests/unit_broll.nim` — pattern for `tests/unit_audio.nim` with HttpClientLike mocks + fixture transcripts
- `tests/test_broll.py` — pattern for `tests/test_audio.py` E2E harness
- Phase 21 `confirmVeoCost` — direct analog for `confirmElevenlabsCost`

## Constraints carried forward

- **Local-first AI with API fallback** (PROJECT.md). DeepFilterNet local; ElevenLabs API.
- **Windows ML stub limitation** — face-detection is stubbed on Windows due to LTO. Audio enhancement has no native ML in honeyclip's binary; both paths are external (Python subprocess or HTTP API), so Windows works for both backends provided dependencies are met.
- **No new nimble deps required** — `toml_serialization` already in nimble file (Phase 21); HTTP via stdlib; FFmpeg subprocess via `osproc.execCmdEx`.
- **API key never logged** (Phase 21 threat T-21-02 carries forward to ELEVENLABS_API_KEY).

## Scope sanity flag

The chosen scope (5-stage enhancement chain + auto-detect analyzer + dual backend + dual output format) is roughly equivalent in surface area to Phase 21. The single biggest cost driver is **auto-detect**: if the analyzer is too unreliable in research, the planner should downgrade default behavior to "full chain with --no-{stage} opt-outs" (the second-place answer from discuss-phase). Researcher MUST report a confidence level on auto-detect before planner commits.

---
*Decisions captured for downstream researcher and planner. Researcher should treat the "Open questions" section as the research backlog. Auto-detect is the highest-risk decision and warrants the deepest research.*
