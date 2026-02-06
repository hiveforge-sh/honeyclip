# Quality Metrics Validation

This document explains how honeyclip validates output quality in benchmarks to ensure that performance optimizations don't degrade video quality.

## Overview

The benchmark system includes two quality validation methods:

1. **PSNR/SSIM** (Preferred) - Accurate visual quality metrics using FFmpeg filters
2. **Hash-based** (Fallback) - Simple file comparison when FFmpeg unavailable

## PSNR and SSIM Metrics

### What They Measure

**PSNR (Peak Signal-to-Noise Ratio):**
- Measures pixel-level accuracy between two videos
- Unit: Decibels (dB)
- Higher is better
- Interpretation:
  - **>40 dB** - Excellent (archival quality)
  - **35-40 dB** - Very good (production quality)
  - **30-35 dB** - Good (acceptable for most uses)
  - **<30 dB** - Poor (visible degradation)

**SSIM (Structural Similarity Index):**
- Measures perceptual quality (how similar videos look to human eyes)
- Range: 0-1 (1 = identical)
- Better correlates with human perception than PSNR
- Interpretation:
  - **>0.99** - Excellent (imperceptible difference)
  - **0.95-0.99** - Very good (minor artifacts)
  - **0.90-0.95** - Good (visible but acceptable)
  - **<0.90** - Poor (significant artifacts)

### Quality Thresholds

Benchmarks enforce minimum quality standards:

```nim
const
  MinimumPSNR = 30.0dB    # Below this = failed quality check
  MinimumSSIM = 0.95      # Below this = visible artifacts
```

**Regression detection:**
- PSNR drop >1dB triggers warning
- Failing to meet minimums fails the benchmark

### How It Works

1. **Create reference video:**
   ```bash
   # Passthrough (no edits) to create reference with same encoding
   honeyclip input.mp4 -o reference.mp4 --edit "(not (and false true))"
   ```

2. **Process test video:**
   ```bash
   # Apply actual edit being benchmarked
   honeyclip input.mp4 -o test.mp4 --edit audio:0.04
   ```

3. **Calculate PSNR:**
   ```bash
   ffmpeg -i test.mp4 -i reference.mp4 \
     -filter_complex "psnr=stats_file=-" \
     -f null - 2>&1
   ```
   
   **Output:**
   ```
   psnr_avg:38.21 psnr_y:39.45 psnr_u:42.18 psnr_v:41.92
   ```

4. **Calculate SSIM:**
   ```bash
   ffmpeg -i test.mp4 -i reference.mp4 \
     -filter_complex "ssim=stats_file=-" \
     -f null - 2>&1
   ```
   
   **Output:**
   ```
   All:0.987654 (18.456789)
   ```

5. **Parse and validate:**
   ```nim
   let metrics = QualityMetrics(
     psnr: 38.21,
     ssim: 0.987654,
     valid: true
   )
   
   if metrics.psnr < MinimumPSNR:
     echo "FAILED: PSNR below threshold"
   if metrics.ssim < MinimumSSIM:
     echo "FAILED: SSIM below threshold"
   ```

### Requirements

- FFmpeg binary with libavfilter
- PSNR and SSIM filter support (standard in most builds)

**Check if available:**
```bash
ffmpeg -filters 2>&1 | grep -E '(psnr|ssim)'
```

**Expected output:**
```
 ... psnr         VV->V      Calculate the PSNR between two video streams.
 ... ssim         VV->V      Calculate the SSIM between two video streams.
```

## Hash-Based Validation (Fallback)

When FFmpeg filters aren't available, fall back to simpler validation:

### File Size Comparison

```nim
proc hashBasedQualityCheck(reference: string, test: string): bool =
  let refSize = getFileSize(reference)
  let testSize = getFileSize(test)
  
  # Allow 1% variance (encoding differences)
  let diff = abs(testSize.float - refSize.float) / refSize.float * 100.0
  
  if diff > 1.0:
    debug &"Size difference: {diff:.1f}% (FAILED)"
    return false
  
  return true  # Sizes match within tolerance
```

### MD5 Hash Comparison

```nim
import checksums/md5

proc hashFile(path: string): string =
  let content = readFile(path)
  return $toMD5(content)

# Store in baseline
result.outputHash = hashFile("output.mp4")

# Compare against baseline
if result.outputHash != baseline.outputHash:
  echo "Hash mismatch (output changed)"
```

**Limitations:**
- Brittle (any encoding change breaks hash)
- Can't detect subtle quality loss
- Doesn't measure actual quality

**When to use:**
- FFmpeg not available
- Deterministic output (exact pixel matches)
- Fast sanity check

## Example Benchmark Output

### With PSNR/SSIM

```
Running benchmark: full_pipeline_with_quality
  Completed in 5123ms
  Quality: PSNR: 38.21dB ✓, SSIM: 0.9877 ✓

Performance Comparison vs Baseline
============================================================
full_pipeline_with_quality:
  Baseline: 5000ms
  Current:  5123ms (+2.5%)
  Quality:  PSNR 38.21dB (OK)
  Status:   OK
============================================================
```

### With Hash Validation

```
Running benchmark: full_pipeline_with_quality
  Completed in 5123ms
  Quality metrics unavailable (FFmpeg with libavfilter needed)
  Hash-based quality check: PASSED

Performance Comparison vs Baseline
============================================================
full_pipeline_with_quality:
  Baseline: 5000ms, hash: a1b2c3d4...
  Current:  5123ms (+2.5%), hash: a1b2c3d4...
  Status:   OK (output unchanged)
============================================================
```

### With Quality Regression

```
Running benchmark: full_pipeline_with_quality
  Completed in 5123ms
  Quality: PSNR: 28.45dB ✗, SSIM: 0.9211 ✗
  WARNING: Quality below threshold!

Performance Comparison vs Baseline
============================================================
full_pipeline_with_quality:
  Baseline: 5000ms, PSNR: 38.21dB
  Current:  5123ms (+2.5%), PSNR: 28.45dB
  Quality:  PSNR dropped 9.76dB (was 38.21dB, now 28.45dB)
  Status:   QUALITY REGRESSION
============================================================

ERROR: Quality regression detected!
```

## Adding Quality Validation to Benchmarks

### Basic Template

```nim
proc benchYourFeature(): BenchmarkResult =
  result = runBenchmark("your_feature") do():
    # 1. Create reference (if needed)
    let refPath = "tests/benchmark_output/reference.mp4"
    if not fileExists(refPath):
      # Create reference with same encoding parameters
      createReference(BenchmarkVideo, refPath)
    
    # 2. Process test video
    let testPath = "tests/benchmark_output/test.mp4"
    processVideo(BenchmarkVideo, testPath)
    
    # 3. Calculate quality metrics
    let metrics = calculateQualityMetrics(refPath, testPath)
    
    if metrics.valid:
      result.qualityPSNR = metrics.psnr
      result.qualitySSIM = metrics.ssim
      
      if not meetsQualityThreshold(metrics):
        echo "WARNING: Quality below threshold!"
    else:
      # Fallback to hash check
      if hashBasedQualityCheck(refPath, testPath):
        echo "Hash-based quality check: PASSED"
      else:
        echo "Hash-based quality check: FAILED"
```

### Full Example

See `tests/benchmark.nim` function `benchFullPipeline()` for complete implementation.

## Best Practices

### Do:
- ✅ Use PSNR/SSIM when FFmpeg available
- ✅ Set realistic quality thresholds for your use case
- ✅ Create reference with same encoding parameters as test
- ✅ Document expected quality ranges
- ✅ Track quality metrics over time (in baseline JSON)

### Don't:
- ❌ Rely solely on hash comparison (too brittle)
- ❌ Ignore quality warnings (investigate before merging)
- ❌ Compare videos with different codecs/parameters
- ❌ Use PSNR for perceptual quality (use SSIM instead)
- ❌ Optimize for metrics (optimize for real-world quality)

## Troubleshooting

### "Quality metrics unavailable"

**Cause:** FFmpeg not found or lacks libavfilter.

**Solution:**
```bash
# Check FFmpeg is available
./build/bin/ffmpeg -version

# Or use system FFmpeg
which ffmpeg

# Verify filters exist
ffmpeg -filters 2>&1 | grep psnr
ffmpeg -filters 2>&1 | grep ssim
```

### PSNR/SSIM values seem wrong

**Cause:** Comparing videos with different properties (resolution, framerate, codec).

**Solution:**
- Ensure reference and test have same resolution
- Use same codec and encoding parameters
- Check both videos have same frame count
- Verify colorspace matches (BT.601 vs BT.709)

### Hash-based check always fails

**Cause:** Non-deterministic encoding (timestamps, metadata, slight compression variance).

**Solution:**
- Use PSNR/SSIM instead (more robust)
- Or compare file size only (allow 1% variance)
- Or disable hash check for non-deterministic outputs

## References

- **PSNR:** https://en.wikipedia.org/wiki/Peak_signal-to-noise_ratio
- **SSIM:** https://en.wikipedia.org/wiki/Structural_similarity
- **FFmpeg PSNR filter:** https://ffmpeg.org/ffmpeg-filters.html#psnr
- **FFmpeg SSIM filter:** https://ffmpeg.org/ffmpeg-filters.html#ssim
- **Video quality assessment:** https://github.com/Netflix/vmaf (VMAF is even better but more complex)
