# Phase 11: ML Library Size Optimization - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Reduce ML library size from 114MB to under 50MB (soft limit) or 100MB (hard limit) through build configuration, module selection, and post-build stripping. No new capabilities — optimization only.

</domain>

<decisions>
## Implementation Decisions

### OpenCV module selection
- Keep core, imgproc, objdetect modules (required for face detection)
- Keep photo module (useful for future image preprocessing)
- Disable highgui, video modules (unused)
- Disable image codecs (JPEG/PNG support) — FFmpeg handles media I/O
- Claude determines exact minimum module set through dependency analysis

### ONNX Runtime configuration
- Keep GPU/hardware acceleration capability available
- CPU-only as default, but don't remove provider infrastructure
- Enable CoreML (macOS), CUDA (Linux) as build options

### Build optimization flags
- MinSizeRel (-Os) for OpenCV and libfacedetection
- Release (-O2) for ONNX Runtime inference performance
- LTO enabled on macOS/Linux, disabled on Windows (known issues)
- Enable all SIMD optimizations (NEON/SSE/AVX) — performance worth small size increase
- Claude determines thin vs regular archives based on build constraints

### Symbol stripping approach
- Keep function names in stripped binary (useful for crash reports)
- Create separate debug symbol files (.dSYM on macOS, .debug on Linux)
- Strip fat binary on macOS (not per-architecture)
- Claude determines optimal strip timing (post-build vs during compile)

### Size validation behavior
- Run size check automatically after every ML build
- 50MB soft limit: warning + interactive prompt (skip prompt in CI)
- 100MB hard limit: warning only (no build failure)
- Report per-library breakdown with comparison to previous sizes

### Claude's Discretion
- Exact OpenCV module dependency analysis
- Thin vs regular archive decision
- Strip timing in build pipeline
- CI-specific behavior adjustments

</decisions>

<specifics>
## Specific Ideas

- Want ability to enable GPU acceleration later — don't remove the infrastructure
- Crash reports should show function names, not just addresses
- Size tracking should help identify which library is causing bloat

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-ml-library-size-optimization*
*Context gathered: 2026-02-05*
