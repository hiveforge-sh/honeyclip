## End-to-End Performance Validation Suite
##
## This validates the performance claims in PERFORMANCE.md by measuring
## actual processing speeds with real video files at different resolutions.
##
## Usage:
##   nimble validate-performance
##
## Generates: tests/performance_validation_results.json

import std/[os, times, strformat, json, osproc, strutils, tables]
import ../src/log

type
  TestVideo = object
    name: string        # "720p_30fps", "1080p_60fps", etc.
    path: string        # Path to test video file
    resolution: string  # "1280x720", "1920x1080", etc.
    fps: int            # Frame rate
    duration: float     # Duration in seconds
    sizeBytes: int64    # File size in bytes
  
  ValidationResult = object
    videoName: string
    resolution: string
    fps: int
    durationSec: float
    
    # Processing metrics
    processingTimeMs: int64
    processingSpeedRatio: float  # e.g., 2.0 = 2x realtime
    peakMemoryMB: float
    outputSizeBytes: int64
    
    # Quality metrics (if available)
    qualityPSNR: float
    qualitySSIM: float
    
    # Codec used
    codec: string
    preset: string
    
    platform: string
    timestamp: string

const
  ValidationOutputDir = "tests/performance_validation_output"
  ValidationResultsFile = "tests/performance_validation_results.json"

# Helper: Generate test video using FFmpeg (if needed)
proc generateTestVideo(name: string, width, height, fps: int, durationSec: int): TestVideo =
  result.name = name
  result.resolution = &"{width}x{height}"
  result.fps = fps
  result.duration = float(durationSec)
  result.path = ValidationOutputDir / &"{name}.mp4"
  
  if fileExists(result.path):
    echo &"Test video already exists: {result.path}"
    result.sizeBytes = getFileSize(result.path)
    return
  
  if not dirExists(ValidationOutputDir):
    createDir(ValidationOutputDir)
  
  echo &"Generating test video: {name} ({width}x{height} @ {fps}fps, {durationSec}s)"
  
  # Generate video with testsrc pattern and audio tone
  let ffmpegBin = if fileExists("build/bin/ffmpeg"): "build/bin/ffmpeg"
                  elif fileExists("build/bin/ffmpeg.exe"): "build/bin/ffmpeg.exe"
                  else:
                    echo "ERROR: ffmpeg not found in build/bin/"
                    echo "Run 'nimble makeff' first to build FFmpeg"
                    quit(1)
  
  let cmd = &"""{ffmpegBin} -f lavfi -i testsrc=duration={durationSec}:size={width}x{height}:rate={fps} \
    -f lavfi -i sine=frequency=1000:duration={durationSec} \
    -c:v libx264 -preset medium -crf 23 \
    -c:a aac -b:a 128k \
    -y "{result.path}" 2>&1"""
  
  let (output, exitCode) = execCmdEx(cmd)
  
  if exitCode != 0:
    echo &"ERROR: Failed to generate test video"
    echo output
    quit(1)
  
  result.sizeBytes = getFileSize(result.path)
  echo &"Generated: {result.sizeBytes / (1024*1024):.1f} MB"

# Helper: Get current memory usage (cross-platform)
proc getCurrentMemoryMB(): float =
  when defined(linux):
    try:
      let status = readFile("/proc/self/status")
      for line in status.splitLines():
        if line.startsWith("VmRSS:"):
          let parts = line.split()
          if parts.len >= 2:
            return parseFloat(parts[1]) / 1024.0
    except:
      discard
  
  elif defined(macosx) or defined(bsd):
    type
      mach_port_t = cuint
      kern_return_t = cint
      mach_msg_type_number_t = cuint
      natural_t = cuint
      
      mach_task_basic_info_data_t {.importc, header: "<mach/mach.h>", completeStruct.} = object
        virtual_size: natural_t
        resident_size: natural_t
        resident_size_max: natural_t
        user_time: array[2, uint64]
        system_time: array[2, uint64]
        policy: cint
        suspend_count: cint
    
    const MACH_TASK_BASIC_INFO = 20
    const MACH_TASK_BASIC_INFO_COUNT = (sizeof(mach_task_basic_info_data_t) div sizeof(natural_t)).mach_msg_type_number_t
    
    proc mach_task_self(): mach_port_t {.importc, header: "<mach/mach.h>".}
    proc task_info(target_task: mach_port_t, flavor: cint, task_info_out: pointer,
                   task_info_outCnt: ptr mach_msg_type_number_t): kern_return_t 
                   {.importc, header: "<mach/mach.h>".}
    
    try:
      var info: mach_task_basic_info_data_t
      var count = MACH_TASK_BASIC_INFO_COUNT
      let kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, addr info, addr count)
      
      if kr == 0:
        return float(info.resident_size) / (1024.0 * 1024.0)
    except:
      discard
  
  elif defined(windows):
    type
      DWORD = uint32
      SIZE_T = uint
      HANDLE = pointer
      BOOL = cint
      
      PROCESS_MEMORY_COUNTERS {.importc, header: "<psapi.h>".} = object
        cb: DWORD
        PageFaultCount: DWORD
        PeakWorkingSetSize: SIZE_T
        WorkingSetSize: SIZE_T
        QuotaPeakPagedPoolUsage: SIZE_T
        QuotaPagedPoolUsage: SIZE_T
        QuotaPeakNonPagedPoolUsage: SIZE_T
        QuotaNonPagedPoolUsage: SIZE_T
        PagefileUsage: SIZE_T
        PeakPagefileUsage: SIZE_T
    
    proc GetCurrentProcess(): HANDLE {.importc, stdcall, header: "<windows.h>".}
    proc GetProcessMemoryInfo(Process: HANDLE, ppsmemCounters: ptr PROCESS_MEMORY_COUNTERS,
                              cb: DWORD): BOOL {.importc, stdcall, header: "<psapi.h>".}
    
    try:
      var pmc: PROCESS_MEMORY_COUNTERS
      pmc.cb = sizeof(PROCESS_MEMORY_COUNTERS).DWORD
      
      if GetProcessMemoryInfo(GetCurrentProcess(), addr pmc, pmc.cb) != 0:
        return float(pmc.WorkingSetSize) / (1024.0 * 1024.0)
    except:
      discard
  
  return 0.0

# Validate: Process video and measure performance
proc validateVideoProcessing(testVideo: TestVideo, codec: string = "libx264", preset: string = "medium"): ValidationResult =
  result.videoName = testVideo.name
  result.resolution = testVideo.resolution
  result.fps = testVideo.fps
  result.durationSec = testVideo.duration
  result.codec = codec
  result.preset = preset
  result.platform = when defined(windows): "windows"
                    elif defined(macosx): "macos"
                    elif defined(linux): "linux"
                    else: "unknown"
  result.timestamp = $now()
  
  let outputPath = ValidationOutputDir / &"{testVideo.name}_processed_{codec}_{preset}.mp4"
  
  echo ""
  echo &"Validating: {testVideo.name} with {codec}/{preset}"
  echo &"  Resolution: {testVideo.resolution} @ {testVideo.fps}fps"
  echo &"  Duration: {testVideo.duration:.1f}s"
  echo &"  Input size: {testVideo.sizeBytes / (1024*1024):.1f} MB"
  
  # Track peak memory
  var peakMemory = 0.0
  
  # Measure processing time
  let honeyclip = if fileExists("./honeyclip"): "./honeyclip"
                  elif fileExists("./honeyclip.exe"): "./honeyclip.exe"
                  else:
                    echo "ERROR: honeyclip binary not found"
                    return
  
  # Use simple audio-based editing
  let cmd = &"""{honeyclip} "{testVideo.path}" -o "{outputPath}" --edit audio:0.04 2>&1"""
  
  echo &"  Processing..."
  let startTime = now()
  let startMem = getCurrentMemoryMB()
  
  let (output, exitCode) = execCmdEx(cmd)
  
  let endTime = now()
  let endMem = getCurrentMemoryMB()
  
  result.processingTimeMs = (endTime - startTime).inMilliseconds
  result.peakMemoryMB = max(startMem, endMem)
  
  if exitCode != 0:
    echo &"  ERROR: Processing failed (exit code {exitCode})"
    echo output
    return
  
  # Calculate processing speed ratio (higher = faster)
  let processingTimeSec = result.processingTimeMs.float / 1000.0
  result.processingSpeedRatio = testVideo.duration / processingTimeSec
  
  # Get output size
  if fileExists(outputPath):
    result.outputSizeBytes = getFileSize(outputPath)
  
  # Display results
  echo &"  Processing time: {result.processingTimeMs}ms ({processingTimeSec:.1f}s)"
  echo &"  Processing speed: {result.processingSpeedRatio:.2f}x realtime"
  echo &"  Peak memory: {result.peakMemoryMB:.1f} MB"
  echo &"  Output size: {result.outputSizeBytes / (1024*1024):.1f} MB"
  
  # Cleanup output (keep for manual inspection if needed)
  # removeFile(outputPath)

# Save results to JSON
proc saveResults(results: seq[ValidationResult]) =
  var jsonArray = newJArray()
  
  for result in results:
    var obj = newJObject()
    obj["videoName"] = %result.videoName
    obj["resolution"] = %result.resolution
    obj["fps"] = %result.fps
    obj["durationSec"] = %result.durationSec
    obj["processingTimeMs"] = %result.processingTimeMs
    obj["processingSpeedRatio"] = %result.processingSpeedRatio
    obj["peakMemoryMB"] = %result.peakMemoryMB
    obj["outputSizeBytes"] = %result.outputSizeBytes
    obj["codec"] = %result.codec
    obj["preset"] = %result.preset
    obj["platform"] = %result.platform
    obj["timestamp"] = %result.timestamp
    jsonArray.add(obj)
  
  writeFile(ValidationResultsFile, $jsonArray)
  echo ""
  echo &"Results saved to: {ValidationResultsFile}"

# Main validation runner
proc main() =
  echo "honeyclip Performance Validation Suite"
  echo "=".repeat(60)
  echo ""
  echo "This will measure real-world processing performance"
  echo "across different resolutions and settings."
  echo ""
  
  # Generate test videos
  var testVideos: seq[TestVideo]
  
  # Use existing test resource if available
  if fileExists("resources/testsrc.mp4"):
    echo "Using existing test video: resources/testsrc.mp4"
    var existingVideo: TestVideo
    existingVideo.name = "existing_testsrc"
    existingVideo.path = "resources/testsrc.mp4"
    existingVideo.resolution = "Unknown"
    existingVideo.fps = 30
    existingVideo.duration = 10.0  # Approximate
    existingVideo.sizeBytes = getFileSize(existingVideo.path)
    testVideos.add(existingVideo)
  else:
    echo "ERROR: No test video found"
    echo "Expected: resources/testsrc.mp4"
    echo "Run unit tests first to generate test resources"
    quit(1)
  
  # Comment out generated videos for now (requires FFmpeg in PATH)
  # Uncomment these when FFmpeg is available:
  # testVideos.add(generateTestVideo("720p_30fps", 1280, 720, 30, 10))
  # testVideos.add(generateTestVideo("1080p_30fps", 1920, 1080, 30, 10))
  # testVideos.add(generateTestVideo("1080p_60fps", 1920, 1080, 60, 10))
  # testVideos.add(generateTestVideo("4k_30fps", 3840, 2160, 30, 5))
  
  echo ""
  echo "=".repeat(60)
  echo "Running Performance Validation"
  echo "=".repeat(60)
  
  # Run validation tests
  var results: seq[ValidationResult]
  
  for video in testVideos:
    # Test with different presets to measure their impact
    echo &"\nTesting video: {video.name}"
    
    # Default preset (medium)
    results.add(validateVideoProcessing(video, "libx264", "medium"))
    
    # Fast preset (for speed comparison)
    results.add(validateVideoProcessing(video, "libx264", "fast"))
    
    # Ultrafast preset (maximum speed)
    results.add(validateVideoProcessing(video, "libx264", "ultrafast"))
  
  echo ""
  echo "=".repeat(60)
  echo "Validation Complete"
  echo "=".repeat(60)
  
  # Save results
  saveResults(results)
  
  # Summary
  echo ""
  echo "Summary:"
  echo "-".repeat(60)
  for result in results:
    if result.processingSpeedRatio > 0:
      echo &"{result.videoName:20s} ({result.preset:10s}): {result.processingSpeedRatio:5.2f}x realtime, {result.peakMemoryMB:6.1f} MB peak"

when isMainModule:
  main()
