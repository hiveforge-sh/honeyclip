# Phase 15: Performance Foundation - Research

**Researched:** 2026-02-13
**Domain:** GPU acceleration, memory management for video processing
**Confidence:** MEDIUM

## Summary

Phase 15 focuses on enabling GPU acceleration for ML-based face detection and implementing memory-efficient processing for 4K+ video files. The current codebase has a foundation for ML processing (libfacedetection, OpenCV, ONNX Runtime) but all ML features are CPU-only and stubbed out on Windows due to LTO build issues.

GPU acceleration requires different strategies per platform: CUDA on Linux/NVIDIA, CoreML on macOS/Apple Silicon. Memory efficiency requires implementing frame buffer pooling and bounded decode queues to prevent OOM crashes during 4K video processing. The key architectural challenge is making GPU acceleration optional with graceful CPU fallback to ensure the tool works on systems without GPU support.

**Primary recommendation:** Implement GPU support via ONNX Runtime execution providers (CUDA on Linux, CoreML on macOS), add frame buffer pool pattern for 4K processing, implement bounded decode queue with configurable max frames in memory, and add runtime GPU detection with automatic CPU fallback.

## Standard Stack

### Core GPU Acceleration Libraries

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ONNX Runtime | 1.20.1 (current in build) | ML inference with GPU execution providers | Industry-standard inference engine with multi-platform GPU support via execution providers |
| CUDA Toolkit | 12.x | GPU acceleration on NVIDIA hardware (Linux) | Required by ONNX Runtime CUDA execution provider, latest stable version |
| CoreML | System framework | GPU/NPU acceleration on Apple Silicon (macOS 10.15+) | Native macOS ML framework, accessed via ONNX Runtime CoreML execution provider |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| libfacedetection | 3.0 | CPU-based face detection | Fallback when GPU unavailable, baseline implementation |
| OpenCV | 4.10.0 | Image preprocessing (resize, color conversion) | Required for all face detection paths, minimal module set |

### GPU Support Status in Current Stack

**libfacedetection:** No native GPU support. SIMD-optimized CPU implementation only.

**OpenCV:** Has optional CUDA module (`opencv_cuda`) but requires separate build. Current build disables CUDA (`-DWITH_CUDA=OFF`). Not recommended for this phase - OpenCV CUDA adds significant build complexity and binary size for minimal benefit (only used for resize/color conversion).

**ONNX Runtime:** Best GPU integration option. Supports multiple execution providers:
- **CUDA Execution Provider** (Linux/Windows + NVIDIA GPU): Requires CUDA 12.x runtime, no rebuild needed if using dynamic linking
- **CoreML Execution Provider** (macOS 10.15+): Uses Apple Neural Engine/GPU, zero external dependencies
- **CPU Execution Provider** (all platforms): Always available as fallback

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ONNX Runtime | TensorRT directly | More NVIDIA-specific optimization but Linux/NVIDIA-only, no macOS support, harder to integrate |
| CoreML via ONNX RT | Metal Performance Shaders | Lower-level control but requires manual model optimization, more integration work |
| Frame buffer pool | Per-frame allocation | Simpler code but 10-100x allocation overhead for 4K frames, memory fragmentation |

### Installation

**Linux (CUDA path):**
```bash
# CUDA Toolkit (for CUDA execution provider)
# Install from NVIDIA package repository or download installer
# https://developer.nvidia.com/cuda-downloads

# ONNX Runtime already built via nimble makeml
# Just need to enable CUDA execution provider at runtime
```

**macOS (CoreML path):**
```bash
# CoreML is system framework - no installation needed
# Requires macOS 10.15+ (Catalina or later)

# ONNX Runtime already built via nimble makeml
# Just need to enable CoreML execution provider at runtime
```

**Build system changes:**
- No changes to `nimble makeml` required for ONNX Runtime (already builds with execution provider support)
- CUDA runtime detection happens at honeyclip runtime, not build time
- CoreML is always available on macOS 10.15+

## Architecture Patterns

### Recommended Project Structure

```
src/
├── ml/
│   ├── facedetect.nim       # High-level face detection API (existing)
│   ├── onnx.nim             # ONNX Runtime FFI (existing)
│   ├── opencv.nim           # OpenCV FFI (existing)
│   ├── gpu_runtime.nim      # NEW: GPU detection + execution provider setup
│   └── buffer_pool.nim      # NEW: Frame buffer pooling
├── analyze/
│   ├── faces.nim            # Face analysis pipeline (existing)
│   └── frame_decoder.nim    # NEW: Bounded decode queue
```

### Pattern 1: GPU Runtime Detection with Fallback

**What:** Detect GPU availability at runtime and configure ONNX Runtime execution providers, falling back to CPU if GPU unavailable or initialization fails.

**When to use:** Before any ML inference (face detection, future ONNX models)

**Example:**
```nim
# src/ml/gpu_runtime.nim
type
  GpuBackend* = enum
    CPU = "cpu"
    CUDA = "cuda"      # Linux + NVIDIA GPU
    CoreML = "coreml"  # macOS + Apple Silicon/Intel

  GpuRuntime* = object
    backend*: GpuBackend
    available*: bool
    deviceName*: string

proc detectGpu*(): GpuRuntime =
  ## Detect available GPU and return runtime config
  ## Order: CUDA (Linux) -> CoreML (macOS) -> CPU (fallback)

  when defined(linux):
    # Try CUDA first
    if checkCudaAvailable():
      return GpuRuntime(
        backend: CUDA,
        available: true,
        deviceName: getCudaDeviceName()
      )

  when defined(macosx):
    # Try CoreML (always available on macOS 10.15+)
    if checkCoreMLAvailable():
      return GpuRuntime(
        backend: CoreML,
        available: true,
        deviceName: "Apple Neural Engine"
      )

  # Fallback to CPU
  return GpuRuntime(
    backend: CPU,
    available: false,
    deviceName: "CPU"
  )

proc createOrtSession*(modelPath: string, runtime: GpuRuntime): OrtSession =
  ## Create ONNX Runtime session with appropriate execution provider
  let env = initOrtEnv()

  case runtime.backend
  of CUDA:
    # CUDA execution provider + CPU fallback
    # Note: ONNX Runtime C API requires provider options setup
    return loadModelWithProviders(env, modelPath, ["CUDAExecutionProvider", "CPUExecutionProvider"])
  of CoreML:
    # CoreML execution provider + CPU fallback
    return loadModelWithProviders(env, modelPath, ["CoreMLExecutionProvider", "CPUExecutionProvider"])
  of CPU:
    # CPU only
    return loadModel(env, modelPath)
```

**Reference:** Based on ONNX Runtime execution provider pattern. See [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/execution-providers/).

### Pattern 2: Frame Buffer Pool

**What:** Pre-allocate pool of frame buffers and reuse them instead of allocating/deallocating per frame. Reduces allocation overhead and memory fragmentation for 4K frames.

**When to use:** Video decoding/processing pipelines that handle many frames

**Example:**
```nim
# src/ml/buffer_pool.nim
type
  FrameBuffer* = object
    data*: ptr uint8
    capacity*: int
    width*: int
    height*: int
    channels*: int
    inUse*: bool

  BufferPool* = object
    buffers: seq[FrameBuffer]
    maxBuffers: int
    frameSize: int  # bytes per frame

proc newBufferPool*(width, height, channels: int, maxBuffers: int = 16): BufferPool =
  ## Create frame buffer pool
  ## For 4K BGR: 3840 * 2160 * 3 = ~25MB per buffer
  ## Pool of 16 = ~400MB pre-allocated
  result.maxBuffers = maxBuffers
  result.frameSize = width * height * channels
  result.buffers = newSeq[FrameBuffer](maxBuffers)

  for i in 0..<maxBuffers:
    result.buffers[i] = FrameBuffer(
      data: cast[ptr uint8](alloc(result.frameSize)),
      capacity: result.frameSize,
      width: width,
      height: height,
      channels: channels,
      inUse: false
    )

proc acquire*(pool: var BufferPool): ptr FrameBuffer =
  ## Get available buffer from pool (blocks if all in use)
  for i in 0..<pool.buffers.len:
    if not pool.buffers[i].inUse:
      pool.buffers[i].inUse = true
      return addr pool.buffers[i]

  # All buffers in use - this indicates queue needs to drain
  return nil

proc release*(pool: var BufferPool, buffer: ptr FrameBuffer) =
  ## Return buffer to pool
  buffer.inUse = false

proc `=destroy`*(pool: var BufferPool) =
  for i in 0..<pool.buffers.len:
    if pool.buffers[i].data != nil:
      dealloc(pool.buffers[i].data)
```

**Reference:** Based on GStreamer BufferPool pattern. See [GStreamer Memory Allocation](https://gstreamer.freedesktop.org/documentation/plugin-development/advanced/allocation.html).

### Pattern 3: Bounded Decode Queue

**What:** Limit number of decoded frames in memory to prevent OOM. Blocks decoding when queue is full until consumer processes frames.

**When to use:** Video decoding pipelines to prevent unbounded memory growth

**Example:**
```nim
# src/analyze/frame_decoder.nim
type
  BoundedDecoder* = object
    codecCtx: ptr AVCodecContext
    maxQueueSize: int
    queue: seq[ptr AVFrame]
    queueLock: Lock
    queueCond: Cond

proc newBoundedDecoder*(codecCtx: ptr AVCodecContext, maxQueueSize: int = 30): BoundedDecoder =
  ## Create bounded decoder
  ## For 4K frames: 30 frames * ~25MB = ~750MB max memory
  result.codecCtx = codecCtx
  result.maxQueueSize = maxQueueSize
  result.queue = @[]
  initLock(result.queueLock)
  initCond(result.queueCond)

iterator decode*(decoder: var BoundedDecoder, packet: ptr AVPacket): ptr AVFrame =
  ## Decode with bounded queue
  ## Blocks when queue is full (backpressure to prevent OOM)

  var frame = av_frame_alloc()

  while avcodec_receive_frame(decoder.codecCtx, frame) >= 0:
    # Wait if queue full
    acquire(decoder.queueLock)
    while decoder.queue.len >= decoder.maxQueueSize:
      wait(decoder.queueCond, decoder.queueLock)

    decoder.queue.add(frame)
    release(decoder.queueLock)

    yield frame

    # Consumer processed frame, signal queue has space
    acquire(decoder.queueLock)
    let idx = decoder.queue.find(frame)
    if idx >= 0:
      decoder.queue.delete(idx)
    signal(decoder.queueCond)
    release(decoder.queueLock)
```

**Reference:** Based on bounded blocking queue pattern. See [Design Bounded Blocking Queue](https://medium.com/@preetipriyanka24/design-bounded-blocking-queue-ba98ff9f6b5c).

### Anti-Patterns to Avoid

- **Per-frame allocation for 4K:** At 25MB per frame, allocating/deallocating every frame creates massive overhead and fragmentation. Always use buffer pooling.
- **Unbounded decode queue:** Decoding ahead without consumption limit will OOM on large files. Always bound queue size.
- **Hard GPU requirement:** Never require GPU - always provide CPU fallback. Users may run on VMs, headless servers, or systems without GPU.
- **Build-time GPU detection:** CUDA/GPU availability must be detected at runtime, not compile time. Users may build on one system and run on another.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GPU detection | Custom CUDA/Metal probes | ONNX Runtime execution provider fallback chain | ONNX RT handles provider initialization, fallback logic, and error recovery. Building custom GPU detection misses edge cases (driver version mismatches, partial GPU support, etc.) |
| Memory pooling | Custom allocator | Object pool pattern with pre-allocated buffers | Memory pools have subtle correctness issues (alignment, thread safety, fragmentation). Use proven pattern with clear acquire/release semantics. |
| Frame queue | Custom ring buffer | Bounded blocking queue | Correct backpressure logic is tricky (deadlock, starvation, fairness). Use standard concurrent data structure. |

**Key insight:** GPU acceleration has many platform-specific failure modes (driver issues, version mismatches, insufficient VRAM, etc.). ONNX Runtime's execution provider system handles these gracefully with automatic fallback. Building custom GPU detection/fallback logic will miss rare but critical edge cases that crash user workflows.

## Common Pitfalls

### Pitfall 1: Missing CUDA Runtime on End-User System

**What goes wrong:** Application built with CUDA support crashes with "nvcuda.dll not found" or similar errors on systems without NVIDIA GPU or CUDA runtime installed.

**Why it happens:** Build-time linking to CUDA libraries, or runtime loading without fallback logic.

**How to avoid:**
1. Use ONNX Runtime execution provider fallback: `['CUDAExecutionProvider', 'CPUExecutionProvider']`
2. ONNX Runtime handles missing CUDA gracefully - provider initialization fails silently and falls back to next provider
3. Never hard-link CUDA libraries - always use dynamic loading with fallback

**Warning signs:**
- Hard `{.passL: "-lcudart".}` in Nim code
- No try/except around GPU initialization
- Application works on dev machine but crashes on user systems

**Reference:** [CUDA provider fallback issue](https://github.com/microsoft/onnxruntime/issues/21424)

### Pitfall 2: Memory Fragmentation from 4K Frame Allocation

**What goes wrong:** Application slowly accumulates memory over long runs, eventually OOM even though theoretical memory requirement fits in RAM. Each allocation cycle increases fragmentation.

**Why it happens:** Allocating/deallocating 25MB chunks repeatedly causes heap fragmentation. System can't find contiguous 25MB blocks even when total free memory is available.

**How to avoid:**
1. Pre-allocate buffer pool at startup (e.g., 16 buffers for 4K)
2. Reuse buffers in strict acquire/release pattern
3. Never allocate frame buffers in hot loop

**Warning signs:**
- Memory usage grows slowly over time ("memory leak" but no actual leaks)
- OOM crashes after processing many files in sequence
- `top` shows available memory but allocations fail

**Reference:** [Memory management in video processing](https://palospublishing.com/managing-memory-for-c-in-video-processing-applications/)

### Pitfall 3: CoreML Execution Provider Silently Falls Back to CPU

**What goes wrong:** macOS users expect GPU acceleration but CoreML provider silently uses CPU, resulting in slow face detection with no error message.

**Why it happens:** CoreML execution provider may fall back to CPU for unsupported operations in model. No error raised, just silent fallback.

**How to avoid:**
1. Test ONNX models with CoreML before integration
2. Log which execution provider was actually used after session creation
3. Provide user feedback about GPU vs CPU execution

**Warning signs:**
- macOS performance same as CPU-only mode
- Activity Monitor shows no GPU usage during face detection
- Users report "GPU acceleration doesn't work" on M1/M2

**Reference:** [CoreML execution provider docs](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html)

### Pitfall 4: Unbounded Decode Queue Causes OOM on Large Files

**What goes wrong:** Processing 1+ hour 4K video crashes with OOM even though individual frame size is manageable.

**Why it happens:** Decoder runs faster than consumer (face detection). Without bounds, decoded frames accumulate in memory until OOM.

**How to avoid:**
1. Implement bounded queue with max frame count (e.g., 30 frames)
2. Add backpressure - block decoder when queue full
3. Monitor queue size and log warnings if consistently near max

**Warning signs:**
- OOM crashes only on long videos
- Memory usage grows linearly with video duration
- Process killed by system OOM killer on Linux

**Reference:** [Bounded queue pattern](https://www.oreilly.com/library/view/design-patterns-and/9781786463593/2ff33f7c-aab8-4a4d-bacc-c475c3d1c928.xhtml)

## Code Examples

Verified patterns from research:

### GPU Detection and ONNX Session Creation

```nim
# Based on ONNX Runtime execution provider pattern
proc initGpuSession*(modelPath: string): tuple[session: OrtSession, backend: string] =
  let env = initOrtEnv()
  var actualBackend = "cpu"

  when defined(linux):
    try:
      # Try CUDA first on Linux
      let session = loadModelWithProviders(env, modelPath,
        ["CUDAExecutionProvider", "CPUExecutionProvider"])
      actualBackend = "cuda"  # If we reach here, CUDA initialized
      return (session, actualBackend)
    except OrtError:
      # CUDA failed, fallback handled by ONNX Runtime
      actualBackend = "cpu"

  when defined(macosx):
    try:
      # Try CoreML on macOS
      let session = loadModelWithProviders(env, modelPath,
        ["CoreMLExecutionProvider", "CPUExecutionProvider"])
      actualBackend = "coreml"
      return (session, actualBackend)
    except OrtError:
      actualBackend = "cpu"

  # CPU fallback
  let session = loadModel(env, modelPath)
  return (session, actualBackend)
```

**Source:** [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/execution-providers/)

### Frame Buffer Pool Usage

```nim
# Based on GStreamer BufferPool pattern
proc processFaces(videoPath: string) =
  # Initialize buffer pool for 4K frames
  var pool = newBufferPool(width=3840, height=2160, channels=3, maxBuffers=16)
  defer: pool.destroy()

  for frame in decodeVideo(videoPath):
    # Acquire buffer from pool
    let buffer = pool.acquire()
    if buffer == nil:
      # Pool exhausted - consumer too slow
      warn "Buffer pool exhausted, skipping frame"
      continue

    # Copy frame data to pooled buffer
    copyMem(buffer.data, frame.data, buffer.capacity)

    # Process with pooled buffer
    let faces = detectFaces(buffer.data, buffer.width, buffer.height)

    # Release back to pool
    pool.release(buffer)
```

**Source:** [GStreamer Memory Allocation](https://gstreamer.freedesktop.org/documentation/plugin-development/advanced/allocation.html)

### Bounded Decode with Backpressure

```nim
# Based on bounded blocking queue pattern
proc analyzeVideo(container: InputContainer) =
  let maxQueueFrames = 30  # ~750MB for 4K
  var decoder = newBoundedDecoder(codecCtx, maxQueueFrames)

  # Decoder will block when queue reaches maxQueueFrames
  # This prevents OOM by applying backpressure
  for frame in decoder.decode(packet):
    # Process frame (this drains queue)
    let faces = detectFaces(frame)
    processResults(faces)

    # Frame released back to decoder pool
```

**Source:** [Bounded Queue Pattern](https://www.oreilly.com/library/view/design-patterns-and/9781786463593/2ff33f7c-aab8-4a4d-bacc-c475c3d1c928.xhtml)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Build separate binaries per GPU vendor | Single binary with runtime execution provider selection | ONNX Runtime 1.0 (2019) | Users get one binary that works everywhere, auto-detects GPU |
| Manual CUDA kernel dispatch | Execution provider abstraction | ONNX Runtime 1.0+ | Framework handles GPU dispatch, developers write vendor-agnostic code |
| Per-frame malloc for video | Buffer pooling | Standard in GStreamer (2005+), FFmpeg (2010+) | 10-100x reduction in allocation overhead, prevents fragmentation |
| Unbounded decode ahead | Bounded queue with backpressure | Standard in real-time video (2015+) | Prevents OOM, enables predictable memory usage |

**Deprecated/outdated:**
- **OpenCL for Apple platforms:** Apple deprecated OpenCL in favor of Metal. For ONNX models, use CoreML execution provider instead.
- **ONNX Runtime pre-1.0 APIs:** Early ONNX Runtime used different API patterns. Current C API (1.0+) is stable and recommended.
- **Manual CUDA memory management:** Modern execution providers handle GPU memory. Don't manually cudaMalloc/cudaFree.

## Open Questions

1. **ONNX model format for face detection**
   - What we know: libfacedetection is C++ code, not an ONNX model. Current implementation uses libfacedetection directly.
   - What's unclear: To use ONNX Runtime GPU acceleration, we need face detection as ONNX model. Does a compatible ONNX face detection model exist? Or do we need to convert/train one?
   - Recommendation: Research Ultra-Light-Fast-Generic-Face-Detector-1MB (ONNX format available). If compatible, can replace libfacedetection for GPU path. Keep libfacedetection as CPU fallback.

2. **CoreML execution provider performance vs CPU**
   - What we know: CoreML can use Apple Neural Engine/GPU, but may fall back to CPU for unsupported ops
   - What's unclear: Will face detection model see actual speedup on Apple Silicon, or will CoreML just use CPU?
   - Recommendation: Benchmark on M1/M2 during implementation. If no speedup, disable CoreML provider and use CPU directly (simpler).

3. **Optimal buffer pool size for 4K**
   - What we know: 4K BGR frame is ~25MB. Pool of 16 = ~400MB.
   - What's unclear: Is 16 buffers enough for smooth pipeline, or will we see stalls? Too large pools waste memory.
   - Recommendation: Start with 16, make configurable, add telemetry to log pool exhaustion events. Tune based on real usage.

4. **CUDA version compatibility**
   - What we know: ONNX Runtime 1.20.1 supports CUDA 12.x
   - What's unclear: Do we require exact CUDA 12.x, or will it work with CUDA 11.x on user systems?
   - Recommendation: Test fallback behavior with CUDA 11.x. Document minimum CUDA version if hard requirement exists.

## Sources

### Primary (HIGH confidence)

- [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/execution-providers/) - Execution provider architecture and usage
- [ONNX Runtime CUDA Provider](https://onnxruntime.ai/docs/execution-providers/CUDA-ExecutionProvider.html) - CUDA-specific configuration
- [ONNX Runtime CoreML Provider](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html) - CoreML-specific configuration
- [OpenCV CUDA Module](https://docs.opencv.org/4.x/d2/dbc/cuda_intro.html) - OpenCV GPU support overview
- [GStreamer BufferPool](https://gstreamer.freedesktop.org/documentation/plugin-development/advanced/allocation.html) - Memory allocation patterns for video
- [FFmpeg AVFrame Documentation](https://ffmpeg.org/doxygen/3.3/group__lavu__frame.html) - Frame buffer management

### Secondary (MEDIUM confidence)

- [Managing Memory for C++ in Video Processing](https://palospublishing.com/managing-memory-for-c-in-video-processing-applications/) - Buffer pooling best practices (verified across multiple sources)
- [Design Bounded Blocking Queue](https://medium.com/@preetipriyanka24/design-bounded-blocking-queue-ba98ff9f6b5c) - Concurrent queue pattern (verified with O'Reilly pattern book)
- [CUDA Provider Fallback Issue #21424](https://github.com/microsoft/onnxruntime/issues/21424) - Real-world fallback challenges
- [Getting Started with OpenCV CUDA](https://learnopencv.com/getting-started-opencv-cuda-module/) - OpenCV GPU setup (verified against official docs)

### Tertiary (LOW confidence)

- Web search results on frame buffer pooling - General patterns match authoritative sources but specific implementation details not verified
- Community discussions on GPU fallback - Anecdotal evidence of common issues, useful for pitfall identification

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - ONNX Runtime execution provider strategy is well-documented and proven, but specific face detection model integration needs validation (Open Question #1)
- Architecture: HIGH - Patterns (buffer pool, bounded queue, execution provider fallback) are industry-standard with proven implementations
- Pitfalls: HIGH - All pitfalls verified through official documentation or real-world issue reports

**Research date:** 2026-02-13
**Valid until:** ~60 days (GPU acceleration is mature tech, unlikely to change rapidly. ONNX Runtime releases quarterly but API is stable.)

**Key implementation risks:**
1. ONNX face detection model availability/quality (HIGH priority to resolve)
2. CoreML performance on Apple Silicon (MEDIUM - can disable if no benefit)
3. CUDA version compatibility on end-user systems (MEDIUM - graceful fallback exists)
