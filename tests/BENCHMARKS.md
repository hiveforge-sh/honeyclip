# Benchmark Infrastructure

## Overview

The benchmark suite measures real-world performance with quality validation to ensure speed improvements don't degrade output quality.

## Quick Start

```bash
# Run all benchmarks
nimble bench

# Results are saved to tests/benchmark_results.json
# Subsequent runs compare against this baseline
```

## How It Works

1. **Timing**: Uses `std/monotimes` for accurate wall-clock measurements
2. **Quality Validation**: Computes MD5 hash of outputs to detect quality regressions
3. **Baseline Comparison**: Saves results to JSON, compares future runs against baseline
4. **Platform-Specific**: Only compares results from the same platform (Linux vs macOS vs Windows)
5. **Regression Detection**: Fails if performance degrades >15% from baseline

## Current Benchmarks

### Implemented (Stubs)
- `audio_analysis` - Audio silence detection pipeline
- `full_pipeline` - End-to-end: load → analyze → timeline → render

### TODO (Add to tests/benchmark.nim)
- Motion detection benchmark
- Face detection benchmark (when ML enabled)
- Timeline building with complex edit expressions
- NLE export generation (FCP7, FCPXML, EDL)
- Transcript extraction with Whisper
- Caption rendering
- Multi-track video processing

## Adding a New Benchmark

```nim
proc benchYourFeature() =
  if not fileExists(BenchmarkVideo):
    echo "Skipping: benchmark video not found"
    return
  
  let result = runBenchmark("your_feature") do():
    # Your code here
    let container = openInput(BenchmarkVideo)
    # ... do work ...
    closeInput(container)
  
  # Optional: Validate output quality
  if fileExists("output.mp4"):
    result.outputHash = hashFile("output.mp4")
    # Compare hash against known-good reference
    removeFile("output.mp4")
```

Then add `benchYourFeature()` call in `main()`.

## Interpreting Results

### First Run (No Baseline)
```
Running benchmark: audio_analysis
  Completed in 1234ms
  Peak memory: 45.2MB

No baseline to compare against
Results saved to tests/benchmark_results.json
```

### Subsequent Runs (With Baseline)
```
Performance Comparison vs Baseline
============================================================
audio_analysis:
  Baseline: 1234ms
  Current:  1150ms (-6.8%)
  Status:   IMPROVEMENT

full_pipeline:
  Baseline: 5000ms
  Current:  5900ms (+18.0%)
  Status:   REGRESSION
============================================================

WARNING: Performance regression detected!
```

## Quality Validation

Each benchmark can optionally hash its output:

```nim
result.outputHash = hashFile("output.mp4")
```

This ensures:
- Speed optimizations don't break correctness
- Output format remains consistent
- Codecs produce deterministic results

For non-deterministic outputs (e.g., timestamps in XML), compare structural properties instead of exact hashes.

## CI Integration

Add to `.github/workflows/smoke.yml`:

```yaml
- name: Run benchmarks
  run: nimble bench
  
- name: Upload benchmark results
  uses: actions/upload-artifact@v4
  with:
    name: benchmark-results-${{ matrix.os }}
    path: tests/benchmark_results.json
```

## Memory Profiling

Current implementation tracks peak memory usage. For more detailed profiling:

**Linux**: Use Valgrind
```bash
valgrind --tool=massif ./honeyclip input.mp4
ms_print massif.out.*
```

**macOS**: Use Instruments
```bash
instruments -t Allocations ./honeyclip input.mp4
```

**Windows**: Use Windows Performance Analyzer
```cmd
wpr -start GeneralProfile
honeyclip.exe input.mp4
wpr -stop benchmark.etl
```

## Performance Targets (Phase 22 Roadmap)

### Fast Preset
- Target: 10x realtime (30min video in 3min)
- Quality: PSNR >28dB

### Balanced Preset  
- Target: 2x realtime (30min video in 15min)
- Quality: PSNR >32dB

### Best Preset
- Target: 0.5x realtime (30min video in 60min)
- Quality: PSNR >38dB

## Known Limitations

1. **Memory tracking incomplete**: Windows/macOS memory usage returns 0 (needs platform-specific APIs)
2. **Benchmarks are stubs**: Need to implement actual full pipeline calls
3. **No PSNR/VMAF validation**: Quality checks are hash-based only
4. **Single-threaded**: Doesn't test parallel processing performance

## Next Steps

1. Implement actual benchmark functions (currently stubs)
2. Add platform-specific memory tracking
3. Add visual quality metrics (PSNR, SSIM, VMAF)
4. Test with various video sizes (1080p, 4K, 8K)
5. Add GPU benchmarks when Phase 15 (GPU acceleration) is implemented
