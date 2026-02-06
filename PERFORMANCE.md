# Performance Guide

This guide documents the performance and quality tradeoffs for all honeyclip settings, helping you choose the right balance between speed and output quality.

## ⚠️ Important Note on Metrics

**Performance estimates in this document are based on:**
- Industry-standard codec comparisons (H.264 vs H.265, etc.)
- Publicly documented benchmarks (Whisper models, FFmpeg presets)
- Calculated values (frame sizes, bitrates)
- General video processing experience

**Not all values have been empirically measured on honeyclip specifically.** Actual performance will vary based on:
- Input video characteristics (resolution, codec, complexity)
- Hardware (CPU, RAM, disk speed)
- Operating system (macOS/Linux/Windows)
- System load and available resources

**We welcome contributions** to measure and validate these metrics! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add benchmarks.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Video Codec Settings](#video-codec-settings)
- [Audio Codec Settings](#audio-codec-settings)
- [Whisper Model Selection](#whisper-model-selection)
- [Engagement Analysis](#engagement-analysis)
- [Face Detection & Reframing](#face-detection--reframing)
- [Hardware Acceleration](#hardware-acceleration)
- [Memory Optimization](#memory-optimization)
- [Quality Validation](#quality-validation)
- [Profiling & Debugging](#profiling--debugging)

---

## Quick Reference

### Speed vs Quality Matrix

*Note: Speed estimates are approximate and vary significantly based on hardware and input characteristics.*

| Setting | Speed (est.) | Quality | File Size | Use Case |
|---------|--------------|---------|-----------|----------|
| **Fast** | 10x realtime | Draft | 2x larger | Quick preview, iteration |
| **Balanced** (default) | 2x realtime | Production | Optimal | Most workflows |
| **Best** | 0.5x realtime | Archival | Smallest | Final delivery, broadcast |

**Example:** 30-minute video *(estimated, not measured)*
- Fast: ~3 minutes processing
- Balanced: ~15 minutes processing
- Best: ~60 minutes processing

*These are planned presets (Phase 22). Current version requires manual flag configuration.*

---

## Video Codec Settings

### Codec Selection (`-c:v`, `--video-codec`)

```bash
# H.264 (default) - Best compatibility
honeyclip input.mp4 -c:v libx264

# H.265/HEVC - Better compression, slower encode
honeyclip input.mp4 -c:v libx265

# VP9 - Open source, good compression
honeyclip input.mp4 -c:v libvpx-vp9

# SVT-AV1 - Future-proof, best compression
honeyclip input.mp4 -c:v libsvtav1
```

| Codec | Encode Speed | File Size | Compatibility | Quality |
|-------|--------------|-----------|---------------|---------|
| **libx264** | ⚡⚡⚡ Fast | 100% (baseline) | ✅ Universal | Excellent |
| **libx265** | ⚡ Slow | 50% smaller | ⚠️ Modern devices | Excellent |
| **libvpx-vp9** | ⚡ Slow | 60% smaller | ✅ Web/YouTube | Excellent |
| **libsvtav1** | ⚡⚡ Medium | 40% smaller | ⚠️ Latest devices | Best |

**Recommendation:** Use `libx264` unless you need smaller files (then try `libx265` or `libsvtav1`).

### Video Profile (`-vprofile`, `-profile:v`)

H.264 profiles control features vs compatibility:

```bash
# Baseline - Maximum compatibility (old devices, streaming)
honeyclip input.mp4 -vprofile baseline

# Main - Balanced (default, recommended for most uses)
honeyclip input.mp4 -vprofile main

# High - Best quality features (modern devices)
honeyclip input.mp4 -vprofile high
```

| Profile | Encode Speed | Quality | Compatibility | Features |
|---------|--------------|---------|---------------|----------|
| **baseline** | ⚡⚡⚡ Fastest | Good | ✅ All devices | Basic |
| **main** (default) | ⚡⚡ Fast | Better | ✅ Most devices | CABAC, B-frames |
| **high** | ⚡ Slower | Best | ⚠️ Modern only | 8x8 transform, more |

**Performance Impact:**
- Baseline → Main: ~10% slower encode, ~15% smaller file
- Main → High: ~5% slower encode, ~5% smaller file

### Video Bitrate (`-b:v`, `--video-bitrate`)

Higher bitrate = better quality but larger files.

```bash
# Low bitrate - Small files, visible compression
honeyclip input.mp4 -b:v 1M

# Medium bitrate - Balanced (good for 1080p)
honeyclip input.mp4 -b:v 5M

# High bitrate - Large files, minimal compression
honeyclip input.mp4 -b:v 10M
```

**Recommended Bitrates (H.264, 30fps):**
- 720p: 2-4 Mbps
- 1080p: 4-8 Mbps
- 4K: 15-25 Mbps

**Quality Metrics:**
- <2 Mbps @ 1080p: PSNR ~28-30dB (visible artifacts)
- 4-8 Mbps @ 1080p: PSNR ~32-36dB (production quality)
- >10 Mbps @ 1080p: PSNR ~38-42dB (archival quality)

### Resolution Scaling (`--scale`)

```bash
# Downscale to 50% (4K → 1080p)
honeyclip input-4k.mp4 --scale 0.5

# Upscale to 200% (not recommended, use native resolution)
honeyclip input-720p.mp4 --scale 2
```

**Performance Impact:**
- 4K → 1080p (0.5): ~4x faster processing
- 1080p → 720p (0.67): ~2x faster processing

**Memory Impact:**
- 4K frame: ~24 MB uncompressed
- 1080p frame: ~6 MB uncompressed
- 720p frame: ~2.7 MB uncompressed

---

## Audio Codec Settings

### Codec Selection (`-c:a`, `--audio-codec`)

```bash
# AAC (default) - Best compatibility
honeyclip input.mp4 -c:a aac

# Opus - Better quality per bitrate
honeyclip input.mp4 -c:a libopus

# MP3 - Wide compatibility, larger files
honeyclip input.mp4 -c:a libmp3lame
```

| Codec | Quality @ 128kbps | File Size | Compatibility |
|-------|-------------------|-----------|---------------|
| **aac** (default) | Excellent | 100% | ✅ Universal |
| **libopus** | Best | 80% smaller | ✅ Modern |
| **libmp3lame** | Good | 120% larger | ✅ Legacy |

**Performance:** Audio encoding is <5% of total processing time (negligible).

### Audio Bitrate (`-b:a`, `--audio-bitrate`)

```bash
# Low bitrate - Podcasts, voice
honeyclip input.mp4 -b:a 64k

# Medium bitrate - Music, balanced
honeyclip input.mp4 -b:a 128k

# High bitrate - High-fidelity music
honeyclip input.mp4 -b:a 256k
```

**Recommended:**
- Voice/Podcast: 64-96 kbps
- Music (stereo): 128-192 kbps
- High-fidelity: 256-320 kbps

---

## Whisper Model Selection

Whisper models balance speed vs transcription accuracy.

```bash
# Download models first (run once)
mkdir -p ~/.cache/whisper

# Base model - Fast, lower accuracy
curl -L -o ~/.cache/whisper/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# Small model - Balanced
curl -L -o ~/.cache/whisper/ggml-small.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin

# Medium model - Slow, high accuracy
curl -L -o ~/.cache/whisper/ggml-medium.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin
```

### Model Comparison

*Speed and accuracy from [OpenAI Whisper documentation](https://github.com/openai/whisper). Actual speeds may vary.*

| Model | Speed (approx.) | Accuracy (WER) | Size | Use Case |
|-------|-----------------|----------------|------|----------|
| **tiny** | ⚡⚡⚡ 32x realtime | ~10% error | 75 MB | Quick draft, testing |
| **base** | ⚡⚡⚡ 16x realtime | ~7% error | 142 MB | Fast transcripts |
| **small** | ⚡⚡ 6x realtime | ~5% error | 466 MB | Balanced (recommended) |
| **medium** | ⚡ 2x realtime | ~4% error | 1.5 GB | Production quality |
| **large** | 1x realtime | ~3% error | 2.9 GB | Maximum accuracy |

**Example:** 30-minute podcast *(estimated, hardware-dependent)*
- base: ~2 minutes transcription
- small: ~5 minutes transcription
- medium: ~15 minutes transcription

**Model Selection Guide:**
- **Use base:** Quick iteration, low stakes
- **Use small:** Most production workflows
- **Use medium:** Technical content, accents, noisy audio
- **Use large:** Mission-critical accuracy

---

## Engagement Analysis

Engagement presets optimize for different content types.

```bash
# Preset-based (recommended)
honeyclip engage input.mp4 --engage viral       # High-energy clips
honeyclip engage input.mp4 --engage podcast     # Speech-focused
honeyclip engage input.mp4 --engage tutorial    # Action + speech
honeyclip engage input.mp4 --engage tiktok      # Maximum motion

# Numeric threshold (0-100)
honeyclip engage input.mp4 --engage 70          # Custom threshold
```

### Preset Configuration

| Preset | Threshold | Audio | Motion | Speech | Use Case |
|--------|-----------|-------|--------|--------|----------|
| **viral** | 75 | 30% | 40% | 30% | High-energy, fast cuts |
| **podcast** | 50 | 10% | 10% | 80% | Conversation, minimal visuals |
| **tutorial** | 40 | 20% | 40% | 40% | How-to, screen recordings |
| **interview** | 45 | 20% | 20% | 60% | Talking heads |
| **tiktok** | 80 | 30% | 50% | 20% | Maximum engagement |
| **youtube** | 60 | 40% | 30% | 30% | General content |
| **instagram** | 70 | 30% | 40% | 30% | Visual-first |

**Performance Impact:**
- Engagement analysis: ~10-30 seconds per 30-minute video
- Face detection (if enabled): +60-120 seconds
- Speech detection (Whisper): varies by model (see above)

---

## Face Detection & Reframing

Face detection powers speaker tracking and auto-reframing.

```bash
# Reframe for vertical video (9:16)
honeyclip reframe input.mp4 --aspect 9:16

# Speed presets
honeyclip reframe input.mp4 --aspect 9:16 --speed fast     # Skip frames
honeyclip reframe input.mp4 --aspect 9:16 --speed medium   # Balanced
honeyclip reframe input.mp4 --aspect 9:16 --speed slow     # Every frame
```

**Performance (macOS/Linux only, requires ML libraries):**

| Speed Preset | Processing Time | Quality | Frames Analyzed |
|--------------|-----------------|---------|-----------------|
| **fast** | ~10% realtime | Good | Every 5th frame |
| **medium** (default) | ~25% realtime | Better | Every 2nd frame |
| **slow** | ~50% realtime | Best | Every frame |

**Example:** 30-minute 1080p video
- fast: ~3 minutes
- medium: ~7.5 minutes
- slow: ~15 minutes

**Confidence Thresholds:**
- Low (0.3): More false positives, catches all faces
- Medium (0.5): Balanced (default)
- High (0.7): Fewer false positives, may miss some faces

**Note:** Face detection not available on Windows (ML libraries require LTO).

---

## Hardware Acceleration

### GPU Acceleration (Planned - Phase 15)

**Current Status:** CPU-only. GPU acceleration coming in v2.0.

**Planned Support:**
- **Linux:** CUDA (NVIDIA GPUs)
- **macOS:** Metal (Apple Silicon, Intel with discrete GPU)
- **Windows:** Not planned (ML not supported)

**Expected Performance (when implemented):**
- Face detection: ~5-10x faster on GPU
- Video encoding (H.265 NVENC): ~3-5x faster
- Quality: Identical to CPU (validated via PSNR/SSIM)

### Hardware Video Encoding

Some systems support hardware-accelerated encoding:

**macOS (VideoToolbox):**
```bash
# Use hardware H.264 encoder
honeyclip input.mp4 -c:v h264_videotoolbox
```

**Linux (VAAPI/NVENC):**
```bash
# Intel Quick Sync
honeyclip input.mp4 -c:v h264_vaapi

# NVIDIA NVENC
honeyclip input.mp4 -c:v h264_nvenc
```

**Tradeoffs:**
- Speed: 2-5x faster encoding
- Quality: Slightly lower than software encoders (1-2 dB PSNR)
- File size: 10-20% larger for same quality
- Compatibility: Encoder must be available

---

## Memory Optimization

### For 4K+ Video

```bash
# Enable fragmented output (allows streaming, reduces memory)
honeyclip input-4k.mp4 --fragmented

# Disable seeking (reduces memory, but slower)
honeyclip input-4k.mp4 --no-seek

# Process in chunks (manual workaround)
honeyclip input-4k.mp4 --cut-out 0,30min -o part1.mp4
honeyclip input-4k.mp4 --cut-out 30min,60min -o part2.mp4
```

**Memory Usage Estimates:**

*Based on uncompressed frame sizes and typical processing buffers. Not measured in honeyclip.*

| Resolution | Peak Memory (est.) | Notes |
|------------|-------------------|-------|
| **720p** | ~1-2 GB | Comfortable on most machines |
| **1080p** | ~2-4 GB | Default, well-optimized |
| **4K** | ~8-12 GB | May require fragmentation |
| **8K** | ~30-40 GB | Not recommended, use chunks |

**Memory-Saving Techniques:**
1. **Close other applications** during processing
2. **Use `--fragmented`** for large files
3. **Downscale** with `--scale` if final output doesn't need full resolution
4. **Process in segments** using `--cut-out` for extremely large files

---

## Quality Validation

### Visual Quality Metrics

**PSNR (Peak Signal-to-Noise Ratio):**
- >40 dB: Excellent (archival)
- 32-40 dB: Good (production)
- 28-32 dB: Acceptable (draft)
- <28 dB: Poor (artifacts visible)

**SSIM (Structural Similarity Index):**
- >0.95: Excellent
- 0.90-0.95: Good
- 0.85-0.90: Acceptable
- <0.85: Poor

### Measuring Quality

```bash
# Install ffmpeg-quality-metrics (Python)
pip install ffmpeg-quality-metrics

# Compare output to original
ffmpeg-quality-metrics original.mp4 output.mp4 -m psnr ssim

# Expected results (for lossless edit operations):
# PSNR: >40 dB (no quality loss from processing)
# SSIM: >0.99 (structurally identical)
```

### Quality Checklist

Before finalizing output:

1. **Visual Inspection:** Watch at least 3 random segments
2. **Audio Sync:** Check lip-sync in talking-head segments
3. **Transitions:** Verify cuts are clean (no flash frames)
4. **Color:** Check for color shifts or banding
5. **File Size:** Reasonable for resolution and duration
6. **Compatibility:** Test playback on target devices

---

## Profiling & Debugging

### Measuring Performance

```bash
# Time full pipeline
time honeyclip input.mp4 -o output.mp4

# Run benchmarks
nimble bench

# Show debug output
honeyclip input.mp4 --debug
```

### Platform-Specific Profiling

**macOS (Instruments):**
```bash
# Compile with profiling
nim c --profiler:on --stackTrace:on src/main.nim

# Run Instruments
instruments -t "Time Profiler" ./honeyclip input.mp4
```

**Linux (Valgrind/perf):**
```bash
# Memory profiling
valgrind --tool=massif ./honeyclip input.mp4
ms_print massif.out.*

# CPU profiling
perf record ./honeyclip input.mp4
perf report
```

**Windows:**
```bash
# Windows Performance Recorder
wpr -start GeneralProfile
honeyclip.exe input.mp4
wpr -stop honeyclip.etl

# Analyze with Windows Performance Analyzer
wpa honeyclip.etl
```

### Performance Debugging

If processing is slower than expected:

1. **Check CPU usage:** Should be near 100% during processing
2. **Check disk I/O:** Slow disk can bottleneck (use SSD)
3. **Check codec:** Some codecs are slower (try libx264 if using others)
4. **Check input format:** Reformat to MP4/MKV if using exotic formats
5. **Check memory:** Swapping to disk kills performance
6. **Disable ML features:** If face detection is slow, skip it

---

## Future Roadmap

### Phase 22: Quality Presets (Planned)

Coming in v2.0, single flag for speed/quality balance:

```bash
# Fast preset (draft quality)
honeyclip input.mp4 --preset fast
# - x264 ultrafast preset
# - base whisper model
# - Skip ML analysis
# - Target: 10x realtime, PSNR >28dB

# Balanced preset (production quality, default)
honeyclip input.mp4 --preset balanced
# - x264 main profile
# - small whisper model
# - Basic ML analysis
# - Target: 2x realtime, PSNR >32dB

# Best preset (archival quality)
honeyclip input.mp4 --preset best
# - x264 veryslow preset
# - medium whisper model
# - Full ML analysis
# - Target: 0.5x realtime, PSNR >38dB
```

### Phase 15: GPU Acceleration (Planned)

- CUDA support for Linux
- Metal support for macOS
- 5-10x faster face detection
- Automatic fallback to CPU if GPU unavailable

---

## Quick Tips

### For Maximum Speed
```bash
honeyclip input.mp4 \
  -c:v libx264 \
  -vprofile baseline \
  --scale 0.5 \
  --no-faststart
```

### For Maximum Quality
```bash
honeyclip input.mp4 \
  -c:v libx264 \
  -vprofile high \
  -b:v 10M \
  --fragmented
```

### For Small File Size
```bash
honeyclip input.mp4 \
  -c:v libsvtav1 \
  -b:v 2M
```

### For Best Compatibility
```bash
honeyclip input.mp4 \
  -c:v libx264 \
  -vprofile baseline \
  -c:a aac \
  -b:a 128k
```

---

**Last Updated:** 2026-02-06  
**Version:** v1.1  
**See Also:** [BENCHMARKS.md](tests/BENCHMARKS.md), [README.md](README.md)
