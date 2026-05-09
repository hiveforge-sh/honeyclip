---
phase: 21
plan: 01
subsystem: analyze/broll + http_client + config + test-fixtures
tags: [nim, http, toml, topic-shift, unittest, tdd, async-seam]
dependency_graph:
  requires: []
  provides:
    - HttpClientLike abstraction (src/http_client.nim)
    - MockHttpClient for unit-testing providers without network
    - HoneyclipConfig / env-first TOML key resolution (src/config.nim)
    - BrollInsertion detector + greedy selector (src/analyze/broll.nim)
    - Three test fixtures under tests/fixtures/
    - tests/unit_broll.nim wired into nimble test
  affects:
    - honeyclip.nimble (test task now runs unit_broll.nim)
    - Wave 2 plans (21-02, 21-03) depend on HttpClientLike + config seams
tech_stack:
  added: []
  patterns:
    - MockHttpClient (method/urlSubstring keyed Table) for provider testing
    - env-first then TOML loadConfig pattern (mirrors src/batch/templates.nim)
    - Three-signal greedy insertion-point detection (mirrors detectEngagementPeaks)
key_files:
  created:
    - src/http_client.nim
    - src/config.nim
    - src/analyze/broll.nim
    - tests/unit_broll.nim
    - tests/fixtures/broll_transcript.json
    - tests/fixtures/comfyui_workflow.json
    - tests/fixtures/veo_lro_response.json
  modified:
    - honeyclip.nimble
decisions:
  - "Speaker identity comparison uses int (0+ speaker index) not string, matching actual TranscriptSegment.speaker type"
  - "broll.nim imports ../transcript/types directly; no separate broll-local type aliases needed"
  - "Build symlink (build -> main repo build/) required for worktree test compilation against FFmpeg libs"
  - "configPath on Windows: returns empty string when APPDATA unset rather than raising"
metrics:
  duration: ~25 min
  completed: 2026-05-08
  tasks: 4
  files: 8
---

# Phase 21 Plan 01: Wave 0 + Wave 1 Foundations Summary

HTTP client abstraction + MockHttpClient test seam + env-first TOML config + pure topic-shift insertion-point detector, all with 22 passing unit tests across 4 suites.

## What Was Built

### Task 21-01-01: HTTP client abstraction + Wave 0 test scaffolding
**Commit:** faaad69

- `src/http_client.nim`: `HttpClientLike` base ref, `RealHttpClient` (stdlib sync), `MockHttpClient` with response registry keyed by `(method, urlSubstring)` and call log.
- `tests/unit_broll.nim`: new separate test binary with suite "http_client" (4 tests).
- `honeyclip.nimble`: extended task test to compile and run `tests/unit_broll.nim` (with proper `--path:src` flag).

### Task 21-01-02: Test fixtures
**Commit:** 9fde0e3

- `tests/fixtures/broll_transcript.json`: 200s transcript with 8 segments. Pause structure: 500ms (reject), 3000ms + speaker change 0->1 (candidate), 35s gap (candidate), 400ms/100ms (rejects), 3000ms after topic shift (candidate), 30s gap + speaker change (candidate). Engagement: 40→80 delta across 55s gap.
- `tests/fixtures/comfyui_workflow.json`: ComfyUI API-format export with `{{PROMPT}}`, `{{SEED}}`, `{{LENGTH}}` placeholders.
- `tests/fixtures/veo_lro_response.json`: Veo LRO snapshots (inProgress/completed/errored).
- Added suite "fixtures" (6 smoke tests) to unit_broll.nim.

### Task 21-01-03: src/config.nim
**Commit:** 3c3df97

- `HoneyclipConfig` + `ApiSection` (geminiKey, comfyuiUrl) types.
- `configPath()`: Windows → `%APPDATA%/honeyclip/config.toml`; Linux/macOS → XDG or `~/.config`.
- `loadConfig()`: zero-value return when file missing/parse fails; warning cites path not content (T-21-02 compliant).
- `resolveGeminiKey()`: env var first, TOML fallback, empty string when neither set.
- `resolveComfyUrl()`: env var first, TOML fallback, default `http://127.0.0.1:8188`.
- Added suite "config" (6 tests) to unit_broll.nim.
- Secret-leak grep gate passes: zero matches for log calls with secret variable names.

### Task 21-01-04: src/analyze/broll.nim
**Commit:** 1f59030

- `BrollInsertion`: startMs, endMs, pauseMs, contextText, score (0..100), sourceTag.
- `BrollParams` + `defaultBrollParams()`: minSpacingMs=30s, targetDensityPerMin=1.0, maxInsertions=-1 (auto), minPauseMs=800, maxPauseMs=6000, contextWindowSec=8, minScore=50.0, weights 0.4/0.3/0.3.
- `detectBrollInsertions()`: walks adjacent segment pairs, scores with three weighted signals; speaker comparison on `int` (matches actual `TranscriptSegment.speaker` type — not `string` as in plan's interface section).
- `selectInsertions()`: filter→sort-desc→greedy-pick→chronological-sort; resolves maxInsertions from density when -1.
- endMs clamped: `startMs + min(pauseMs, maxPauseMs)`.
- Added suite "broll detection" (6 fixture-driven tests) to unit_broll.nim.
- All 22 tests pass across 4 suites.

## Verification Results

```
nim c -r --path:src tests/unit_broll.nim → EXIT 0
[Suite] http_client          4/4 OK
[Suite] fixtures             6/6 OK
[Suite] config               6/6 OK
[Suite] broll detection      6/6 OK
Total: 22/22 tests passing

nim check src/http_client.nim    → SuccessX
nim check src/config.nim         → SuccessX
nim check src/analyze/broll.nim  → SuccessX
Secret-leak grep gate (T-21-02)  → CLEAN (0 matches)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TranscriptSegment.speaker is int not string**
- **Found during:** Task 21-01-04 (reading src/transcript/types.nim)
- **Issue:** Plan's `<interfaces>` section showed `speaker*: string`, but actual `TranscriptSegment.speaker` is `int` (-1 = unassigned, 0+ = speaker index). Would have caused type mismatch compile error.
- **Fix:** `detectBrollInsertions()` compares `curr.speaker != next.speaker` as int; additionally guards `curr.speaker >= 0 and next.speaker >= 0` to treat unassigned speakers as non-boundary. Fixture JSON uses `"speaker": 0` / `"speaker": 1` (int).
- **Files modified:** `src/analyze/broll.nim`, `tests/fixtures/broll_transcript.json`, `tests/unit_broll.nim`
- **Commits:** 1f59030 (broll.nim), 9fde0e3 (fixtures)

**2. [Rule 3 - Blocking] Worktree lacks build/ symlink for FFmpeg libraries**
- **Found during:** Task 21-01-01 verification
- **Issue:** nim.cfg links against `./build/lib/libavfilter.a` etc. The worktree directory had no `build/` directory (FFmpeg libraries live in the main repo root). Without it, the linker fails.
- **Fix:** Created `build -> /c/Users/Preston/git/honeyclip/build` symlink in the worktree. This is a worktree-local environmental fix; it is NOT committed.
- **Note for future executors:** If running tests in a worktree, ensure `build/` is reachable from the worktree CWD.

## Known Stubs

None. All exported procs are fully implemented; no placeholder or TODO values flow to test assertions.

## Threat Surface Scan

No new network endpoints or trust-boundary surfaces introduced in this plan. HTTP abstraction is tested exclusively via `MockHttpClient`; `RealHttpClient` code path is not invoked. `src/config.nim` reads env vars and TOML (user-owned file, low risk). T-21-02 verified via grep gate. No threat flags to add.

## Self-Check: PASSED

Files exist:
- src/http_client.nim ✓
- src/config.nim ✓
- src/analyze/broll.nim ✓
- tests/unit_broll.nim ✓
- tests/fixtures/broll_transcript.json ✓
- tests/fixtures/comfyui_workflow.json ✓
- tests/fixtures/veo_lro_response.json ✓

Commits exist:
- faaad69 feat(21-01): add HttpClientLike abstraction + Wave 0 test scaffolding ✓
- 9fde0e3 feat(21-01): add test fixtures and fixture smoke tests ✓
- 3c3df97 feat(21-01): add src/config.nim for env-first then TOML key resolution ✓
- 1f59030 feat(21-01): add src/analyze/broll.nim topic-shift detector + greedy selector ✓
