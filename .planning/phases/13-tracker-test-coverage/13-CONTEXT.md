# Phase 13: Tracker Test Coverage - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Add comprehensive unit tests for speaker tracking modules. Tests cover Kalman filter, assignment algorithm, and tracker. Coverage must reach 80% per module for all reframe modules, enforced in CI.

</domain>

<decisions>
## Implementation Decisions

### Test data strategy
- Multi-face scenarios are essential — test 2-3 faces crossing paths, swapping positions, partial occlusion
- Temporal edge cases are critical — test face disappearing for N frames then reappearing, track age limits, hit streaks
- Claude's discretion: Whether to use synthetic generators or JSON fixtures
- Claude's discretion: Whether test data simulates smooth motion or discrete jumps (may vary by module)

### Coverage approach
- 80% coverage is a hard requirement — phase not complete until achieved
- Each module must individually hit 80% — no averaging across modules (kalman.nim at 75% fails even if tracker.nim is 95%)
- Modules in scope: All reframe modules (kalman.nim, assignment.nim, tracker.nim, crop.nim, easing.nim, compositor.nim)
- CI enforces coverage gate — builds fail if coverage drops below 80%
- Coverage regression prevention — CI fails if coverage decreases from previous commit
- Per-module breakdown in reporting — show coverage % for each module individually
- Claude's discretion: Line vs branch coverage (use what Nim tooling supports best)
- Claude's discretion: Sensible code path exclusions (error handlers, FFmpeg subprocess code)
- Claude's discretion: Coverage tool choice and upload destination

### Test isolation
- Mock embeddings for tracker tests — no real ONNX inference, keeps tests fast and ML-independent
- End-to-end tracker tests are essential — tests that feed N frames through tracker and verify final track identities
- Performance benchmarks required — verify Kalman update timing, tracker handles N faces/frame
- Claude's discretion: Whether Kalman filter tests are pure math or integrated with face types

### Assertion style
- Tolerance-based assertions for all floating point comparisons (e.g., 1e-6 epsilon)
- Track identity validation: both ID consistency AND association correctness
- Claude's discretion: Whether to verify Kalman state vectors directly or just outputs
- Claude's discretion: Hard time limits vs soft reporting for benchmarks (consider CI hardware variability)

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-tracker-test-coverage*
*Context gathered: 2026-02-05*
