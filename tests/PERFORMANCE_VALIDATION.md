# Performance Validation Methodology

This document describes how to validate the performance claims in `PERFORMANCE.md`.

## Overview

The `performance_validation.nim` tool measures real-world processing performance with actual video files at different resolutions. This validates documentation claims and provides data for performance regression tracking.

## Prerequisites

### Test Video Generation

Generate test videos using FFmpeg (requires standalone FFmpeg binary):

```bash
# 720p @ 30fps (10 seconds)
ffmpeg -f lavfi -i testsrc=duration=10:size=1280x720:rate=30 \
  -f lavfi -i sine=frequency=1000:duration=10 \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  -y tests/performance_validation_output/720p_30fps.mp4

# 1080p @ 30fps (10 seconds)
ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
  -f lavfi -i sine=frequency=1000:duration=10 \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  -y tests/performance_validation_output/1080p_30fps.mp4

# 1080p @ 60fps (10 seconds)
ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=60 \
  -f lavfi -i sine=frequency=1000:duration=10 \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  -y tests/performance_validation_output/1080p_60fps.mp4

# 4K @ 30fps (5 seconds - shorter to keep test fast)
ffmpeg -f lavfi -i testsrc=duration=5:size=3840x2160:rate=30 \
  -f lavfi -i sine=frequency=1000:duration=5 \
  -c:v libx264 -preset medium -crf 23 \
  -c:a aac -b:a 128k \
  -y tests/performance_validation_output/4k_30fps.mp4
```

## Running Validation

```bash
# Generate test videos first (see above)

# Run validation suite
nimble validateperf

# Results saved to: tests/performance_validation_results.json
```

## What Gets Measured

For each test video and preset combination:

1. **Processing Time** - Wall-clock time from start to finish (milliseconds)
2. **Processing Speed Ratio** - `video_duration / processing_time`
   - Example: 2.0x = processes 10s video in 5s (2x realtime)
3. **Peak Memory Usage** - Maximum RSS during processing (MB)
4. **Output Size** - Size of processed output file (bytes)

## Tested Configurations

### Resolutions
- 720p @ 30fps (1280x720)
- 1080p @ 30fps (1920x1080)
- 1080p @ 60fps (1920x1080)
- 4K @ 30fps (3840x2160)

### Codec Presets
- `ultrafast` - Maximum speed, larger file size
- `fast` - Good speed/quality balance
- `medium` - Default balance
- `veryslow` - Maximum quality, slower (optional)

## Expected Results

Based on typical hardware (Intel i7/M1 Pro, 16GB RAM):

### 720p @ 30fps (10 seconds)
| Preset     | Speed Ratio | Memory  | Notes                          |
|------------|-------------|---------|--------------------------------|
| ultrafast  | ~15-20x     | ~50MB   | Fastest, use for drafts        |
| fast       | ~8-12x      | ~60MB   | Good for quick edits           |
| medium     | ~4-6x       | ~70MB   | Production quality             |
| veryslow   | ~1-2x       | ~80MB   | Archive quality (rarely needed)|

### 1080p @ 30fps (10 seconds)
| Preset     | Speed Ratio | Memory  |
|------------|-------------|---------|
| ultrafast  | ~8-10x      | ~80MB   |
| fast       | ~4-6x       | ~100MB  |
| medium     | ~2-3x       | ~120MB  |

### 1080p @ 60fps (10 seconds)
| Preset     | Speed Ratio | Memory  |
|------------|-------------|---------|
| ultrafast  | ~4-6x       | ~100MB  |
| fast       | ~2-3x       | ~130MB  |
| medium     | ~1-2x       | ~150MB  |

### 4K @ 30fps (5 seconds)
| Preset     | Speed Ratio | Memory  |
|------------|-------------|---------|
| ultrafast  | ~2-3x       | ~200MB  |
| fast       | ~1-2x       | ~250MB  |
| medium     | ~0.5-1x     | ~300MB  |

## Validating PERFORMANCE.md Claims

The validation suite helps verify claims in `PERFORMANCE.md`:

### Processing Speed Claims
- **Claim**: "2x realtime for 1080p @ 30fps with medium preset"
- **Validation**: Run 1080p_30fps with medium preset, check speed ratio ≥2.0

### Memory Usage Claims
- **Claim**: "~150MB peak for 1080p @ 60fps"
- **Validation**: Check peakMemoryMB for 1080p_60fps ≤200MB (with buffer)

### Codec Preset Impact
- **Claim**: "ultrafast is ~10x faster than medium for 720p"
- **Validation**: Compare speed ratios: `ultrafast_speed / medium_speed ≥10`

## Platform Differences

Performance varies by platform and hardware:

### macOS (Apple Silicon)
- **VideoToolbox acceleration**: Faster encoding on M-series chips
- **Unified memory**: Lower memory overhead
- **Expected**: Higher speed ratios than estimates

### Linux (Intel/AMD)
- **Baseline reference**: Estimates based on typical x86_64
- **Varies by CPU**: Modern CPUs (12th gen+) significantly faster

### Windows
- **Similar to Linux**: Performance comparable on same hardware
- **ML features disabled**: engage/reframe not tested

## Regression Detection

Compare results across commits:

```bash
# Baseline (before optimization)
git checkout main
nimble validateperf
cp tests/performance_validation_results.json baseline.json

# After optimization
git checkout feature/my-optimization
nimble validateperf

# Compare
diff baseline.json tests/performance_validation_results.json
```

**Acceptable regression**: <15% slower (matching benchmark threshold)

## Contributing Validation Results

If you run validation on different hardware, please share results:

1. Run validation: `nimble validateperf`
2. Copy results: `tests/performance_validation_results.json`
3. Create GitHub issue: "Performance Validation Results: [Your CPU/OS]"
4. Include:
   - CPU model and core count
   - RAM amount
   - OS version
   - Compiler version (nim --version)
   - JSON results

This helps improve documentation accuracy across different hardware configurations!

## Troubleshooting

### "Test video not found"
Generate test videos using FFmpeg commands above.

### Processing fails
- Check honeyclip binary exists: `ls -lh ./honeyclip`
- Verify video is valid: `ffprobe <test_video>`

### Memory measurements show 0.0 MB
Memory profiling works on Linux, macOS, and Windows. If showing 0:
- Ensure running compiled binary (not nimble directly)
- Check platform implementation in `getCurrentMemoryMB()`

### Speed ratios lower than expected
- CPU throttling (thermal): Check temperatures
- Background processes: Close other apps
- Debug build: Ensure release build (`-d:release`)
