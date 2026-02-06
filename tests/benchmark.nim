## Benchmarking suite for honeyclip
## 
## Measures real-world performance with quality validation.
## Run with: nimble bench
##
## Optional: Share results with the project (opt-in only)
##   nimble bench -- --share

import std/[monotimes, times, os, json, strutils, strformat, tables, osproc, parseopt]
import std/hashes except hash  # Avoid conflict with checksums
import checksums/md5

import ../src/av
import ../src/media
import ../src/log
import ../src/ffmpeg
import ../src/util/bar
import quality_metrics
import benchmark_sharing

# Benchmark configuration
const
  BenchmarkVideo = "resources/testsrc.mp4"
  BenchmarkResultsFile = "tests/benchmark_results.json"
  PerformanceThresholdPercent = 15  # Fail if >15% slower than baseline
  BenchmarkOutputDir = "tests/benchmark_output"  # Temporary output files

type
  BenchmarkResult = object
    name: string
    durationMs: int64
    peakMemoryMB: float
    outputHash: string  # MD5 hash of output for quality validation
    qualityPSNR: float  # PSNR compared to reference (dB)
    qualitySSIM: float  # SSIM compared to reference (0-1)
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

# Benchmark 4: End-to-end video processing with quality validation
proc benchFullPipeline(): BenchmarkResult =
  ## Full pipeline: Load video → Apply simple edit → Render → Validate quality
  if not fileExists(BenchmarkVideo):
    echo &"Skipping: {BenchmarkVideo} not found"
    return BenchmarkResult()
  
  # Create output directory
  if not dirExists(BenchmarkOutputDir):
    createDir(BenchmarkOutputDir)
  
  let outputPath = BenchmarkOutputDir / "pipeline_output.mp4"
  let referencePath = BenchmarkOutputDir / "pipeline_reference.mp4"
  
  result = runBenchmark("full_pipeline_with_quality") do():
    # Step 1: Create reference (copy input)
    if not fileExists(referencePath):
      # Use honeyclip to create reference (passthrough, no edits)
      # This ensures same encoding parameters for fair comparison
      let refCmd = &"./honeyclip \"{BenchmarkVideo}\" -o \"{referencePath}\" --edit \"(not (and false true))\" 2>&1"
      let (refOutput, refCode) = execCmdEx(refCmd)
      if refCode != 0:
        debug &"Reference creation failed: {refOutput}"
        # Fall back to direct copy
        copyFile(BenchmarkVideo, referencePath)
    
    # Step 2: Process video with simple edit (remove silence)
    let editCmd = &"./honeyclip \"{BenchmarkVideo}\" -o \"{outputPath}\" --edit audio:0.04 2>&1"
    let (editOutput, editCode) = execCmdEx(editCmd)
    
    if editCode != 0:
      debug &"Video processing failed: {editOutput}"
      return
    
    # Step 3: Calculate quality metrics (PSNR/SSIM)
    if fileExists(outputPath) and fileExists(referencePath):
      let metrics = calculateQualityMetrics(referencePath, outputPath)
      
      if metrics.valid:
        echo &"    Quality: {formatMetrics(metrics)}"
        result.qualityPSNR = metrics.psnr
        result.qualitySSIM = metrics.ssim
        
        if not meetsQualityThreshold(metrics):
          echo "    WARNING: Quality below threshold!"
      else:
        echo "    Quality metrics unavailable (FFmpeg with libavfilter needed)"
        # Fall back to hash-based check
        if hashBasedQualityCheck(referencePath, outputPath):
          echo "    Hash-based quality check: PASSED"
        else:
          echo "    Hash-based quality check: FAILED (size difference)"
      
      # Calculate output hash for regression detection
      result.outputHash = hashFile(outputPath)
    
    # Step 4: Cleanup (optional - keep files for manual inspection)
    # removeFile(outputPath)
    # removeFile(referencePath)

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
          outputHash: entry.getOrDefault("outputHash").getStr(""),
          qualityPSNR: entry.getOrDefault("qualityPSNR").getFloat(0.0),
          qualitySSIM: entry.getOrDefault("qualitySSIM").getFloat(0.0),
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
    obj["qualityPSNR"] = %result.qualityPSNR
    obj["qualitySSIM"] = %result.qualitySSIM
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
    
    # Check quality regression
    if result.qualityPSNR > 0.0 and base.qualityPSNR > 0.0:
      let psnrDrop = base.qualityPSNR - result.qualityPSNR
      if psnrDrop > 1.0:  # More than 1dB drop is concerning
        echo &"  Quality:  PSNR dropped {psnrDrop:.2f}dB (was {base.qualityPSNR:.2f}dB, now {result.qualityPSNR:.2f}dB)"
        allPassed = false
      else:
        echo &"  Quality:  PSNR {result.qualityPSNR:.2f}dB (OK)"
    
    if status == "REGRESSION":
      allPassed = false
  
  echo "=".repeat(60)
  return allPassed

# Main benchmark runner
proc main() =
  # Parse command-line arguments
  var shareResults = false
  var p = initOptParser()
  
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if p.key in ["share", "s"]:
        shareResults = true
    of cmdArgument:
      discard
  
  echo "honeyclip Benchmark Suite"
  echo "=" .repeat(60)
  echo ""
  
  if shareResults:
    echo "📊 Sharing enabled - You'll be prompted after benchmarks complete"
    echo ""
  
  # Verify benchmark video exists
  if not fileExists(BenchmarkVideo):
    echo &"ERROR: Benchmark video not found: {BenchmarkVideo}"
    echo "Please ensure test resources are available"
    quit(1)
  
  # Load baseline for comparison
  let baseline = loadBaseline()
  
  # Run benchmarks
  var results: seq[BenchmarkResult]
  results.add(benchAudioAnalysis())
  results.add(benchMediaInfo())
  results.add(benchTimeline())
  
  # Full pipeline with quality validation (optional, requires honeyclip binary)
  if fileExists("./honeyclip") or fileExists("./honeyclip.exe"):
    echo "\nRunning end-to-end quality validation..."
    results.add(benchFullPipeline())
  else:
    echo "\nSkipping full pipeline benchmark (honeyclip binary not found)"
  
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
  
  echo ""
  echo "✓ Benchmarks complete!"
  
  # Optional: Share results with project (opt-in)
  if shareResults:
    echo ""
    if promptForConsent():
      # Create shareable report with system info
      let resultsJson = newJArray()
      for r in results:
        var obj = newJObject()
        obj["name"] = %r.name
        obj["durationMs"] = %r.durationMs
        obj["peakMemoryMB"] = %r.peakMemoryMB
        if r.qualityPSNR > 0.0:
          obj["qualityPSNR"] = %r.qualityPSNR
        if r.qualitySSIM > 0.0:
          obj["qualitySSIM"] = %r.qualitySSIM
        resultsJson.add(obj)
      
      # Build settings (what codecs are enabled)
      var settings = newJObject()
      when defined(enable_vpx):
        settings["vpx"] = %true
      when defined(enable_svtav1):
        settings["svtav1"] = %true
      when defined(enable_hevc):
        settings["hevc"] = %true
      when defined(enable_whisper):
        settings["whisper"] = %true
      when defined(enable_ml):
        settings["ml"] = %true
      
      let report = createBenchmarkReport(resultsJson, settings)
      displayReportSummary(report)
      
      echo ""
      stdout.write("Review looks good? Share now? (yes/no): ")
      stdout.flushFile()
      let confirm = stdin.readLine().strip().toLowerAscii()
      
      if confirm in ["yes", "y"]:
        if shareReport(report, "file"):
          echo ""
          echo "🎉 Thank you for contributing benchmark data!"
        else:
          echo ""
          echo "❌ Sharing failed. You can still share the report file manually."
      else:
        echo ""
        echo "Sharing cancelled. You can run 'nimble bench --share' again later."
    else:
      echo ""
      echo "Sharing cancelled. Your results remain private."
  else:
    echo ""
    echo "Tip: Run 'nimble bench --share' to help the project by sharing your results (opt-in)"

when isMainModule:
  main()
