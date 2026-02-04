## Preview generation for clip review
##
## This module generates thumbnails and video snippets for quick preview of
## detected clips before committing to full renders. Users can review clip
## content via:
##   - Contact sheet: thumbnail grid showing all clips at a glance
##   - Best frame thumbnails: auto-selected representative frame per clip
##   - Video snippets: 9-second preview (3s start + 3s middle + 3s end)
##
## Previews are stored in subfolder next to video (video_previews/) and include
## burned-in metadata (clip number, time range) for easy identification.

import std/[strformat, strutils, os, osproc]

type
  PreviewMode* = enum
    ## Preview generation mode
    PreviewThumbnails    # Static images (contact sheet + individual frames)
    PreviewSnippets      # Short video clips (9s per clip)

  PreviewResult* = object
    ## Result of preview generation
    contactSheetPath*: string    # Grid image path (empty if not generated)
    thumbnailPaths*: seq[string] # Individual frame paths
    snippetPaths*: seq[string]   # Video snippet paths
    success*: bool               # Overall success status
    error*: string               # Error message if failed

  ClipPreviewInfo* = tuple
    ## Clip information for preview generation
    startMs, endMs: int64
    rank: int

# ===== Helper functions =====

proc findFFmpegPath*(): string =
  ## Find FFmpeg executable, checking build/bin first then PATH
  ##
  ## Returns:
  ##   Path to ffmpeg executable, empty string if not found
  ##
  ## Follows existing pattern from reframe.nim: prefer honeyclip's
  ## built FFmpeg over system FFmpeg.

  # Check build/bin/ffmpeg first (honeyclip's built FFmpeg)
  let buildPath = getAppDir().parentDir() / "build" / "bin" / "ffmpeg"
  if fileExists(buildPath):
    return buildPath

  # Also check relative to current directory (for development)
  let localBuildPath = "build" / "bin" / "ffmpeg"
  if fileExists(localBuildPath):
    return localBuildPath

  # Fall back to PATH
  let pathFFmpeg = findExe("ffmpeg")
  if pathFFmpeg != "":
    return pathFFmpeg

  return ""

proc msToTimestamp*(ms: int64): string =
  ## Convert milliseconds to human-readable timestamp
  ## Format: 00:00:00 (HH:MM:SS)
  let totalSeconds = ms div 1000
  let hours = totalSeconds div 3600
  let minutes = (totalSeconds mod 3600) div 60
  let seconds = totalSeconds mod 60
  result = &"{hours:02}:{minutes:02}:{seconds:02}"

proc msToSeconds*(ms: int64): float64 =
  ## Convert milliseconds to seconds
  ms.float64 / 1000.0

proc escapeFFmpegPath*(path: string): string =
  ## Escape path for FFmpeg filter (Windows colon escaping)
  ## Per 03-02: Windows paths need colon escaping for FFmpeg
  result = path.replace(":", "\\:")

proc buildDrawtextFilter*(rank: int, startMs, endMs: int64): string =
  ## Build FFmpeg drawtext filter for metadata overlay
  ##
  ## Args:
  ##   rank: Clip rank number
  ##   startMs: Clip start time in milliseconds
  ##   endMs: Clip end time in milliseconds
  ##
  ## Returns:
  ##   FFmpeg drawtext filter string
  ##
  ## Per CONTEXT.md: burn metadata into previews with clip number and time range
  let startTime = msToTimestamp(startMs)
  let endTime = msToTimestamp(endMs)
  let text = &"Clip {rank} [{startTime}-{endTime}]"

  # Drawtext with semi-transparent background for readability
  result = &"drawtext=text='{text}':fontsize=18:fontcolor=white:x=10:y=10:box=1:boxcolor=black@0.5:boxborderw=5"

# ===== Contact sheet generation =====

proc generateContactSheet*(inputPath: string, outputPath: string,
                           clips: seq[ClipPreviewInfo],
                           cols: int = 4): bool =
  ## Generate NxM thumbnail grid using FFmpeg tile filter
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   outputPath: Output image path (jpg/png)
  ##   clips: Clip information with timestamps
  ##   cols: Number of columns in grid (default 4)
  ##
  ## Returns:
  ##   true if generation succeeded, false otherwise
  ##
  ## One frame per clip (from midpoint), arranged in grid.
  ## Uses select filter to pick specific frames, tile filter for grid layout.

  let ffmpegPath = findFFmpegPath()
  if ffmpegPath == "":
    return false

  if clips.len == 0:
    return false

  # Calculate rows needed
  let rows = (clips.len + cols - 1) div cols

  # Build select expression for frame at each clip's midpoint
  # Format: select='eq(n,FRAME1)+eq(n,FRAME2)+...'
  var selectExprs: seq[string] = @[]

  # We need to calculate frame numbers from timestamps
  # This requires knowing the video framerate, so we use a simpler approach:
  # Extract frames at specific times using multiple -ss/-i inputs

  # For contact sheet, generate individual thumbnails then tile them
  # This is more reliable than complex select expressions

  # Use FFmpeg's thumbnail filter on each clip range
  # Since we need specific time ranges, we'll generate one frame per clip
  # using time-based seeking

  # Build filter chain: extract frame from each clip midpoint, scale, tile
  var args = @["-y"]

  # Add input with seeks for each clip midpoint
  for i, clip in clips:
    let midpointSec = ((clip.startMs + clip.endMs) div 2).msToSeconds()
    args.add(@["-ss", &"{midpointSec:.3f}", "-i", inputPath])

  # Build filter complex for scaling and tiling
  var filterParts: seq[string] = @[]
  var inputs: seq[string] = @[]

  for i in 0..<clips.len:
    # Scale each input and label it
    filterParts.add(&"[{i}:v]scale=240:-1[thumb{i}]")
    inputs.add(&"[thumb{i}]")

  # Combine all scaled thumbnails with xstack/hstack or tile
  # For simplicity, use tile filter which handles arbitrary inputs
  # Note: tile filter works on a single input stream with multiple frames
  # So we need to concat first

  if clips.len > 1:
    # Concat all thumbnails into single stream, then tile
    filterParts.add(inputs.join("") & &"concat=n={clips.len}:v=1:a=0[all]")
    filterParts.add(&"[all]tile={cols}x{rows}:padding=4:color=gray")
  else:
    # Single clip - just scale
    filterParts.add(&"[thumb0]tile=1x1:padding=4:color=gray")

  args.add(@["-filter_complex", filterParts.join(";")])
  args.add(@["-frames:v", "1"])
  args.add(@["-q:v", "2"])  # High quality JPEG
  args.add(outputPath)

  # Execute FFmpeg
  let exitCode = execCmd(&"\"{ffmpegPath}\" " & args.join(" "))
  return exitCode == 0

# ===== Best frame thumbnail =====

proc generateBestFrameThumbnail*(inputPath: string, outputPath: string,
                                  startMs, endMs: int64,
                                  rank: int = 0,
                                  burnMetadata: bool = true): bool =
  ## Auto-select best frame from clip range using histogram analysis
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   outputPath: Output image path (jpg/png)
  ##   startMs: Clip start time in milliseconds
  ##   endMs: Clip end time in milliseconds
  ##   rank: Clip rank for metadata overlay (0 = no rank)
  ##   burnMetadata: Whether to burn clip info into thumbnail
  ##
  ## Returns:
  ##   true if generation succeeded, false otherwise
  ##
  ## Uses FFmpeg thumbnail filter which analyzes histogram to find
  ## most representative frame. Per RESEARCH.md Pattern 3.

  let ffmpegPath = findFFmpegPath()
  if ffmpegPath == "":
    return false

  let startSec = startMs.msToSeconds()
  let duration = (endMs - startMs).msToSeconds()

  # Build filter chain
  var filterChain = "thumbnail=100"  # Batch 100 frames, select best

  # Add metadata overlay if requested
  if burnMetadata and rank > 0:
    let drawtext = buildDrawtextFilter(rank, startMs, endMs)
    filterChain = filterChain & "," & drawtext

  var args = @[
    "-y",
    "-ss", &"{startSec:.3f}",
    "-t", &"{duration:.3f}",
    "-i", inputPath,
    "-vf", filterChain,
    "-frames:v", "1",
    "-q:v", "2",  # High quality JPEG
    outputPath
  ]

  # Execute FFmpeg
  let exitCode = execCmd(&"\"{ffmpegPath}\" " & args.join(" "))
  return exitCode == 0

# ===== Video snippets =====

proc generateVideoSnippets*(inputPath: string, outputDir: string,
                            clipRank: int, startMs, endMs: int64,
                            burnMetadata: bool = true): seq[string] =
  ## Generate 3-second snippets: start, middle, end (9s total)
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   outputDir: Output directory for snippet files
  ##   clipRank: Clip rank number (for filename and metadata)
  ##   startMs: Clip start time in milliseconds
  ##   endMs: Clip end time in milliseconds
  ##   burnMetadata: Whether to burn clip info into snippets
  ##
  ## Returns:
  ##   Sequence of paths to generated snippet files
  ##
  ## Creates 3 files: clip_{rank:02}_start.mp4, clip_{rank:02}_middle.mp4, clip_{rank:02}_end.mp4
  ## Uses fast preset + CRF 28 for preview quality (faster than final render).
  ## Per CONTEXT.md and RESEARCH.md.

  result = @[]

  let ffmpegPath = findFFmpegPath()
  if ffmpegPath == "":
    return result

  let clipDuration = endMs - startMs
  let snippetDurationMs: int64 = 3000  # 3 seconds per snippet

  # Calculate snippet time ranges
  type SnippetInfo = tuple[name: string, snippetStart, snippetEnd: int64]
  var snippets: seq[SnippetInfo] = @[]

  # Start snippet (first 3 seconds or less)
  let startSnippetEnd = min(startMs + snippetDurationMs, endMs)
  snippets.add(("start", startMs, startSnippetEnd))

  # Middle snippet (3 seconds around midpoint)
  let midpoint = startMs + clipDuration div 2
  let middleStart = max(startMs, midpoint - snippetDurationMs div 2)
  let middleEnd = min(endMs, midpoint + snippetDurationMs div 2)
  # Only add if not overlapping significantly with start
  if middleStart > startSnippetEnd - 1000:
    snippets.add(("middle", middleStart, middleEnd))

  # End snippet (last 3 seconds or less)
  let endSnippetStart = max(startMs, endMs - snippetDurationMs)
  # Only add if not overlapping significantly with middle
  if endSnippetStart > middleEnd - 1000:
    snippets.add(("end", endSnippetStart, endMs))

  # Build filter for metadata if requested
  var filterArg: seq[string] = @[]
  if burnMetadata:
    let drawtext = buildDrawtextFilter(clipRank, startMs, endMs)
    filterArg = @["-vf", drawtext]

  # Generate each snippet
  for snippet in snippets:
    let (name, snippetStart, snippetEnd) = snippet
    let outputPath = outputDir / &"clip_{clipRank:02}_{name}.mp4"

    let startSec = snippetStart.msToSeconds()
    let duration = (snippetEnd - snippetStart).msToSeconds()

    var args = @[
      "-y",
      "-ss", &"{startSec:.3f}",
      "-t", &"{duration:.3f}",
      "-i", inputPath
    ]

    # Add filter if metadata requested
    args.add(filterArg)

    # Encoding settings: fast preset + CRF 28 for preview quality
    args.add(@[
      "-c:v", "libx264",
      "-preset", "fast",
      "-crf", "28",
      "-c:a", "aac",
      "-b:a", "96k",
      "-movflags", "+faststart",
      outputPath
    ])

    let exitCode = execCmd(&"\"{ffmpegPath}\" " & args.join(" "))
    if exitCode == 0:
      result.add(outputPath)

# ===== Combined preview generation =====

proc createPreviewDir*(inputPath: string): string =
  ## Create preview directory next to video
  ##
  ## Args:
  ##   inputPath: Source video path
  ##
  ## Returns:
  ##   Path to created preview directory
  ##
  ## Per CONTEXT.md: previews stored in subfolder next to video (video_previews/)
  let (dir, name, _) = splitFile(inputPath)
  result = dir / name & "_previews"

  if not dirExists(result):
    createDir(result)

proc generatePreviews*(inputPath: string, clips: seq[ClipPreviewInfo],
                       mode: PreviewMode): PreviewResult =
  ## Generate all previews for clips in specified mode
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   clips: Clip information with timestamps and ranks
  ##   mode: PreviewThumbnails or PreviewSnippets
  ##
  ## Returns:
  ##   PreviewResult with paths to generated files and success status
  ##
  ## Creates preview directory: {video}_previews/
  ## Generates contact sheet (thumbnails mode) or video snippets.

  result = PreviewResult(
    contactSheetPath: "",
    thumbnailPaths: @[],
    snippetPaths: @[],
    success: false,
    error: ""
  )

  if clips.len == 0:
    result.error = "No clips provided"
    return result

  # Verify FFmpeg available
  let ffmpegPath = findFFmpegPath()
  if ffmpegPath == "":
    result.error = "FFmpeg not found"
    return result

  # Create preview directory
  let previewDir = createPreviewDir(inputPath)

  case mode:
  of PreviewThumbnails:
    # Generate contact sheet
    let contactSheetPath = previewDir / "contact_sheet.jpg"
    if generateContactSheet(inputPath, contactSheetPath, clips):
      result.contactSheetPath = contactSheetPath

    # Generate individual best-frame thumbnails
    for clip in clips:
      let thumbPath = previewDir / &"clip_{clip.rank:02}_thumb.jpg"
      if generateBestFrameThumbnail(inputPath, thumbPath, clip.startMs, clip.endMs, clip.rank):
        result.thumbnailPaths.add(thumbPath)

    result.success = result.thumbnailPaths.len > 0 or result.contactSheetPath != ""

  of PreviewSnippets:
    # Generate video snippets for each clip
    for clip in clips:
      let snippets = generateVideoSnippets(inputPath, previewDir, clip.rank, clip.startMs, clip.endMs)
      result.snippetPaths.add(snippets)

    result.success = result.snippetPaths.len > 0

  if not result.success and result.error == "":
    result.error = "Failed to generate any previews"
