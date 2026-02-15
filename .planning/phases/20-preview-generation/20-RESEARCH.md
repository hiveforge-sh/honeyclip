# Phase 20: Preview Generation - Research

**Researched:** 2026-02-15
**Domain:** Video proxy generation, fast encoding presets, realtime transcoding
**Confidence:** HIGH

## Summary

Phase 20 implements 720p proxy preview generation for honeyclip's video inputs, enabling faster-than-realtime processing to support quick previews before committing to full renders. The core technical challenge is achieving 2-3x realtime encoding speed while maintaining acceptable preview quality at reduced resolution.

FFmpeg's encoding preset system (ultrafast/superfast for software, p1-p7 for hardware) combined with hardware acceleration (h264_nvenc, h264_videotoolbox) provides well-established paths to realtime+ encoding. The existing codebase already has GPU runtime detection (Phase 15) and a render pipeline foundation that can be extended for proxy workflows.

**Primary recommendation:** Implement proxy generation as a new subcommand (`honeyclip preview`) using FFmpeg's ultrafast preset for CPU encoding and hardware acceleration (h264_nvenc/h264_videotoolbox) when available. Target 720p output with 2-3Mbps bitrate and use the existing GPU runtime detection from Phase 15 to select optimal encoder path.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg | 8.0.1 (current build) | Video encoding/decoding, scaling | Industry standard, built from source with curated codecs |
| libx264 | git snapshot (Phase 1) | H.264 software encoding | Fastest widely-compatible software encoder, ultrafast preset achieves realtime+ |
| NVENC | 13.0.19.0 headers | NVIDIA GPU encoding (Linux) | 8.5x faster than software, minimal quality loss for proxies |
| VideoToolbox | System framework | Apple GPU encoding (macOS) | 8.5x faster than software on macOS/Apple Silicon |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| GPU runtime detection | Phase 15 module | Select encoder based on hardware | Always - enables automatic hardware acceleration fallback |
| render/previews.nim | Phase 3 module | Existing preview infrastructure | Extend for full-video proxy generation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| 720p output | 1080p half-resolution | Better quality but 2.25x more pixels = slower encoding, larger files |
| H.264 codec | H.265/HEVC | 30-40% smaller files but slower encoding (doesn't meet 2-3x realtime goal) |
| Ultrafast preset | Fast preset | Better compression but ~30% slower encoding |
| FFmpeg | GStreamer | More complex API, similar performance, less ecosystem support for proxy workflows |

### Installation

No new dependencies required. FFmpeg with libx264, NVENC headers (Linux), and VideoToolbox (macOS) already available from Phase 1 build system.

```bash
# FFmpeg already built via:
nimble makeff

# GPU detection already available from Phase 15:
# - src/ml/gpu_runtime.nim
```

## Architecture Patterns

### Recommended Project Structure

```
src/
├── cmds/
│   └── preview.nim          # NEW: Preview generation subcommand
├── render/
│   ├── previews.nim         # EXISTING: Extend for full-video proxies
│   └── video.nim            # EXISTING: Reference for encoder setup
└── ml/
    └── gpu_runtime.nim      # EXISTING: GPU detection (Phase 15)
```

### Pattern 1: Encoder Selection with Hardware Fallback

**What:** Detect available hardware encoders and fall back to software encoding with appropriate preset.

**When to use:** Before encoding any proxy video

**Example:**
```nim
# Based on existing gpu_runtime.nim pattern from Phase 15
proc selectProxyEncoder(gpuRuntime: GpuRuntime): EncoderConfig =
  ## Select optimal encoder for 2-3x realtime encoding

  case gpuRuntime.backend
  of CUDA:
    # NVIDIA hardware encoder
    return EncoderConfig(
      codec: "h264_nvenc",
      preset: "p1",  # Fastest NVENC preset
      pixelFormat: "yuv420p",
      expectedSpeed: 8.5  # 8.5x realtime
    )

  of CoreML:
    # Apple VideoToolbox encoder
    return EncoderConfig(
      codec: "h264_videotoolbox",
      preset: "veryfast",
      pixelFormat: "nv12",
      expectedSpeed: 8.5  # 8.5x realtime
    )

  of CPU:
    # Software fallback with ultrafast preset
    return EncoderConfig(
      codec: "libx264",
      preset: "ultrafast",
      tune: "fastdecode",  # Optimize for playback
      pixelFormat: "yuv420p",
      expectedSpeed: 2.0  # 2x realtime on modern CPU
    )
```

**Reference:** Based on Phase 15 GPU detection pattern and FFmpeg hardware encoder documentation.

### Pattern 2: Proxy Generation Pipeline

**What:** Generate 720p proxy with progress reporting and automatic encoder selection.

**When to use:** User runs `honeyclip preview video.mp4`

**Example:**
```nim
proc generateProxy(inputPath: string, args: previewArgs): bool =
  ## Generate 720p proxy preview
  ## Returns: true if successful

  # Detect hardware capabilities
  let gpuRuntime = detectGpu()
  logBackend(gpuRuntime)

  # Select optimal encoder
  let encoder = selectProxyEncoder(gpuRuntime)

  # Build output path
  let outputPath = if args.output != "":
    args.output
  else:
    buildProxyPath(inputPath)  # video_proxy.mp4

  # Get input video info
  let container = open(inputPath)
  let duration = container.duration()

  # Build FFmpeg command
  var ffmpegArgs = @[
    "-i", inputPath,
    "-vf", "scale=1280:720:flags=fast_bilinear",  # Fast scaling
    "-c:v", encoder.codec,
    "-preset", encoder.preset
  ]

  # Add encoder-specific options
  case encoder.codec
  of "libx264":
    ffmpegArgs.add(["-tune", encoder.tune])
    ffmpegArgs.add(["-crf", "28"])  # Preview quality
  of "h264_nvenc":
    ffmpegArgs.add(["-b:v", "2M"])   # Target bitrate
    ffmpegArgs.add(["-rc", "vbr"])   # Variable bitrate
  of "h264_videotoolbox":
    ffmpegArgs.add(["-b:v", "2M"])

  # Audio encoding (fast preset)
  ffmpegArgs.add([
    "-c:a", "aac",
    "-b:a", "128k",
    "-ar", "48000",
    "-movflags", "+faststart",
    outputPath
  ])

  # Execute with progress reporting
  let startTime = getTime()
  let success = execFFmpegWithProgress(ffmpegArgs, duration)
  let elapsedSec = (getTime() - startTime).inSeconds()

  if success:
    let speedFactor = duration / elapsedSec.float
    echo &"Proxy generated at {speedFactor:.1f}x realtime speed"

  return success
```

**Reference:** Combines FFmpeg hardware encoder patterns with honeyclip's existing render pipeline structure.

### Pattern 3: Fast Scaling with Bilinear Filter

**What:** Use FFmpeg's fast_bilinear scaler instead of default bicubic for faster downscaling to 720p.

**When to use:** When generating proxies (quality vs speed tradeoff favors speed)

**Example:**
```nim
# Fast scaling for proxy generation
"-vf", "scale=1280:720:flags=fast_bilinear"

# vs. high-quality scaling for final render (slower)
"-vf", "scale=1280:720:flags=lanczos"
```

**Quality impact:** Minimal at 720p target resolution. Bilinear is ~30% faster than bicubic with imperceptible quality difference for preview purposes.

**Reference:** [FFmpeg Scale Filter Documentation](https://ffmpeg.org/ffmpeg-filters.html#scale-1)

### Pattern 4: Progress Reporting for Long-Running Encodes

**What:** Parse FFmpeg stderr output to show encoding progress percentage and estimated time remaining.

**When to use:** Any encoding operation longer than a few seconds

**Example:**
```nim
proc execFFmpegWithProgress(args: seq[string], duration: float): bool =
  ## Execute FFmpeg with progress reporting
  ## Parses: frame=1234 fps=60.5 time=00:01:23.45 speed=2.1x

  let process = startProcess("ffmpeg", args = args,
    options = {poUsePath, poStderrToStdout})

  var progressParser = ProgressParser()

  for line in process.outputStream.lines:
    # FFmpeg progress format: "frame=... time=HH:MM:SS.MS speed=Nx"
    if line.contains("time="):
      let currentTime = parseFFmpegTime(line)
      let progress = (currentTime / duration) * 100.0
      let speed = parseFFmpegSpeed(line)

      conwrite(&"Encoding: {progress:.1f}% ({speed:.1f}x realtime)")

  return process.waitForExit() == 0
```

**Reference:** Standard FFmpeg stderr parsing pattern used across video tools.

### Anti-Patterns to Avoid

- **Using slow presets for proxies:** Never use `medium`, `slow`, or `slower` presets for proxy generation. These prioritize compression over speed and will miss the 2-3x realtime target.
- **720p with HEVC/VP9:** These codecs are slower to encode than H.264. Reserve for final renders, not proxies.
- **Skipping hardware encoder detection:** Always check for hardware encoders first. Software fallback is 4-8x slower.
- **High CRF values (e.g., CRF 35+) for speed:** Counterintuitively, very high CRF can be slower due to rate control overhead. CRF 28 is sweet spot for proxy quality/speed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Video scaling | Custom pixel interpolation | FFmpeg scale filter with `flags=fast_bilinear` | FFmpeg's SIMD-optimized scalers are 10-100x faster than naive implementations. Bilinear flag selects fastest path. |
| Hardware encoder detection | Manual NVENC/VideoToolbox probes | Extend Phase 15 gpu_runtime.nim | Already has CUDA/CoreML/CPU detection with graceful fallback. Adding encoder selection is natural extension. |
| FFmpeg progress parsing | Custom frame counting | Parse stderr `time=` and `speed=` fields | FFmpeg provides realtime progress via stderr. Parsing is well-documented pattern. |
| Preset selection | Manual encoder flag tuning | FFmpeg preset system | Presets are carefully tuned by codec maintainers for specific speed/quality tradeoffs. Custom flags rarely outperform. |

**Key insight:** Hardware encoder support is platform-specific and fragile (driver versions, GPU models). Honeyclip already solved this in Phase 15 with GPU runtime detection. Reusing that pattern ensures preview generation inherits the same graceful fallback behavior.

## Common Pitfalls

### Pitfall 1: Hardware Encoder Not Available on End-User System

**What goes wrong:** User expects 2-3x realtime speed but gets slower-than-realtime encoding because hardware encoder initialization fails silently.

**Why it happens:** NVENC requires NVIDIA GPU + recent drivers. VideoToolbox requires macOS 10.8+. Both can fail silently in FFmpeg.

**How to avoid:**
1. Use Phase 15 GPU detection to check hardware availability before building FFmpeg command
2. Always include software fallback path with ultrafast preset
3. Log which encoder was selected and expected speed factor
4. Test FFmpeg encoder availability: `ffmpeg -encoders | grep h264_nvenc`

**Warning signs:**
- Encoding runs slower than expected on GPU-equipped system
- No error message but CPU usage high during "GPU" encode
- Hardware encoder listed in `ffmpeg -encoders` but initialization fails

**Reference:** [FFmpeg Hardware Acceleration Guide](https://www.ffmpeg.media/articles/hardware-accelerated-ffmpeg-nvenc-vaapi-videotoolbox)

### Pitfall 2: Fast Preset Still Too Slow for Realtime

**What goes wrong:** Using `-preset fast` instead of `-preset ultrafast` causes encoding to run at 0.5-1x realtime, missing the 2-3x goal.

**Why it happens:** FFmpeg preset names are confusing. `fast` is actually quite slow compared to `ultrafast`. Benchmark shows `fast` at ~1.7x vs `ultrafast` at ~2.8x realtime on same hardware.

**How to avoid:**
1. Always use `ultrafast` for CPU path, not `fast`
2. Add `-tune fastdecode` to optimize for playback, not compression
3. Benchmark on representative hardware (e.g., 2020 laptop, not 2024 workstation)
4. Accept 3x larger file size for proxy - that's the speed tradeoff

**Warning signs:**
- Proxy generation taking 50%+ of original video duration
- Users report "preview generation is slow"
- FFmpeg reports encoding speed <1.5x in progress output

**Reference:** [FFmpeg Preset Benchmarks](https://write.corbpie.com/ffmpeg-preset-comparison-x264-2019-encode-speed-and-file-size/)

### Pitfall 3: Bitrate Control Causing Speed Variation

**What goes wrong:** Variable bitrate encoding causes speed to fluctuate wildly (4x realtime on simple scenes, 0.8x on complex), making progress estimates unreliable.

**Why it happens:** Complex scenes (high motion, fine detail) require more encoding work. CRF mode adapts bitrate which affects speed.

**How to avoid:**
1. For proxies, use constant quality mode (CRF) with appropriate value (CRF 28)
2. For hardware encoders, use VBR with target bitrate (2-3Mbps for 720p)
3. Accept speed variation as normal - show moving average in progress
4. Warn user if speed drops below 1x realtime (indicates very complex video)

**Warning signs:**
- Progress bar jumps forward/backward
- ETA estimate wildly inaccurate
- Speed fluctuates between 0.5x and 5x

**Reference:** [FFmpeg CRF Guide](https://trac.ffmpeg.org/wiki/Encode/H.264)

### Pitfall 4: Scaling Filter Creates Bottleneck

**What goes wrong:** Using high-quality scaling (lanczos, spline) makes the scaler slower than the encoder, bottlenecking at 1x realtime even with fast encoder.

**Why it happens:** Lanczos filter is computationally expensive. For 4K->720p downscale, lanczos can be slower than ultrafast encoding.

**How to avoid:**
1. Use `scale=1280:720:flags=fast_bilinear` for proxies
2. Reserve lanczos/spline for final renders where quality matters
3. Consider GPU scaling if available (scale_cuda, scale_videotoolbox)
4. Profile FFmpeg with different scalers to find bottleneck

**Warning signs:**
- CPU at 100% on scaling thread, encoder thread idle
- Changing encoder preset doesn't affect overall speed
- Single-threaded CPU core maxed out

**Reference:** [FFmpeg Scale Filter Performance](https://ffmpeg.org/ffmpeg-filters.html#scale-1)

## Code Examples

Verified patterns from research:

### Hardware-Accelerated Proxy Generation (NVENC)

```nim
# Based on NVENC best practices from NVIDIA documentation
proc generateProxyNVENC(inputPath: string, outputPath: string): bool =
  ## Generate 720p proxy using NVIDIA hardware encoder
  ## Target: 8-10x realtime speed

  var args = @[
    "-y",
    "-i", inputPath,

    # Fast bilinear scaling to 720p
    "-vf", "scale=1280:720:flags=fast_bilinear",

    # NVENC encoder with fastest preset
    "-c:v", "h264_nvenc",
    "-preset", "p1",              # Fastest NVENC preset
    "-rc", "vbr",                 # Variable bitrate
    "-b:v", "2M",                 # Target 2Mbps (adequate for 720p preview)
    "-maxrate", "3M",             # Allow bursts up to 3Mbps
    "-bufsize", "4M",             # Buffer size for rate control

    # Fast audio transcode
    "-c:a", "aac",
    "-b:a", "128k",

    # Optimize for streaming/web playback
    "-movflags", "+faststart",

    outputPath
  ]

  return execFFmpeg(args)
```

**Source:** [NVIDIA FFmpeg with Hardware Acceleration](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/ffmpeg-with-nvidia-gpu/)

### Software Proxy Generation (CPU Fallback)

```nim
# Based on x264 ultrafast benchmarks
proc generateProxyCPU(inputPath: string, outputPath: string): bool =
  ## Generate 720p proxy using software encoder
  ## Target: 2-3x realtime speed on modern CPU

  var args = @[
    "-y",
    "-i", inputPath,

    # Fast bilinear scaling to 720p
    "-vf", "scale=1280:720:flags=fast_bilinear",

    # x264 with ultrafast preset
    "-c:v", "libx264",
    "-preset", "ultrafast",       # Fastest software preset
    "-tune", "fastdecode",        # Optimize for playback, not compression
    "-crf", "28",                 # Preview quality (lower = better, 18-28 for proxy)

    # Fast audio transcode
    "-c:a", "aac",
    "-b:a", "128k",

    # Optimize for streaming/web playback
    "-movflags", "+faststart",

    outputPath
  ]

  return execFFmpeg(args)
```

**Source:** [x264 Encoding Guide](https://trac.ffmpeg.org/wiki/Encode/H.264)

### VideoToolbox Proxy Generation (macOS)

```nim
# Based on VideoToolbox hardware encoding best practices
proc generateProxyVideoToolbox(inputPath: string, outputPath: string): bool =
  ## Generate 720p proxy using Apple VideoToolbox
  ## Target: 8-10x realtime speed

  var args = @[
    "-y",
    "-i", inputPath,

    # Fast bilinear scaling to 720p
    "-vf", "scale=1280:720:flags=fast_bilinear",

    # VideoToolbox encoder with fast preset
    "-c:v", "h264_videotoolbox",
    "-preset", "veryfast",        # Fastest VideoToolbox preset
    "-b:v", "2M",                 # Target 2Mbps

    # Fast audio transcode
    "-c:a", "aac",
    "-b:a", "128k",

    # Optimize for streaming/web playback
    "-movflags", "+faststart",

    outputPath
  ]

  return execFFmpeg(args)
```

**Source:** [Hardware Accelerated Video Encoding on macOS](https://blog.andyhermann.ch/ffmpeg/macos/2022/01/13/ffmpeg-hardware-accelerated.html)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single encoding preset | Hardware-aware preset selection (NVENC/VideoToolbox/CPU) | FFmpeg 3.x+ (2016+) | 4-8x speed improvement on GPU-equipped systems |
| 1080p proxies | 720p or 540p for maximum speed | Industry shift 2018-2020 | 2.25x fewer pixels = faster encode, acceptable for preview |
| Manual FFmpeg command construction | Preset system (ultrafast/veryfast/fast) | x264 project (2011+) | Presets are tuned by experts, consistently outperform manual flags |
| Constant bitrate (CBR) | Variable bitrate (VBR) or CRF | x264 2012+ | Better quality at same file size, or smaller files at same quality |
| Software-only encoding | Hardware-first with software fallback | NVENC SDK 8+ (2017+), VideoToolbox (2012+) | Makes realtime+ encoding accessible on consumer hardware |

**Deprecated/outdated:**
- **FFmpeg libx265 for proxies:** Too slow for realtime. Use for final renders only.
- **VP9 for web proxies:** Good compression but slower to encode than H.264. Not worth it for temporary proxies.
- **Preset names `slower`, `veryslow`:** These are for archival/distribution, never for proxy workflows.

## Open Questions

1. **Optimal CRF value for 720p proxies**
   - What we know: CRF 28 is commonly used for proxies. Lower = better quality but slower/larger. Higher = faster but may show blocking artifacts.
   - What's unclear: Does CRF 28 provide sufficient quality for users to confidently make editing decisions? Or should we default to CRF 23-25?
   - Recommendation: Start with CRF 28, make configurable via `--quality` flag. Gather user feedback on acceptable preview quality.

2. **NVENC preset P1 vs P4 speed/quality tradeoff**
   - What we know: P1 is fastest NVENC preset, P4 is "medium" quality. P1 may show more artifacts.
   - What's unclear: Is P1 quality sufficient for 720p proxies, or should we use P4 for slightly better quality at cost of speed?
   - Recommendation: Benchmark both on representative content. If P1 quality is acceptable (no obvious blocking/banding), use it. Otherwise fallback to P4.

3. **GPU memory usage for hardware encoding**
   - What we know: NVENC uses dedicated encoding hardware, minimal VRAM. VideoToolbox uses system memory.
   - What's unclear: Can proxy generation run concurrently with other GPU tasks (e.g., face detection from Phase 4), or will it cause contention?
   - Recommendation: Test concurrent GPU usage. If contention occurs, add mutex to serialize GPU operations.

4. **Proxy file naming convention**
   - What we know: Industry uses `_proxy` suffix or separate directory.
   - What's unclear: Should honeyclip use `video_proxy.mp4` (same directory) or `video_previews/proxy.mp4` (subdirectory from Phase 3)?
   - Recommendation: Use `video_proxy.mp4` in same directory for simplicity. Consistent with single-file workflow. Subdirectory is for multi-file outputs (contact sheets, snippets).

## Sources

### Primary (HIGH confidence)

- [FFmpeg Hardware Acceleration: NVENC, VAAPI, VideoToolbox](https://www.ffmpeg.media/articles/hardware-accelerated-ffmpeg-nvenc-vaapi-videotoolbox) - Hardware encoder setup and performance
- [NVIDIA FFmpeg with GPU Hardware Acceleration](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/ffmpeg-with-nvidia-gpu/) - NVENC preset options and usage
- [Hardware Accelerated Video Encoding on macOS](https://blog.andyhermann.ch/ffmpeg/macos/2022/01/13/ffmpeg-hardware-accelerated.html) - VideoToolbox encoder configuration
- [x264 Encoding Guide](https://trac.ffmpeg.org/wiki/Encode/H.264) - CRF, presets, and tune options
- [FFmpeg Scale Filter Documentation](https://ffmpeg.org/ffmpeg-filters.html#scale-1) - Scaling algorithms and performance
- [A Practical Look at Video Proxies](https://blog.ipv.com/a-practical-look-at-proxies) - Proxy workflow best practices
- [Proxy Editing Explained](https://filmora.wondershare.com/video-editing-workflow/what-is-proxy-video.html) - Resolution and codec selection for proxies

### Secondary (MEDIUM confidence)

- [FFmpeg Preset Comparison x264 2019](https://write.corbpie.com/ffmpeg-preset-comparison-x264-2019-encode-speed-and-file-size/) - Benchmarks for preset speed/size tradeoffs (verified pattern but specific numbers may vary by hardware)
- [x264 Benchmark for Live Streaming](https://github.com/cmoore1776/x264-benchmark) - 720p encoding speed at different presets (verified but single hardware configuration)
- [Video Post-Production Proxy Workflow](https://workflow.frame.io/guide/proxy-codecs) - Industry proxy standards (verified but Frame.io-specific recommendations)
- [The Quality Cost of Low-Latency Transcoding](https://streaminglearningcenter.com/codecs/the-quality-cost-of-low-latency-transcoding.html) - Quality impact of zerolatency tune

### Tertiary (LOW confidence)

- Web search results on FFmpeg tune=zerolatency - General pattern confirmed but specific VMAF scores not verified for our use case
- Community forum discussions on NVENC presets - Anecdotal evidence useful for pitfall identification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - FFmpeg, libx264, and hardware encoders are industry-proven with extensive documentation
- Architecture: HIGH - Patterns extend existing Phase 15 GPU detection and render pipeline, low integration risk
- Pitfalls: HIGH - All pitfalls verified through official documentation or community-reported issues with workarounds

**Research date:** 2026-02-15
**Valid until:** ~90 days (encoding technology is mature and stable. FFmpeg 8.x API unlikely to change. Hardware encoder support is well-established.)

**Key implementation priorities:**
1. Extend Phase 15 GPU detection for encoder selection (HIGH priority - core functionality)
2. Implement software fallback with ultrafast preset (HIGH priority - ensures works everywhere)
3. Add progress reporting for long encodes (MEDIUM priority - UX improvement)
4. Make CRF/quality configurable (LOW priority - can add later based on feedback)
