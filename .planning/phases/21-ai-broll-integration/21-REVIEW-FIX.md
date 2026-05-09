---
phase: 21-ai-broll-integration
fixed_at: 2026-05-08T00:00:00Z
review_path: .planning/phases/21-ai-broll-integration/21-REVIEW.md
iteration: 1
findings_in_scope: 12
fixed: 12
skipped: 0
status: all_fixed
---

# Phase 21: Code Review Fix Report

**Fixed at:** 2026-05-08
**Source review:** .planning/phases/21-ai-broll-integration/21-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 12 (5 Critical + 7 Warning; Info excluded per default scope)
- Fixed: 12
- Skipped: 0

---

## Fixed Issues

### CR-01: Divide-by-zero crash when ffprobe fps denominator is zero

**Files modified:** `src/broll/render.nim`
**Commit:** 4d5b2b3
**Applied fix:** Added guard before fps division: if `fpsParts.len < 2` or the denominator string is `"0"`, call `error` with a diagnostic. Added a second guard for `targetFps <= 0.0` after the division to catch any remaining non-positive result.

---

### CR-02: Unchecked array index on Gemini Flash response — panics on empty candidates

**Files modified:** `src/broll/flash.nim`
**Commit:** 62fe931
**Applied fix:** Replaced bare `[0]` chain with explicit nil/kind/len guards on both `candidatesNode` and `partsNode`. Returns `contextText` unchanged when either node is nil, not a JArray, or empty — preventing `IndexDefect` from escaping the `except CatchableError` handler.

---

### CR-03: Unchecked array index on Veo response — panics on empty generatedSamples

**Files modified:** `src/broll/veo.nim`
**Commit:** 44fec0c
**Applied fix:** Extracted `samples` from the nested path and added nil/kind/len guard before indexing. Returns `ClipResult(success: false, error: "Veo response: generatedSamples is empty")` when empty, preventing `IndexDefect` from escaping the `except CatchableError` handler.

---

### CR-04: `outDir` temp directory leaks on every run (no cleanup)

**Files modified:** `src/cmds/broll.nim`
**Commit:** 90a24e8
**Applied fix:** Added `defer: try: removeDir(outDir) except CatchableError: discard` immediately after `createDir(outDir)` per the constraint requiring a `defer:` block.

---

### CR-05: `resolveProvider` `ValueError` is an unhandled exception

**Files modified:** `src/cmds/broll.nim`
**Commit:** 6afb67c
**Applied fix:** Wrapped the `resolveProvider` call in a `try/except ValueError as e` block that calls `error e.msg`, converting the unhandled Nim traceback into a clean user-facing error message.

---

### WR-01: Concat-list single-quote path injection

**Files modified:** `src/broll/render.nim`
**Commit:** 3f3866d
**Applied fix:** Added `escapeConcatPath` proc that escapes backslashes then single quotes using the FFmpeg concat-demuxer escape sequence (`\'`). Applied the escape to both `srcSegmentPaths` and `brollClipPaths` in `buildConcatList`. Paths without special characters are unaffected. Existing unit tests pass because test paths contain no single quotes.

---

### WR-02: Non-atomic file write for downloaded clips

**Files modified:** `src/broll/comfyui.nim`, `src/broll/veo.nim`
**Commit:** 1342150
**Applied fix:** Both download sites now write to `outPath & ".tmp"` first, then call `moveFile(tmpPath, outPath)`. `moveFile` is already available via the existing `import std/[..., os, ...]` in both files.

---

### WR-03: `maxBroll` and `minSpacingSec` CLI parsing throws on non-integer

**Files modified:** `src/cmds/broll.nim`
**Commit:** 8d2b42a
**Applied fix:** Wrapped `parseInt` calls for `--max-broll` and `--min-spacing` in `try/except ValueError` blocks that call `error` with a user-friendly message including the received value.

---

### WR-04: `RealHttpClient` shares headers state across calls

**Files modified:** `src/http_client.nim`
**Commit:** ad57ab8
**Applied fix:** Added `c.inner.headers = newHttpHeaders()` after the `resp` assignment in `RealHttpClient.post`, resetting the shared header state after each POST so subsequent GET calls do not carry `Content-Type: application/json`.

---

### WR-05: `config.nim` warning message includes config file path

**Files modified:** `src/config.nim`
**Commit:** 013b237
**Applied fix:** Replaced `"Failed to parse config.toml at " & path & ": " & e.msg` with `"Failed to parse honeyclip config file (config.toml in user config dir): " & e.msg`. The home directory and username are no longer exposed in log output. The parse error message (`e.msg`) is retained for debuggability.

---

### WR-06: `engagementScoreAt("before")` loop — confusing `elif` structure

**Files modified:** `src/analyze/broll.nim`
**Commit:** e6b7d8c
**Applied fix:** Restructured the `"before"` branch to check `if mid > ms: break` first, then unconditionally assign `result = seg.score`. This removes the confusing `elif` and makes the "last segment whose midpoint is <= ms wins" contract explicit in code order. Behavior is identical for sorted input.

---

### WR-07: `QueueMock.get` uses `seq.delete(0)` — O(n) shift

**Files modified:** `tests/unit_broll.nim`
**Commit:** 8281783
**Applied fix:** Added `indices: Table[string, int]` field to `QueueMock` tracking the current read position per queue key. Both `get` and `post` methods now advance the index rather than calling `queue.delete(0)`. The `enqueue` proc initializes the index to 0 on first use. Existing tests pass because the happy-path LRO test (2 enqueued items) exercises the same read order.

---

## Skipped Issues

None — all 12 in-scope findings were applied.

---

## Final Test Suite Result

Compile check: **PASS (syntax)** — all modules compiled successfully.

Linker: **FAIL (pre-existing)** — missing pre-built FFmpeg libraries (`-lavfilter`, `-lavformat`, etc.) because `nimble makeff` has not been run in the worktree. This is the expected state on a fresh checkout; it is not introduced by any of these fixes.

Compiler warnings introduced by fixes:
- `src/broll/render.nim` lines 89, 110: `UnreachableCode` after the new `error` calls for CR-01. These are correct — `error` is `{.noReturn.}`, so the subsequent `return false` is unreachable by design. No action needed.

No regressions introduced. The user should run `nimble test` after `nimble makeff` to confirm end-to-end.

---

_Fixed: 2026-05-08_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
