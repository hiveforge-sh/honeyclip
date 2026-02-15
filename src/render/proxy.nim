## Proxy preview generation with hardware-accelerated encoding
##
## Generates 720p proxy videos for fast review before full renders.
## Auto-selects hardware encoder (NVENC/VideoToolbox) when available,
## falls back to ultrafast CPU encoding.

import std/[strformat, strutils, os, osproc, times, streams]
import ../ml/gpu_runtime
import ../render/previews
import ../log
import ../av

type
  EncoderConfig* = object
    ## Hardware or software encoder configuration
    codec*: string
    preset*: string
    tune*: string
    pixelFormat*: string
    bitrateMode*: string  # "crf" or "vbr"
    bitrateValue*: string

  ProxyResult* = object
    ## Result of proxy generation
    outputPath*: string
    success*: bool
    speedFactor*: float
    error*: string

proc selectProxyEncoder*(gpuRuntime: GpuRuntime): EncoderConfig =
  ## Select optimal encoder based on GPU detection
  ##
  ## Returns:
  ##   EncoderConfig with hardware or CPU fallback settings
  ##
  ## Hardware encoders prioritize speed over quality for proxy generation.
  ## CPU fallback uses ultrafast preset with CRF 28 for acceptable quality.

  case gpuRuntime.backend:
  of CUDA:
    # NVIDIA NVENC - fastest hardware encoder on Linux
    result = EncoderConfig(
      codec: "h264_nvenc",
      preset: "p1",           # p1 = fastest preset
      tune: "",               # no tune for NVENC
      pixelFormat: "yuv420p",
      bitrateMode: "vbr",
      bitrateValue: "2M"
    )
  of CoreML:
    # Apple VideoToolbox - macOS hardware encoder
    result = EncoderConfig(
      codec: "h264_videotoolbox",
      preset: "veryfast",
      tune: "",               # no tune for VideoToolbox
      pixelFormat: "nv12",    # VideoToolbox prefers nv12
      bitrateMode: "vbr",
      bitrateValue: "2M"
    )
  of CPU:
    # Software fallback - ultrafast x264
    result = EncoderConfig(
      codec: "libx264",
      preset: "ultrafast",
      tune: "fastdecode",     # optimize for playback
      pixelFormat: "yuv420p",
      bitrateMode: "crf",
      bitrateValue: "28"      # lower quality for speed
    )

proc buildProxyPath*(inputPath: string): string =
  ## Generate output path: same directory, {name}_proxy.mp4 suffix
  ##
  ## Args:
  ##   inputPath: Source video path
  ##
  ## Returns:
  ##   Output path with _proxy suffix
  ##
  ## Example:
  ##   /videos/talk.mp4 -> /videos/talk_proxy.mp4

  let (dir, name, _) = splitFile(inputPath)
  result = dir / name & "_proxy.mp4"

proc buildFFmpegArgs*(inputPath, outputPath: string, encoder: EncoderConfig): seq[string] =
  ## Build complete FFmpeg argument list for proxy generation
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   outputPath: Destination proxy path
  ##   encoder: Encoder configuration
  ##
  ## Returns:
  ##   Complete FFmpeg command arguments
  ##
  ## Uses fast_bilinear scaling for speed, ensures 720p output.

  result = @[
    "-y",                    # overwrite
    "-i", inputPath
  ]

  # Video filters: scale to 720p with fast algorithm
  result.add(@["-vf", "scale=1280:720:flags=fast_bilinear"])

  # Video codec
  result.add(@["-c:v", encoder.codec])

  # Preset
  if encoder.preset != "":
    result.add(@["-preset", encoder.preset])

  # Tune (if available)
  if encoder.tune != "":
    result.add(@["-tune", encoder.tune])

  # Pixel format
  result.add(@["-pix_fmt", encoder.pixelFormat])

  # Bitrate control
  case encoder.bitrateMode:
  of "crf":
    # Constant Rate Factor (software encoding)
    result.add(@["-crf", encoder.bitrateValue])
  of "vbr":
    # Variable Bitrate (hardware encoding)
    result.add(@["-b:v", encoder.bitrateValue])
    if encoder.codec == "h264_nvenc":
      result.add(@["-rc", "vbr"])  # NVENC-specific rate control
    result.add(@["-maxrate", "3M", "-bufsize", "4M"])

  # Audio: AAC 128k
  result.add(@[
    "-c:a", "aac",
    "-b:a", "128k",
    "-ar", "48000"
  ])

  # Fast start for web playback
  result.add(@["-movflags", "+faststart"])

  # Output path
  result.add(outputPath)

proc parseProgress*(line: string, durationSec: float): tuple[progress: float, speed: float] =
  ## Parse FFmpeg stderr line for progress information
  ##
  ## Args:
  ##   line: FFmpeg stderr output line
  ##   durationSec: Total video duration in seconds
  ##
  ## Returns:
  ##   Tuple of (progress percentage 0-100, speed factor)
  ##   Returns (-1, -1) if line doesn't contain progress info
  ##
  ## Looks for patterns like:
  ##   time=00:01:23.45 speed=2.3x

  result = (-1.0, -1.0)

  # Look for time= pattern
  if "time=" notin line:
    return

  # Extract time value
  var timeStr = ""
  let timeIdx = line.find("time=")
  if timeIdx >= 0:
    let afterTime = line[timeIdx + 5 .. ^1]
    let spaceIdx = afterTime.find(" ")
    if spaceIdx > 0:
      timeStr = afterTime[0 ..< spaceIdx].strip()
    else:
      timeStr = afterTime.strip()

  # Parse HH:MM:SS.MS format
  if timeStr != "":
    try:
      let parts = timeStr.split(":")
      if parts.len == 3:
        let hours = parseFloat(parts[0])
        let minutes = parseFloat(parts[1])
        let seconds = parseFloat(parts[2])
        let currentSec = hours * 3600.0 + minutes * 60.0 + seconds

        if durationSec > 0:
          result.progress = (currentSec / durationSec) * 100.0
          result.progress = min(100.0, max(0.0, result.progress))
    except ValueError:
      discard

  # Look for speed= pattern
  if "speed=" in line:
    let speedIdx = line.find("speed=")
    if speedIdx >= 0:
      let afterSpeed = line[speedIdx + 6 .. ^1]
      var speedStr = ""
      for ch in afterSpeed:
        if ch in {'0'..'9', '.', '-'}:
          speedStr.add(ch)
        else:
          break

      if speedStr != "":
        try:
          result.speed = parseFloat(speedStr)
        except ValueError:
          result.speed = -1.0

proc generateProxy*(inputPath: string, outputPath: string = "", quiet: bool = false): ProxyResult =
  ## Main entry point for proxy generation
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   outputPath: Output file path (default: auto-generated _proxy.mp4)
  ##   quiet: Suppress progress output
  ##
  ## Returns:
  ##   ProxyResult with success status, output path, and speed factor
  ##
  ## Detects GPU, selects optimal encoder, generates 720p proxy with
  ## live progress updates. On failure, returns error message.

  result = ProxyResult(
    outputPath: "",
    success: false,
    speedFactor: 0.0,
    error: ""
  )

  # Validate input
  if not fileExists(inputPath):
    result.error = &"Input file not found: {inputPath}"
    return

  # Detect GPU and select encoder
  let gpuRuntime = detectGpu()
  if not quiet:
    logBackend(gpuRuntime)

  let encoder = selectProxyEncoder(gpuRuntime)

  # Determine output path
  let finalOutputPath = if outputPath != "":
    outputPath
  else:
    buildProxyPath(inputPath)

  result.outputPath = finalOutputPath

  # Find FFmpeg
  let ffmpegPath = findFFmpegPath()
  if ffmpegPath == "":
    result.error = "FFmpeg not found in build/bin or PATH"
    return

  # Get video duration for progress calculation
  var duration: float = 0.0
  try:
    let container = av.open(inputPath)
    defer: container.close()

    if container.video.len > 0:
      let tb = container.video[0].time_base
      duration = float(container.video[0].duration) * float(tb.num) / float(tb.den)
    elif container.audio.len > 0:
      let tb = container.audio[0].time_base
      duration = float(container.audio[0].duration) * float(tb.num) / float(tb.den)
  except IOError as e:
    result.error = &"Failed to open input file: {e.msg}"
    return

  # Build FFmpeg arguments
  let args = buildFFmpegArgs(inputPath, finalOutputPath, encoder)

  # Start FFmpeg process
  let startTime = epochTime()

  try:
    let process = startProcess(
      ffmpegPath,
      args = args,
      options = {poStdErrToStdOut, poUsePath}
    )
    defer: process.close()

    # Read output for progress
    var lastProgress: float = -1.0
    var lastSpeed: float = -1.0

    while process.running:
      try:
        let line = process.outputStream.readLine()

        # Parse progress
        let (prog, speed) = parseProgress(line, duration)

        if prog >= 0:
          lastProgress = prog
        if speed >= 0:
          lastSpeed = speed

        # Update progress display
        if lastProgress >= 0 and not quiet:
          if lastSpeed > 0:
            conwrite(&"Encoding proxy: {lastProgress:.1f}% (speed: {lastSpeed:.1f}x)")
          else:
            conwrite(&"Encoding proxy: {lastProgress:.1f}%")
      except IOError:
        # End of stream
        break

    let exitCode = process.waitForExit()

    if not quiet:
      conwrite("")  # Clear progress line

    if exitCode != 0:
      result.error = &"FFmpeg exited with code {exitCode}"
      return

    # Calculate actual speed factor
    let elapsedTime = epochTime() - startTime
    if duration > 0 and elapsedTime > 0:
      result.speedFactor = duration / elapsedTime
    else:
      result.speedFactor = lastSpeed

    # Verify output file exists
    if not fileExists(finalOutputPath):
      result.error = "FFmpeg completed but output file not found"
      return

    result.success = true

  except OSError as e:
    result.error = &"Failed to start FFmpeg: {e.msg}"
  except Exception as e:
    result.error = &"Unexpected error: {e.msg}"
