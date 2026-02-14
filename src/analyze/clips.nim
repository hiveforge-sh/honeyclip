## Clip boundary detection combining scene changes, engagement drops, and speech alignment
##
## This module provides automatic clip segmentation for short-form video export.
## Clips are detected by combining multiple signals:
##   - Scene changes (visual cuts from FFmpeg scdet filter)
##   - Engagement drops (score differences between segments)
##   - Speech boundaries (sentence ends for natural cuts)
##
## The multi-signal approach produces clips that feel like natural "moments"
## suitable for social media (TikTok, Reels, Shorts).

import std/[algorithm, strformat, strutils, osproc, os, sets, math]
import engagement_types
import ../exports/presets
import ../reframe/crop

type
  BoundaryReason* = enum
    ## Why a clip boundary was created
    SceneChange       # scdet filter detected visual cut
    EngagementDrop    # Score dropped > threshold
    SpeechBoundary    # Sentence end for natural cuts

  ClipBoundary* = object
    ## A single point where a clip should be split
    timestampMs*: int64
    reason*: BoundaryReason

  Clip* = object
    ## A detected video clip with engagement metadata
    startMs*: int64
    endMs*: int64
    engagementScore*: float32      # Average score from segments
    adjustedScore*: float32        # After overlap penalty
    text*: string                  # Combined transcript text
    audioScore*: float32           # Average audio score
    motionScore*: float32          # Average motion score
    speechScore*: float32          # Average speech score
    hasHook*: bool                 # Any segment has hook
    faceCount*: int                # Max faces in any segment
    rank*: int                     # Final rank (1 = best)
    viralityScore*: float32                # Combined virality score (0-100)
    viralityComponents*: ViralityComponents # Component breakdown

  ClipDetectionParams* = object
    ## Parameters for clip boundary detection and extraction
    engagementDropThreshold*: float32  # Score drop to trigger split (default 20.0)
    minClipDurationMs*: int64          # Minimum clip length (default 15000)
    maxClipDurationMs*: int64          # Maximum clip length (default 60000)
    targetClipDurationMs*: int64       # Target length (default 30000)
    mergeWindowMs*: int64              # Merge boundaries within window (default 2000)
    introSkipMs*: int64                # Skip first N ms (default 0)
    outroSkipMs*: int64                # Skip last N ms (default 0)

  ClipRankingParams* = object
    ## Parameters for clip ranking with overlap penalty
    topN*: int                    # Number of top clips to return (default 5)
    overlapThreshold*: float32    # IoU above this triggers penalty (default 0.3)
    overlapPenalty*: float32      # Points to subtract per overlap (default 30.0)
    hookBoost*: float32           # Extra points for hook clips (default 5.0)
    preferLongerClips*: bool      # When overlapping, prefer longer clip (default true)

  ClipExportParams* = object
    ## Parameters for clip export
    outputDir*: string           # Output directory for clips
    codec*: string               # Video codec (default "libx264")
    preset*: string              # Encoding preset (default "fast")
    crf*: int                    # Quality (default 23)
    maxConcurrent*: int          # Max parallel renders (default 4)
    includeAudio*: bool          # Include audio track (default true)
    metadataPath*: string        # Path to ffmetadata file (empty = no metadata)

  ExportResult* = object
    ## Result of clip export operation
    clip*: Clip
    outputPath*: string
    success*: bool
    error*: string

  AspectExportJob* = object
    ## Single export job for aspect x clip combination
    clip*: Clip
    aspect*: AspectRatio
    outputPath*: string
    skipReframe*: bool      # True if source matches target aspect

  MultiAspectExportParams* = object
    ## Parameters for multi-aspect export
    baseParams*: ClipExportParams    # Base encoding settings
    aspects*: seq[AspectRatio]       # Ratios to export (default: all three)
    sourceAspect*: float             # Source video aspect ratio
    sourceWidth*, sourceHeight*: int # Source dimensions
    preset*: string                  # Optional platform preset name
    metadataPath*: string            # Path to ffmetadata file (empty = no metadata)

# ===== Aspect ratio helpers =====

proc calculateSourceAspect*(width, height: int): float =
  ## Calculate aspect ratio as float (e.g., 1.777 for 16:9)
  width.float / height.float

proc aspectsMatch*(source, target: AspectRatio, tolerance: float = 0.01): bool =
  ## Check if source aspect matches target within tolerance
  ## Used to skip reframing when not needed
  let sourceVal = aspectRatioValue(source)
  let targetVal = aspectRatioValue(target)
  abs(sourceVal - targetVal) < tolerance

proc aspectFromFloat*(ratio: float, tolerance: float = 0.1): AspectRatio =
  ## Determine aspect ratio enum from float value
  if abs(ratio - 16.0/9.0) < tolerance:
    return Landscape
  elif abs(ratio - 9.0/16.0) < tolerance:
    return Portrait
  elif abs(ratio - 1.0) < tolerance:
    return Square
  else:
    # Default to landscape for wider, portrait for taller
    if ratio > 1.0: Landscape else: Portrait

proc generateAspectSubfolder*(baseDir: string, aspect: AspectRatio): string =
  ## Generate output subfolder path for aspect ratio
  ## e.g., video_clips/16x9/, video_clips/9x16/, video_clips/1x1/
  baseDir / aspectToString(aspect)

# ===== Default parameters =====

proc defaultClipDetectionParams*(): ClipDetectionParams =
  ## Create default clip detection parameters
  ##
  ## Optimized for short-form social media content:
  ##   - 15-60 second clips (target 30s)
  ##   - 20 point engagement drop threshold
  ##   - 2 second merge window for nearby boundaries
  result.engagementDropThreshold = 20.0f
  result.minClipDurationMs = 15000    # 15 seconds
  result.maxClipDurationMs = 60000    # 60 seconds
  result.targetClipDurationMs = 30000 # 30 seconds
  result.mergeWindowMs = 2000         # 2 seconds
  result.introSkipMs = 0
  result.outroSkipMs = 0

proc defaultClipRankingParams*(): ClipRankingParams =
  ## Create default clip ranking parameters
  ##
  ## Optimized for variety in top clips:
  ##   - Top 5 clips by engagement score
  ##   - 0.3 IoU overlap threshold
  ##   - 30.0 point penalty per overlap
  ##   - 5.0 point hook boost
  result.topN = 5
  result.overlapThreshold = 0.3f
  result.overlapPenalty = 30.0f
  result.hookBoost = 5.0f
  result.preferLongerClips = true

proc defaultClipExportParams*(): ClipExportParams =
  ## Create default clip export parameters
  ##
  ## Optimized for fast rendering with good quality:
  ##   - libx264 codec with fast preset
  ##   - CRF 23 (good quality/size tradeoff)
  ##   - 4 concurrent renders
  result.outputDir = ""          # Set by caller
  result.codec = "libx264"
  result.preset = "fast"
  result.crf = 23
  result.maxConcurrent = 4
  result.includeAudio = true

# ===== Helper functions =====

proc durationMs*(clip: Clip): int64 =
  ## Calculate clip duration in milliseconds
  clip.endMs - clip.startMs

proc mergeNearbyBoundaries*(boundaries: seq[ClipBoundary], windowMs: int64): seq[ClipBoundary] =
  ## Merge boundaries within windowMs, prefer SceneChange > EngagementDrop > SpeechBoundary
  ##
  ## When multiple boundaries fall within the window, keep the highest priority one:
  ##   1. SceneChange (visual cut is strongest signal)
  ##   2. EngagementDrop (content shift)
  ##   3. SpeechBoundary (avoid mid-sentence cuts)
  if boundaries.len == 0:
    return @[]

  result = @[]
  var currentGroup: seq[ClipBoundary] = @[boundaries[0]]

  for i in 1 ..< boundaries.len:
    let boundary = boundaries[i]
    let prevBoundary = currentGroup[^1]

    if boundary.timestampMs - prevBoundary.timestampMs <= windowMs:
      # Within merge window - add to current group
      currentGroup.add(boundary)
    else:
      # Outside window - commit current group and start new one
      # Find highest priority boundary in group
      var best = currentGroup[0]
      for b in currentGroup:
        if b.reason < best.reason:  # Lower enum value = higher priority
          best = b
      result.add(best)
      currentGroup = @[boundary]

  # Commit final group
  if currentGroup.len > 0:
    var best = currentGroup[0]
    for b in currentGroup:
      if b.reason < best.reason:
        best = b
    result.add(best)

# ===== Scene change detection =====

proc extractSceneChanges*(inputPath: string, threshold: float = 0.4): seq[float64] =
  ## Extract scene change timestamps using FFmpeg scdet filter
  ##
  ## Args:
  ##   inputPath: Path to video file
  ##   threshold: Scene change detection threshold (0.0-1.0, default 0.4)
  ##
  ## Returns:
  ##   Timestamps in seconds where scene changes detected
  ##
  ## Uses FFmpeg scdet filter with metadata output. Parses stderr for
  ## lavfi.scd.time entries which indicate when score > threshold.
  result = @[]

  # Run FFmpeg and capture output (stderr redirected to stdout)
  let output = execProcess("ffmpeg", args = @[
    "-i", inputPath,
    "-vf", &"scdet=t={threshold}:s=1",
    "-f", "null", "-"
  ], options = {poStdErrToStdOut, poUsePath})

  # Parse lavfi.scd.time from output
  # Format: "lavfi.scd.time: 12.345678"
  for line in output.splitLines():
    if "lavfi.scd.time" in line:
      let parts = line.split(":")
      if parts.len >= 2:
        try:
          let timestamp = parseFloat(parts[1].strip())
          result.add(timestamp)
        except ValueError:
          discard

# ===== Speech boundary helpers =====

proc findNearestSentenceBoundary*(timeline: EngagementTimeline,
                                   targetMs: int64,
                                   searchWindowMs: int64 = 2000): int64 =
  ## Find nearest segment end (sentence boundary) to target timestamp
  ##
  ## Returns original targetMs if no sentence boundary within window.
  ## Sentence boundaries are defined as the end of segments with text
  ## (non-speech segments like silence or music don't have boundaries).
  var bestMatch = targetMs
  var bestDistance = int64.high

  for seg in timeline.segments:
    if seg.text.len > 0:  # Only speech segments have sentence boundaries
      let distance = abs(seg.endMs - targetMs)
      if distance < bestDistance and distance <= searchWindowMs:
        bestDistance = distance
        bestMatch = seg.endMs

  return bestMatch

proc isWithinSpeech*(timeline: EngagementTimeline, timestampMs: int64): bool =
  ## Check if timestamp falls within a speech segment
  for seg in timeline.segments:
    if seg.text.len > 0 and seg.startMs <= timestampMs and timestampMs < seg.endMs:
      return true
  return false

# ===== Boundary detection =====

proc detectBoundaries*(timeline: EngagementTimeline,
                       sceneChanges: seq[float64],
                       params: ClipDetectionParams): seq[ClipBoundary] =
  ## Combine scene changes, engagement drops, and speech boundaries
  ##
  ## Multi-signal approach:
  ##   1. Add scene changes as primary boundaries (visual cuts)
  ##   2. Add engagement drops (score difference > threshold between segments)
  ##   3. Sort and merge nearby boundaries (within mergeWindowMs)
  ##   4. Align to sentence boundaries (extend to complete thoughts)
  ##
  ## Args:
  ##   timeline: Engagement analysis result with scored segments
  ##   sceneChanges: Scene change timestamps from extractSceneChanges
  ##   params: Detection parameters
  ##
  ## Returns:
  ##   Sorted sequence of clip boundaries with reasons
  var boundaries: seq[ClipBoundary] = @[]

  # 1. Add scene changes as primary boundaries
  for sceneTs in sceneChanges:
    boundaries.add(ClipBoundary(
      timestampMs: (sceneTs * 1000.0).int64,
      reason: SceneChange
    ))

  # 2. Add engagement drops (major score changes)
  for i in 1 ..< timeline.segments.len:
    let scoreDrop = timeline.segments[i-1].score - timeline.segments[i].score
    if scoreDrop >= params.engagementDropThreshold:
      boundaries.add(ClipBoundary(
        timestampMs: timeline.segments[i].startMs,
        reason: EngagementDrop
      ))

  # 3. Sort and merge nearby boundaries
  boundaries.sort(proc(a, b: ClipBoundary): int = cmp(a.timestampMs, b.timestampMs))
  boundaries = mergeNearbyBoundaries(boundaries, params.mergeWindowMs)

  # 4. Align to sentence boundaries (avoid mid-sentence cuts)
  # If boundary falls within speech segment, extend to segment.endMs
  for i in 0 ..< boundaries.len:
    let boundary = boundaries[i]
    if timeline.isWithinSpeech(boundary.timestampMs):
      # Extend to nearest sentence boundary
      boundaries[i].timestampMs = timeline.findNearestSentenceBoundary(
        boundary.timestampMs,
        params.mergeWindowMs
      )

  # Remove duplicates after alignment (multiple boundaries may align to same sentence end)
  var unique: seq[ClipBoundary] = @[]
  if boundaries.len > 0:
    unique.add(boundaries[0])
    for i in 1 ..< boundaries.len:
      if boundaries[i].timestampMs != unique[^1].timestampMs:
        unique.add(boundaries[i])

  return unique

# ===== IoU and ranking =====

proc calculateIoU*(clipA, clipB: Clip): float32 =
  ## Calculate Intersection over Union for two clip time ranges
  ## Returns 0.0 (no overlap) to 1.0 (identical range)
  let intersectionStart = max(clipA.startMs, clipB.startMs)
  let intersectionEnd = min(clipA.endMs, clipB.endMs)
  let intersection = max(0'i64, intersectionEnd - intersectionStart)

  let unionStart = min(clipA.startMs, clipB.startMs)
  let unionEnd = max(clipA.endMs, clipB.endMs)
  let union = unionEnd - unionStart

  if union == 0:
    return 0.0f

  return intersection.float32 / union.float32

proc rankClips*(clips: seq[Clip], params: ClipRankingParams): seq[Clip] =
  ## Rank clips with overlap penalty to promote variety
  ##
  ## Algorithm:
  ## 1. Sort candidates by virality score (descending)
  ## 2. For each candidate, calculate overlap with already-selected clips
  ## 3. Apply penalty for overlapping clips (IoU * penalty)
  ## 4. Add hook boost if clip has hook
  ## 5. Select top N clips with positive adjusted scores
  ##
  ## CONTEXT.md decisions:
  ## - "Default to top 5 clips by virality score"
  ## - "Promote variety: reduce score of clips that overlap significantly"
  ## - "When clips overlap in time, prefer the longer clip"
  ## - "Slight boost for hook segments"

  if clips.len == 0:
    return @[]

  var ranked: seq[Clip] = @[]
  var candidates = clips

  # Sort by virality score descending
  candidates.sort(proc(a, b: Clip): int = cmp(b.viralityScore, a.viralityScore))

  for candidate in candidates:
    if ranked.len >= params.topN:
      break

    # Start with base virality score
    var adjustedScore = candidate.viralityScore

    # Add hook boost
    if candidate.hasHook:
      adjustedScore += params.hookBoost

    # Calculate overlap penalty with already-selected clips
    for selected in ranked:
      let iou = calculateIoU(candidate, selected)
      if iou > params.overlapThreshold:
        # Apply penalty proportional to overlap
        adjustedScore -= params.overlapPenalty * iou

        # If preferLongerClips and this clip is shorter, add extra penalty
        if params.preferLongerClips and candidate.durationMs < selected.durationMs:
          adjustedScore -= 5.0f

    # Only add if adjusted score still positive (or if first clip)
    if adjustedScore > 0.0f or ranked.len == 0:
      var rankedClip = candidate
      rankedClip.adjustedScore = adjustedScore
      rankedClip.rank = ranked.len + 1
      ranked.add(rankedClip)

  # Re-sort by adjusted score and reassign ranks
  ranked.sort(proc(a, b: Clip): int = cmp(b.adjustedScore, a.adjustedScore))
  for i in 0 ..< ranked.len:
    ranked[i].rank = i + 1

  return ranked

# ===== Virality scoring =====

proc calculateHookScore(firstSegment: EngagementSegment): float32 =
  ## Calculate hook score from first segment
  ## Base score + bonus for detected hook patterns
  result = firstSegment.score
  if firstSegment.hasHook:
    result = min(100.0f, result + 15.0f)

proc calculateFlowScore(segments: seq[EngagementSegment]): float32 =
  ## Calculate flow score: average engagement with variance penalty
  ## Penalizes inconsistent retention (high variance in segment scores)
  if segments.len == 0:
    return 0.0f

  # Calculate average score
  var avgScore = 0.0f
  for seg in segments:
    avgScore += seg.score
  avgScore /= segments.len.float32

  # Calculate standard deviation
  var variance = 0.0f
  for seg in segments:
    let diff = seg.score - avgScore
    variance += diff * diff
  variance /= segments.len.float32
  let stdDev = sqrt(variance)

  # Apply variance penalty (capped at 30 points)
  let flowPenalty = min(stdDev * 0.5f, 30.0f)

  result = max(0.0f, avgScore - flowPenalty)

proc calculateValueScore(segments: seq[EngagementSegment], maxFaceCount: int): float32 =
  ## Calculate value score: average engagement + face presence boost
  ## Face presence indicates human-centered content (higher value)
  if segments.len == 0:
    return 0.0f

  # Calculate average score
  var avgScore = 0.0f
  for seg in segments:
    avgScore += seg.score
  avgScore /= segments.len.float32

  result = avgScore

  # Add face boost (capped at 15 points)
  if maxFaceCount > 0:
    let faceBoost = min(maxFaceCount.float32 * 3.0f, 15.0f)
    result = min(100.0f, result + faceBoost)

proc calculateTrendScore(segments: seq[EngagementSegment]): float32 =
  ## Calculate trend score based on hook pattern diversity
  ## More diverse patterns = higher originality/authenticity
  var uniquePatterns: HashSet[string]

  for seg in segments:
    for pattern in seg.hookMatches:
      uniquePatterns.incl(pattern)

  if uniquePatterns.len == 0:
    return 50.0f  # Neutral score for no hooks

  # More diverse patterns = higher trend score
  # 1 pattern = 33, 2 patterns = 67, 3+ patterns = 100
  result = min(100.0f, uniquePatterns.len.float32 * 33.33f)

proc calculateViralityComponents(segments: seq[EngagementSegment], maxFaceCount: int): ViralityComponents =
  ## Calculate all four virality components from clip segments
  if segments.len == 0:
    return ViralityComponents(hook: 0.0f, flow: 0.0f, value: 0.0f, trend: 0.0f)

  result.hook = calculateHookScore(segments[0])
  result.flow = calculateFlowScore(segments)
  result.value = calculateValueScore(segments, maxFaceCount)
  result.trend = calculateTrendScore(segments)

proc combineViralityScore(components: ViralityComponents): float32 =
  ## Combine virality components with research-backed weights
  ## Hook 35%, Flow 30%, Value 25%, Trend 10%
  result = (components.hook * 0.35f +
            components.flow * 0.30f +
            components.value * 0.25f +
            components.trend * 0.10f)

# ===== Clip extraction =====

proc detectClips*(timeline: EngagementTimeline,
                  boundaries: seq[ClipBoundary],
                  params: ClipDetectionParams): seq[Clip] =
  ## Convert boundaries to clips, applying duration constraints
  ##
  ## Process:
  ##   1. Skip intro/outro based on params
  ##   2. Create clips between consecutive boundaries
  ##   3. Filter clips outside duration range
  ##   4. Calculate clip scores as weighted average of segment scores
  ##   5. Combine segment texts, hooks, face counts
  ##
  ## Args:
  ##   timeline: Engagement analysis result with scored segments
  ##   boundaries: Clip boundaries from detectBoundaries
  ##   params: Detection parameters
  ##
  ## Returns:
  ##   Sequence of clips with engagement metadata
  result = @[]

  if boundaries.len == 0:
    return result

  # Apply intro/outro skip
  let videoStartMs = params.introSkipMs
  let videoEndMs = timeline.duration - params.outroSkipMs

  # Create clips between consecutive boundaries
  var clipStarts: seq[int64] = @[videoStartMs]
  for boundary in boundaries:
    if boundary.timestampMs > videoStartMs and boundary.timestampMs < videoEndMs:
      clipStarts.add(boundary.timestampMs)
  clipStarts.add(videoEndMs)

  # Build clips from boundaries
  for i in 0 ..< clipStarts.len - 1:
    let startMs = clipStarts[i]
    let endMs = clipStarts[i + 1]
    let durationMs = endMs - startMs

    # Filter by duration constraints
    if durationMs < params.minClipDurationMs or durationMs > params.maxClipDurationMs:
      continue

    # Calculate clip scores from segments
    var totalScore = 0.0f
    var totalAudioScore = 0.0f
    var totalMotionScore = 0.0f
    var totalSpeechScore = 0.0f
    var segmentCount = 0
    var texts: seq[string] = @[]
    var hasHook = false
    var maxFaceCount = 0
    var clipSegments: seq[EngagementSegment] = @[]

    for seg in timeline.segments:
      # Check if segment overlaps with clip
      if seg.endMs > startMs and seg.startMs < endMs:
        totalScore += seg.score
        totalAudioScore += seg.audioScore
        totalMotionScore += seg.motionScore
        totalSpeechScore += seg.speechScore
        segmentCount += 1
        clipSegments.add(seg)

        if seg.text.len > 0:
          texts.add(seg.text)

        if seg.hasHook:
          hasHook = true

        if seg.faceCount > maxFaceCount:
          maxFaceCount = seg.faceCount

    # Skip clips with no segments (shouldn't happen, but guard)
    if segmentCount == 0:
      continue

    # Calculate virality components and score
    let components = calculateViralityComponents(clipSegments, maxFaceCount)
    let viralityScore = combineViralityScore(components)

    # Create clip with averaged scores
    result.add(Clip(
      startMs: startMs,
      endMs: endMs,
      engagementScore: totalScore / segmentCount.float32,
      adjustedScore: totalScore / segmentCount.float32,  # Will be adjusted during ranking
      text: texts.join(" "),
      audioScore: totalAudioScore / segmentCount.float32,
      motionScore: totalMotionScore / segmentCount.float32,
      speechScore: totalSpeechScore / segmentCount.float32,
      hasHook: hasHook,
      faceCount: maxFaceCount,
      rank: 0,  # Will be set during ranking
      viralityScore: viralityScore,
      viralityComponents: components
    ))

# ===== Clip export =====

proc generateClipFilename*(inputPath: string, clip: Clip): string =
  ## Generate output filename with timestamp
  ## Format: video_00m30s-01m15s.mp4 (per CONTEXT.md)
  let (_, name, _) = splitFile(inputPath)

  let startMin = clip.startMs div 60000
  let startSec = (clip.startMs mod 60000) div 1000
  let endMin = clip.endMs div 60000
  let endSec = (clip.endMs mod 60000) div 1000

  result = &"{name}_{startMin:02}m{startSec:02}s-{endMin:02}m{endSec:02}s.mp4"

proc buildFFmpegArgs*(inputPath: string, clip: Clip, outputPath: string,
                      params: ClipExportParams): seq[string] =
  ## Build FFmpeg arguments for clip extraction
  let startSec = clip.startMs.float64 / 1000.0
  let duration = (clip.endMs - clip.startMs).float64 / 1000.0

  result = @[
    "-ss", $startSec,
    "-t", $duration,
    "-i", inputPath
  ]

  # Add metadata input if provided
  # -i input.mp4 [-i metadata.txt -map_metadata 1] -c:v ... output.mp4
  if params.metadataPath != "" and fileExists(params.metadataPath):
    result.add(@["-i", params.metadataPath])
    result.add(@["-map_metadata", "1"])

  # Video and audio encoding settings
  result.add(@[
    "-c:v", params.codec,
    "-preset", params.preset,
    "-crf", $params.crf
  ])

  if params.includeAudio:
    result.add(@["-c:a", "aac", "-b:a", "128k"])
  else:
    result.add("-an")

  # Add faststart for streaming compatibility
  result.add(@["-movflags", "+faststart"])

  # Output file (overwrite without asking)
  result.add(@["-y", outputPath])

proc batchExportClips*(inputPath: string, clips: seq[Clip],
                       params: ClipExportParams,
                       onProgress: proc(completed, total: int) = nil): seq[ExportResult] =
  ## Export clips in parallel with limited concurrency
  ##
  ## RESEARCH.md: "Limit concurrent FFmpeg processes"
  ## RESEARCH.md: "Use defer for cleanup"
  ## CONTEXT.md: "Render clips in parallel for speed"
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   clips: Clips to export
  ##   params: Export parameters (codec, quality, concurrency)
  ##   onProgress: Optional callback for progress updates
  ##
  ## Returns:
  ##   Export results with success/error status per clip

  result = @[]

  if clips.len == 0:
    return result

  # Create output directory if needed
  let outputDir = if params.outputDir != "":
    params.outputDir
  else:
    # Default: subfolder next to source video (per CONTEXT.md)
    let (dir, name, _) = splitFile(inputPath)
    dir / name & "_clips"

  if not dirExists(outputDir):
    createDir(outputDir)

  # Track active processes
  type ProcessInfo = tuple[process: Process, clipIndex: int, outputPath: string]
  var activeProcesses: seq[ProcessInfo] = @[]
  var completed = 0

  # Find ffmpeg executable
  let ffmpegPath = findExe("ffmpeg")
  if ffmpegPath == "":
    # Return error for all clips
    for clip in clips:
      result.add(ExportResult(
        clip: clip,
        outputPath: "",
        success: false,
        error: "ffmpeg not found in PATH"
      ))
    return result

  for i, clip in clips:
    let outputPath = outputDir / generateClipFilename(inputPath, clip)
    let args = buildFFmpegArgs(inputPath, clip, outputPath, params)

    # Wait for available slot
    while activeProcesses.len >= params.maxConcurrent:
      # Check for completed processes
      var stillRunning: seq[ProcessInfo] = @[]
      for info in activeProcesses:
        if info.process.running():
          stillRunning.add(info)
        else:
          let exitCode = info.process.waitForExit()
          completed += 1
          result.add(ExportResult(
            clip: clips[info.clipIndex],
            outputPath: info.outputPath,
            success: exitCode == 0,
            error: if exitCode != 0: &"FFmpeg exited with code {exitCode}" else: ""
          ))
          info.process.close()
          if onProgress != nil:
            onProgress(completed, clips.len)
      activeProcesses = stillRunning

      if activeProcesses.len >= params.maxConcurrent:
        sleep(100)  # Poll every 100ms

    # Start new export process
    try:
      let process = startProcess(ffmpegPath, args = args,
                                  options = {poUsePath, poStdErrToStdOut})
      activeProcesses.add((process, i, outputPath))
    except OSError as e:
      result.add(ExportResult(
        clip: clip,
        outputPath: outputPath,
        success: false,
        error: e.msg
      ))

  # Wait for remaining processes
  for info in activeProcesses:
    let exitCode = info.process.waitForExit()
    completed += 1
    result.add(ExportResult(
      clip: clips[info.clipIndex],
      outputPath: info.outputPath,
      success: exitCode == 0,
      error: if exitCode != 0: &"FFmpeg exited with code {exitCode}" else: ""
    ))
    info.process.close()
    if onProgress != nil:
      onProgress(completed, clips.len)

  # Sort results by clip rank
  result.sort(proc(a, b: ExportResult): int = cmp(a.clip.rank, b.clip.rank))

# ===== Multi-aspect export =====

proc buildReframeArgs*(inputPath: string, clip: Clip, outputPath: string,
                       params: MultiAspectExportParams, aspect: AspectRatio,
                       skipReframe: bool): seq[string] =
  ## Build FFmpeg arguments for clip extraction with optional reframe
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   clip: Clip to extract
  ##   outputPath: Output file path
  ##   params: Multi-aspect export parameters
  ##   aspect: Target aspect ratio
  ##   skipReframe: If true, skip crop filter (source matches target)
  ##
  ## Returns:
  ##   FFmpeg argument sequence
  let startSec = clip.startMs.float64 / 1000.0
  let duration = (clip.endMs - clip.startMs).float64 / 1000.0

  result = @[
    "-ss", $startSec,
    "-t", $duration,
    "-i", inputPath
  ]

  # Add metadata input if provided
  # -i input.mp4 [-i metadata.txt -map_metadata 1] -vf ... output.mp4
  if params.metadataPath != "" and fileExists(params.metadataPath):
    result.add(@["-i", params.metadataPath])
    result.add(@["-map_metadata", "1"])

  if not skipReframe:
    # Calculate target dimensions based on aspect ratio
    var targetW, targetH: int
    case aspect
    of Portrait:
      # 9:16 - fit to source height
      targetH = params.sourceHeight
      targetW = targetH * 9 div 16
    of Landscape:
      # 16:9 - fit to source width
      targetW = params.sourceWidth
      targetH = targetW * 9 div 16
    of Square:
      # 1:1 - use smaller dimension
      let size = min(params.sourceWidth, params.sourceHeight)
      targetW = size
      targetH = size

    # Center crop + scale filter
    let cropX = (params.sourceWidth - targetW) div 2
    let cropY = (params.sourceHeight - targetH) div 2
    result.add(@["-vf", &"crop={targetW}:{targetH}:{cropX}:{cropY}"])

  # Encoding settings from base params
  result.add(@[
    "-c:v", params.baseParams.codec,
    "-preset", params.baseParams.preset,
    "-crf", $params.baseParams.crf
  ])

  if params.baseParams.includeAudio:
    result.add(@["-c:a", "aac", "-b:a", "128k"])
  else:
    result.add("-an")

  result.add(@["-movflags", "+faststart", "-y", outputPath])

proc batchExportMultiAspect*(inputPath: string, clips: seq[Clip],
                              params: MultiAspectExportParams,
                              metadataPath: string = "",
                              onProgress: proc(completed, total: int) = nil): seq[ExportResult] =
  ## Export clips in multiple aspect ratios using process pool
  ##
  ## Per CONTEXT.md:
  ## - Parallel rendering: all ratios render concurrently
  ## - Output structure: subfolders by ratio (video_clips/16x9/, etc.)
  ## - Skip reframing when source matches target ratio
  ##
  ## Args:
  ##   inputPath: Source video path
  ##   clips: Clips to export
  ##   params: Multi-aspect export parameters
  ##   metadataPath: Optional path to ffmetadata file for metadata embedding
  ##   onProgress: Optional callback for progress updates
  ##
  ## Returns:
  ##   Export results with success/error status per job

  # Set metadataPath in params if provided
  var effectiveParams = params
  effectiveParams.metadataPath = metadataPath

  result = @[]
  if clips.len == 0 or effectiveParams.aspects.len == 0:
    return result

  # Determine source aspect
  let sourceAspect = aspectFromFloat(effectiveParams.sourceAspect)

  # Build all jobs
  var jobs: seq[AspectExportJob] = @[]
  for aspect in effectiveParams.aspects:
    let aspectDir = generateAspectSubfolder(effectiveParams.baseParams.outputDir, aspect)
    if not dirExists(aspectDir):
      createDir(aspectDir)

    for clip in clips:
      let skipReframe = aspectsMatch(sourceAspect, aspect)
      let outputPath = aspectDir / generateClipFilename(inputPath, clip)
      jobs.add(AspectExportJob(
        clip: clip,
        aspect: aspect,
        outputPath: outputPath,
        skipReframe: skipReframe
      ))

  # Execute with concurrency limit (reuse pattern from batchExportClips)
  type ProcessInfo = tuple[process: Process, jobIndex: int]
  var activeProcesses: seq[ProcessInfo] = @[]
  var completed = 0
  let totalJobs = jobs.len

  let ffmpegPath = findExe("ffmpeg")
  if ffmpegPath == "":
    for job in jobs:
      result.add(ExportResult(
        clip: job.clip,
        outputPath: job.outputPath,
        success: false,
        error: "ffmpeg not found in PATH"
      ))
    return result

  for i, job in jobs:
    let args = buildReframeArgs(inputPath, job.clip, job.outputPath, effectiveParams, job.aspect, job.skipReframe)

    # Wait for available slot
    while activeProcesses.len >= effectiveParams.baseParams.maxConcurrent:
      var stillRunning: seq[ProcessInfo] = @[]
      for info in activeProcesses:
        if info.process.running():
          stillRunning.add(info)
        else:
          let exitCode = info.process.waitForExit()
          completed += 1
          let completedJob = jobs[info.jobIndex]
          result.add(ExportResult(
            clip: completedJob.clip,
            outputPath: completedJob.outputPath,
            success: exitCode == 0,
            error: if exitCode != 0: &"FFmpeg exited with code {exitCode}" else: ""
          ))
          info.process.close()
          if onProgress != nil:
            onProgress(completed, totalJobs)
      activeProcesses = stillRunning
      if activeProcesses.len >= effectiveParams.baseParams.maxConcurrent:
        sleep(100)

    # Start new process
    try:
      let process = startProcess(ffmpegPath, args = args,
                                  options = {poUsePath, poStdErrToStdOut})
      activeProcesses.add((process, i))
    except OSError as e:
      result.add(ExportResult(
        clip: job.clip,
        outputPath: job.outputPath,
        success: false,
        error: e.msg
      ))

  # Wait for remaining processes
  for info in activeProcesses:
    let exitCode = info.process.waitForExit()
    completed += 1
    let completedJob = jobs[info.jobIndex]
    result.add(ExportResult(
      clip: completedJob.clip,
      outputPath: completedJob.outputPath,
      success: exitCode == 0,
      error: if exitCode != 0: &"FFmpeg exited with code {exitCode}" else: ""
    ))
    info.process.close()
    if onProgress != nil:
      onProgress(completed, totalJobs)
