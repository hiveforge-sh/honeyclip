# Getting Started with Benchmarks

## First Time Setup

1. **Ensure test video exists:**
   ```bash
   ls resources/testsrc.mp4
   ```
   If missing, run the test suite first to generate test resources.

2. **Run benchmarks to establish baseline:**
   ```bash
   nimble bench
   ```
   
   Expected output:
   ```
   honeyclip Benchmark Suite
   ============================================================
   
   Running benchmarks...
   
   Running benchmark: audio_analysis
     Completed in 145ms
   Running benchmark: media_info
     Completed in 12ms
   Running benchmark: timeline_building
     Completed in 8ms
   
   No baseline to compare against
   Results saved to tests/benchmark_results.json
   
   Benchmark suite completed successfully
   ```

## Making Changes and Validating Performance

1. **Make your performance optimization**

2. **Run benchmarks again:**
   ```bash
   nimble bench
   ```

3. **Check for regressions:**
   ```
   Performance Comparison vs Baseline
   ============================================================
   audio_analysis:
     Baseline: 145ms
     Current:  132ms (-9.0%)
     Status:   IMPROVEMENT
   
   media_info:
     Baseline: 12ms
     Current:  12ms (+0.0%)
     Status:   OK
   
   timeline_building:
     Baseline: 8ms
     Current:  10ms (+25.0%)
     Status:   REGRESSION
   ============================================================
   
   WARNING: Performance regression detected!
   ```

4. **If regression is acceptable** (e.g., you added functionality):
   ```bash
   # The current results become the new baseline automatically
   # Just commit the updated benchmark_results.json
   git add tests/benchmark_results.json
   git commit -m "Update benchmark baseline after feature X"
   ```

## Understanding Results

### Performance Status
- **IMPROVEMENT**: >5% faster than baseline
- **OK**: Within ±5% of baseline
- **REGRESSION**: >15% slower than baseline (fails the build)

### Platform Differences
Baselines are platform-specific:
- Linux results only compare to Linux baseline
- macOS results only compare to macOS baseline
- Windows results only compare to Windows baseline

This prevents false positives from platform-specific performance characteristics.

## Continuous Integration

In CI, benchmarks run on every PR to catch performance regressions early.

See `.github/workflows/smoke.yml` for integration (coming soon).

## Troubleshooting

### "Benchmark video not found"
```bash
# Generate test resources
nimble test
```

### "No baseline to compare against"
This is normal on first run. The current run becomes the baseline.

### Inconsistent results
Benchmarks can vary due to:
- CPU frequency scaling
- Background processes
- Thermal throttling

For stable results:
- Close other applications
- Run multiple times and average
- Use consistent power settings (don't run on battery)

## Next Steps

See `tests/BENCHMARKS.md` for:
- Adding new benchmarks
- Quality validation
- Memory profiling
- CI integration
