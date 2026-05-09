---
phase: 21
plan: 03
subsystem: tests + docs
tags: [e2e, python, unittest, snapshot, cli, docs, readme]
dependency_graph:
  requires:
    - honeyclip broll subcommand binary (src/cmds/broll.nim) from 21-02
    - tests/fixtures/comfyui_workflow.json from 21-01
    - BrollInsertion marker JSON shape (src/broll/markers.nim) from 21-02
  provides:
    - tests/test_broll.py (Phase 21 E2E harness, 4 TestCase classes)
    - tests/fixtures/broll_marker_snapshot.json (stable marker JSON shape fixture)
    - README.md B-Roll section (setup, backends, cost, config, SSRF caveat)
    - tests/test.py wired to invoke test_broll.py
  affects:
    - tests/test.py (Phase 21 E2E wiring appended to main())
    - README.md (B-Roll section added before License)
tech_stack:
  added: []
  patterns:
    - Python unittest.TestCase (matches existing tests/test.py pattern)
    - subprocess invocation from tests/test.py for cross-framework wiring
    - find_binary() worktree probe via git --git-common-dir
    - GEMINI_API_KEY env strip in offline failure test (T-21-02 compliance)
key_files:
  created:
    - tests/test_broll.py
    - tests/fixtures/broll_marker_snapshot.json
  modified:
    - tests/test.py
    - README.md
decisions:
  - "find_binary() probes git --git-common-dir to locate binary in main worktree when running inside a git worktree; avoids hard-coding paths"
  - "BrollOfflineFailureTest uses --backend auto + closed port (127.0.0.1:1) + no GEMINI_API_KEY; asserts non-zero exit and presence of a backend-related term in combined output"
  - "BrollAudioSyncSmokeTest gates on HONEYCLIP_E2E_LIVE=1 env var; always skips in offline/CI context (live render requires ComfyUI or Veo)"
  - "README B-Roll section placed before License; uses ## heading level matching all other top-level sections"
  - "Binary compiled in worktree for test execution (nimble make); build/ symlink required per 21-01 pattern"
metrics:
  duration: ~30 min
  completed: 2026-05-09
  tasks: 2
  files: 4
---

# Phase 21 Plan 03: E2E Harness + README Documentation Summary

Python E2E harness validating `honeyclip broll` CLI against the built binary via subprocess; stable marker JSON shape fixture; README B-Roll section covering ComfyUI/Veo setup, config.toml location and permissions, cost worked example, and SSRF caveat.

## What Was Built

### Task 21-03-01: E2E Python harness + marker JSON snapshot + audio-sync smoke
**Commit:** bc1fe71

- `tests/test_broll.py`: 4 TestCase classes:
  - `BrollHelpTest`: asserts exit 0 and all 7 documented flags in `--help` output
  - `BrollOfflineFailureTest`: strips GEMINI_API_KEY, points --comfy-url at closed port, asserts non-zero exit with backend-relevant error text (T-21-02 compliant)
  - `BrollMarkerSnapshotTest`: loads `tests/fixtures/broll_marker_snapshot.json`, asserts top-level `{sourceVideo, insertions}` keys and per-insertion 10-key set
  - `BrollAudioSyncSmokeTest`: always skips in offline/CI (gates on HONEYCLIP_E2E_LIVE=1)
- `tests/fixtures/broll_marker_snapshot.json`: stable JSON fixture with full 10-key insertion shape
- `tests/test.py`: Phase 21 B-roll E2E wired via subprocess at end of `main()`, with `from pathlib import Path` import added

### Task 21-03-02: README B-Roll section
**Commit:** 146b9e4

- New `## B-Roll` section in README.md (96 lines):
  - What broll does (1-sentence intro)
  - ComfyUI quick start: `--workflow`, `--render`, 3 example invocations
  - Veo quick start: `GEMINI_API_KEY`, config.toml path by OS, `chmod 600` instruction, `.gitignore` reminder
  - `[api]` TOML shape with `geminiKey` and `comfyuiUrl` keys
  - Backend selection table (auto / comfyui / veo)
  - Cost note: pricing table + worked example (30min * $0.15/s * 8s = $36), `--max-broll`, `--yes`
  - SSRF caveat: `--comfy-url` is trusted; do not point at internal services
  - Output formats: marker JSON (default) vs --render muxed video + sidecar
  - Caveat: broll is the first network-dependent honeyclip feature

## Verification Results

```
python3 tests/test_broll.py:
  BrollAudioSyncSmokeTest ... skipped (HONEYCLIP_E2E_LIVE != 1)
  BrollHelpTest ... ok
  BrollMarkerSnapshotTest ... ok
  BrollOfflineFailureTest ... ok
  Ran 4 tests in 2.095s — OK (skipped=1)

grep -cE "^## .*B-?Roll" README.md → 1
grep -c "GEMINI_API_KEY" README.md → 2
grep -c "config.toml" README.md → 4
grep -c "chmod 600" README.md → 1
grep -cE "(--max-broll|--workflow|--backend|--render|--yes)" README.md → 9
grep -c "127.0.0.1:8188" README.md → 3
grep -c "\[api\]" README.md → 1
grep -iE "(SSRF|do not point)" README.md → 2
grep -c "test_broll" tests/test.py → 1
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] honeyclip binary in worktree not compiled (outdated main-repo binary)**
- **Found during:** Task 21-03-01 verification
- **Issue:** The main-repo binary (`honeyclip.exe`, Feb 14 timestamp) predates Phase 21 work and does not include the `broll` subcommand. Running `honeyclip broll --help` from it returned exit 0 but showed the root help (without broll). The worktree had no compiled binary.
- **Fix:** Created `build -> /c/Users/Preston/git/honeyclip/build` symlink (per 21-01 pattern) and ran `nimble make` in the worktree. Binary compiled in 122s. This environmental fix is not committed (same as 21-01 pattern).
- **Note for future executors:** Worktree builds require the `build/` symlink and `nimble make` before E2E tests can pass.

**2. [Rule 2 - Missing] `from pathlib import Path` missing in tests/test.py**
- **Found during:** Task 21-03-01 wiring
- **Issue:** The Phase 21 wiring appended to tests/test.py's `main()` uses `Path(__file__).parent / "test_broll.py"`, but `pathlib.Path` was not imported in tests/test.py.
- **Fix:** Added `from pathlib import Path` to imports.
- **Files modified:** `tests/test.py`
- **Commit:** bc1fe71

## Known Stubs

None. All test assertions are real; snapshot fixture uses synthetic but structurally complete data; README documents actual shipped behavior.

## Threat Surface Scan

No new network endpoints, auth paths, or file-system trust boundaries introduced.
- `tests/test_broll.py` invokes the binary as subprocess; it strips GEMINI_API_KEY from the offline test env (T-21-02 mitigated)
- `tests/fixtures/broll_marker_snapshot.json` is static synthetic JSON (no secrets, no real API keys)
- `README.md` is documentation only

No threat flags to add.

## Self-Check: PASSED

Files exist:
- tests/test_broll.py FOUND
- tests/fixtures/broll_marker_snapshot.json FOUND
- tests/test.py FOUND (modified)
- README.md FOUND (modified)

Commits exist:
- bc1fe71 test(21-03): add E2E Python harness + marker JSON snapshot for broll subcommand FOUND
- 146b9e4 docs(21-03): add B-Roll section to README with setup, cost, and SSRF caveat FOUND
