# Phase 1: Foundation & Build Infrastructure - Context

**Gathered:** 2026-02-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish cross-platform build system for ML libraries (libfacedetection, ONNX Runtime, OpenCV) with Nim FFI memory management patterns. This is foundational infrastructure — no user-facing features, just the build and integration layer that later phases depend on.

</domain>

<decisions>
## Implementation Decisions

### Build Configuration
- All ML libraries required (not optional) — full capability guaranteed, simpler code paths
- Fail fast on missing dependencies with clear messages listing what's missing
- Version-locked cache for ML library builds — rebuild only when lib version changes
- Parallel compilation by default — build ONNX, OpenCV, libfacedetection concurrently

### Binary Size Strategy
- Target full static linking for single-binary deployment
- If exceeding size limit, fall back to dynamic linking as primary mitigation
- Same linking strategy across all platforms (Windows, Linux, macOS) for consistency
- Hard ceiling: 100MB acceptable if needed for full functionality
- Include ALL ONNX execution providers (CPU, CUDA, DirectML, CoreML) for maximum hardware acceleration
- ONNX model files downloaded on first use, not bundled — smaller initial binary
- Full LTO (Link-Time Optimization) for release builds
- CI produces both release and debug builds

### FFI Error Handling
- Catch C++ exceptions and convert to Nim errors — graceful error messages
- On frame-level ML failure: skip frame, log warning, continue processing
- On memory allocation failure: attempt recovery (free caches, reduce batch size, retry)
- 30-second timeout per FFI call to prevent hangs on corrupted input

### Developer Experience
- Build output shows progress summary (current step, elapsed time, % complete) — hide cmake/make noise
- First-time build checks dependencies and provides platform-specific install hints
- Windows cross-compilation documented step-by-step in README
- Build failures generate diagnostic report file (system info, logs, versions) for easy bug reporting

### Claude's Discretion
- Exact GC_ref/GC_unref patterns for each library
- CMake configuration details
- Specific strip flags and optimization levels
- Cache directory structure and invalidation logic

</decisions>

<specifics>
## Specific Ideas

- User wants extreme performance focus and scalability to millions of users
- For Phase 1, this means: fast parallel builds, optimized binary size, reliable cross-platform support
- Runtime ML performance optimization comes in later phases (face detection, engagement scoring)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-foundation-build-infrastructure*
*Context gathered: 2026-02-01*
