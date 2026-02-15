---
phase: 20-preview-generation
plan: 01
subsystem: proxy-preview
tags: [proxy, hardware-encoding, cli, preview]

dependency_graph:
  requires: [gpu_runtime, av, previews]
  provides: [proxy_generation, preview_command]
  affects: [render_pipeline, cli_commands]

tech_stack:
  added:
    - h264_nvenc (NVIDIA NVENC hardware encoder)
    - h264_videotoolbox (Apple VideoToolbox hardware encoder)
    - fast_bilinear (FFmpeg fast scaling algorithm)
  patterns:
    - GPU-aware encoder selection with CPU fallback
    - Live FFmpeg stderr progress parsing
    - Stateful CLI argument parsing

key_files:
  created:
    - src/render/proxy.nim
    - src/cmds/preview.nim
  modified:
    - src/main.nim

decisions:
  - title: "Bitrate mode by backend"
    rationale: "Hardware encoders (NVENC/VideoToolbox) use VBR 2M, CPU uses CRF 28 for balanced speed/quality"
    alternatives: ["Uniform CRF across all backends", "Expose bitrate as CLI option"]
    chosen: "Backend-specific defaults optimize for hardware capabilities"

  - title: "fast_bilinear scaling"
    rationale: "Fastest scaling algorithm for proxy generation where quality is secondary to speed"
    alternatives: ["lanczos (higher quality)", "bicubic", "bilinear"]
    chosen: "fast_bilinear maximizes encoding speed for preview use case"

  - title: "Progress parsing from stderr"
    rationale: "FFmpeg outputs progress to stderr, parse time= and speed= for live updates"
    alternatives: ["Poll output file size", "Use FFmpeg progress protocol"]
    chosen: "Stderr parsing is simplest, no special FFmpeg flags needed"

metrics:
  duration_seconds: 149
  tasks_completed: 2
  files_created: 2
  files_modified: 1
  commits: 2
  completed_date: 2026-02-15
---

# Phase 20 Plan 01: Proxy Preview Generation Summary

**One-liner:** 720p proxy generation with GPU-aware encoder selection (NVENC/VideoToolbox/x264) and live progress reporting via `honeyclip preview` command.

## Overview

Implemented a fast proxy generation pipeline that creates 720p preview videos for quick review before full renders. The system automatically detects available GPU hardware (CUDA on Linux, CoreML on macOS) and selects the optimal encoder, falling back to ultrafast CPU encoding when hardware acceleration is unavailable.

## Implementation Details

### Core Modules

**src/render/proxy.nim** - Proxy encoding pipeline with hardware acceleration:
- `EncoderConfig` type: codec, preset, tune, pixelFormat, bitrateMode, bitrateValue
- `ProxyResult` type: outputPath, success, speedFactor, error
- `selectProxyEncoder()`: GPU-aware encoder selection
  - CUDA → h264_nvenc with p1 preset (fastest NVENC mode)
  - CoreML → h264_videotoolbox with veryfast preset
  - CPU → libx264 with ultrafast preset and fastdecode tune
- `buildProxyPath()`: generates `{name}_proxy.mp4` output path
- `buildFFmpegArgs()`: constructs complete FFmpeg argument list
  - Video: scale to 720p with fast_bilinear, hardware/software encoding
  - Audio: AAC 128k 48kHz
  - Container: MP4 with +faststart for web playback
- `parseProgress()`: extracts time= and speed= from FFmpeg stderr
- `generateProxy()`: main entry point with live progress updates via `conwrite()`

**src/cmds/preview.nim** - CLI subcommand:
- Follows established pattern from chapters.nim
- Arguments: input file (positional), -o/--output, -q/--quiet, --help
- Calls `generateProxy()` and prints summary with speed factor

**src/main.nim** - Command registration:
- Added preview to import list and cmdHandlers seq
- Updated help text with preview command description

### Encoder Selection Strategy

| Backend | Codec | Preset | Bitrate Mode | Target Speed |
|---------|-------|--------|--------------|--------------|
| CUDA | h264_nvenc | p1 | VBR 2M | 5-10x realtime |
| CoreML | h264_videotoolbox | veryfast | VBR 2M | 3-5x realtime |
| CPU | libx264 | ultrafast | CRF 28 | 2-3x realtime |

All configurations target 720p (1280x720) output with fast_bilinear scaling for maximum speed.

### Progress Reporting

FFmpeg stderr is parsed in real-time for:
- `time=HH:MM:SS.MS` → converted to progress percentage (0-100%)
- `speed=Nx` → encoding speed factor (e.g., 2.3x realtime)

Updates displayed via `conwrite()` for in-place terminal output:
```
Encoding proxy: 47.3% (speed: 2.8x)
```

Final summary shows actual speed factor based on wall-clock time:
```
Proxy created: video_proxy.mp4 (2.7x realtime)
```

## Integration Points

1. **GPU Runtime Detection** (Phase 15):
   - Calls `detectGpu()` to determine available backend
   - Calls `logBackend()` to inform user of encoder selection

2. **FFmpeg Path Resolution**:
   - Uses `findFFmpegPath()` from previews module
   - Checks build/bin first, then PATH (matches existing pattern)

3. **Media Container Parsing**:
   - Opens input via `av.open()` to extract duration
   - Calculates duration from timebase for progress percentage

4. **CLI Subcommand Pattern**:
   - Stateful argument parsing with `expecting` variable
   - `handleKey()` for key normalization
   - Help text with examples following chapters.nim format

## Testing Verification

All verification steps passed:
- `nim check src/render/proxy.nim` ✓ (compiles cleanly)
- `nim check src/cmds/preview.nim` ✓ (compiles cleanly)
- `nim check src/main.nim` ✓ (compiles cleanly with preview import)
- `grep -n "preview" src/main.nim` ✓ (shows import and handler registration)
- `grep -n "selectProxyEncoder" src/render/proxy.nim` ✓ (function exists)
- `grep -n "generateProxy" src/render/proxy.nim` ✓ (function exists)

## Deviations from Plan

None - plan executed exactly as written.

## Commits

1. **4150540** - `feat(20-01): implement proxy encoding pipeline with hardware encoder selection`
   - Created src/render/proxy.nim with EncoderConfig, ProxyResult types
   - Implemented selectProxyEncoder, buildProxyPath, buildFFmpegArgs, parseProgress, generateProxy
   - Support for CUDA (h264_nvenc), CoreML (h264_videotoolbox), CPU (libx264) backends

2. **c486df8** - `feat(20-01): add preview CLI subcommand and register in main`
   - Created src/cmds/preview.nim with argument parsing and help text
   - Registered preview command in main.nim cmdHandlers
   - Updated main help text with preview command description

## Files Modified

**Created:**
- `src/render/proxy.nim` (340 lines)
- `src/cmds/preview.nim` (56 lines)

**Modified:**
- `src/main.nim` (added import, handler registration, help text)

## Success Criteria

All success criteria met:

- ✓ proxy.nim compiles and exports EncoderConfig, selectProxyEncoder, buildProxyPath, generateProxy
- ✓ preview.nim compiles and follows established CLI subcommand pattern
- ✓ main.nim registers preview subcommand in cmdHandlers
- ✓ Encoder selection covers CUDA, CoreML, and CPU backends
- ✓ Progress parsing handles FFmpeg stderr output format (time= and speed= patterns)
- ✓ Output defaults to {input}_proxy.mp4, overridable with --output

## Next Steps

Phase 20 Plan 02 will implement multi-format proxy generation with aspect ratio variants (1:1, 9:16, 16:9, 4:5) for platform-specific previews. The current single-format proxy provides the foundation for the multi-format batch processing system.

---

## Self-Check: PASSED

All claimed files and commits verified:

**Files:**
- ✓ src/render/proxy.nim exists
- ✓ src/cmds/preview.nim exists
- ✓ src/main.nim modified (preview import and registration confirmed)

**Commits:**
- ✓ 4150540 exists (proxy encoding pipeline)
- ✓ c486df8 exists (preview CLI subcommand)
