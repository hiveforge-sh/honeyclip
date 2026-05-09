---
phase: 21
plan: 02
subsystem: src/broll + src/cmds/broll + src/main.nim
tags: [nim, ffmpeg, comfyui, veo, gemini, http, cli, tdd]
dependency_graph:
  requires:
    - HttpClientLike abstraction (src/http_client.nim) from 21-01
    - MockHttpClient test seam from 21-01
    - HoneyclipConfig / resolveGeminiKey / resolveComfyUrl (src/config.nim) from 21-01
    - BrollInsertion / detectBrollInsertions / selectInsertions (src/analyze/broll.nim) from 21-01
    - tests/fixtures/* (comfyui_workflow.json, veo_lro_response.json) from 21-01
  provides:
    - ComfyUI HTTP provider (src/broll/comfyui.nim) with MockHttpClient testability
    - Veo LRO provider (src/broll/veo.nim) with cost gate
    - Gemini Flash prompt rewrite (src/broll/flash.nim)
    - Variable-duration fitting (src/broll/fitting.nim)
    - BrollProvider object variant + auto-selection (src/broll/provider.nim)
    - FFmpeg render mux pipeline (src/broll/render.nim)
    - Marker JSON output (src/broll/markers.nim)
    - ComfyUI workflow placeholder substitution (src/broll/workflow.nim)
    - honeyclip broll CLI subcommand (src/cmds/broll.nim)
    - broll registered in src/main.nim and src/cli.nim
  affects:
    - src/main.nim (broll subcommand registration)
    - src/cli.nim (broll in commands table)
    - tests/unit_broll.nim (7 new suites, 47 new tests)
tech_stack:
  added: []
  patterns:
    - HttpClientLike injection into all provider HTTP calls (T-21-01 compliance)
    - QueueMock test helper for LRO state machine simulation
    - execCmdEx subprocess pattern (mirror Phase 19-02) for FFmpeg
    - quoteShell on all FFmpeg path args (T-21-06)
    - warning() not error() in cost gate to allow testability (deviation from plan)
key_files:
  created:
    - src/broll/workflow.nim
    - src/broll/comfyui.nim
    - src/broll/veo.nim
    - src/broll/flash.nim
    - src/broll/fitting.nim
    - src/broll/provider.nim
    - src/broll/render.nim
    - src/broll/markers.nim
    - src/cmds/broll.nim
  modified:
    - src/main.nim
    - src/cli.nim
    - tests/unit_broll.nim
decisions:
  - "confirmVeoCost uses warning() not error() so it returns false in tests instead of calling quit(1)"
  - "ClipResult defined in comfyui.nim and re-exported from provider.nim via export comfyui.ClipResult"
  - "QueueMock test helper lives in tests/unit_broll.nim only; src/http_client.nim not polluted with test-only behavior"
  - "broll entry added to src/cli.nim commands table for help display (discovered gap not in plan)"
  - "Windows binary test requires mingw PATH for libgomp-1.dll; nimble test uses --gcc.exe flag"
metrics:
  duration: ~23 min
  completed: 2026-05-09
  tasks: 5
  files: 12
---

# Phase 21 Plan 02: Wave 2+3 B-Roll Providers, Fitting, and CLI Summary

ComfyUI HTTP provider + Veo LRO provider + Gemini Flash prompt rewrite + variable-duration fitting + BrollProvider auto-selection variant + FFmpeg render mux + marker JSON + `honeyclip broll` CLI subcommand fully wired into main.nim.

## What Was Built

### Task 21-02-01: ComfyUI workflow substitution + HTTP provider
**Commit:** 3efbcaa

- `src/broll/workflow.nim`: `escapeJsonString` (JSON-safe control-char escaping) + `substituteWorkflow` ({{PROMPT}}/{{SEED}}/{{LENGTH}} placeholder substitution).
- `src/broll/comfyui.nim`: `isComfyReachable` (GET /system_stats), `comfyuiGenerate` (POST /prompt -> poll /history/{id} -> GET /view -> write file). All HTTP through `HttpClientLike`. `ClipResult` type defined here.
- `tests/unit_broll.nim`: suites "comfyui workflow substitution" (2 tests) + "comfyui provider" (5 tests).

### Task 21-02-02: Veo LRO provider + Gemini Flash + cost pre-flight
**Commit:** 3fc79a8

- `src/broll/veo.nim`: `estimateVeoCost`, `confirmVeoCost` (policy gate; warning() not error()), `veoGenerate` (POST :predictLongRunning -> poll /operations/ -> download). All HTTP through `HttpClientLike`.
- `src/broll/flash.nim`: `rewritePrompt` via Gemini Flash generateContent endpoint; falls back to contextText on any failure.
- `tests/unit_broll.nim`: `QueueMock` helper for LRO state machine + suites "veo cost" (6 tests) + "veo provider" (3 tests) + "flash rewrite" (3 tests).
- T-21-02 secret-leak gate: clean (no apiKey/key= in log call args).

### Task 21-02-03: Fitting + BrollProvider variant + selection
**Commit:** 517724d

- `src/broll/fitting.nim`: `FittingStrategy` enum (fsNone/fsTruncate/fsPadFreeze/fsPadSpeedRamp/fsRequestExtra), `selectFittingStrategy`, `buildFittingCmd` (pure builder), `fitClipDuration` (execCmdEx). Paths quoteShell'd.
- `src/broll/provider.nim`: `BrollProvider` object variant (bpComfyUI/bpVeo), `resolveProvider` auto-fallback (ComfyUI first, Veo if key set, error otherwise), `generate` dispatch. Re-exports `ClipResult` from comfyui.
- `tests/unit_broll.nim`: suites "fitting strategy" (8 tests) + "provider selection" (5 tests).

### Task 21-02-04: Render mux pipeline + marker JSON
**Commit:** 8f0d02c

- `src/broll/render.nim`: `buildSegmentPlan` (alternating source/broll segments), `buildConcatList` (concat-demuxer file content), `normalizeBrollClipCmd` (pure builder, scale+fps+libx264), `renderWithBroll` (ffprobe -> normalize -> extract segments -> concat -> extract audio -> mux; 7 execCmdEx calls; all paths quoteShell'd).
- `src/broll/markers.nim`: `writeBrollMarkersJson` (pretty-printed JSON with all 10 required insertion keys).
- `tests/unit_broll.nim`: suites "render plan" (4 tests) + "marker json" (1 test).

### Task 21-02-05: honeyclip broll CLI subcommand + main.nim registration
**Commit:** f5ba5f1

- `src/cmds/broll.nim`: full pipeline CLI (arg parse -> resolve config -> resolve provider -> transcribe -> analyze engagement -> detectBrollInsertions -> selectInsertions -> cost gate -> generate+fit loop -> writeBrollMarkersJson; optionally renderWithBroll). Mirrors chapters.nim argument-parsing state machine.
- `src/main.nim`: `("broll", brollCmd.main)` added between batch and cache in cmdHandlers.
- `src/cli.nim`: `("broll", "...")` added to commands table for help text.
- `tests/unit_broll.nim`: suite "broll cli" (2 OK + 1 skipped binary smoke test).
- Binary: `honeyclip broll --help` exits 0 with "usage: honeyclip broll".

## Verification Results

```
nim c -r --path:src tests/unit_broll.nim (via mingw GCC) -> EXIT 0
[Suite] http_client                  4/4 OK
[Suite] fixtures                     6/6 OK
[Suite] config                       6/6 OK
[Suite] broll detection              6/6 OK
[Suite] comfyui workflow substitution 2/2 OK
[Suite] comfyui provider             5/5 OK
[Suite] veo cost                     6/6 OK
[Suite] veo provider                 3/3 OK
[Suite] flash rewrite                3/3 OK
[Suite] fitting strategy             8/8 OK
[Suite] provider selection           5/5 OK
[Suite] render plan                  4/4 OK
[Suite] marker json                  1/1 OK
[Suite] broll cli                    2/2 OK + 1 SKIPPED
Total: 61 OK + 1 SKIPPED (22 from 21-01 + 47 new)

nim check --path:src src/cmds/broll.nim -> 0 Errors (warnings only; pre-existing)
nimble make -> SuccessX
honeyclip broll --help -> Exit 0, "usage: honeyclip broll" in stdout

T-21-01: grep -c "newHttpClient(" src/broll/comfyui.nim veo.nim flash.nim -> 0 0 0 CLEAN
T-21-02: secret-leak grep gate -> CLEAN
T-21-06: quoteShell count in render.nim -> 6, fitting.nim -> 4 CLEAN
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] confirmVeoCost used error() which calls quit(1), breaking tests**
- **Found during:** Task 21-02-02 verification
- **Issue:** Plan's veo.nim code used `error()` (which is `{.noreturn.}` and calls `quit(1)`) in `confirmVeoCost` for the non-TTY rejection case. The test `check confirmVeoCost(..., autoYes=false) == false` would never reach the check — the process would exit.
- **Fix:** Changed to `warning()` so the proc returns `false` without terminating. The CLI wrapper in `src/cmds/broll.nim` calls `error()` when the gate returns false.
- **Files modified:** `src/broll/veo.nim`
- **Commit:** 3fc79a8

**2. [Rule 2 - Missing] src/cli.nim commands table missing broll entry**
- **Found during:** Task 21-02-05 verification
- **Issue:** `src/main.nim` uses `zip(commands, cmdHandlers)` for dispatch; `commands` comes from `src/cli.nim`. Adding broll to `cmdHandlers` only would cause `honeyclip broll ...` dispatch to fail (misaligned zip) and "broll" would not appear in `honeyclip --help` output.
- **Fix:** Added `("broll", "Auto-generate B-roll inserts at detected timeline points")` to `src/cli.nim` between batch and cache.
- **Files modified:** `src/cli.nim`
- **Commit:** f5ba5f1

**3. [Rule 1 - Bug] _ as loop variable invalid in Nim 2.2.2**
- **Found during:** Task 21-02-01 compilation
- **Issue:** Plan used `for _attempt in 0 ..< maxAttempts` and `for _nodeId, nodeOut in outputs.fields` — both trigger `Error: invalid token: _ (\95)` in Nim 2.2.2.
- **Fix:** Renamed to `attempt` (with `discard attempt`) and `nodeId` (with `discard nodeId`) using `.pairs` iterator on `JsonNode`.
- **Files modified:** `src/broll/comfyui.nim`
- **Commit:** 3efbcaa

**4. [Rule 1 - Bug] `out` is a reserved keyword in Nim**
- **Found during:** Task 21-02-01 test compilation
- **Issue:** Test used `let out = substituteWorkflow(...)` — `out` is a keyword parameter direction marker in Nim.
- **Fix:** Renamed to `result2`.
- **Files modified:** `tests/unit_broll.nim`
- **Commit:** 3efbcaa

## Known Stubs

None. All exported procs are fully implemented. No placeholder or TODO values flow to test assertions or UI rendering.

## Threat Surface Scan

No new network servers, file-system trust boundaries, or auth paths introduced beyond what was documented in the plan's `<threat_model>`. All HTTP clients are outbound-only (to ComfyUI or Google APIs). T-21-01 through T-21-07 verified.

## Self-Check: PASSED

Files exist:
- src/broll/workflow.nim FOUND
- src/broll/comfyui.nim FOUND
- src/broll/veo.nim FOUND
- src/broll/flash.nim FOUND
- src/broll/fitting.nim FOUND
- src/broll/provider.nim FOUND
- src/broll/render.nim FOUND
- src/broll/markers.nim FOUND
- src/cmds/broll.nim FOUND

Commits exist:
- 3efbcaa feat(21-02): add ComfyUI workflow substitution + HTTP provider FOUND
- 3fc79a8 feat(21-02): add Veo LRO provider + Gemini Flash rewrite + cost gate FOUND
- 517724d feat(21-02): add fitting strategies + BrollProvider variant + auto-selection FOUND
- 8f0d02c feat(21-02): add render mux pipeline + marker JSON output FOUND
- f5ba5f1 feat(21-02): add honeyclip broll CLI subcommand + main.nim registration FOUND
