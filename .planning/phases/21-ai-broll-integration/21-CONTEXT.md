# Phase 21 Context: AI B-Roll Integration

**Created:** 2026-05-08
**Phase:** 21 — AI B-Roll Integration
**Goal:** Users can auto-insert generated B-roll at detected timeline points
**Requirements:** BROLL-01, BROLL-02, BROLL-03, BROLL-04

## Domain

Phase 21 delivers honeyclip's first AI-generative + first network-dependent feature. It detects narrative-meaningful points in an already-analyzed timeline, generates short B-roll video clips for each point (locally via ComfyUI or remotely via Gemini Veo), and emits a markers/EDL file that can optionally be rendered into a final muxed video. This is the first phase that introduces (a) outbound HTTP, (b) optional config file, and (c) async/long-running generation calls into the codebase.

## Canonical refs

Downstream agents (researcher, planner) MUST read these before acting:

- `.planning/ROADMAP.md` — Phase 21 entry (lines 197-211)
- `.planning/REQUIREMENTS.md` — BROLL-01..04 requirements (lines 56-59)
- `.planning/PROJECT.md` — "Local-first AI with API fallback" decision
- `.planning/codebase/ARCHITECTURE.md` — multi-stage CLI pipeline; timeline construction layer
- `.planning/codebase/INTEGRATIONS.md` — confirms honeyclip is currently offline-first / no external APIs (Phase 21 is the first to break this)
- `.planning/phases/17-virality-scoring/17-RESEARCH.md` — virality + transcript scoring patterns to mirror
- `.planning/phases/18-chapter-detection/18-01-PLAN.md` — peak detection + spacing pattern to reuse for insertion-point selection
- `.planning/phases/18-chapter-detection/18-02-PLAN.md` — `honeyclip chapters` subcommand pattern to mirror for `honeyclip broll`
- `.planning/phases/19-brand-templates/19-02-PLAN.md` — post-process subprocess pattern for the `--render` mux step
- `src/timeline.nim` — timeline data structures (v1/v2/v3) that B-roll markers must integrate with
- `src/cmds/` — existing subcommand implementations (caption, chapters, engage, preview) for the `broll` command shape
- `src/exports/json.nim` — JSON marker output pattern

## Decisions

### Insertion-point detection
- **Primary signal:** transcript topic shift, derived from existing transcript segments + speaker pauses (Phase 17 already provides transcript with engagement scores)
- **Density default:** conservative — ~1 insertion per 60s, 30s minimum spacing between insertions. Mirrors Phase 18-01 chapter spacing default
- **User overrides:** must be exposed via `--max-broll N` and `--min-spacing` flags; planner should design these on top of the same algorithm Phase 18 uses

### B-roll generation backend
- **Local backend:** ComfyUI via HTTP API to a user-running server. Default URL `http://127.0.0.1:8188`, overridable via flag/env
- **ComfyUI workflow:** user supplies an exported workflow JSON template containing placeholder tokens (e.g., `{{PROMPT}}`, `{{SEED}}`, `{{LENGTH}}`). Honeyclip substitutes these per insertion. We do NOT ship a built-in workflow and do NOT auto-detect installed nodes
- **Remote backend:** Gemini (Veo) only in this phase, but implemented behind a `BrollProvider` interface (Nim concept or object variant) so future providers (Runway, Pika) can drop in without refactor. Researcher: design the interface so the local ComfyUI path is also expressible as a `BrollProvider` implementation
- **Selection:** local-first per PROJECT.md; CLI flag forces a specific backend; auto-fallback to API when ComfyUI is unreachable AND an API key is configured

### Prompt sourcing
- **Default:** auto. Take the transcript window around each insertion point and run it through Gemini Flash (same API key as Veo) to rewrite spoken language into a concrete visual prompt
- **No user-template override in this phase.** Keep the surface area small; a `--prompt-template` flag can be added later if needed
- Researcher: confirm Gemini Flash + Veo can share a single API key; document the per-call cost

### Auth / config
- **API key:** read from `GEMINI_API_KEY` env var first, then fall back to a config file
- **Config file:** TOML at `$XDG_CONFIG_HOME/honeyclip/config.toml` on Linux/macOS, `%APPDATA%\honeyclip\config.toml` on Windows. This is honeyclip's first config file — planner should add a small `src/config.nim` module rather than scattering TOML reads across the codebase
- **Never commit keys.** Document in README that the config file should be `chmod 600`-equivalent

### Splice mechanism
- **Mode:** full cut. B-roll fully replaces the speaker video for its duration; original audio (the speaker) plays underneath, untouched. This is the standard YouTube/podcast B-roll convention
- **No PIP / overlay mode in this phase** — deferred
- **Clip length:** variable, matches the underlying transcript pause length at each insertion point. ⚠️ This is the highest-risk decision because most generative video models produce fixed-length output (3s or 5s). Researcher MUST investigate:
  1. Does Veo support arbitrary durations, or only fixed?
  2. How to handle the gap when requested length > model output (loop last frame? slow-motion stretch? request multiple clips and concat?)
  3. How to handle when requested length < model output (truncate)
  4. Whether ComfyUI workflows can accept a length parameter via the placeholder system

### CLI / output
- **Command:** new `honeyclip broll` subcommand. Mirrors Phase 18's `honeyclip chapters` pattern exactly
- **Default output:** marker JSON file describing detected insertion points + generated clip paths. Reviewable before rendering
- **Render flag:** `--render` muxes the final video. Reuses the post-process subprocess pattern from Phase 19-02
- **Existing edit command:** NOT modified to take a `--broll` flag in this phase. Subcommand-only keeps coupling clean

## Open questions for researcher

These were surfaced during discussion but require codebase + external-doc investigation before planning:

1. **Variable-duration B-roll given fixed-length model output.** This is the single biggest unknown. Concrete output: a recommended strategy per backend (ComfyUI / Veo) for matching transcript pause lengths
2. **Veo API specifics:** auth flow, async job polling pattern, output container/codec, max prompt length, rate limits, async or sync request model. Cost per second of generated video
3. **Gemini Flash prompt-rewrite call:** model name, latency, cost. Whether a single Gemini API key authorizes both Veo and Flash
4. **ComfyUI workflow JSON shape:** what node IDs / placeholder substitution syntax should the template use? Survey the standard ComfyUI exported workflow.json format and pick a substitution scheme
5. **HTTP client in Nim:** stdlib `httpclient` vs. async via `asyncdispatch`. Long-running Veo polls likely need async; Phase 19's subprocess pattern can't be reused for HTTP
6. **TOML parsing in Nim:** stdlib doesn't include TOML. Pick a dependency (parsetoml is the common choice) and confirm it's already linked or acceptable to add
7. **Transcript "topic shift" signal:** Phase 17 has engagement components but no explicit topic-shift detector. Researcher to specify whether this is (a) a delta on existing engagement signals, (b) a new embedding-distance computation, or (c) heuristic based on transcript-segment boundaries + pause length

## Deferred ideas

Captured here so they aren't lost — out of scope for Phase 21:

- Picture-in-picture / overlay mode (`--broll-mode cut|pip`)
- Additional API providers (Runway, Pika) beyond the pluggable interface
- User-supplied prompt templates with `{topic}` substitution
- Auto-detected ComfyUI workflows from installed nodes
- User-curated stock B-roll library / search
- B-roll caching to avoid regenerating identical prompts
- `--broll` flag on the main edit command for one-shot UX

## Code context

Reusable patterns / assets the researcher should plan to leverage:

- `src/timeline.nim` — extend timeline format to carry B-roll markers (or a parallel marker stream)
- `src/cmds/chapters.nim` (created in Phase 18-02) — closest analog for `cmds/broll.nim`
- `src/exports/json.nim` — JSON marker writer pattern
- Phase 19 brand-template post-processing — pattern for the `--render` final-mux subprocess
- `src/log.nim` `info()` logging proc — added Phase 15
- Phase 17-03 `checkApprox` test helper — useful for any float comparisons in scoring
- Existing FFmpeg subprocess invocation in `src/render/` — for the eventual mux step

## Constraints carried forward

- **Local-first AI with API fallback** (PROJECT.md). ComfyUI is the local path; Veo is the fallback
- **Windows ML stub limitation** (STATE.md): face-detection ML is stubbed on Windows due to LTO. B-roll has no native ML dependency on Windows since both backends are external (HTTP), so this phase should work on Windows
- **Offline-first heritage** (codebase/INTEGRATIONS.md says "no external APIs"). Phase 21 is the documented break with that. Update INTEGRATIONS.md when execution lands

---
*Decisions captured for downstream researcher and planner. Researcher should treat the "Open questions" section as the research backlog.*
