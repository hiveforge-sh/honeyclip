# Benchmark Sharing

honeyclip allows users to **optionally** share benchmark results with the project to help gather real-world performance data across different platforms and hardware configurations.

## Privacy First

**All sharing is OPT-IN and requires explicit user consent.**

- ✅ **Opt-in only** - Never sends data automatically
- ✅ **Explicit consent** - You must approve before sharing
- ✅ **Transparent** - Shows exactly what will be shared
- ✅ **Review first** - See the full report before sharing
- ✅ **Anonymous** - No personal information collected

## How to Share Results

### Run benchmarks with --share flag:

```bash
nimble bench -- --share
```

### You'll be prompted:

```
Share Benchmark Results
============================================================

Would you like to share your benchmark results with the project?

This helps us:
  • Understand real-world performance across different hardware
  • Optimize for common configurations
  • Validate performance claims

What will be shared:
  • Benchmark timings (ms)
  • OS and architecture (e.g., 'macOS 14.2 x86_64')
  • CPU model and core count
  • RAM amount
  • Compiler version

What will NOT be shared:
  • Your name, email, or any personal information
  • IP address or location
  • File paths or data from your system
  • Anything else not listed above

You can review the full report before sharing.
============================================================
Share results? (yes/no):
```

### Review the report:

```
Benchmark Report Summary
============================================================
Version:      1.0
Timestamp:    2026-02-06 15:30:45

System Information:
  OS:         macOS 14.2 (x86_64)
  CPU:        Intel Core i7-9700K
  Cores:      8 physical, 8 logical
  RAM:        32GB
  Compiler:   Nim Compiler Version 2.2.6

Benchmark Results:
  audio_analysis: 2ms
  media_info: 1ms
  timeline_building: 3ms
  full_pipeline_with_quality: 5123ms
============================================================

Review looks good? Share now? (yes/no):
```

### Confirm and share:

```
Benchmark report saved!

To share with the project:
  1. Review the file: benchmark_report_20260206_153045.json
  2. Create a GitHub issue: https://github.com/hiveforge-sh/honeyclip/issues/new
  3. Title: 'Benchmark Results: [Your CPU/OS]'
  4. Paste the contents of the report file

Thank you for contributing!

🎉 Thank you for contributing benchmark data!
```

## What Gets Shared

### System Information (Anonymous)

- **OS**: Operating system name and version (e.g., "macOS 14.2", "Ubuntu 24.04")
- **Architecture**: CPU architecture (e.g., "x86_64", "aarch64")
- **CPU Model**: Processor name (e.g., "Intel Core i7-9700K", "Apple M2")
- **CPU Cores**: Physical and logical core count
- **RAM**: Total system memory in GB
- **Compiler**: Nim and GCC versions used to build

### Benchmark Results

- **Timings**: How long each benchmark took (milliseconds)
- **Memory**: Peak memory usage during benchmarks (MB)
- **Quality Metrics**: PSNR and SSIM scores (if available)

### Build Settings

- **Enabled Codecs**: VP8/VP9, SVT-AV1, HEVC, etc.
- **Features**: Whisper, ML support

### Example Report

```json
{
  "version": "1.0",
  "timestamp": "2026-02-06T15:30:45-08:00",
  "system": {
    "os": "macos",
    "osVersion": "macOS 14.2",
    "arch": "x86_64",
    "cpuModel": "Intel Core i7-9700K CPU @ 3.60GHz",
    "cpuCores": 8,
    "cpuThreads": 8,
    "ramGB": 32,
    "compiler": "Nim Compiler Version 2.2.6 [MacOSX: amd64]"
  },
  "results": [
    {
      "name": "audio_analysis",
      "durationMs": 2,
      "peakMemoryMB": 45.2
    },
    {
      "name": "full_pipeline_with_quality",
      "durationMs": 5123,
      "peakMemoryMB": 187.5,
      "qualityPSNR": 38.21,
      "qualitySSIM": 0.9877
    }
  ],
  "settings": {
    "vpx": true,
    "svtav1": true,
    "hevc": true,
    "whisper": true,
    "ml": true
  }
}
```

## What Does NOT Get Shared

We **never** collect:

- ❌ Your name, email, or username
- ❌ IP address or geographic location
- ❌ File paths or filenames from your system
- ❌ Video content or any media files
- ❌ Environment variables
- ❌ Command history
- ❌ Any other personal or identifying information

## Why Share?

Your benchmark data helps us:

### Understand Real-World Performance

- How does honeyclip perform on different CPUs? (Intel vs AMD vs Apple Silicon)
- What's the performance difference between platforms? (macOS vs Linux vs Windows)
- How much RAM is actually needed? (8GB vs 16GB vs 32GB)

### Optimize for Common Configurations

- Identify performance bottlenecks on popular hardware
- Prioritize optimizations for most-used platforms
- Validate that optimizations don't hurt common cases

### Validate Performance Claims

- "10x realtime on modern CPUs" - is this accurate across hardware?
- Quality metrics across different builds and settings
- Memory usage patterns

### Improve Documentation

- Update PERFORMANCE.md with real-world numbers
- Set realistic expectations for different hardware
- Provide hardware recommendations

## Declining to Share

You can always decline:

```
Share results? (yes/no): no

Sharing cancelled. Your results remain private.
```

Or don't use the `--share` flag:

```bash
nimble bench  # No sharing prompt
```

Your benchmarks still run and save locally for regression detection. Sharing is completely optional.

## Manual Sharing

If you decline automatic sharing but change your mind later:

1. **Find the report file**: `benchmark_report_YYYYMMDD_HHMMSS.json`
2. **Review it**: Ensure you're comfortable with what's in it
3. **Create a GitHub issue**: https://github.com/hiveforge-sh/honeyclip/issues/new
4. **Title**: "Benchmark Results: [Your CPU/OS]"
5. **Paste the JSON**: Include the full report

## Privacy Policy

We respect your privacy:

- **No tracking**: We don't track who submits reports
- **No correlation**: Can't link multiple reports from the same person
- **Public data**: All shared reports may be made public (in aggregated form)
- **Deletion**: Contact us to remove your submission if desired

## Future: Automated Sharing

In the future, we may add automated sharing via GitHub App:

- Still opt-in only
- Same privacy guarantees
- Easier contribution process

But for now, manual sharing ensures full transparency.

## Questions?

- **Q: Can you identify me from the report?**
  - A: No. We only collect anonymous hardware/software info.

- **Q: What if I have a unique CPU?**
  - A: Still anonymous. We can't link it to you personally.

- **Q: Can I share results for multiple machines?**
  - A: Yes! Run benchmarks on each machine and share separately.

- **Q: Will sharing slow down benchmarks?**
  - A: No. Sharing happens after benchmarks complete.

- **Q: Can I edit the report before sharing?**
  - A: Yes. Review and modify the JSON file before posting.

- **Q: What if I accidentally share?**
  - A: Contact us to remove the submission.

## Thank You!

Community contributions make open source better. If you choose to share your benchmark results, **thank you for helping improve honeyclip for everyone!** 🎉
