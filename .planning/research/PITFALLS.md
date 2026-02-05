# Domain Pitfalls: Adding Workflow & Performance Features

**Domain:** Video processing CLI (batch, GPU, 4K, chapter detection)
**Project:** honeyclip v1.2
**Researched:** 2026-02-05

## Critical Pitfalls

Mistakes that cause rewrites, major performance degradation, or system instability.

### Pitfall 1: GPU Memory Round-Trip During Hardware Acceleration

**What goes wrong:** When using FFmpeg GPU acceleration for decode-filter-encode pipelines, frames are copied from GPU to system RAM after decode, then copied back to GPU for filtering/encoding. This creates PCIe bandwidth saturation and defeats the purpose of GPU acceleration.

**Why it happens:** Missing the `-hwaccel_output_format cuda` (NVIDIA) or platform-specific equivalent flag causes FFmpeg to implicitly perform hardware-to-software transfer (hwdownload) after decoding. This is not documented prominently and seems optional.

**Consequences:**
- Up to 2x throughput degradation compared to optimized GPU pipeline
- PCIe bandwidth becomes the bottleneck, not decode/encode speed
- System memory pressure from uncompressed frame buffers
- No performance benefit from GPU acceleration despite using hwaccel

**Prevention:**
```nim
# BAD: Decoded frames copied to system RAM
ffmpeg -hwaccel cuda -i input.mp4 ...

# GOOD: Frames stay in GPU memory
ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i input.mp4 ...
```

For platform-specific implementations:
- **NVIDIA CUDA:** `-hwaccel cuda -hwaccel_output_format cuda`
- **AMD (DX9):** `-hwaccel_output_format dxva2_vld`
- **AMD (DX11):** `-hwaccel_output_format d3d11`
- **macOS VideoToolbox:** `-hwaccel videotoolbox` (no explicit output format needed, but verify with `-init_hw_device videotoolbox`)

**Detection:**
- Monitor PCIe bandwidth during processing (expect minimal if GPU-only)
- Check system memory usage (should not spike with uncompressed frames)
- Profile with `nvidia-smi` (CUDA) or Activity Monitor (macOS) - GPU memory should hold decoded frames
- Throughput significantly below expected GPU performance

**Prevention strategy:**
1. **Phase: GPU Acceleration Basics** - Document platform-specific hwaccel flags in architecture decision record
2. Verify GPU-resident pipeline with profiling before implementing filters
3. Create unit test that checks memory transfer patterns with ffprobe
4. Add compile-time validation that FFmpeg was built with correct hwaccel support

**Sources:**
- [NVIDIA FFmpeg Transcoding Guide](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/ffmpeg-with-nvidia-gpu/index.html)
- [FFmpeg AMF HW Acceleration](https://github.com/GPUOpen-LibrariesAndSDKs/AMF/wiki/FFmpeg-and-AMF-HW-Acceleration)
- [Using FFmpeg with NVIDIA GPU Acceleration](https://developer.nvidia.com/blog/nvidia-ffmpeg-transcoding-guide/)

---

### Pitfall 2: Thread Count Misconfiguration for Hybrid CPU/GPU Workloads

**What goes wrong:** Using default thread count (all CPU cores) while also running GPU-accelerated encoding causes context-switching overhead, cache thrashing, and CPU starvation for critical system tasks. Conversely, using too few threads for CPU-only fallback paths severely degrades performance.

**Why it happens:**
- FFmpeg defaults to `thread_count = 0` (auto-detect all cores)
- GPU encoding only uses 15-20% CPU, but FFmpeg still allocates full thread pool
- Higher thread counts (>8) create transient quality issues in encoders
- Developers assume "more threads = better performance" without profiling

**Consequences:**
- CPU saturation at 100% while GPU sits at 20% utilization (wasted resources)
- System becomes unresponsive during batch processing
- 30-50% performance loss from cache thrashing
- Quality degradation in encoded output (transient artifacts)
- macOS/Windows systems starve UI thread, causing beachballs/hangs

**Prevention:**
```nim
# Current honeyclip decoder setup (src/av.nim:53)
result.thread_count = 0  # Auto-detect CPU cores

# BETTER: Dynamic thread allocation based on GPU availability
when defined(enable_cuda) or defined(macosx):  # GPU-accelerated platforms
  result.thread_count = min(4, countProcessors())  # Limit to 4 threads
else:  # CPU-only fallback
  result.thread_count = 0  # Use all available cores
```

**Production recommendations from research:**
- **GPU encode:** 4-8 threads maximum (research shows higher counts hurt quality)
- **CPU-only encode:** 1 thread per encode instance for best quality/throughput balance
- **4K content:** Scales efficiently to 8-16 threads only on CPU-only path
- **Batch processing:** Reserve 1-2 cores for system tasks (don't use all cores)

**Detection:**
- CPU usage at 100% with low GPU utilization (imbalanced workload)
- System becomes unresponsive during processing
- Encoding quality issues (visible artifacts in output)
- FFmpeg progress output shows thread contention (decode stalls)

**Prevention strategy:**
1. **Phase: GPU Acceleration Basics** - Add runtime thread count selection based on hwaccel availability
2. Add CLI flag `--threads` for override (default to smart detection)
3. Create benchmark suite comparing thread counts (2, 4, 8, 16) with quality metrics
4. Document thread recommendations in ARCHITECTURE.md per resolution/platform
5. Monitor CPU/GPU utilization during integration tests

**Integration with honeyclip:**
- Modify `initDecoder()` in `src/av.nim` to accept thread configuration
- Add thread policy to MediaInfo struct to persist per-file decisions
- Batch processor must share thread policy across files to prevent over-subscription

**Sources:**
- [FFmpeg Threads Command Performance](https://streaminglearningcenter.com/blogs/ffmpeg-command-threads-how-it-affects-quality-and-performance.html)
- [How Thread Count Impacts Quality and Cost](https://streaminglearningcenter.com/encoding/how-thread-count-impacts-video-encoding-quality-throughput-and-cost.html)
- [FFmpeg 7.1 multi-threading](https://www.phoronix.com/news/FFmpeg-CLI-Multi-Threaded)
- [Multi-Threaded GPU Encoding Guide](https://hostkey.com/blog/12-multi-threaded-video-encoding-on-a-professional-gpu/)

---

### Pitfall 3: 4K Frame Buffer Accumulation Without Backpressure

**What goes wrong:** Decode queue fills faster than filter/encode queue can drain. With 4K content, each uncompressed frame is 32MB (3840x2160 RGBA). A queue of 30 frames = 960MB. Multiple concurrent files = multi-GB memory spike leading to OOM kills.

**Why it happens:**
- FFmpeg's `av_read_frame()` continuously populates packet queue
- No built-in backpressure mechanism between decode and encode stages
- Nim's GC doesn't track C-allocated frame buffers (allocated via `av_frame_alloc()`)
- Developers focus on throughput, not memory ceiling
- 4K content increases frame buffer size 4x vs 1080p (8MB → 32MB per frame)

**Consequences:**
- Out-of-memory (OOM) killer terminates process mid-batch
- Swap storm on systems with insufficient RAM (10x slowdown)
- Partial output files with no checkpoint/resume capability
- Silent failure on GPU memory allocation (CUDA OOM)
- macOS memory pressure causes system-wide slowdown

**Prevention:**
```nim
# BAD: Unbounded decode queue
while av_read_frame(formatCtx, packet) >= 0:
  decodePacket(packet)
  av_packet_unref(packet)

# GOOD: Bounded queue with backpressure
const MaxQueuedFrames = 8  # Limit based on resolution
var queuedFrames = 0

while av_read_frame(formatCtx, packet) >= 0:
  # Block if encode queue is full
  while queuedFrames >= MaxQueuedFrames:
    if not tryDrainEncodeQueue():
      sleep(10)  # Yield to encoder thread

  decodePacket(packet)
  queuedFrames.inc
  av_packet_unref(packet)
```

**Queue size recommendations:**
- **1080p:** 16 frames max (128MB)
- **4K:** 8 frames max (256MB)
- **8K:** 4 frames max (256MB)
- **Batch processing:** Divide limits by concurrent file count

**Detection:**
- Memory usage spikes then crashes (OOM)
- System swap usage increases during processing
- GPU memory allocation failures (CUDA error 2: "out of memory")
- Processing slows down before crash (swap storm)
- `dmesg` shows OOM killer events (Linux)

**Prevention strategy:**
1. **Phase: 4K Memory Optimization** - Implement bounded frame queue with configurable depth
2. Add memory pressure monitoring (check available RAM before decode)
3. Dynamic queue sizing based on frame dimensions: `queueDepth = min(16, 256MB / frameSize)`
4. Use `av_frame_unref()` immediately after consuming frame (don't hold references)
5. Test with `ulimit -v` (Linux) to simulate memory constraints

**Integration with honeyclip:**
- Current `InputContainer` (src/av.nim) reads packets synchronously (good!)
- Batch processor must enforce memory budget across all concurrent files
- Add `MemoryBudget` type with current usage tracking
- Preview generation (`src/render/previews.nim`) likely needs explicit limits

**Platform-specific considerations:**
- **Linux:** OOM killer has no grace period - hard kill
- **macOS:** Memory pressure subsystem throttles allocations (slower but survives)
- **Windows:** Virtual memory manager similar to Linux but more forgiving
- **CUDA:** GPU OOM is immediate hard failure (no recovery)

**Sources:**
- [OpenClaw CUDA OOM Errors](https://openclaw-ai.org/guides/fix-openclaw-cuda-oom-errors)
- [ComfyUI VRAM Memory Management](https://github.com/RandomInternetPreson/ComfyUI_LTX-2_VRAM_Memory_Management)
- [Low-VRAM GPU Optimization](https://medium.com/the-ai-mindscape/optimizing-gpu-usage-on-low-vram-machines-6-practical-steps-to-dodge-oom-errors-2957c779f3e0)
- [Linux Kernel Stateless Decoder Buffer Management](https://docs.kernel.org/userspace-api/media/v4l/dev-stateless-decoder.html)

---

### Pitfall 4: Batch Processing Without Checkpoint/Resume Capability

**What goes wrong:** Multi-hour batch jobs fail midway through (OOM, power loss, disk full, Ctrl+C). Without checkpointing, the entire batch must restart from file 1, wasting hours of compute and potentially missing deadlines.

**Why it happens:**
- Developers implement batch as simple loop over files
- State (which files completed) only exists in memory
- No interrupt signal handlers
- Assumption that jobs will always complete successfully
- Focus on happy path, not failure recovery

**Consequences:**
- 100-file batch at 30min/file = 50 hours wasted on failure at file 99
- User frustration ("I had 5% left and it crashed!")
- Resource waste (re-processing already completed files)
- Production pipelines become unreliable
- Manual tracking of completion becomes error-prone

**Prevention:**
```nim
# Checkpoint file format (.honeyclip-batch-state.json)
type BatchCheckpoint = object
  batchId: string            # Hash of input file list
  startTime: DateTime
  completedFiles: seq[string]  # Absolute paths
  failedFiles: Table[string, string]  # path -> error message
  totalFiles: int

proc processBatch(files: seq[string], outputDir: string) =
  let checkpointPath = outputDir / ".honeyclip-batch-state.json"
  var checkpoint = loadOrCreateCheckpoint(checkpointPath, files)

  # Install signal handler for graceful shutdown
  setControlCHook(proc() {.noconv.} =
    checkpoint.save(checkpointPath)
    quit(130)  # Exit code 130 = interrupted
  )

  for file in files:
    if file in checkpoint.completedFiles:
      echo &"Skipping {file} (already completed)"
      continue

    try:
      processFile(file, outputDir)
      checkpoint.completedFiles.add(file)
      checkpoint.save(checkpointPath)  # Checkpoint after each file
    except CatchableError as e:
      checkpoint.failedFiles[file] = e.msg
      checkpoint.save(checkpointPath)
      # Continue to next file (don't abort entire batch)

  # Clean up checkpoint on successful completion
  if checkpoint.failedFiles.len == 0:
    removeFile(checkpointPath)
```

**Resume behavior:**
```bash
# Initial run (interrupted at file 50/100)
$ honeyclip batch *.mp4 --out rendered/
Processing: file001.mp4... OK
Processing: file002.mp4... OK
...
Processing: file050.mp4... ^C (user interrupted)

# Resume run (skips files 1-50)
$ honeyclip batch *.mp4 --out rendered/
Found existing batch checkpoint (50/100 completed)
Skipping: file001.mp4 (already completed)
...
Skipping: file050.mp4 (already completed)
Processing: file051.mp4... OK
```

**Detection:**
- Users report re-processing files after interruption
- Complaints about long-running jobs not being resumable
- Feature requests for "resume from where it left off"
- Support tickets about wasted compute time

**Prevention strategy:**
1. **Phase: Batch Processing Core** - Design checkpoint schema before implementing batch loop
2. Save checkpoint after EACH file completes (not at end of batch)
3. Include batch ID (hash of input files) to detect changed inputs
4. Store both completed and failed files (don't retry failures without user action)
5. Provide `--force-reprocess` flag to ignore checkpoint
6. Add `--resume` flag that errors if no checkpoint found (explicit user intent)

**Integration with honeyclip:**
- Batch command doesn't exist yet (new feature for v1.2)
- Checkpoint format should match export formats (src/exports/) for consistency
- Use JSON for checkpoint (human-readable, editable if needed)
- Store in output directory (not input directory - may be read-only)
- Consider XDG cache directory for ephemeral state ($XDG_CACHE_HOME/honeyclip/)

**Edge cases to handle:**
- Input file list changes between runs (detect via batch ID hash)
- Output directory deleted/moved (checkpoint references missing files)
- Partial file output (file completed in checkpoint but output missing - corrupted?)
- Multiple concurrent batch jobs (use unique checkpoint names)

**Sources:**
- [HTCondor Checkpointing Jobs](https://chtc.cs.wisc.edu/uw-research-computing/checkpointing)
- [Northeastern NURC Checkpointing](https://rc-docs.northeastern.edu/en/explorer-main/best-practices/checkpointing.html)
- [AWS SageMaker Checkpoints](https://docs.aws.amazon.com/sagemaker/latest/dg/model-checkpoints.html)
- [Batch Error Handling](https://oneuptime.com/blog/post/2026-01-30-batch-processing-error-handling/view)

---

### Pitfall 5: Chapter Detection Confidence Without Speaker Diarization

**What goes wrong:** Transcript-based chapter detection creates boundaries based on topic changes alone. Without speaker diarization, chapters split mid-conversation when topic changes occur naturally in dialogue. Result: 50+ micro-chapters instead of 8-10 meaningful segments.

**Why it happens:**
- Whisper provides high-quality transcription (7.75% WER on mixed audio) but no speaker labels
- Developers use LLM or rule-based topic detection on raw transcript
- Topic shifts during conversation appear as new chapters
- No distinction between "speaker changed topics" vs "new speaker introduced new topic"
- Assumption that sentence boundaries = chapter boundaries

**Consequences:**
- Chapter count explosion (90-minute video → 60 chapters instead of 8)
- Chapters split mid-sentence during topic pivots
- Poor user experience (chapters are navigation tool, not sentence index)
- False confidence in chapter accuracy (algorithm thinks it's correct)
- Manual post-processing required to merge micro-chapters

**Example failure case:**
```
[0:00-2:30] Host: "Today we'll discuss React hooks..."  [Chapter: Intro]
[2:30-5:00] Host: "But first, let's talk about the history of React..."  [NEW CHAPTER: History?]
[5:00-8:00] Host: "...which brings us back to hooks."  [NEW CHAPTER: Hooks again?]
```

Without speaker diarization, the algorithm sees three topic transitions. With diarization, it recognizes continuous speech by same speaker = single chapter.

**Prevention:**
```nim
# BAD: Topic detection alone
proc detectChapters(transcript: Transcript): seq[Chapter] =
  let topicBoundaries = detectTopicChanges(transcript)  # Sentence-level
  return topicBoundaries.map(b => Chapter(start: b.time))

# BETTER: Speaker-aware chapter detection
proc detectChapters(transcript: Transcript, diarization: Diarization): seq[Chapter] =
  # Merge speaker diarization with transcript
  let annotatedTranscript = mergeWithSpeakers(transcript, diarization)

  # Only create chapter boundaries when:
  # 1. Speaker changes AND topic changes, OR
  # 2. Same speaker but long silence (>3s) AND topic shift
  var chapters: seq[Chapter]
  for i, segment in annotatedTranscript:
    let speakerChanged = (i > 0 and segment.speaker != annotatedTranscript[i-1].speaker)
    let topicChanged = detectTopicChange(segment, annotatedTranscript[i-1])
    let longPause = segment.silence > 3.0

    if (speakerChanged and topicChanged) or (longPause and topicChanged):
      chapters.add(Chapter(start: segment.time, title: segment.topic))

  return chapters
```

**Speaker diarization integration:**
- Whisper.cpp added experimental support via `tinydiarize` (2026)
- WhisperX provides production-ready diarization pipeline
- Falcon Speaker Diarization works offline with whisper.cpp

**Detection:**
- Chapter count significantly exceeds expected (>20 chapters for 60min video)
- User feedback: "chapters are too granular"
- Chapter duration variance is high (some 30s, some 10min)
- Chapters split during monologues (should be single chapter)

**Prevention strategy:**
1. **Phase: Chapter Detection** - Implement speaker diarization BEFORE chapter detection algorithm
2. Test on multi-speaker content (podcast, interview) not just monologues
3. Validate chapter count against duration heuristic (90min video should have 6-12 chapters)
4. Add confidence scores to chapters (low confidence = merge candidate)
5. Provide `--min-chapter-duration` flag (default 2 minutes)
6. Log chapter count and duration distribution for validation

**Integration with honeyclip:**
- Existing transcript support (`src/transcript/`) provides foundation
- Speaker diarization belongs in `src/transcript/diarization.nim` (already exists!)
- Chapter detection should be new `src/chapters/` module
- whisper.cpp integration (`src/cmds/whisper.nim`) must output speaker labels

**Quality gates:**
- Monologue (1 speaker): Max 1 chapter per 5-10 minutes
- Dialogue (2 speakers): Chapters aligned with speaker turns + topic
- Multi-speaker (3+ speakers): Chapters when new speaker joins or leaves

**Sources:**
- [Auphonic Automatic Chapters](https://auphonic.com/help/algorithms/speech_recognition.html)
- [WhisperX Transcription Pipeline](https://vogla.com/whisperx-transcription-pipeline-guide/)
- [Whisper.cpp Speaker Diarization](https://picovoice.ai/blog/whisper-cpp-speaker-diarization/)
- [WhisperX GitHub](https://github.com/m-bain/whisperX)

---

## Moderate Pitfalls

Mistakes that cause delays, technical debt, or performance degradation (but recoverable).

### Pitfall 6: macOS VideoToolbox Assuming Metal Availability

**What goes wrong:** Code assumes all macOS systems support Metal-accelerated VideoToolbox. Older Macs (pre-2017) or macOS VMs don't have Metal, causing hard crashes when attempting hardware acceleration.

**Why it happens:**
- Documentation says "VideoToolbox on macOS 10.8+" without mentioning Metal requirement
- Metal is required for full VideoToolbox acceleration (tone-mapping, advanced filters)
- Developers test on modern MacBooks (all have Metal) not older hardware
- FFmpeg doesn't gracefully fallback when Metal is unavailable

**Prevention:**
```nim
when defined(macosx):
  proc hasMetalSupport(): bool =
    # Check if Metal framework is available
    let (output, exitCode) = gorgeEx("system_profiler SPDisplaysDataType | grep -i metal")
    return exitCode == 0 and "Metal" in output

  proc initHwAccel(): HwAccelConfig =
    if hasMetalSupport():
      result.method = HwAccelMethod.VideoToolbox
      result.tonemap = ToneMapMethod.Metal
    else:
      # Fallback to CPU or VideoToolbox without tone-mapping
      result.method = HwAccelMethod.VideoToolboxLegacy
      result.tonemap = ToneMapMethod.None
```

**Detection:**
- Crash with "Metal device not found" on older Macs
- FFmpeg error "Cannot initialize videotoolbox" on macOS VMs
- Feature requests from users on older hardware

**Prevention strategy:**
1. **Phase: GPU Acceleration Basics** - Add runtime Metal detection before enabling VideoToolbox
2. Test on macOS VM (no Metal) and 2011-2016 Macs
3. Provide clear error message if Metal required but unavailable
4. Document minimum macOS hardware requirements (2017+ for full features)

**Sources:**
- [Jellyfin Apple Hardware Acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/apple/)
- [FFmpeg Apple Silicon Hardware Acceleration](https://codetv.dev/blog/hardware-acceleration-ffmpeg-apple-silicon)

---

### Pitfall 7: Batch Processing Error Cascade Without Isolation

**What goes wrong:** Batch processor shares state (cache, temp files, database connections) across files. One corrupted file causes state corruption that affects all subsequent files. Batch continues processing but produces invalid outputs silently.

**Why it happens:**
- Performance optimization: reuse cache/connections across files
- Insufficient error isolation between batch items
- Global state instead of per-file state
- Error handling at batch level, not file level

**Prevention:**
```nim
proc processBatch(files: seq[string]) =
  for file in files:
    # Isolate each file in try-finally block
    try:
      var fileCtx = createFileContext(file)  # Fresh state per file
      defer: fileCtx.cleanup()  # Always cleanup

      processFile(fileCtx)
    except CatchableError as e:
      # Log error, continue to next file
      logError(&"Failed to process {file}: {e.msg}")
      continue  # Don't abort batch
```

**Prevention strategy:**
1. **Phase: Batch Processing Core** - Design for isolation-first (optimize later)
2. Use per-file context objects (no shared global state)
3. Cleanup resources in `defer` blocks (ensures cleanup even on exception)
4. Test with mixed valid/corrupted files to verify isolation

**Sources:**
- [MuleSoft Batch Error Handling](https://mulesy.com/error-handling-in-batch-job/)
- [Azure Batch Error Handling](https://learn.microsoft.com/en-us/azure/batch/error-handling)

---

### Pitfall 8: Nim GC Not Tracking C-Allocated Frame Buffers

**What goes wrong:** FFmpeg frames allocated with `av_frame_alloc()` are not visible to Nim's GC. Even with `GC_ref()` calls, the GC doesn't know about the large frame data buffers, leading to memory bloat and eventual OOM.

**Why it happens:**
- `GC_ref()` only prevents GC of Nim wrapper object, not C data
- Frame data buffer (32MB for 4K) is allocated by C code
- Nim GC sees small 200-byte `AVFrame` struct, not 32MB buffer
- Manual memory management required but often forgotten

**Prevention:**
```nim
type FrameWrapper = ref object
  frame: ptr AVFrame
  size: int  # Track buffer size for GC hints

proc allocFrame(width, height: int): FrameWrapper =
  result = FrameWrapper()
  result.frame = av_frame_alloc()
  result.size = width * height * 4  # RGBA estimate

  # Hint to GC about external memory
  when defined(gcDestructors):
    GC_addCycleRoot(cast[pointer](result))
  else:
    GC_ref(result)
    # Register external memory with GC
    GC_setMaxPause(10)  # Force more frequent collection

proc freeFrame(fw: FrameWrapper) =
  if fw.frame != nil:
    av_frame_free(addr fw.frame)
    when not defined(gcDestructors):
      GC_unref(fw)
```

**Better approach: Use --gc:arc or --gc:orc:**
```nim
# With ARC/ORC, use destructors instead of manual GC_ref/unref
type FrameWrapper = object
  frame: ptr AVFrame

proc `=destroy`(fw: var FrameWrapper) =
  if fw.frame != nil:
    av_frame_free(addr fw.frame)

proc allocFrame(): FrameWrapper =
  result.frame = av_frame_alloc()
  # No GC_ref needed - destructor handles cleanup
```

**Detection:**
- Memory usage climbs without GC collecting
- `av_frame_free()` called but memory not released
- Process RSS continues growing despite cleanup code

**Prevention strategy:**
1. **Phase: 4K Memory Optimization** - Switch to --gc:arc/orc for deterministic cleanup
2. Wrap all FFmpeg objects in ref types with destructors
3. Test with memory profiler (Valgrind, Instruments, heaptrack)
4. Add memory usage assertions in tests

**Integration with honeyclip:**
- Current code uses default GC (refc)
- Good pattern: `defer: avcodec_free_context(addr codecCtx)` in media.nim
- Should apply same pattern to all AVFrame allocations
- Consider --gc:orc migration for v1.2 (better for multimedia workloads)

**Sources:**
- [Nim refc Documentation](https://nim-lang.github.io/Nim/refc.html)
- [Nim Destructors](https://nim-lang.org/araq/destructors.html)

---

### Pitfall 9: Preview Generation Creates Memory Pressure in Batch Mode

**What goes wrong:** Generating previews for batch processing keeps decoded frames in memory for thumbnail extraction. With 100 videos × 10 thumbnails × 32MB/frame = 32GB memory usage spike.

**Why it happens:**
- Preview extraction seeks to specific timestamps, decodes frame, keeps in memory
- Batch mode generates all previews before starting encode
- No streaming preview generation (decode → thumbnail → discard)

**Prevention:**
```nim
# BAD: Load all preview frames first
var previewFrames: seq[ptr AVFrame]
for timestamp in previewTimestamps:
  previewFrames.add(seekAndDecode(timestamp))
generateThumbnails(previewFrames)

# GOOD: Streaming preview generation
for timestamp in previewTimestamps:
  let frame = seekAndDecode(timestamp)
  generateThumbnail(frame, outputPath)
  av_frame_free(addr frame)  # Immediate cleanup
```

**Prevention strategy:**
1. **Phase: Preview Generation** - Design for streaming (one frame at a time)
2. Limit max concurrent preview extractions in batch mode
3. Add `--preview-quality` flag (lower resolution = less memory)
4. Consider preview cache with LRU eviction

---

### Pitfall 10: FFmpeg 7.x Parallel Pipeline Without Resource Limits

**What goes wrong:** FFmpeg 7.x introduced parallel demux-decode-filter-encode-mux pipeline. Without resource limits, each file in batch mode spawns full pipeline, leading to thread explosion and memory exhaustion.

**Why it happens:**
- FFmpeg 7.x "most complex refactoring in decades" changed execution model
- Each stage (demux, decode, filter, encode, mux) now runs in parallel
- Multiple files × 5 stages × thread pool = hundreds of threads
- No automatic resource scaling based on concurrent operations

**Prevention:**
```nim
# Configure FFmpeg 7.x pipeline limits
proc configurePipeline(fileCount: int): FFmpegConfig =
  # Reserve resources per concurrent file
  let threadsPerFile = max(1, totalCores div fileCount)

  result.threads = threadsPerFile
  result.filterThreads = max(1, threadsPerFile div 2)
  result.decodingThreads = threadsPerFile

  # Limit pipeline depth
  result.maxQueuedFrames = if fileCount > 1: 4 else: 8
```

**Detection:**
- Thread count exceeds CPU cores × 2 (check with `ps` or `top`)
- Context switch rate very high (thousands per second)
- CPU usage paradoxically drops during heavy load (thrashing)

**Prevention strategy:**
1. **Phase: Batch Processing Core** - Calculate per-file resource budget
2. Test with FFmpeg 7.x CLI flags for pipeline tuning
3. Monitor thread count during batch processing
4. Add `--max-parallel` flag for user control

**Sources:**
- [FFmpeg CLI Multi-Threading](https://news.ycombinator.com/item?id=38613219)
- [FFmpeg Patches Multi-Threaded CLI](https://www.phoronix.com/news/FFmpeg-CLI-Multi-Threaded)

---

## Minor Pitfalls

Mistakes that cause annoyance but are fixable without major refactoring.

### Pitfall 11: Chapter Title Generation Without Context Window

**What goes wrong:** LLM-based chapter title generation processes each chapter boundary in isolation. Without surrounding context, titles are generic ("Discussion continues", "More on topic X").

**Prevention:**
```nim
# BAD: Single segment
generateTitle(transcript[chapterStart..chapterEnd])

# GOOD: Include context
let contextBefore = transcript[max(0, chapterStart-50)..chapterStart]
let contextAfter = transcript[chapterEnd..min(len(transcript), chapterEnd+50)]
generateTitle(contextBefore, transcript[chapterStart..chapterEnd], contextAfter)
```

**Prevention strategy:**
1. **Phase: Chapter Detection** - Include 30-60 seconds before/after for context
2. Validate titles aren't generic (check against blacklist: "continues", "more on")
3. Provide fallback to timestamp-based titles if generation fails

---

### Pitfall 12: GPU Model Selection Without Capability Detection

**What goes wrong:** Code assumes all NVIDIA GPUs support same features. Older GPUs (Pascal, Maxwell) lack INT8 support, newer encoders (AV1), or tensor cores, causing initialization failures.

**Prevention:**
```nim
when defined(enable_cuda):
  proc detectGpuCapabilities(): GpuCapabilities =
    let (output, _) = gorgeEx("nvidia-smi --query-gpu=compute_cap --format=csv,noheader")
    let computeCapability = parseFloat(output.strip())

    result.supportsTensorCores = computeCapability >= 7.0  # Volta+
    result.supportsInt8 = computeCapability >= 6.1  # Pascal+
    result.supportsAV1 = computeCapability >= 8.6  # Ada+

    if not result.supportsTensorCores:
      warn "GPU lacks Tensor Cores - ML features will be slow"
```

**Prevention strategy:**
1. **Phase: GPU Acceleration Basics** - Runtime capability detection
2. Graceful degradation (disable features not supported)
3. Document minimum GPU requirements (Compute Capability 6.1+)

---

### Pitfall 13: Batch Progress Reporting Without ETA Calculation

**What goes wrong:** Progress bar shows "Processing file 37/100" without time remaining. Users don't know if batch will finish in 10 minutes or 10 hours.

**Prevention:**
```nim
type BatchProgress = object
  completed: int
  total: int
  startTime: DateTime

proc reportProgress(bp: var BatchProgress) =
  let elapsed = now() - bp.startTime
  let avgTimePerFile = elapsed.inSeconds / bp.completed
  let remaining = (bp.total - bp.completed) * avgTimePerFile

  echo &"[{bp.completed}/{bp.total}] ETA: {remaining.formatDuration()}"
```

**Prevention strategy:**
1. **Phase: Batch Processing Core** - Calculate ETA from start
2. Update ETA every file (moving average of last 10 files)
3. Show both file count and time remaining

---

### Pitfall 14: Cross-Platform Path Handling in Batch Checkpoints

**What goes wrong:** Checkpoint file stores absolute paths with Unix separators (`/Users/...`). Loading checkpoint on Windows fails because paths don't match (`C:\Users\...`).

**Prevention:**
```nim
import std/os

proc normalizePathForCheckpoint(path: string): string =
  # Store relative to current directory when possible
  try:
    result = relativePath(path, getCurrentDir())
  except:
    # Fall back to absolute path
    result = path.absolutePath()

proc resolvePathFromCheckpoint(stored: string): string =
  if stored.isAbsolute():
    return stored
  else:
    return (getCurrentDir() / stored).normalizePathEnd()
```

**Prevention strategy:**
1. **Phase: Batch Processing Core** - Store relative paths in checkpoint
2. Normalize path separators on load
3. Test checkpoint portability between platforms

---

## Phase-Specific Warnings

Warnings organized by which phase they're most likely to surface in.

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| **GPU Acceleration Basics** | Missing hwaccel_output_format flag (Pitfall 1) | Add integration test that verifies GPU memory usage, not system RAM |
| **GPU Acceleration Basics** | macOS Metal assumption (Pitfall 6) | Runtime detection with graceful fallback |
| **GPU Acceleration Basics** | GPU capability detection (Pitfall 12) | Query compute capability before initialization |
| **4K Memory Optimization** | Unbounded frame buffer queue (Pitfall 3) | Implement backpressure with resolution-based limits |
| **4K Memory Optimization** | Nim GC not tracking C buffers (Pitfall 8) | Migrate to --gc:orc for deterministic cleanup |
| **Batch Processing Core** | No checkpoint/resume (Pitfall 4) | Design checkpoint schema before implementing loop |
| **Batch Processing Core** | Error cascade without isolation (Pitfall 7) | Per-file context with defer cleanup |
| **Batch Processing Core** | FFmpeg 7.x thread explosion (Pitfall 10) | Calculate per-file resource budget |
| **Batch Processing Core** | Progress without ETA (Pitfall 13) | Moving average ETA calculation |
| **Batch Processing Core** | Cross-platform checkpoint paths (Pitfall 14) | Store relative paths |
| **Chapter Detection** | No speaker diarization (Pitfall 5) | Implement diarization before chapter algorithm |
| **Chapter Detection** | Generic chapter titles (Pitfall 11) | Include context window in title generation |
| **Preview Generation** | Memory pressure in batch (Pitfall 9) | Streaming preview generation |
| **All GPU Phases** | Thread count misconfiguration (Pitfall 2) | Dynamic thread allocation based on hwaccel |

---

## Pitfalls Honeyclip Has Already Overcome

Document existing solutions to avoid regression.

### Memory Management at Nim/C++ FFI Boundary

**Solution in place:** Consistent use of `defer` blocks for cleanup
```nim
# src/media.nim:76
var codecCtx = avcodec_alloc_context3(nil)
discard avcodec_parameters_to_context(codecCtx, codecParameters)
defer: avcodec_free_context(addr codecCtx)
```

**Why it worked:** Nim's `defer` guarantees cleanup even on exception paths.

**Recommendation:** Apply same pattern to all new FFmpeg object allocations in v1.2 features.

---

### Binary Size from Static Linking

**Solution in place:** MinSizeRel for ML libraries, aggressive codec pruning
```nim
# honeyclip.nimble: Explicit codec disable lists
var disableDecoders: seq[string] = @[]
var disableEncoders: seq[string] = @[]
```

**Why it worked:** Explicit control over linked codecs reduces binary bloat.

**Recommendation:** For GPU features, only enable required codecs (h264_nvenc, hevc_nvenc, etc.)

---

### Cross-Platform Builds (CMake Compatibility)

**Solution in place:** CMake policy version override for ONNX Runtime
```bash
# -DCMAKE_POLICY_VERSION_MINIMUM=3.5 for older CMakeLists.txt
```

**Why it worked:** Newer CMake versions removed compatibility with CMake < 3.5.

**Recommendation:** Apply same policy override to any new ML library dependencies.

---

## Research Confidence Assessment

| Pitfall Category | Confidence | Source Quality |
|------------------|-----------|----------------|
| GPU Memory Transfer (1) | HIGH | NVIDIA official docs, multiple sources |
| Thread Misconfiguration (2) | HIGH | FFmpeg 7.x release notes, performance studies |
| 4K Frame Buffer OOM (3) | MEDIUM | Linux kernel docs, real-world reports |
| Checkpoint/Resume (4) | HIGH | Industry standard patterns, AWS/Azure docs |
| Chapter Detection (5) | MEDIUM | Whisper ecosystem, diarization tools |
| macOS VideoToolbox (6) | HIGH | Apple/Jellyfin official docs |
| Batch Error Isolation (7) | HIGH | Enterprise batch processing patterns |
| Nim GC with C FFI (8) | MEDIUM | Nim official docs (need Valgrind validation) |
| Preview Memory (9) | LOW | Inferred from frame buffer patterns |
| FFmpeg 7.x Pipeline (10) | MEDIUM | FFmpeg release notes, Hacker News discussion |
| Generic Titles (11) | LOW | Common LLM pattern (not domain-specific) |
| GPU Capabilities (12) | MEDIUM | NVIDIA docs, community reports |
| Progress ETA (13) | HIGH | Standard UX pattern |
| Path Handling (14) | HIGH | Cross-platform development best practice |

---

## Recommended Validation During Development

For each phase, validate against corresponding pitfalls:

### GPU Acceleration Basics
1. Profile GPU memory usage (nvidia-smi, Activity Monitor)
2. Verify frames stay GPU-resident (no system RAM spikes)
3. Test on macOS without Metal (VM or old hardware)
4. Measure throughput with different thread counts (2, 4, 8, 16)

### 4K Memory Optimization
1. Test with ulimit -v 4GB (simulate constrained memory)
2. Process 4K file and monitor memory ceiling
3. Validate frame queue never exceeds configured depth
4. Test with --gc:orc and verify deterministic cleanup

### Batch Processing Core
1. Interrupt batch at 50% completion, verify resume
2. Inject corrupted file mid-batch, verify isolation
3. Measure thread count during batch (should not exceed cores × 2)
4. Test checkpoint loading on different platform

### Chapter Detection
1. Validate chapter count against duration heuristic
2. Test on monologue (1 speaker) - expect low chapter count
3. Test on interview (2 speakers) - chapters should align with turns
4. Verify speaker labels present in output

### Preview Generation
1. Generate previews for 10 files, monitor memory usage
2. Verify frames discarded after thumbnail creation
3. Test batch preview generation (should not accumulate frames)

---

## Sources Summary

**Official Documentation:**
- [NVIDIA FFmpeg Transcoding Guide](https://developer.nvidia.com/blog/nvidia-ffmpeg-transcoding-guide/)
- [FFmpeg with NVIDIA GPU Acceleration](https://docs.nvidia.com/video-technologies/video-codec-sdk/13.0/ffmpeg-with-nvidia-gpu/index.html)
- [Jellyfin Hardware Acceleration](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/)
- [Apple VideoToolbox](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/apple/)
- [Linux Kernel V4L2 Decoder](https://docs.kernel.org/userspace-api/media/v4l/dev-stateless-decoder.html)
- [Azure Batch Error Handling](https://learn.microsoft.com/en-us/azure/batch/error-handling)
- [AWS SageMaker Checkpoints](https://docs.aws.amazon.com/sagemaker/latest/dg/model-checkpoints.html)

**Performance Studies (2026):**
- [FFmpeg Threads Performance](https://streaminglearningcenter.com/blogs/ffmpeg-command-threads-how-it-affects-quality-and-performance.html)
- [Thread Count Impact on Quality](https://streaminglearningcenter.com/encoding/how-thread-count-impacts-video-encoding-quality-throughput-and-cost.html)
- [Optimizing FFmpeg Performance](https://www.cincopa.com/learn/optimizing-ffmpeg-performance-threads-presets-and-tuning)
- [How to Reduce CPU Usage](https://copyprogramming.com/howto/how-to-reduce-cpu-usage-of-ffmpeg)

**ML/Transcription:**
- [Auphonic Chapter Detection](https://auphonic.com/help/algorithms/speech_recognition.html)
- [WhisperX Pipeline](https://vogla.com/whisperx-transcription-pipeline-guide/)
- [Whisper.cpp Speaker Diarization](https://picovoice.ai/blog/whisper-cpp-speaker-diarization/)
- [WhisperX vs Competitors](https://brasstranscripts.com/blog/whisperx-vs-competitors-accuracy-benchmark)

**Memory Optimization:**
- [CUDA OOM Errors](https://openclaw-ai.org/guides/fix-openclaw-cuda-oom-errors)
- [Low-VRAM Optimization](https://medium.com/the-ai-mindscape/optimizing-gpu-usage-on-low-vram-machines-6-practical-steps-to-dodge-oom-errors-2957c779f3e0)
- [ComfyUI VRAM Management](https://github.com/RandomInternetPreson/ComfyUI_LTX-2_VRAM_Memory_Management)

**Batch Processing:**
- [Batch Error Handling 2026](https://oneuptime.com/blog/post/2026-01-30-batch-processing-error-handling/view)
- [HTCondor Checkpointing](https://chtc.cs.wisc.edu/uw-research-computing/checkpointing)
- [MuleSoft Batch Error Handling](https://mulesy.com/error-handling-in-batch-job/)

**FFmpeg Architecture:**
- [FFmpeg 7.x Multi-Threading](https://news.ycombinator.com/item?id=38613219)
- [FFmpeg CLI Multi-Threaded Patches](https://www.phoronix.com/news/FFmpeg-CLI-Multi-Threaded)
- [Multi-Threaded GPU Encoding](https://hostkey.com/blog/12-multi-threaded-video-encoding-on-a-professional-gpu/)

**Nim Language:**
- [Nim refc Documentation](https://nim-lang.github.io/Nim/refc.html)
- [Nim Destructors](https://nim-lang.org/araq/destructors.html)
- [Nim asyncdispatch](https://nim-lang.org/docs/asyncdispatch.html)
- [Nim Concurrency](https://nim-by-example.github.io/concurrency/)
