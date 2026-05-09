# Phase 21: AI B-Roll Integration - Research

**Researched:** 2026-05-08
**Domain:** AI-generative video B-roll, async HTTP, ComfyUI/Veo orchestration, transcript topic-shift detection
**Confidence:** HIGH (architecture, stack, patterns) / MEDIUM (Veo API specifics, prompt-rewrite latency)

## Summary

Phase 21 introduces honeyclip's first network-dependent feature and first generative AI feature. It must (a) detect narrative-meaningful B-roll insertion points from existing transcript + engagement data, (b) generate short B-roll clips per insertion via ComfyUI (local) or Gemini Veo (remote), (c) emit a marker JSON describing detected points + generated clip paths, and optionally (d) mux those clips into a final video via FFmpeg subprocess. The Phase 18 (`chapters`) pattern provides a near-perfect skeleton: peak detection + greedy spacing + CLI command + multi-format export. The Phase 19-02 batch runner provides the proven post-processing subprocess pattern for the `--render` step.

Three constraints dominate the implementation:
1. **Variable-duration vs fixed-output mismatch.** Veo only emits fixed-length clips (8s in 2026). ComfyUI's frame count is workflow-controlled but model-bounded (AnimateDiff/WAN typically 2-16s natively). Honeyclip must adapt with a documented fitting strategy (truncate when too long, slow-pad / freeze-pad / re-request when too short).
2. **No prior HTTP usage.** Zero `httpclient` or `asyncdispatch` imports exist anywhere in `src/`. Veo's long-running operation (LRO) polling pattern (30-90s, sometimes minutes) effectively requires `std/asyncdispatch` + `std/httpclient.AsyncHttpClient`, even though ComfyUI alone could survive on sync polling.
3. **First config file.** No `~/.config/honeyclip` reads exist today. `toml_serialization` is already a dependency (used by `src/batch/templates.nim`), so the new `src/config.nim` should reuse `Toml.loadFile()` rather than introducing a second TOML library.

**Primary recommendation:** Mirror Phase 18 layering exactly — `src/analyze/broll.nim` (insertion-point detection, types, no I/O), `src/broll/provider.nim` + `src/broll/comfyui.nim` + `src/broll/veo.nim` (BrollProvider abstraction over an async HTTP boundary), `src/broll/render.nim` (FFmpeg mux subprocess in the Phase 19-02 style), `src/config.nim` (env→TOML key resolution), and `src/cmds/broll.nim` (CLI). Use `std/asyncdispatch` for Veo polling, `waitFor` to bridge to honeyclip's sync main path. Topic-shift detection should be a heuristic combining transcript-segment boundaries + speaker-pause length + engagement-score delta — no embeddings.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Insertion-point detection:** primary signal is transcript topic shift derived from existing transcript segments + speaker pauses. Density default ~1 insertion per 60s, 30s minimum spacing. User overrides via `--max-broll N` and `--min-spacing` flags. Mirrors Phase 18-01 chapter-spacing default.
- **Local backend:** ComfyUI via HTTP API to a user-running server. Default URL `http://127.0.0.1:8188`, overridable via flag/env.
- **ComfyUI workflow:** user supplies an exported workflow JSON template containing placeholder tokens (e.g., `{{PROMPT}}`, `{{SEED}}`, `{{LENGTH}}`). honeyclip substitutes per insertion. honeyclip does NOT ship a built-in workflow and does NOT auto-detect installed nodes.
- **Remote backend:** Gemini Veo only in this phase, behind a `BrollProvider` interface (Nim concept or object variant) so future providers (Runway, Pika) can drop in. Local ComfyUI path also expressible as a `BrollProvider`.
- **Selection:** local-first per PROJECT.md. CLI flag forces a specific backend. Auto-fallback to API when ComfyUI is unreachable AND an API key is configured.
- **Prompt sourcing:** auto. Take transcript window around each insertion point and run through Gemini Flash (same API key as Veo) to rewrite spoken language into a concrete visual prompt. **No** user-template override this phase.
- **API key:** read from `GEMINI_API_KEY` env var first, then fall back to TOML config at `$XDG_CONFIG_HOME/honeyclip/config.toml` on Linux/macOS, `%APPDATA%\honeyclip\config.toml` on Windows. Add a small `src/config.nim` module rather than scattering TOML reads.
- **Splice mechanism:** full cut. B-roll fully replaces the speaker video for its duration; original audio plays underneath, untouched. **No PIP / overlay mode this phase.**
- **Clip length:** variable, matches the underlying transcript pause length at each insertion point.
- **Command:** new `honeyclip broll` subcommand. Mirrors Phase 18's `honeyclip chapters` exactly.
- **Default output:** marker JSON file describing detected insertion points + generated clip paths.
- **Render flag:** `--render` muxes the final video. Reuses post-process subprocess pattern from Phase 19-02.
- **Existing edit command:** NOT modified to take a `--broll` flag in this phase.

### Claude's Discretion

- Topic-shift detector implementation: heuristic on transcript-segment boundaries + pause length + engagement delta vs embedding distance — researcher recommends a specific approach below.
- HTTP client choice (sync `httpclient` vs `AsyncHttpClient` + `asyncdispatch`) — researcher recommends async below.
- TOML library — researcher recommends reusing existing `toml_serialization` rather than adding `parsetoml`.
- Variable-duration fitting strategy per backend — researcher recommends a specific algorithm below.
- ComfyUI placeholder substitution syntax — researcher recommends `{{PROMPT}}/{{SEED}}/{{LENGTH}}` (Mustache-like) implemented via plain `string.replace`.
- BrollProvider Nim shape — researcher recommends `object variant` over `concept` for simpler dispatch and easier testing.

### Deferred Ideas (OUT OF SCOPE)

- Picture-in-picture / overlay mode (`--broll-mode cut|pip`).
- Additional API providers (Runway, Pika) beyond pluggable interface.
- User-supplied prompt templates with `{topic}` substitution.
- Auto-detected ComfyUI workflows from installed nodes.
- User-curated stock B-roll library / search.
- B-roll caching to avoid regenerating identical prompts.
- `--broll` flag on the main `edit` command for one-shot UX.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BROLL-01 | User can auto-detect B-roll insertion points in timeline | "Insertion-Point Detection" section: heuristic combining transcript-segment boundaries, speaker pauses (`Word.endMs[i+1] - Word.startMs[i] >= pauseThresholdMs`), and engagement-score delta from `EngagementTimeline.segments`. Reuses Phase 18 greedy-spacing selection. |
| BROLL-02 | User can generate B-roll locally via ComfyUI integration | "ComfyUI Provider" section: POST `/prompt` with workflow JSON (placeholder substitution via `string.replace`), poll `/history/{prompt_id}` until output node reports a saved file, fetch via `/view?filename=...&type=output`. |
| BROLL-03 | User can generate B-roll via API (Gemini or similar) | "Veo Provider" section: POST to `:predictLongRunning`, poll operation `name` via `:fetchPredictOperation` or GET `operations/{name}` until `done==true`, download MP4 from returned URI. Same `GEMINI_API_KEY` authorizes Veo + Flash. |
| BROLL-04 | Generated B-roll auto-inserts at detected points | "Render / Mux" section: marker-JSON describes insertions; `--render` triggers FFmpeg subprocess using `concat` demuxer + `overlay`/`select` filter pattern (full-cut splice). Reuses Phase 19-02 watermark/concat post-processing pattern. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Insertion-point detection | Analysis Layer (`src/analyze/broll.nim`) | — | Pure compute over Transcript + EngagementTimeline; mirrors `src/analyze/chapters.nim`. No I/O. |
| BrollProvider abstraction | New module group (`src/broll/`) | — | New external boundary; deserves its own namespace, parallel to `src/transcript/`, `src/brand/`. |
| HTTP I/O (ComfyUI, Veo, Flash) | `src/broll/comfyui.nim`, `src/broll/veo.nim`, `src/broll/flash.nim` | — | Each external service isolated; testable behind a shared `BrollProvider` variant. |
| Config / API-key resolution | New `src/config.nim` | — | Cross-cutting; env var first, then TOML fallback. Single read point for the codebase. |
| Marker JSON output | `src/exports/json.nim` extension OR new `src/broll/markers.nim` | `src/analyze/broll.nim` | Reuses existing JSON-export pattern; marker format owned by broll module. |
| Final video mux (`--render`) | `src/broll/render.nim` (FFmpeg subprocess) | Batch runner pattern | Post-processing via subprocess, identical pattern to Phase 19-02 watermark/concat. |
| CLI surface | `src/cmds/broll.nim` | `src/main.nim` (registration) | Mirrors `src/cmds/chapters.nim` exactly. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Nim stdlib | 2.2.2+ | Math, sorting, JSON, string ops | `[VERIFIED: codebase grep]` Already required by project |
| `std/httpclient` | stdlib | HTTP requests to ComfyUI / Gemini | `[CITED: nim-lang.org/docs/httpclient.html]` Stdlib, no new dep |
| `std/asyncdispatch` | stdlib | Long-running poll loops for Veo | `[CITED: nim-lang.org/docs/asyncdispatch.html]` Stdlib, no new dep |
| `std/json` | stdlib | Workflow JSON parse, marker JSON write, response parse | `[VERIFIED: src/exports/json.nim already uses it]` |
| `toml_serialization` | already required | Parse `config.toml` for API key fallback | `[VERIFIED: honeyclip.nimble line 14, used in src/batch/templates.nim:2]` Already a project dependency |
| `std/osproc` | stdlib | FFmpeg subprocess for `--render` mux | `[VERIFIED: src/batch/runner.nim already uses execCmdEx]` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| existing `engagement_types` | current | `EngagementTimeline`, `EngagementSegment.score` for engagement-delta signal | When computing topic-shift score component |
| existing `transcript/types` | current | `Transcript.segments`, `Word.startMs/endMs` for pause + segment-boundary signals | When computing topic-shift score component |
| existing `exports/json.nim` | current | Pretty-print JSON output for marker file | When writing default marker output |
| existing `log.nim` | current | `info()`, `debug()`, `error()` | All status output and error reporting |
| existing `util/bar` | current | Progress bar during multi-clip generation | When generating N>1 clips |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `toml_serialization` | `parsetoml` package | `[VERIFIED: nimble file]` `toml_serialization` is already a project dep; `parsetoml` would add a second TOML implementation. Reject. |
| `std/asyncdispatch` polling | sync `httpclient` + `sleep()` polling | Sync works but blocks; Veo can take 30-90s per clip and N clips per run. With async, multiple Veo jobs poll concurrently. `[CITED: nim-lang.org/docs/httpclient.html]` "An asynchronous client instance can only deal with one request at a time" — use multiple `AsyncHttpClient` instances for parallel jobs. |
| `concept` for BrollProvider | object variant `case kind: BrollProviderKind` | Concepts in Nim 2.2 still have caveats; object variants are concrete, debuggable, and easy to mock in tests. `[ASSUMED]` based on Nim community preference for variants in shipping code. |
| `embeddings` for topic shift | heuristic on transcript boundaries + pauses + engagement delta | Embeddings would add a model dependency (e.g., sentence-transformers via nimpy or onnx). Out of scope; heuristic is sufficient for v1. |
| picture-in-picture overlay filter | full-cut `concat`/`select` | PIP deferred per CONTEXT.md. |

**Installation:** No new nimble dependencies. All required libraries are either Nim stdlib or already in `honeyclip.nimble`.

**Version verification:**
- `toml_serialization`: `[VERIFIED: honeyclip.nimble line 14]` — version unpinned, last published version on Nimble was confirmed compatible with Nim 2.2 by the existing successful build of Phase 16 batch templates.
- Nim 2.2.2 stdlib: `httpclient`, `asyncdispatch`, `json`, `osproc` are all present. `[CITED: nim-lang.org/docs/httpclient.html]`

## Architecture Patterns

### System Architecture Diagram

```
                    honeyclip broll video.mp4 [model] [flags]
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │  src/cmds/broll.nim         │
                    │  - parse CLI args           │
                    │  - resolve config           │
                    │  - print + export marker JSON│
                    └────────────┬────────────────┘
                                 │
                ┌────────────────┼────────────────┬──────────────────┐
                ▼                ▼                ▼                  ▼
   ┌─────────────────┐  ┌──────────────────┐ ┌─────────────────┐  ┌─────────────────┐
   │ transcript/     │  │ analyze/         │ │ broll/          │  │ config.nim      │
   │ extract         │  │ engagement       │ │ provider.nim    │  │ - env first     │
   │ (existing)      │  │ (existing)       │ │ (new)           │  │ - TOML fallback │
   └────────┬────────┘  └────────┬─────────┘ └────────┬────────┘  └─────────────────┘
            │                    │                   │
            └────────┬───────────┘                   │
                     ▼                               │
        ┌────────────────────────────┐               │
        │ analyze/broll.nim (new)    │               │
        │ detectBrollInsertions(     │               │
        │   transcript, engagement,  │               │
        │   params) -> seq[Insertion]│               │
        │ - segment boundary signal  │               │
        │ - pause-length signal      │               │
        │ - engagement-delta signal  │               │
        │ - greedy spacing (P18)     │               │
        └─────────────┬──────────────┘               │
                      │                              │
                      ▼                              │
        ┌─────────────────────────────────────┐      │
        │ broll/provider.nim (new)            │◄─────┘
        │ BrollProvider variant:              │
        │   bpComfyUI | bpVeo                 │
        │ generate(insertion) -> ClipResult   │
        │ - local-first selection             │
        │ - auto-fallback on failure          │
        └─────┬──────────────────────┬────────┘
              │                      │
              ▼                      ▼
   ┌────────────────────┐   ┌─────────────────────┐
   │ broll/comfyui.nim  │   │ broll/veo.nim       │
   │ - placeholder sub  │   │ - asyncdispatch LRO │
   │ - POST /prompt     │   │ - POST :predictLR   │
   │ - poll /history    │   │ - poll operation    │
   │ - GET /view        │   │ - GET MP4 URI       │
   └────────────────────┘   └──────────┬──────────┘
                                       │  (prompts)
                                       ▼
                            ┌─────────────────────┐
                            │ broll/flash.nim     │
                            │ Gemini Flash:       │
                            │ rewrite transcript  │
                            │ window → visual     │
                            │ prompt              │
                            └─────────────────────┘

         ┌──────────────────────────────────────────────────────┐
         ▼  (default)                                           ▼ (--render)
   marker.json                                          broll/render.nim
   { insertions: [{ startMs, endMs,                     - FFmpeg subprocess
       pauseMs, prompt, clipPath, ... }] }              - concat/select splice
                                                        - audio underneath
                                                        - reuses P19-02 pattern
```

Data flow: video + model → transcript + engagement → insertion points → (per-point) Flash prompt → provider generation → clips on disk → marker JSON → optional final mux.

### Recommended Project Structure

```
src/
├── analyze/
│   └── broll.nim             # NEW: types, insertion-point detection (no I/O)
├── broll/                    # NEW namespace, parallel to brand/, transcript/
│   ├── provider.nim          # BrollProvider variant + selection/fallback
│   ├── comfyui.nim           # ComfyUI HTTP client (sync OK; ComfyUI poll is short)
│   ├── veo.nim               # Veo async LRO client
│   ├── flash.nim             # Gemini Flash prompt-rewrite
│   ├── workflow.nim          # ComfyUI workflow JSON load + placeholder substitution
│   ├── fitting.nim           # variable-duration fitting strategy (truncate/loop/repeat)
│   └── render.nim            # FFmpeg mux subprocess for --render
├── cmds/
│   └── broll.nim             # NEW: CLI command (mirror cmds/chapters.nim)
├── config.nim                # NEW: env→TOML key resolution
└── main.nim                  # MODIFIED: register "broll" handler
```

### Pattern 1: Insertion-Point Detection (Topic-Shift Heuristic)

**What:** Score each candidate point (transcript-segment boundary) by combining three normalized signals; greedy-select with min-spacing à la Phase 18.
**When to use:** Inside `detectBrollInsertions()` in `src/analyze/broll.nim`, after both transcript and engagement timeline are available.

**Signal mix (researcher recommendation):**

```nim
# In src/analyze/broll.nim
import std/[algorithm, math]
import ../transcript/types as transcriptTypes
import ../analyze/engagement_types

type
  BrollInsertion* = object
    startMs*: int64           # where the cut begins (start of pause)
    endMs*: int64             # where the cut ends (end of pause)
    pauseMs*: int64           # endMs - startMs (target B-roll duration)
    contextText*: string      # transcript window around the point (for Flash rewrite)
    score*: float32           # topic-shift score 0..100 (higher = stronger shift)
    sourceTag*: string        # "boundary"|"engagement-delta"|"long-pause" (for debug)

  BrollParams* = object
    minSpacingMs*: int64      # default 30_000 (mirrors Phase 18-01)
    targetDensityPerMin*: float32  # default 1.0 → ~1 per 60s
    maxInsertions*: int       # default = ceil(duration_minutes * targetDensityPerMin)
    minPauseMs*: int64        # default 800ms — pauses shorter than this aren't B-roll candidates
    maxPauseMs*: int64        # default 6000ms — pauses longer than this are still candidates but capped at maxPauseMs for clip length
    contextWindowSec*: int    # default 8 (transcript window before+after)
    minScore*: float32        # default 50.0 — below this, skip
    pauseWeight*: float32     # default 0.4
    boundaryWeight*: float32  # default 0.3
    engagementDeltaWeight*: float32  # default 0.3

proc defaultBrollParams*(): BrollParams =
  result.minSpacingMs = 30_000
  result.targetDensityPerMin = 1.0
  result.maxInsertions = -1   # -1 → derive from duration
  result.minPauseMs = 800
  result.maxPauseMs = 6000
  result.contextWindowSec = 8
  result.minScore = 50.0f
  result.pauseWeight = 0.4f
  result.boundaryWeight = 0.3f
  result.engagementDeltaWeight = 0.3f
```

**Algorithm:**

1. **Candidate enumeration** — walk `transcript.segments`. For each adjacent pair `(seg[i], seg[i+1])`, compute `pauseMs = seg[i+1].startMs - seg[i].endMs`. If `pauseMs < params.minPauseMs`, skip. Else this is a candidate at `(seg[i].endMs, seg[i+1].startMs)`.

2. **Score the candidate (0..100):**
   - **Pause-length component** (0..100): `min(100.0, pauseMs.float32 / params.maxPauseMs.float32 * 100.0)`. Longer pause = stronger candidate.
   - **Boundary component** (0..100): if `seg[i].speaker != seg[i+1].speaker` → 100; if both segments end in `.`/`!`/`?` and the next starts a new sentence → 75; else → 50 (any segment boundary is at least a soft boundary).
   - **Engagement-delta component** (0..100): find segments in `EngagementTimeline.segments` whose midpoint falls in `[seg[i].endMs - 1500, seg[i+1].startMs + 1500]`. Compute `abs(score_after - score_before)`. Map directly: a delta of 30+ engagement points → 100, 0 → 0, linear in between.
   - Combine: `score = pause * pauseWeight + boundary * boundaryWeight + engagementDelta * engagementDeltaWeight`.

3. **Filter** candidates with `score < params.minScore`.

4. **Greedy select** (mirror `detectEngagementPeaks` from `src/analyze/chapters.nim` line 111+):
   - Sort by score descending.
   - For each candidate: if no already-selected insertion is within `params.minSpacingMs`, accept.
   - Stop at `maxInsertions` (resolved from `targetDensityPerMin` if `-1`).

5. **Sort** selected chronologically and return.

6. **Set `endMs = startMs + min(pauseMs, params.maxPauseMs)`** so an absurdly long pause doesn't request a 60-second B-roll clip.

7. **Build `contextText`**: concatenate transcript words whose `startMs` falls within `[insertion.startMs - contextWindowSec*1000, insertion.endMs + contextWindowSec*1000]`, joined by space. This is the input to `flash.nim` for prompt rewriting.

`[ASSUMED]` Specific signal weights (0.4/0.3/0.3) and thresholds (minPauseMs=800) are reasonable starting values; they may need tuning after dogfooding. The planner should expose these as CLI flags (`--pause-weight`, etc.) only if user feedback demands it — start with hardcoded defaults.

### Pattern 2: BrollProvider as Object Variant

**What:** A tagged union over the supported backends, dispatched in a single `generate()` proc.
**When to use:** All call sites that produce a clip from an insertion + prompt.

```nim
# In src/broll/provider.nim
import std/[asyncdispatch, options]
import ../analyze/broll as brollAnalyze

type
  BrollProviderKind* = enum
    bpComfyUI
    bpVeo

  BrollProvider* = object
    case kind*: BrollProviderKind
    of bpComfyUI:
      comfyUrl*: string         # e.g., "http://127.0.0.1:8188"
      workflowPath*: string     # path to user's exported workflow JSON
    of bpVeo:
      apiKey*: string
      model*: string            # e.g., "veo-3.0-fast-generate-001"

  ClipResult* = object
    success*: bool
    clipPath*: string           # absolute path to MP4 on disk
    actualDurationMs*: int64    # may differ from requested
    error*: string

proc generate*(p: BrollProvider, insertion: BrollInsertion, prompt: string,
               outDir: string): Future[ClipResult] {.async.} =
  case p.kind:
  of bpComfyUI:
    result = await comfyuiGenerate(p, insertion, prompt, outDir)
  of bpVeo:
    result = await veoGenerate(p, insertion, prompt, outDir)
```

**Why a variant, not a `concept`:**
- Easier to mock in tests (just construct a `BrollProvider(kind: bpComfyUI, comfyUrl: "http://mock", ...)`).
- Concrete dispatch — no compiler magic, debuggable.
- `case` exhaustiveness checks at compile time when Nim grows new providers.

**Selection + auto-fallback** (researcher recommendation, mirror local-first PROJECT.md decision):

```nim
proc resolveProvider*(forceBackend: string, comfyUrl: string,
                      workflowPath: string, apiKey: string,
                      model: string): BrollProvider =
  ## Resolve provider per CONTEXT.md selection rule:
  ## - explicit --backend wins
  ## - else: try ComfyUI; if reachable, use it
  ## - else if apiKey set: use Veo
  ## - else: error with actionable message
  if forceBackend == "comfyui":
    return BrollProvider(kind: bpComfyUI, comfyUrl: comfyUrl, workflowPath: workflowPath)
  if forceBackend == "veo":
    if apiKey == "":
      error "Backend 'veo' requires GEMINI_API_KEY env var or config.toml [api] gemini_key"
    return BrollProvider(kind: bpVeo, apiKey: apiKey, model: model)
  # Auto: local-first
  if isComfyReachable(comfyUrl):
    return BrollProvider(kind: bpComfyUI, comfyUrl: comfyUrl, workflowPath: workflowPath)
  if apiKey != "":
    info &"ComfyUI not reachable at {comfyUrl}; falling back to Veo"
    return BrollProvider(kind: bpVeo, apiKey: apiKey, model: model)
  error &"No B-roll backend available. Start ComfyUI at {comfyUrl} or set GEMINI_API_KEY."
```

`isComfyReachable` is a 2-second-timeout GET to `{comfyUrl}/system_stats`.

### Pattern 3: ComfyUI Client (sync HTTP, short polls OK)

`[CITED: docs.comfy.org/development/cloud/overview, deepwiki.com/Comfy-Org/ComfyUI/7.3-workflow-json-format]`

**API surface** honeyclip uses:
- `POST /prompt` body `{"prompt": <workflow JSON>, "client_id": "<uuid>"}` → returns `{"prompt_id": "<uuid>", ...}`.
- `GET /history/{prompt_id}` → returns `{<prompt_id>: {"status": {"completed": bool, ...}, "outputs": {<node_id>: {"images": [...]} | {"gifs": [...]} | {"videos": [...]}}}}`. Empty object until done.
- `GET /view?filename=<f>&subfolder=<s>&type=output` → fetches the actual file bytes.

**Workflow JSON format:** API-format export. Top level is `{<node_id>: {"class_type": "...", "inputs": {...}, "_meta": {...}}}`. Honeyclip does NOT parse this structurally — it does a string-level placeholder substitution, then submits.

**Placeholder substitution (recommended Mustache-style):**

```nim
# In src/broll/workflow.nim
proc substituteWorkflow*(workflowJson: string, prompt: string,
                         seed: int64, lengthFrames: int): string =
  ## String-level substitution. User is responsible for putting placeholders
  ## in their workflow at the correct nodes (e.g., the CLIPTextEncode node's
  ## "text" input, KSampler's "seed" input, AnimateDiff loader's "frame_count").
  result = workflowJson
    .replace("{{PROMPT}}", escapeJson(prompt))
    .replace("{{SEED}}", $seed)
    .replace("{{LENGTH}}", $lengthFrames)
```

`escapeJson` ensures the prompt string is safe to embed inside an existing JSON string literal (escape `"`, `\`, control chars).

**Polling pattern (sync, 1-second interval, 5-min timeout):**

```nim
proc comfyuiGenerate*(p: BrollProvider, insertion: BrollInsertion,
                     prompt: string, outDir: string): Future[ClipResult] {.async.} =
  let workflowRaw = readFile(p.workflowPath)
  let lengthFrames = max(8, int(insertion.pauseMs * 24 div 1000))  # assume 24 fps
  let body = substituteWorkflow(workflowRaw, prompt, rand(int64.high), lengthFrames)

  let client = newAsyncHttpClient()
  let submitResp = await client.post(p.comfyUrl & "/prompt",
                                     body = """{"prompt":""" & body & ""","client_id":"honeyclip"}""")
  let promptId = parseJson(await submitResp.body)["prompt_id"].getStr

  # Poll /history/{prompt_id} every 1s, max 300s
  for attempt in 0 ..< 300:
    await sleepAsync(1000)
    let hist = await client.getContent(p.comfyUrl & "/history/" & promptId)
    let histJson = parseJson(hist)
    if histJson.hasKey(promptId):
      let outputs = histJson[promptId]["outputs"]
      # Find the first node whose outputs contain a video/gif/image file
      for nodeId, nodeOut in outputs:
        for kind in ["videos", "gifs", "images"]:
          if nodeOut.hasKey(kind) and nodeOut[kind].len > 0:
            let f = nodeOut[kind][0]
            return await downloadFile(client, p.comfyUrl, f, outDir)
  return ClipResult(success: false, error: "ComfyUI timeout after 300s")
```

### Pattern 4: Veo Async Long-Running Operation Client

`[CITED: ai.google.dev/gemini-api/docs/video]` Veo uses Google's standard LRO pattern.

**API surface (Gemini API, NOT Vertex AI):**
- `POST https://generativelanguage.googleapis.com/v1beta/models/veo-3.0-fast-generate-001:predictLongRunning?key={GEMINI_API_KEY}` body:
  ```json
  {
    "instances": [{"prompt": "<text>"}],
    "parameters": {"aspectRatio": "16:9", "personGeneration": "allow_adult"}
  }
  ```
  → returns `{"name": "models/veo-3.0-fast-generate-001/operations/<id>"}`.
- `GET https://generativelanguage.googleapis.com/v1beta/{operation_name}?key={GEMINI_API_KEY}` → returns operation status. Check `done` field. When `done==true`, response includes either `response.generateVideoResponse.generatedSamples[0].video.uri` (Files API URI) or an error.
- Poll interval: 10 seconds. Total timeout: 600 seconds. `[CITED: ai.google.dev — "video generation takes 30-90 seconds, use timeouts of at least 5-10 minutes"]`

**Output:** MP4 (H.264), 24 fps, **fixed 8-second** duration in 2026 (Veo 3.1). Aspect ratios: 16:9, 9:16, 1:1. Resolution selectable: 720p / 1080p / 4k.

**Cost:** `[CITED: ai.google.dev/gemini-api/docs/pricing, veo3ai.io/blog/veo-3-pricing-2026]`
- Veo 3 Fast: $0.15/sec → $1.20 per 8-sec clip
- Veo 3 Standard: $0.40/sec → $3.20 per 8-sec clip
- The Gemini Flash 2.5 prompt-rewrite call is essentially free at this scale: $0.30/M input tokens, $2.50/M output tokens. A single rewrite is ~500 tokens in + 100 tokens out ≈ $0.0004 per rewrite. Negligible vs Veo cost.

**API key sharing:** `[VERIFIED: ai.google.dev/gemini-api/docs/pricing]` A single `GEMINI_API_KEY` authorizes both Veo and Gemini Flash text generation through `generativelanguage.googleapis.com`. No separate key needed.

**Async polling pattern:**

```nim
# In src/broll/veo.nim
import std/[asyncdispatch, httpclient, json, strformat]

const veoBase = "https://generativelanguage.googleapis.com/v1beta"

proc veoGenerate*(p: BrollProvider, insertion: BrollInsertion,
                  prompt: string, outDir: string): Future[ClipResult] {.async.} =
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})

  let aspect = "16:9"  # could be CLI flag in future
  let body = %*{
    "instances": [{"prompt": prompt}],
    "parameters": {"aspectRatio": aspect, "personGeneration": "allow_adult"}
  }
  let submitUrl = &"{veoBase}/models/{p.model}:predictLongRunning?key={p.apiKey}"
  let submitResp = await client.postContent(submitUrl, $body)
  let opName = parseJson(submitResp)["name"].getStr

  # Poll every 10s, max 60 attempts (10 min total)
  let pollUrl = &"{veoBase}/{opName}?key={p.apiKey}"
  for attempt in 0 ..< 60:
    await sleepAsync(10_000)
    let pollResp = await client.getContent(pollUrl)
    let opJson = parseJson(pollResp)
    if opJson.hasKey("done") and opJson["done"].getBool:
      if opJson.hasKey("error"):
        return ClipResult(success: false, error: opJson["error"]["message"].getStr)
      let videoUri = opJson["response"]["generateVideoResponse"]["generatedSamples"][0]["video"]["uri"].getStr
      # videoUri is a Files API URI; download via GET with key appended
      return await downloadVeoVideo(client, videoUri, p.apiKey, outDir, insertion)
  return ClipResult(success: false, error: "Veo timeout after 600s")
```

### Pattern 5: Variable-Duration Fitting (HIGHEST RISK)

**The mismatch:**
- ComfyUI: workflow-controlled. `{{LENGTH}}` placeholder maps to AnimateDiff/WAN frame_count or context_length. Range typically 8-200 frames (≈ 0.3s-8s at 24 fps; longer with sliding window). User's workflow may or may not honor `{{LENGTH}}`.
- Veo: **strict 8-second output, no duration parameter.** `[CITED: ai.google.dev/gemini-api/docs/video — "Currently 8 seconds per generation"]`

**Insertion pause distribution (likely):** 0.8s-6s based on natural conversation pauses. Most pauses < Veo's 8s.

**Fitting strategy (recommended):**

```nim
# In src/broll/fitting.nim
type
  FittingStrategy* = enum
    fsTruncate          # actual > requested → cut to requested length
    fsPadFreeze         # actual < requested → freeze last frame to fill
    fsPadSpeedRamp      # actual < requested → tpf=requested/actual via setpts
    fsRequestExtra      # ComfyUI only: re-request with longer LENGTH

proc fitClipDuration*(clipPath: string, requestedMs: int64,
                     actualMs: int64, strategy: FittingStrategy,
                     outPath: string): bool =
  ## Use FFmpeg subprocess to adapt clip to requested duration.
  let cmd = case strategy:
  of fsTruncate:
    &"ffmpeg -y -i {clipPath.quoteShell} -t {requestedMs / 1000} -c copy {outPath.quoteShell}"
  of fsPadFreeze:
    let padMs = requestedMs - actualMs
    # tpad with stop_mode=clone to freeze last frame
    &"ffmpeg -y -i {clipPath.quoteShell} -vf tpad=stop_mode=clone:stop_duration={padMs / 1000} {outPath.quoteShell}"
  of fsPadSpeedRamp:
    let speedRatio = actualMs.float / requestedMs.float
    &"ffmpeg -y -i {clipPath.quoteShell} -vf setpts={1.0 / speedRatio}*PTS {outPath.quoteShell}"
  of fsRequestExtra:
    raiseAssert "fsRequestExtra handled by provider, not fitting"
  let (_, exitCode) = execCmdEx(cmd)
  return exitCode == 0
```

**Per-backend recommendation:**

| Backend | Requested duration vs output | Strategy |
|---------|------------------------------|----------|
| **Veo (always 8s)** | requested ≤ 8s | `fsTruncate` to requested |
| **Veo (always 8s)** | requested > 8s | Cap target at 8s in detection (set `params.maxPauseMs = 8000`); document limit |
| **ComfyUI** | output < requested (workflow honored {{LENGTH}} but model maxed out) | `fsPadFreeze` for ≤500ms gap, `fsPadSpeedRamp` for ≤2000ms gap, otherwise log warning and accept short clip |
| **ComfyUI** | output > requested | `fsTruncate` |
| **ComfyUI** | output exactly matches | no fitting needed |

**Default `params.maxPauseMs = 6000` works for both backends.** For Veo, the truncate path is safe (Veo always returns 8s ≥ 6s requested). For ComfyUI, 6s is achievable with sliding-window AnimateDiff (>16 frames triggers sliding window per `[CITED: openart.ai/workflows/.../animatediff-flicker-free-animation-video-workflow]`).

**Highest-risk fallback:** if neither backend can produce the requested length and fitting fails, drop the insertion entirely (mark `success=false` in ClipResult, exclude from marker JSON, log a warning). Do not insert a black frame or fail the whole run.

### Pattern 6: Final Mux Subprocess (--render flag)

Mirror Phase 19-02's post-processing pattern (`src/batch/runner.nim:79,115,163` use `execCmdEx` for FFmpeg subprocess steps).

**Strategy:** segment the source video at insertion points, concat with B-roll clips substituted in the gaps, force original audio track underneath.

```
[seg0 source]──[broll_0]──[seg1 source]──[broll_1]──[seg2 source]── ...
audio: continuous source audio across the whole timeline
```

**Two viable FFmpeg approaches:**

1. **`concat` filter approach** (recommended for ≤10 insertions): build a single `-filter_complex` chain with N+1 source segments and N B-roll inputs, all concatenated on video, with original source audio mapped through.
2. **`concat` demuxer approach** (recommended for >10 insertions or when memory matters): pre-extract source segments to temp MP4s using `-ss` + `-t` + `-c copy`, write a concat list, run a second `concat` pass.

Honeyclip should **start with approach #2** because (a) concat-demuxer is what Phase 19-02 already uses (`buildConcatList`), (b) it avoids `-filter_complex` complexity, (c) memory is bounded.

```nim
# In src/broll/render.nim
proc renderWithBroll*(sourceVideo: string, insertions: seq[BrollInsertion],
                     clips: seq[ClipResult], outputPath: string): bool =
  ## Build concat list interleaving source segments and B-roll clips.
  ## Audio: extract source audio separately, mux at end.
  ## Returns true on success.
  # 1. For each gap between insertions (including head + tail), extract source
  #    segment with `ffmpeg -ss start -t dur -i src -c copy seg_N.mp4`.
  # 2. For each insertion, the corresponding clips[i].clipPath is the broll segment.
  # 3. Write a concat list: seg_0, broll_0, seg_1, broll_1, ..., seg_N.
  # 4. Run `ffmpeg -f concat -safe 0 -i list.txt -c copy temp_video.mp4`.
  # 5. Extract source audio: `ffmpeg -i src -vn -c:a copy source_audio.aac`.
  # 6. Mux: `ffmpeg -i temp_video.mp4 -i source_audio.aac -c:v copy -c:a copy
  #    -map 0:v:0 -map 1:a:0 outputPath`.
  # 7. Cleanup temp files in a try/finally.
```

**Resolution/codec assumption:** B-roll clips will not match source codec/resolution. The first concat pass with `-c copy` will fail. Either:
- (a) **Re-encode** during concat: drop `-c copy`, use `-c:v libx264 -preset fast` — slower but reliable.
- (b) **Pre-normalize** B-roll clips to source resolution + codec before concat: `ffmpeg -i broll.mp4 -vf scale={W}:{H} -c:v libx264 -preset fast normalized.mp4`.

Approach (b) is cleaner and faster on retries. **Recommend (b).**

`[ASSUMED]` Audio sync after concat: source audio is 1:1 with original timeline; the video is the same length (B-roll replaces equal-duration source segments). Sync should hold. This needs verification with a real test fixture in Wave 0.

### Pattern 7: Config / API-Key Resolution

```nim
# In src/config.nim
import std/[os, options]
import toml_serialization

type
  HoneyclipConfig* = object
    api*: ApiSection

  ApiSection* = object
    geminiKey*: string
    comfyuiUrl*: string

proc configPath*(): string =
  when defined(windows):
    let appData = getEnv("APPDATA")
    if appData == "": return ""
    return appData / "honeyclip" / "config.toml"
  else:
    let xdg = getEnv("XDG_CONFIG_HOME")
    let base = if xdg != "": xdg else: getHomeDir() / ".config"
    return base / "honeyclip" / "config.toml"

proc loadConfig*(): HoneyclipConfig =
  ## Load config.toml if it exists. Returns zero-valued config if not.
  let path = configPath()
  if path != "" and fileExists(path):
    try:
      result = Toml.loadFile(path, HoneyclipConfig)
    except CatchableError as e:
      warning &"Failed to parse {path}: {e.msg}; using defaults"

proc resolveGeminiKey*(): string =
  ## Env var first per CONTEXT.md, then TOML fallback.
  result = getEnv("GEMINI_API_KEY")
  if result == "":
    result = loadConfig().api.geminiKey
```

**`config.toml` example (document in README only, do not ship):**

```toml
[api]
gemini_key = "AIza..."
comfyui_url = "http://127.0.0.1:8188"
```

The `toml_serialization` library expects field names matching TOML keys directly (default-style serialization based on the existing `src/batch/templates.nim` usage). `[VERIFIED: src/batch/templates.nim:58 uses Toml.loadFile(path, BatchTemplate)]`.

### Anti-Patterns to Avoid

- **Inserting a `--broll` flag on the main `edit` command this phase.** CONTEXT.md explicitly defers this. Subcommand-only keeps coupling clean and avoids reaching into `src/edit.nim`'s argument-parsing maze.
- **Hand-rolling a TOML parser.** `toml_serialization` is already a project dep — use it.
- **Sync `httpclient` with `sleep()` for Veo polling.** Works but blocks the main thread for up to 10 minutes per clip. With async, you can run multiple clips in parallel via `all([f1, f2, f3])`.
- **Parsing the user's ComfyUI workflow JSON structurally.** It varies wildly across models and node packs. Treat it as opaque text + named placeholders.
- **Re-encoding the entire source video during the mux.** Pre-normalize B-roll clips to source codec/resolution; then `-c copy` the source segments. Saves time on long videos.
- **Embedding the API key in error messages or log output.** Always redact in `info()`/`error()` calls.
- **Using embeddings for topic-shift detection.** Adds a model dependency for marginal accuracy gain over the heuristic. Out of scope.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TOML parsing | Custom parser | `toml_serialization` (already in `honeyclip.nimble`) | Already a project dep, used in `src/batch/templates.nim` |
| HTTP client | Raw socket I/O | `std/httpclient` + `std/asyncdispatch` | Stdlib, redirect/cookies/SSL handled |
| JSON parse / write | Hand-roll | `std/json` (`%*`, `parseJson`, `pretty`) | Stdlib, already used in `src/exports/json.nim` |
| FFmpeg invocation | libavformat C bindings (existing in `src/av.nim`) | `osproc.execCmdEx` subprocess | Phase 19-02 / 18-02 / 20-01 all chose subprocess for post-processing — keep pattern consistent |
| Async polling loop | Threads + condvars | `asyncdispatch.sleepAsync` + `await` | Stdlib, integrates with `AsyncHttpClient` |
| Greedy selection w/ spacing | Custom | Reuse `detectEngagementPeaks` algorithm from `src/analyze/chapters.nim` | Already shipped, tested, identical semantics |
| Long-running-operation polling | Custom retry framework | Bounded `for attempt in 0..<N: await sleepAsync(...); GET` | Veo's LRO contract is simple; no retry library needed |
| ComfyUI workflow validation | Schema validator | `string.replace` placeholders + JSON parse for syntax check only | User owns the workflow; honeyclip is opaque template engine |
| Variable-duration fitting | Custom video framework | FFmpeg `tpad`/`setpts`/`-t` filters via subprocess | All fitting operations are 1-line FFmpeg invocations |

**Key insight:** This phase is 90% glue code over external tools (FFmpeg, ComfyUI, Veo, Flash). The honeyclip-specific value is in (a) the topic-shift detector (the only novel algorithm) and (b) the splice-and-mux orchestration. Everything else should be a thin wrapper.

## Runtime State Inventory

**Not applicable** — this is a greenfield additive phase. No renames, refactors, or migrations of existing data.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified by `Grep` for "BrollProvider"/"broll" in src/ (no existing references) | none |
| Live service config | None — honeyclip has no live services today | none |
| OS-registered state | None — honeyclip is a CLI binary, no OS registrations | none |
| Secrets/env vars | NEW: `GEMINI_API_KEY` consumed by this phase. No existing env-var rename. | Document in README; never commit `config.toml`. |
| Build artifacts | None — phase adds new modules, doesn't rename packages | none |

## Common Pitfalls

### Pitfall 1: Synchronous Polling Blocks Multi-Clip Generation

**What goes wrong:** With sync `httpclient` + `sleep(10_000)`, generating 5 Veo clips takes 5 × ~60s = 5 minutes serialized. With `AsyncHttpClient` per clip + `all([futures])`, it's ~60s wall clock (Veo's per-job latency).

**Why it happens:** It's natural to write `var resp = client.get(...)` first, see it work, and not refactor.

**How to avoid:** Make `BrollProvider.generate` return `Future[ClipResult]` from day one. Use `waitFor all([...])` at the call site in `src/cmds/broll.nim` to fan out.

**Warning signs:** B-roll command takes minutes per clip in serial. CPU idle during waits.

### Pitfall 2: Veo Pricing Surprise

**What goes wrong:** User runs `honeyclip broll long-video.mp4 --backend veo` on a 30-minute video. With default density, that's 30 insertions × 8s × $0.40/s = **$96 per run**.

**Why it happens:** Cost compounds with density × duration × per-second pricing. Easy to overlook.

**How to avoid:**
1. Print expected cost before generation when using Veo: `echo &"Veo will generate {N} clips × 8s × $0.15-0.40/s ≈ ${cost} USD. Continue? [y/N]"` — gate on a TTY check or `--yes` flag.
2. Default `params.maxInsertions` to a hard cap (e.g., 20) regardless of duration, and require `--max-broll N` to exceed.
3. Default `--model veo-3.0-fast-generate-001` (the $0.15/s tier), not the standard $0.40/s tier.

**Warning signs:** Bug reports of unexpected billing, requests for `--dry-run`.

### Pitfall 3: ComfyUI Workflow `{{LENGTH}}` Not Honored

**What goes wrong:** User's workflow has `{{LENGTH}}` only in the LoadVideo node, but their AnimateDiff context_length is hardcoded to 16. Result: every clip is 16 frames regardless of pause length.

**Why it happens:** Placeholder substitution is opt-in; honeyclip can't detect which nodes the user wired.

**How to avoid:**
1. Document a reference workflow with `{{PROMPT}}`, `{{SEED}}`, `{{LENGTH}}` correctly placed in `docs/comfyui-broll-workflow.md`.
2. After ComfyUI returns the clip, probe its actual duration via `ffprobe`. If it doesn't match `requested ± 200ms`, fall through to fitting strategy in Pattern 5.
3. Log a clear warning: `&"ComfyUI returned {actualMs}ms clip for {requestedMs}ms request — fitting via {strategy}"`.

**Warning signs:** Many B-roll clips with identical durations regardless of requested length.

### Pitfall 4: Config File Permission Leak

**What goes wrong:** User commits `config.toml` to git, leaks API key.

**Why it happens:** Default placement (`~/.config/honeyclip/`) is outside the repo, but a confused user might place it in the repo dir or symlink.

**How to avoid:**
1. README includes `chmod 600 ~/.config/honeyclip/config.toml` instruction.
2. README includes a `.gitignore` snippet: `config.toml` and `**/honeyclip/config.toml`.
3. On config load, if `path` resolves inside the user's `getCurrentDir()` git tree, log a warning: `"config.toml inside a git repo — verify it's gitignored"`.

**Warning signs:** None until a key leaks. Defensive logging is the prevention.

### Pitfall 5: Async Exception Swallowing

**What goes wrong:** An `await client.postContent(...)` raises `HttpRequestError` inside an async proc. Without `try/except CatchableError`, the future fails silently and the caller gets a confusing "Future failed" with no context.

**Why it happens:** Nim's `await` propagates exceptions through futures, but error messages from deep async stacks are noisy.

**How to avoid:** Wrap every external call in `try / except CatchableError as e: return ClipResult(success: false, error: $e.msg)`. Never let an HTTP exception bubble out of `generate()`.

**Warning signs:** "Future failed" tracebacks with no human-readable cause.

### Pitfall 6: Concat Demuxer Codec Mismatch

**What goes wrong:** `-c copy` concat with B-roll in different codec/resolution → either fails outright or produces corrupted output.

**Why it happens:** ComfyUI commonly outputs WebP/GIF or different H.264 profile; Veo outputs 24fps H.264 but resolution may differ from source.

**How to avoid:** Pre-normalize B-roll clips to source codec/resolution/fps via `ffmpeg -i broll -vf scale=W:H,fps=FPS -c:v libx264 -preset fast` before concat. This is one extra subprocess per clip but avoids concat-time crashes.

**Warning signs:** `--render` succeeds in `ffmpeg -f concat` but output plays scrambled or has black frames.

## Code Examples

### Existing Phase-18 Greedy Selection (pattern to mirror)

```nim
# Source: src/analyze/chapters.nim (verified in this codebase)
proc detectEngagementPeaks*(timeline: EngagementTimeline,
                             minSpacingMs: int64 = 30000,
                             minScore: float32 = 60.0,
                             maxPeaks: int = 10): seq[int64] =
  # 1. Find local maxima
  # 2. Sort by score descending
  # 3. Greedy select with min-spacing
  # 4. Cap at maxPeaks
  # 5. Sort chronologically
  # ...
```

`broll.nim`'s `detectBrollInsertions` should follow this exact shape, swapping the candidate-enumeration step.

### Existing Phase-18 CLI Skeleton (pattern to mirror)

```nim
# Source: src/cmds/chapters.nim (verified in this codebase, lines 36-80)
proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var mode: string = "combined"
  # ... argument parsing via case+expecting state machine ...
```

`cmds/broll.nim` should copy this skeleton verbatim, then change the flag set:
- `--max-broll N` (replaces `--max-chapters`)
- `--min-spacing SECS` (same)
- `--backend comfyui|veo|auto` (new)
- `--comfy-url URL` (new, default `http://127.0.0.1:8188`)
- `--workflow PATH` (new, required for ComfyUI)
- `--model NAME` (new, default `veo-3.0-fast-generate-001`)
- `--render` (new, mux final video)
- `-o, --output PATH` (default: marker JSON path; with `--render`, video output path)

### Existing Phase-19-02 Subprocess Pattern (pattern to mirror)

```nim
# Source: src/batch/runner.nim:79 (verified in this codebase)
let (output, exitCode) = execCmdEx(cmd)
```

`broll/render.nim` will use the identical `execCmdEx` pattern for all FFmpeg invocations.

### Existing TOML Loading Pattern (pattern to reuse)

```nim
# Source: src/batch/templates.nim:2,58 (verified in this codebase)
import toml_serialization
result = Toml.loadFile(path, BatchTemplate)
```

`config.nim` will use `Toml.loadFile(path, HoneyclipConfig)` identically.

## State of the Art

| Old Approach | Current Approach (2026) | When Changed | Impact |
|--------------|-------------------------|--------------|--------|
| Manual stock-footage B-roll | Generative B-roll on demand | 2024-2025 (Sora, Veo, Runway Gen-3) | Editing pipelines now generate purpose-fit B-roll instead of searching libraries |
| Single-clip generation | Multi-shot stitching with consistent characters | Late 2025 (Veo 3.1) | Veo 3.1 supports first/last-frame conditioning for continuity, though honeyclip ignores this in v1 |
| Synchronous video API calls | Long-running operations + polling | 2023 onward (industry standard) | All major video models (Veo, Sora, Runway) use LRO; sync APIs no longer offered |
| Free Veo previews | Per-second billing $0.15-0.40/s | Mid-2025 (Veo 3 GA) | Cost gating becomes a UX requirement |
| Fixed 4-second clips | Mostly 8-second still fixed | 2025-2026 | Veo holds 8s; ComfyUI/AnimateDiff variable up to ~16s natively, longer w/ sliding window |

**Deprecated / outdated:**
- Earlier `gemini-1.5-*` model names — superseded by `veo-3.0-*` and `gemini-2.5-flash` for prompt rewriting.
- Veo Vertex AI endpoints (`us-central1-aiplatform.googleapis.com`) for individual developers — Gemini API endpoint (`generativelanguage.googleapis.com`) is the cheaper, simpler path. Vertex remains for enterprise.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Topic-shift signal weights (pause 0.4 / boundary 0.3 / engagement-delta 0.3) and threshold (50.0) are reasonable starting values | Pattern 1 | Insertion points may cluster poorly; fixable by tuning after dogfooding without API changes |
| A2 | `BrollProvider` as object variant is preferable to `concept` in Nim 2.2 | Pattern 2 | Refactor cost is low; either shape compiles |
| A3 | Concat-demuxer with pre-normalized B-roll is more reliable than `-filter_complex` concat | Pattern 6 | If wrong, switch to filter_complex; FFmpeg supports both |
| A4 | Source-audio-only mux remains in sync after video concat (because total video length is preserved) | Pattern 6, Pitfall 6 | If audio drifts, `--itsoffset` or per-segment audio may be needed; verify in Wave 0 |
| A5 | `toml_serialization` field-name mapping is straight TOML key → Nim field with the existing `src/batch/templates.nim` style (default serializer) | Pattern 7 | If different style is needed, add `{.serializedFieldName: "gemini_key".}` pragmas |
| A6 | A single `GEMINI_API_KEY` authorizes both Veo and Gemini Flash text generation in 2026 | Cost section | Confirmed by `[CITED: ai.google.dev/gemini-api/docs/pricing]` — risk: low |
| A7 | ComfyUI's `/system_stats` endpoint is the right reachability probe (vs `/queue` or root) | Pattern 2 | If endpoint moves, swap to another GET; same pattern applies |
| A8 | Cost-confirmation prompt should default to Veo-Fast tier ($0.15/s) and require explicit `--standard` for the $0.40/s tier | Pitfall 2 | If users prefer Standard quality default, swap defaults; behind a CLI flag either way |

## Open Questions

1. **Audio sync after concat — verify in Wave 0.**
   - What we know: source audio is full-length, B-roll replaces equal-duration source segments. Math says sync should hold.
   - What's unclear: whether re-encoding video segments at concat-time introduces pts/dts drift.
   - Recommendation: Wave 0 must include a smoke-test that compares input.mp4 audio-track waveform fingerprint to output.mp4 audio-track at insertion-point timestamps ± 200ms.

2. **ComfyUI authentication.**
   - What we know: default ComfyUI install has no auth.
   - What's unclear: whether users running ComfyUI behind reverse proxies need an `Authorization` header.
   - Recommendation: defer. Add `--comfy-auth HEADER` flag in a future phase if requested. Document the assumption.

3. **Veo `personGeneration` policy.**
   - What we know: Veo accepts `"allow_adult"`, `"allow_all"`, `"dont_allow"`. Default varies by region.
   - What's unclear: whether "talking-head replacement" B-roll triggers the policy.
   - Recommendation: hardcode `"allow_adult"` for this phase. Surface as flag if users hit policy errors.

4. **Multi-language transcript handling for Flash prompt rewrite.**
   - What we know: transcript can be any language; Flash supports many.
   - What's unclear: whether Flash should be instructed to output the visual prompt in English regardless of input language (Veo's prompt understanding is strongest in English).
   - Recommendation: Always instruct Flash to "respond in English with a concrete visual scene description" in the system prompt. Document.

5. **Default workflow path for ComfyUI.**
   - What we know: CONTEXT.md says "we do NOT ship a built-in workflow."
   - What's unclear: where users put their workflow file; whether `--workflow` should be required when `--backend=comfyui` or default to `~/.config/honeyclip/comfyui-broll.json`.
   - Recommendation: require `--workflow` flag explicitly when ComfyUI backend is selected. No magic path lookup.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Nim | All compilation | likely ✓ (project compiles) | 2.2.2+ | none — required |
| `toml_serialization` (nimble) | `src/config.nim` | ✓ | already in `honeyclip.nimble` | none — already a dep |
| FFmpeg binary at runtime | `src/broll/render.nim`, fitting | ✓ | bundled by `nimble makeff` | none — honeyclip already requires bundled FFmpeg |
| Network egress to `generativelanguage.googleapis.com` | Veo, Flash | runtime-only check | n/a | Local-only mode (ComfyUI required) |
| Network egress to user-supplied ComfyUI URL | ComfyUI provider | runtime-only check | n/a | API mode (Veo, requires key) |
| `GEMINI_API_KEY` env var or config.toml entry | Veo + Flash | depends on user | n/a | ComfyUI-only mode |
| ComfyUI server running on `127.0.0.1:8188` | ComfyUI provider | depends on user | n/a | Veo (requires key) |

**Missing dependencies with no fallback:** none — at least one of (ComfyUI server, Gemini API key) must be configured at runtime, but both are optional at build time. The CLI should emit an actionable error when neither is available.

**Missing dependencies with fallback:** ComfyUI ↔ Veo is the documented fallback pair. CLI auto-fallback when ComfyUI unreachable AND key configured (per CONTEXT.md).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Nim `std/unittest` (existing — `tests/unit.nim`) + Python E2E via `python3 tests/test.py` |
| Config file | `honeyclip.nimble` `task test` (Wave 0 — no broll-specific config needed) |
| Quick run command | `nimble test` |
| Full suite command | `nimble test && python3 tests/test.py` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BROLL-01 | Topic-shift detector returns expected insertions for synthetic transcript+engagement fixture | unit | `nim c -r tests/unit_broll.nim` (Wave 0) | ❌ Wave 0 |
| BROLL-01 | Greedy spacing rejects within-min-spacing candidates | unit | same as above (sub-test) | ❌ Wave 0 |
| BROLL-01 | Pause < `minPauseMs` is filtered | unit | same as above | ❌ Wave 0 |
| BROLL-02 | ComfyUI client substitutes `{{PROMPT}}/{{SEED}}/{{LENGTH}}` correctly | unit (string) | same as above | ❌ Wave 0 |
| BROLL-02 | ComfyUI client posts to `/prompt`, polls `/history`, fetches `/view` (mocked HTTP) | unit w/ HTTP mock | same as above | ❌ Wave 0 |
| BROLL-02 | ComfyUI workflow JSON survives placeholder substitution as valid JSON | unit | same as above | ❌ Wave 0 |
| BROLL-03 | Veo client posts to `:predictLongRunning`, polls operation, downloads URI (mocked HTTP) | unit w/ HTTP mock | same as above | ❌ Wave 0 |
| BROLL-03 | Veo polling honors `done==true` and surfaces error on `error` field | unit | same as above | ❌ Wave 0 |
| BROLL-03 | Provider selection picks ComfyUI when reachable; falls back to Veo when key set | unit (mock both reachability + key) | same as above | ❌ Wave 0 |
| BROLL-03 | `config.nim` resolves env var first, then TOML, returns "" when neither set | unit | same as above | ❌ Wave 0 |
| BROLL-03 | Flash prompt-rewrite returns the rewritten prompt (mocked HTTP) | unit | same as above | ❌ Wave 0 |
| BROLL-04 | `--render` produces an MP4 of expected length and frame count (smoke E2E) | smoke E2E | `python3 tests/test.py` (extend) | ❌ Wave 0 (requires fixture clip pair) |
| BROLL-04 | Marker JSON snapshot for canonical fixture matches expected | unit (JSON snapshot) | `nim c -r tests/unit_broll.nim` | ❌ Wave 0 |
| BROLL-04 | Variable-duration fitting (`fsTruncate`/`fsPadFreeze`) produces correct output duration | unit, FFmpeg subprocess gated by env-flag | same as above | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `nimble test` (Nim unit tests only — fast, no network, no FFmpeg if HTTP-mocked tests run on stubs).
- **Per wave merge:** `nimble test && python3 tests/test.py` (full suite, includes E2E with FFmpeg).
- **Phase gate:** Full suite green before `/gsd-verify-work`. Plus a manual sanity run of `honeyclip broll resources/test.mp4 --backend comfyui --workflow ./test-workflow.json --render -o /tmp/out.mp4` against a real ComfyUI server (recorded in SUMMARY).

### HTTP Mocking Seam

Plans must introduce a thin abstraction so unit tests don't hit real ComfyUI / Veo:

```nim
# In src/broll/http_seam.nim (new)
type
  HttpClientLike* = ref object of RootObj
  ProdHttpClient* = ref object of HttpClientLike
    inner*: AsyncHttpClient
  MockHttpClient* = ref object of HttpClientLike
    responses*: Table[string, string]  # url-pattern → body

method postAsync*(c: HttpClientLike, url, body: string): Future[string] {.base, async.} =
  raiseAssert "abstract"
method getAsync*(c: HttpClientLike, url: string): Future[string] {.base, async.} =
  raiseAssert "abstract"
```

`comfyui.nim`, `veo.nim`, `flash.nim` all take `HttpClientLike` rather than constructing their own `AsyncHttpClient`. Tests inject `MockHttpClient` with a fixture response table. Production call sites use `ProdHttpClient(inner: newAsyncHttpClient())`.

This is the single seam that makes BROLL-02 / BROLL-03 testable without network.

### Transcript Fixture for Topic-Shift Tests

Create `tests/fixtures/broll_transcript.json` containing a 2-minute synthetic transcript with:
- 4 segments, 2 speakers, varying pause lengths (200ms, 1500ms, 4000ms, 700ms)
- Paired `tests/fixtures/broll_engagement.json` with corresponding 5-segment engagement timeline showing one sharp delta and one flat region

Topic-shift unit test loads both, asserts `detectBrollInsertions` returns the 1500ms and 4000ms pauses (paired with the engagement delta) and rejects the 200ms / 700ms ones.

### Prompt-Rewrite Stubbing

Flash unit test:
1. Construct a `MockHttpClient` whose `postAsync` for the Flash URL returns a canned `{"candidates":[{"content":{"parts":[{"text":"a wide cinematic shot of a city at dusk"}]}}]}`.
2. Call `rewriteToVisualPrompt(transcriptWindow, mockClient, apiKey)`.
3. Assert returned string == `"a wide cinematic shot of a city at dusk"`.

### End-to-End Marker JSON Snapshot

Create a deterministic fixture: input video + locked transcript/engagement → `honeyclip broll` (with `--backend mock` flag injected only in test builds, returning canned clip paths) → marker JSON. Snapshot the JSON output and compare on subsequent runs. Use the same `checkApprox`-style helper from Phase 17 for any float fields.

### Wave 0 Gaps

- [ ] `tests/unit_broll.nim` — covers BROLL-01..04 unit-level
- [ ] `tests/fixtures/broll_transcript.json` — topic-shift detector input
- [ ] `tests/fixtures/broll_engagement.json` — paired engagement timeline
- [ ] `tests/fixtures/broll_workflow.json` — minimal ComfyUI workflow with `{{PROMPT}}/{{SEED}}/{{LENGTH}}` placeholders
- [ ] `tests/fixtures/broll_input.mp4` — small (5s) test video for `--render` E2E
- [ ] `tests/fixtures/broll_brollclip.mp4` — small (1s) canned B-roll clip for mock-provider injection
- [ ] HTTP mock seam (`src/broll/http_seam.nim`) — must be in place before `comfyui.nim`/`veo.nim`/`flash.nim` are written, so they're built against the abstraction from day one
- [ ] Add `nimble test` invocation of `tests/unit_broll.nim` if not auto-discovered

## Project Constraints (from CLAUDE.md)

- **Stack lockdown:** Nim 2.2.2+ + FFmpeg only. **No Node.js or Python in core runtime.** Network providers must be implemented in Nim (or via subprocess where the tool is FFmpeg).
- **Cross-platform:** Linux, macOS, Windows. ComfyUI/Veo HTTP work the same on all three. Config path differs (`%APPDATA%` vs `$XDG_CONFIG_HOME`) — already handled in Pattern 7.
- **Windows ML stub limitation:** Face detection ML stubbed on Windows due to LTO. **B-roll has no native ML dependency** (both backends are external HTTP services), so this phase fully works on Windows.
- **Build feature flags:** None of the existing build flags affect this phase. No new flag needed; broll modules compile unconditionally.
- **Test discipline:** Nim unit tests via `nimble test` (`tests/unit.nim`). Python E2E via `python3 tests/test.py`. Both must pass.
- **Existing logging proc:** Use `info()`, `debug()`, `error()` from `src/log.nim` consistently. Phase 15 added `info()`.
- **Existing test helper:** Use `checkApprox` from Phase 17-03 for any float comparisons.
- **Subprocess pattern:** Use `osproc.execCmdEx` for FFmpeg invocations, identical to Phase 18-02 / 19-02 / 20-01.

## Sources

### Primary (HIGH confidence)

- `[VERIFIED: codebase grep]` `honeyclip.nimble` lines 10-15 — confirms `toml_serialization` is already a project dependency
- `[VERIFIED: codebase grep]` `src/batch/templates.nim:2,58` — existing TOML loading idiom
- `[VERIFIED: codebase grep]` `src/batch/runner.nim:79,115,163` — existing `execCmdEx` subprocess idiom
- `[VERIFIED: codebase read]` `src/analyze/chapters.nim` — peak detection + greedy spacing pattern
- `[VERIFIED: codebase read]` `src/cmds/chapters.nim` — CLI command skeleton
- `[VERIFIED: codebase read]` `src/transcript/types.nim` — `Word`, `TranscriptSegment`, `Transcript` shapes
- `[VERIFIED: codebase read]` `src/analyze/engagement_types.nim` — `EngagementSegment.score` field
- `[CITED: https://nim-lang.org/docs/httpclient.html]` — `AsyncHttpClient` and progress callback API
- `[CITED: https://nim-lang.org/docs/asyncdispatch.html]` — `await`, `waitFor`, `sleepAsync`
- `[CITED: https://ai.google.dev/gemini-api/docs/video]` — Veo LRO endpoint, polling pattern, fixed 8-second output, MP4 H.264 24fps
- `[CITED: https://ai.google.dev/gemini-api/docs/pricing]` — Gemini API pricing for Flash 2.5 ($0.30/$2.50 per Mtok); Gemini API key authorizes both Veo and Flash
- `[CITED: https://docs.comfy.org/development/cloud/overview]` — ComfyUI `/prompt` API contract
- `[CITED: https://deepwiki.com/Comfy-Org/ComfyUI/7.3-workflow-json-format]` — Workflow JSON node format (API format)

### Secondary (MEDIUM confidence)

- `[CITED: https://www.veo3ai.io/blog/veo-3-pricing-2026]` — Veo 3 pricing tiers ($0.15/$0.40 per second)
- `[CITED: https://www.aifreeapi.com/en/posts/veo-3-1-pricing-per-second-gemini-api]` — Per-second cost calculator confirmation
- `[CITED: https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved]` — AnimateDiff context_length and sliding-window
- `[CITED: https://artificialanalysis.ai/models/gemini-2-5-flash/providers]` — Flash 2.5 latency benchmarks (~0.7s TTFT)
- `[CITED: https://www.runflow.io/blog/comfyui-api-developer-guide]` — ComfyUI API patterns and examples

### Tertiary (LOW confidence — flag for validation)

- `[ASSUMED]` Specific topic-shift signal weights (0.4/0.3/0.3) and thresholds — needs dogfooding tuning
- `[ASSUMED]` Audio-sync correctness across re-encoded video concat — needs Wave 0 verification
- `[ASSUMED]` ComfyUI's `/system_stats` is the canonical reachability probe — alternatives (`/queue`, `/`) work too
- `[ASSUMED]` Concat-demuxer outperforms `-filter_complex` concat for ≤10 insertions — empirical, may need tuning

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every library in the stack is either Nim stdlib (verified) or already in `honeyclip.nimble` (verified by grep)
- Architecture: HIGH — patterns mirror Phase 18 / Phase 19-02 directly, both shipped and tested in this codebase
- Veo / Flash API specifics: MEDIUM — endpoints, polling, pricing all citable to Google docs current as of May 2026; specifics like `personGeneration` defaults may shift
- ComfyUI workflow shape: MEDIUM — placeholder substitution is opaque text op, robust to schema changes
- Topic-shift heuristic weights: LOW — weights are educated starting points, expect tuning
- Variable-duration fitting: MEDIUM — strategies are sound; specific quality outcomes depend on real B-roll content
- Pitfalls: MEDIUM — based on industry experience with similar pipelines; #1 (sync block) and #2 (cost surprise) are highest confidence

**Research date:** 2026-05-08
**Valid until:** 2026-05-22 (14 days — Veo/Flash pricing and Veo's max duration are the freshest data points; expect minor shifts)

## RESEARCH COMPLETE
