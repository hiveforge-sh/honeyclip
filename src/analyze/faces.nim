## Face detection types and consensus algorithm
##
## Provides face detection types extending libfacedetection FaceRect with
## temporal consensus filtering to reduce false positives.

import std/[algorithm, strformat, strutils, tables, options, math]
import ../ml/facedetect
import ../av
import ../ffmpeg
import ../log
import ../util/dict
import ../util/bar
import ../facecache

# Import VideoProcessor type from motion module
type
  VideoProcessor* = object
    formatCtx*: ptr AVFormatContext
    codecCtx*: ptr AVCodecContext
    tb*: AVRational
    videoIndex*: cint

type
  FaceDetection* = object
    ## Face detection result with frame context and stability
    x*, y*: int
    width*, height*: int
    confidence*: float
    angle*: int
    frameIndex*: int64      # Which frame this detection came from
    stable*: bool           # Whether consensus considers this face stable

  FrameFaces* = object
    ## Face detections grouped per frame
    frameIndex*: int64
    timestamp*: float64     # seconds
    faces*: seq[FaceDetection]

  SceneInfo* = object
    ## Scene change detection information from FFmpeg scdet filter
    score*: float           # 0.0-1.0 scene change score
    isSceneChange*: bool    # score > threshold
    timestamp*: float64     # seconds

  AdaptiveSampler* = object
    ## Adaptive frame sampling to optimize CPU usage
    baseFps*: float         # Baseline sampling rate (default 1.0)
    maxFps*: float          # Maximum during spikes (default 5.0)
    currentFps: float       # Current sampling rate
    sceneThreshold*: float  # Scene change threshold (default 0.4)
    cooldownDuration: float # Seconds before returning to baseline (default 1.0)
    lastSpikeTime: float64  # Timestamp of last sampling spike
    lastFaceCount: int      # Track face state changes
    frameInterval: float    # Current frame interval (1.0 / currentFps)
    nextSampleTime: float64 # Next time to sample a frame

  FaceConsensus* = object
    ## Temporal filtering to reduce false positives
    window: seq[seq[FaceDetection]]  # Sliding window of frame detections
    windowSize*: int                  # Number of frames in window
    threshold*: float                 # Consensus ratio (0.0-1.0)
    minFaceRatio*: float              # Minimum face height as ratio of frame

proc newFaceConsensus*(windowSize: int = 3, threshold: float = 0.6,
                       minFaceRatio: float = 0.05): FaceConsensus =
  ## Create new consensus filter with configurable parameters
  ##
  ## Args:
  ##   windowSize: Number of frames in sliding window (default 3)
  ##   threshold: Ratio of appearances required for stability (default 0.6)
  ##   minFaceRatio: Minimum face height as ratio of frame height (default 0.05)
  result = FaceConsensus(
    window: @[],
    windowSize: windowSize,
    threshold: threshold,
    minFaceRatio: minFaceRatio
  )

proc iou*(a, b: FaceDetection): float =
  ## Calculate Intersection over Union for two face detections
  ## Returns value between 0.0 (no overlap) and 1.0 (perfect overlap)

  # Calculate intersection rectangle
  let x1 = max(a.x, b.x)
  let y1 = max(a.y, b.y)
  let x2 = min(a.x + a.width, b.x + b.width)
  let y2 = min(a.y + a.height, b.y + b.height)

  # No intersection if coordinates are inverted
  if x2 <= x1 or y2 <= y1:
    return 0.0

  # Calculate areas
  let intersectionArea = (x2 - x1) * (y2 - y1)
  let aArea = a.width * a.height
  let bArea = b.width * b.height
  let unionArea = aArea + bArea - intersectionArea

  if unionArea <= 0:
    return 0.0

  return intersectionArea.float / unionArea.float

proc addFrame*(fc: var FaceConsensus, faces: seq[FaceDetection]) =
  ## Add frame detections to consensus window
  ## Maintains window size by removing oldest frame when full
  fc.window.add(faces)

  # Keep window at fixed size
  if fc.window.len > fc.windowSize:
    fc.window.delete(0)

proc getStableFaces*(fc: FaceConsensus): seq[FaceDetection] =
  ## Get faces that appear in threshold% of frames in window
  ## Returns faces marked as stable based on consensus
  result = @[]

  if fc.window.len == 0:
    return

  # Get current frame (most recent)
  let currentFrame = fc.window[^1]

  # For each face in current frame, count appearances across window
  for face in currentFrame:
    var appearances = 1  # Current frame counts as 1

    # Check previous frames for matching faces (IoU > 0.5)
    for i in 0 ..< fc.window.len - 1:
      let prevFrame = fc.window[i]
      var foundMatch = false

      for prevFace in prevFrame:
        if iou(face, prevFace) > 0.5:
          foundMatch = true
          break

      if foundMatch:
        appearances += 1

    # Mark as stable if appears in threshold% of frames
    let appearanceRatio = appearances.float / fc.window.len.float
    var stableFace = face
    stableFace.stable = appearanceRatio >= fc.threshold
    result.add(stableFace)

proc filterBySize*(faces: seq[FaceDetection], frameHeight: int,
                   minRatio: float): seq[FaceDetection] =
  ## Filter out faces smaller than minRatio of frame height
  result = @[]
  let minHeight = (frameHeight.float * minRatio).int

  for face in faces:
    if face.height >= minHeight:
      result.add(face)

proc detectFaces*(imageData: ptr uint8, width, height, stride: int,
                  frameIndex: int64, minConfidence: float = 0.3): seq[FaceDetection] =
  ## Detect faces in image and wrap in FaceDetection objects
  ##
  ## Args:
  ##   imageData: Pointer to BGR image data
  ##   width: Image width in pixels
  ##   height: Image height in pixels
  ##   stride: Row stride in bytes
  ##   frameIndex: Frame number for tracking
  ##   minConfidence: Minimum confidence threshold (default 0.3)
  ##
  ## Returns:
  ##   Sequence of FaceDetection objects filtered by confidence

  # Call libfacedetection
  let rects = facedetect.detect(imageData, width, height, stride)

  # Convert to FaceDetection with confidence filter
  result = @[]
  for rect in rects:
    if rect.confidence >= minConfidence:
      result.add(FaceDetection(
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        confidence: rect.confidence,
        angle: rect.angle,
        frameIndex: frameIndex,
        stable: false  # Will be determined by consensus
      ))

proc newAdaptiveSampler*(baseFps: float = 1.0, maxFps: float = 5.0,
                         sceneThreshold: float = 0.4,
                         cooldown: float = 1.0): AdaptiveSampler =
  ## Create new adaptive sampler with configurable parameters
  ##
  ## Args:
  ##   baseFps: Baseline sampling rate during stable scenes (default 1.0)
  ##   maxFps: Maximum sampling rate during spikes (default 5.0)
  ##   sceneThreshold: Scene change detection threshold (default 0.4)
  ##   cooldown: Seconds to maintain high sampling after spike (default 1.0)
  ##
  ## Returns:
  ##   Initialized AdaptiveSampler starting at baseline rate
  result = AdaptiveSampler(
    baseFps: baseFps,
    maxFps: maxFps,
    currentFps: baseFps,
    sceneThreshold: sceneThreshold,
    cooldownDuration: cooldown,
    lastSpikeTime: -999.0,  # Start at baseline (no recent spike)
    lastFaceCount: 0,
    frameInterval: 1.0 / baseFps,
    nextSampleTime: 0.0
  )

proc updateSamplingRate*(sampler: var AdaptiveSampler, sceneScore: float,
                         faceCount: int, currentTime: float64): float =
  ## Update sampling rate based on scene changes and face state
  ##
  ## Args:
  ##   sampler: Adaptive sampler to update
  ##   sceneScore: Scene change score from scdet filter (0.0-1.0)
  ##   faceCount: Number of faces detected in current frame
  ##   currentTime: Current timestamp in seconds
  ##
  ## Returns:
  ##   Updated sampling rate (fps)

  # Check for spike triggers
  let isSceneChange = sceneScore >= sampler.sceneThreshold
  let faceStateChanged = faceCount != sampler.lastFaceCount

  if isSceneChange or faceStateChanged:
    # Trigger spike: switch to high sampling rate
    sampler.currentFps = sampler.maxFps
    sampler.lastSpikeTime = currentTime
    sampler.frameInterval = 1.0 / sampler.maxFps
  else:
    # Check if cooldown period has elapsed
    let timeSinceSpike = currentTime - sampler.lastSpikeTime
    if timeSinceSpike >= sampler.cooldownDuration:
      # Return to baseline
      sampler.currentFps = sampler.baseFps
      sampler.frameInterval = 1.0 / sampler.baseFps
    # else: maintain current high rate during cooldown

  sampler.lastFaceCount = faceCount
  return sampler.currentFps

proc shouldSampleFrame*(sampler: var AdaptiveSampler, timestamp: float64): bool =
  ## Determine if frame at given timestamp should be sampled
  ##
  ## Args:
  ##   sampler: Adaptive sampler tracking next sample time
  ##   timestamp: Current frame timestamp in seconds
  ##
  ## Returns:
  ##   True if this frame should be processed

  if timestamp >= sampler.nextSampleTime:
    sampler.nextSampleTime = timestamp + sampler.frameInterval
    return true
  return false

proc createFilterGraph(timeBase: AVRational, pixFmtName: cstring,
    codecCtx: ptr AVCodecContext, filter: string): (ptr AVFilterGraph,
    ptr AVFilterContext, ptr AVFilterContext) =
  ## Create FFmpeg filter graph for frame processing
  ## (Copied from motion.nim pattern)
  var filterGraph: ptr AVFilterGraph = avfilter_graph_alloc()
  var bufferSrc: ptr AVFilterContext = nil
  var bufferSink: ptr AVFilterContext = nil

  if filterGraph == nil:
    error "Could not allocate filter graph"

  let width = codecCtx.width
  let height = codecCtx.height

  # Create buffer source with proper arguments
  let bufferArgs = cstring(
    &"video_size={width}x{height}:pix_fmt={pixFmtName}:time_base={timeBase.num}/{timeBase.den}:pixel_aspect=1/1"
  )

  var ret = avfilter_graph_create_filter(addr bufferSrc, avfilter_get_by_name("buffer"),
                                        "in", bufferArgs, nil, filterGraph)
  if ret < 0:
    error &"Cannot create buffer source with args: {bufferArgs}, error code: {ret}"

  # Create buffer sink
  ret = avfilter_graph_create_filter(addr bufferSink, avfilter_get_by_name("buffersink"),
                                    "out", nil, nil, filterGraph)
  if ret < 0:
    error "Cannot create buffer sink"

  # Parse and configure the filter chain
  var inputs = avfilter_inout_alloc()
  var outputs = avfilter_inout_alloc()

  if inputs == nil or outputs == nil:
    error "Could not allocate filter inputs/outputs"

  outputs.name = av_strdup("in")
  outputs.filter_ctx = bufferSrc
  outputs.pad_idx = 0
  outputs.next = nil

  inputs.name = av_strdup("out")
  inputs.filter_ctx = bufferSink
  inputs.pad_idx = 0
  inputs.next = nil

  let filterC = filter.cstring
  ret = avfilter_graph_parse_ptr(filterGraph, filterC, addr inputs, addr outputs, nil)
  if ret < 0:
    error "Could not parse filter graph"

  ret = avfilter_graph_config(filterGraph, nil)
  if ret < 0:
    error "Could not configure filter graph"

  avfilter_inout_free(addr inputs)
  avfilter_inout_free(addr outputs)

  return (filterGraph, bufferSrc, bufferSink)

iterator facesPipeline*(processor: VideoProcessor,
                        sampler: var AdaptiveSampler,
                        targetHeight: int = 480): tuple[frame: ptr AVFrame,
                                                        sceneScore: float,
                                                        timestamp: float64] =
  ## Iterator yielding frames at adaptive sampling rate with scene change detection
  ##
  ## Args:
  ##   processor: Video processor with open stream
  ##   sampler: Adaptive sampler controlling frame selection
  ##   targetHeight: Target height for face detection (default 480)
  ##
  ## Yields:
  ##   Tuple of (frame, sceneScore, timestamp) for adaptive-rate frames
  ##
  ## Filter chain (adaptive based on available FFmpeg filters):
  ## - fps: Frame rate limiting (if available, otherwise handled by sampler)
  ## - scale: Resize for faster face detection (required)
  ## - format: BGR24 required by libfacedetection (required)
  ## - scdet: Scene change detection for adaptive sampling (if available)

  var packet = av_packet_alloc()
  var frame = av_frame_alloc()
  var filteredFrame = av_frame_alloc()
  var ret: cint

  if packet == nil or frame == nil or filteredFrame == nil:
    error "Could not allocate packet/frame"

  defer:
    av_packet_free(addr packet)
    av_frame_free(addr frame)
    av_frame_free(addr filteredFrame)
    if processor.codecCtx != nil:
      avcodec_free_context(addr processor.codecCtx)

  let timeBase = processor.tb

  let pixelFormat = processor.codecCtx.pix_fmt
  let pixFmtName = av_get_pix_fmt_name(pixelFormat)
  if pixFmtName == nil:
    error &"Could not get pixel format name for format: {ord(pixelFormat)}"

  # Build filter chain dynamically based on available filters
  # Check which optional filters are available in this FFmpeg build
  let hasFpsFilter = avfilter_get_by_name("fps") != nil
  let hasScdetFilter = avfilter_get_by_name("scdet") != nil

  var filterParts: seq[string] = @[]

  # fps filter - limits frame rate before processing (optional optimization)
  if hasFpsFilter:
    let fpsStr = if sampler.maxFps == float(int(sampler.maxFps)):
                   $int(sampler.maxFps)
                 else:
                   let num = int(sampler.maxFps * 1000)
                   &"{num}/1000"
    filterParts.add(&"fps={fpsStr}")

  # scale and format - required for face detection
  filterParts.add(&"scale=-1:{targetHeight}")
  filterParts.add("format=bgr24")

  # scdet filter - scene change detection (optional, enables adaptive sampling)
  if hasScdetFilter:
    let scdetStr = formatFloat(sampler.sceneThreshold, ffDecimal, 1)
    filterParts.add(&"scdet=t={scdetStr}:s=1")

  let filter = filterParts.join(",")

  let (filterGraph, bufferSrc, bufferSink) = createFilterGraph(
    timeBase, pixFmtName, processor.codecCtx, filter
  )

  defer:
    if filterGraph != nil:
      avfilter_graph_free(addr filterGraph)

  while av_read_frame(processor.formatCtx, packet) >= 0:
    defer: av_packet_unref(packet)

    if packet.stream_index == processor.videoIndex:
      ret = avcodec_send_packet(processor.codecCtx, packet)
      if ret < 0 and ret != AVERROR_EAGAIN:
        error &"Error sending packet to decoder: {av_err2str(ret)}"

      while ret >= 0:
        ret = avcodec_receive_frame(processor.codecCtx, frame)
        if ret == AVERROR_EAGAIN or ret == AVERROR_EOF:
          break
        elif ret < 0:
          error &"Error receiving frame from decoder: {av_err2str(ret)}"

        if frame.pts == AV_NOPTS_VALUE:
          continue

        if av_buffersrc_write_frame(bufferSrc, frame) < 0:
          error "Error adding frame to filter"

        ret = av_buffersink_get_frame(bufferSink, filteredFrame)
        if ret < 0:
          continue

        # Extract timestamp
        let timestamp = (filteredFrame.pts * processor.formatCtx.streams[
            processor.videoIndex].time_base).float64

        # Extract scene score from metadata
        var sceneScore = 0.0
        if filteredFrame.metadata != nil:
          let metaDict = avdict_to_dict(filteredFrame.metadata)
          if metaDict.hasKey("lavfi.scd.score"):
            try:
              sceneScore = parseFloat(metaDict["lavfi.scd.score"])
            except ValueError:
              sceneScore = 0.0

        # Check if this frame should be sampled (adaptive rate control)
        if sampler.shouldSampleFrame(timestamp):
          yield (filteredFrame, sceneScore, timestamp)

        av_frame_unref(filteredFrame)

  # Flush decoder
  discard avcodec_send_packet(processor.codecCtx, nil)
  while avcodec_receive_frame(processor.codecCtx, frame) >= 0:
    if frame.pts == AV_NOPTS_VALUE:
      continue

    ret = av_buffersrc_write_frame(bufferSrc, frame)
    if ret >= 0:
      ret = av_buffersink_get_frame(bufferSink, filteredFrame)
      if ret >= 0:
        let timestamp = (filteredFrame.pts * processor.formatCtx.streams[
            processor.videoIndex].time_base).float64

        var sceneScore = 0.0
        if filteredFrame.metadata != nil:
          let metaDict = avdict_to_dict(filteredFrame.metadata)
          if metaDict.hasKey("lavfi.scd.score"):
            try:
              sceneScore = parseFloat(metaDict["lavfi.scd.score"])
            except ValueError:
              sceneScore = 0.0

        if sampler.shouldSampleFrame(timestamp):
          yield (filteredFrame, sceneScore, timestamp)

        av_frame_unref(filteredFrame)

# ===== Main face analysis function =====

type
  FaceAnalysisParams* = object
    ## Parameters for face analysis
    stream*: int32          # Video stream index (default 0)
    targetHeight*: int32    # Scale height for detection (default 480)
    minConfidence*: float   # Detection confidence threshold (default 0.3)
    consensusWindow*: int   # Frames for consensus (default 3)
    consensusThreshold*: float  # Agreement ratio (default 0.6)
    minFaceRatio*: float    # Min face height as frame ratio (default 0.05)
    baseFps*: float         # Baseline sampling (default 1.0)
    maxFps*: float          # Max sampling during spikes (default 5.0)
    sceneThreshold*: float  # Scene change threshold (default 0.4)

proc toCacheArgs(params: FaceAnalysisParams): string =
  ## Convert params to cache key string for proper invalidation
  ## Include ALL parameters that affect output
  fmt"{params.stream},{params.targetHeight},{params.minConfidence}," &
  fmt"{params.consensusWindow},{params.consensusThreshold},{params.minFaceRatio}," &
  fmt"{params.baseFps},{params.maxFps},{params.sceneThreshold}"

proc toCachedFace(face: FaceDetection): CachedFace =
  ## Convert runtime face to cache format
  CachedFace(
    x: face.x.uint16,
    y: face.y.uint16,
    width: face.width.uint16,
    height: face.height.uint16,
    confidence: face.confidence.float32,
    angle: face.angle.int16,
    stable: face.stable
  )

proc toFaceDetection(cached: CachedFace, frameIndex: int64): FaceDetection =
  ## Convert cached face to runtime format
  FaceDetection(
    x: cached.x.int,
    y: cached.y.int,
    width: cached.width.int,
    height: cached.height.int,
    confidence: cached.confidence.float,
    angle: cached.angle.int,
    frameIndex: frameIndex,
    stable: cached.stable
  )

proc toCacheEntries(frames: seq[FrameFaces]): seq[FaceCacheEntry] =
  ## Convert runtime frames to cache entries
  result = newSeq[FaceCacheEntry](frames.len)
  for i, frame in frames:
    result[i] = FaceCacheEntry(
      frameIndex: frame.frameIndex.uint32,
      timestamp: frame.timestamp.float32,
      faces: newSeq[CachedFace](frame.faces.len)
    )
    for j, face in frame.faces:
      result[i].faces[j] = toCachedFace(face)

proc fromCacheEntries(entries: seq[FaceCacheEntry]): seq[FrameFaces] =
  ## Convert cache entries to runtime frames
  result = newSeq[FrameFaces](entries.len)
  for i, entry in entries:
    result[i] = FrameFaces(
      frameIndex: entry.frameIndex.int64,
      timestamp: entry.timestamp.float64,
      faces: newSeq[FaceDetection](entry.faces.len)
    )
    for j, cached in entry.faces:
      result[i].faces[j] = toFaceDetection(cached, entry.frameIndex.int64)

proc faces*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
            params: FaceAnalysisParams = FaceAnalysisParams(
              stream: 0,
              targetHeight: 480,
              minConfidence: 0.3,
              consensusWindow: 3,
              consensusThreshold: 0.6,
              minFaceRatio: 0.05,
              baseFps: 1.0,
              maxFps: 5.0,
              sceneThreshold: 0.4
            )): seq[FrameFaces] =
  ## Main face analysis function - analyzes video and returns stable face detections
  ##
  ## This is the primary API for face detection. It:
  ## 1. Checks cache for previous results
  ## 2. Validates stream index
  ## 3. Processes video with adaptive sampling
  ## 4. Applies consensus filtering for stability
  ## 5. Caches results for future runs
  ##
  ## Args:
  ##   bar: Progress bar for user feedback
  ##   container: Opened video container
  ##   path: Path to video file (for cache key)
  ##   tb: Time base (AVRational)
  ##   params: Analysis parameters (optional, uses defaults)
  ##
  ## Returns:
  ##   Sequence of FrameFaces with stable detections
  ##
  ## Cache location: .honeyclip/ folder alongside video file
  ## Cache invalidation: Any parameter change invalidates cache

  # 1. Check cache first
  let cacheArgs = params.toCacheArgs()
  let cacheData = readFaceCache(path, tb, cacheArgs)
  if cacheData.isSome:
    return fromCacheEntries(cacheData.get())

  # 2. Validate stream index
  if params.stream < 0 or params.stream >= container.video.len:
    error fmt"faces: video stream '{params.stream}' does not exist."

  # 3. Set up video processor
  let videoStream: ptr AVStream = container.video[params.stream]
  var processor = VideoProcessor(
    formatCtx: container.formatContext,
    codecCtx: initDecoder(videoStream.codecpar),
    tb: tb,
    videoIndex: videoStream.index,
  )

  # 4. Initialize consensus and sampler
  var consensus = newFaceConsensus(params.consensusWindow, params.consensusThreshold, params.minFaceRatio)
  var sampler = newAdaptiveSampler(params.baseFps, params.maxFps, params.sceneThreshold)

  # 5. Calculate duration for progress bar
  var inaccurateDur: float = 1024.0
  if videoStream.duration != AV_NOPTS_VALUE and videoStream.time_base != AV_NOPTS_VALUE:
    inaccurateDur = float(videoStream.duration) * float(videoStream.time_base * tb)
  elif container.duration != 0.0:
    inaccurateDur = container.duration / float(tb)

  # 6. Process frames
  bar.start(inaccurateDur, "Detecting faces")
  for (frame, sceneScore, timestamp) in processor.facesPipeline(sampler, params.targetHeight):
    let frameIndex = round(timestamp * tb.float64).int64

    # Detect faces in frame
    let rawFaces = detectFaces(
      frame.data[0],
      frame.width.int, frame.height.int,
      frame.linesize[0].int,
      frameIndex,
      params.minConfidence
    )

    # Filter by size
    let filteredFaces = filterBySize(rawFaces, frame.height.int, params.minFaceRatio)

    # Add to consensus
    consensus.addFrame(filteredFaces)

    # Get stable faces for this frame
    let stableFaces = consensus.getStableFaces()

    result.add(FrameFaces(
      frameIndex: frameIndex,
      timestamp: timestamp,
      faces: stableFaces
    ))

    bar.tick(frameIndex.float)

  bar.`end`()

  # 7. Write cache
  writeFaceCache(toCacheEntries(result), path, tb, cacheArgs)
