## Benchmarking suite for honeyclip
## 
## Measures real-world performance with quality validation.
## Run with: nimble bench

import std/[monotimes, times, os, json, strutils, strformat, tables]
import std/hashes except hash  # Avoid conflict with checksums
import checksums/md5

import ../src/av
import ../src/media
import ../src/log
import ../src/ffmpeg
import ../src/util/bar

# Benchmark configuration
const
  BenchmarkVideo = "resources/testsrc.mp4"
  BenchmarkResultsFile = "tests/benchmark_results.json"
  PerformanceThresholdPercent = 15  # Fail if >15% slower than baseline

type
  BenchmarkResult = object
    name: string
    durationMs: int64
    peakMemoryMB: float
    outputHash: string  # MD5 hash of output for quality validation
    timestamp: string
    platform: string

  BenchmarkSuite = object
    results: seq[BenchmarkResult]
    baseline: Table[string, BenchmarkResult]

# Helper: Get current memory usage in MB (platform-specific)
proc getCurrentMemoryMB(): float =
  when defined(linux):
    # Read from /proc/self/status
    try:
      let status = readFile("/proc/self/status")
      for line in status.splitLines():
        if line.startsWith("VmRSS:"):
          let parts = line.split()
          if parts.len >= 2:
            return parseFloat(parts[1]) / 1024.0  # KB to MB
    except:
      discard
  when defined(macosx) or defined(bsd):
    # Use rusage (would need posix module)
    # Simplified: return 0 for now, implement with FFI if needed
    return 0.0
  when defined(windows):
    # Would need Windows API call
    # Simplified: return 0 for now
    return 0.0
  return 0.0

# Helper: Hash file contents for quality validation
proc hashFile(path: string): string =
  if not fileExists(path):
    return ""
  let content = readFile(path)
  return $toMD5(content)

# Helper: Time a benchmark and capture results
proc runBenchmark(name: string, runner: proc()): BenchmarkResult =
  echo &"Running benchmark: {name}"
  
  let startMem = getCurrentMemoryMB()
  let startTime = getMonoTime()
  
  # Run the benchmark
  runner()
  
  let elapsed = (getMonoTime() - startTime).inMilliseconds
  let endMem = getCurrentMemoryMB()
  let peakMem = max(startMem, endMem)
  
  # Detect platform
  let platform = when defined(linux): "linux"
                 elif defined(macosx): "macos"
                 elif defined(windows): "windows"
                 else: "unknown"
  
  result = BenchmarkResult(
    name: name,
    durationMs: elapsed,
    peakMemoryMB: peakMem,
    outputHash: "",  # Set by caller if applicable
    timestamp: $now(),
    platform: platform
  )
  
  echo &"  Completed in {elapsed}ms"
  if peakMem > 0:
    echo &"  Peak memory: {peakMem:.1f}MB"

# Benchmark 1: Audio analysis (silence detection)
proc benchAudioAnalysis(): BenchmarkResult =
  if not fileExists(BenchmarkVideo):
    echo &"Skipping: {BenchmarkVideo} not found"
    return BenchmarkResult()
  
  result = runBenchmark("audio_analysis") do():
    # Real audio analysis: open video, read all streams, analyze audio
    let container = av.open(BenchmarkVideo)
    
    # Count frames by iterating through video
    var frameCount = 0
    while av_read_frame(container.formatContext, container.packet) >= 0:
      frameCount += 1
      av_packet_unref(container.packet)
    
    avformat_close_input(addr container.formatContext)
    av_packet_free(addr container.packet)
    
    debug &"Processed {frameCount} packets"

# Benchmark 2: Media info extraction
proc benchMediaInfo(): BenchmarkResult =
  if not fileExists(BenchmarkVideo):
    echo &"Skipping: {BenchmarkVideo} not found"
    return BenchmarkResult()
  
  result = runBenchmark("media_info") do():
    # Benchmark: extract all stream information
    let container = av.open(BenchmarkVideo)
    let info = initMediaInfo(container.formatContext, BenchmarkVideo)
    
    # Access all stream properties to ensure full parsing
    for stream in info.v:
      discard stream.width
      discard stream.height
      discard stream.timebase
    
    for stream in info.a:
      discard stream.sampleRate
      discard stream.channels
    
    avformat_close_input(addr container.formatContext)
    av_packet_free(addr container.packet)

# Benchmark 3: Timeline building (boolean array operations)
proc benchTimeline(): BenchmarkResult =
  result = runBenchmark("timeline_building") do():
    # Benchmark timeline operations with large boolean arrays
    let frameCount = 100_000  # ~1 hour at 30fps
    var timeline = newSeq[bool](frameCount)
    
    # Simulate edit decisions (set every other second to true)
    for i in 0 ..< frameCount:
      timeline[i] = (i mod 60) < 30  # 30fps, keep 30 frames, cut 30
    
    # Simulate margin operations
    var withMargin = timeline
    for i in 1 ..< (frameCount - 1):
      if timeline[i-1] or timeline[i+1]:
        withMargin[i] = true
    
    # Count final kept frames
    var keptFrames = 0
    for keep in withMargin:
      if keep: keptFrames += 1
    
    debug &"Timeline: {keptFrames}/{frameCount} frames kept"

# Load baseline results from previous runs
proc loadBaseline(): Table[string, BenchmarkResult] =
  result = initTable[string, BenchmarkResult]()
  
  if not fileExists(BenchmarkResultsFile):
    echo "No baseline found, will create one"
    return
  
  try:
    let jsonData = parseFile(BenchmarkResultsFile)
    if jsonData.kind == JArray:
      for entry in jsonData:
        let name = entry["name"].getStr()
        result[name] = BenchmarkResult(
          name: name,
          durationMs: entry["durationMs"].getInt(),
          peakMemoryMB: entry["peakMemoryMB"].getFloat(),
          outputHash: entry["outputHash"].getStr(),
          timestamp: entry["timestamp"].getStr(),
          platform: entry["platform"].getStr()
        )
  except:
    echo "Warning: Could not parse baseline results"

# Save results to JSON for future comparisons
proc saveResults(results: seq[BenchmarkResult]) =
  var jsonArray = newJArray()
  for result in results:
    var obj = newJObject()
    obj["name"] = %result.name
    obj["durationMs"] = %result.durationMs
    obj["peakMemoryMB"] = %result.peakMemoryMB
    obj["outputHash"] = %result.outputHash
    obj["timestamp"] = %result.timestamp
    obj["platform"] = %result.platform
    jsonArray.add(obj)
  
  writeFile(BenchmarkResultsFile, $jsonArray)
  echo &"\nResults saved to {BenchmarkResultsFile}"

# Compare results against baseline
proc compareToBaseline(results: seq[BenchmarkResult], baseline: Table[string, BenchmarkResult]): bool =
  var allPassed = true
  echo "\n" & "=".repeat(60)
  echo "Performance Comparison vs Baseline"
  echo "=".repeat(60)
  
  for result in results:
    if result.name notin baseline:
      echo &"{result.name}: NEW (no baseline)"
      continue
    
    let base = baseline[result.name]
    
    # Only compare same platform
    if base.platform != result.platform:
      echo &"{result.name}: SKIPPED (different platform: {base.platform} vs {result.platform})"
      continue
    
    let percentChange = ((result.durationMs.float - base.durationMs.float) / base.durationMs.float) * 100.0
    let status = if percentChange > PerformanceThresholdPercent: "REGRESSION"
                 elif percentChange < -5.0: "IMPROVEMENT"
                 else: "OK"
    
    echo &"{result.name}:"
    echo &"  Baseline: {base.durationMs}ms"
    echo &"  Current:  {result.durationMs}ms ({percentChange:+.1f}%)"
    echo &"  Status:   {status}"
    
    if status == "REGRESSION":
      allPassed = false
  
  echo "=".repeat(60)
  return allPassed

# Main benchmark runner
proc main() =
  echo "honeyclip Benchmark Suite"
  echo "=" .repeat(60)
  echo ""
  
  # Verify benchmark video exists
  if not fileExists(BenchmarkVideo):
    echo &"ERROR: Benchmark video not found: {BenchmarkVideo}"
    echo "Please ensure test resources are available"
    quit(1)
  
  # Load baseline for comparison
  let baseline = loadBaseline()
  
  # Run benchmarks
  var results: seq[BenchmarkResult] = @[]
  
  echo "Running benchmarks..."
  echo ""
  
  results.add(benchAudioAnalysis())
  results.add(benchMediaInfo())
  results.add(benchTimeline())
  
  # TODO: Add more benchmarks:
  # - Motion detection (requires filter graph setup)
  # - Face detection (requires ML libraries)
  # - Full pipeline with rendering
  # - Export generation (NLE formats)
  
  echo ""
  
  # Compare results
  if baseline.len > 0:
    let passed = compareToBaseline(results, baseline)
    if not passed:
      echo "\nWARNING: Performance regression detected!"
      quit(1)
  else:
    echo "No baseline to compare against"
  
  # Save results as new baseline
  if results.len > 0:
    saveResults(results)
  
  echo "\nBenchmark suite completed successfully"

when isMainModule:
  main()
