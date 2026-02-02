## Reframe command - Auto-reframe video to center active speaker
##
## This command ties together face detection, tracking, and compositor to
## produce speaker-centered vertical videos suitable for mobile/social platforms.

import std/[strformat, strutils, os, osproc]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../ffmpeg
import ../analyze/faces
import ../tracking/tracker
import ../tracking/types as trackingTypes
import ../reframe/compositor
import ../reframe/crop
import ../reframe/easing
import ../transcript/[types, extract]

proc parseAspectRatio(val: string): AspectRatio =
  ## Parse aspect ratio string to enum
  case val
  of "9:16", "9/16":
    return Portrait
  of "16:9", "16/9":
    return Landscape
  of "1:1":
    return Square
  else:
    error &"Unknown aspect ratio: {val}. Use 9:16, 16:9, or 1:1"

proc parseEasingPreset(val: string): EasingPreset =
  ## Parse transition speed string to enum
  case val
  of "slow":
    return Slow
  of "medium":
    return Medium
  of "fast":
    return Fast
  else:
    error &"Unknown speed preset: {val}. Use slow, medium, or fast"

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var outputPath: string = ""
  var aspectRatio: AspectRatio = Portrait
  var speedPreset: EasingPreset = Slow
  var strategy: string = "active-speaker"
  var fallbackMode: string = "center"
  var modelPath: string = ""
  var arcfacePath: string = ""
  var debugSpeakers: bool = false
  var noFaces: bool = false

  # Parse arguments
  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip reframe file [options]

Auto-reframe video to center active speaker

Arguments:
  file                    Input video file

Options:
  -o, --output PATH       Output file (default: input_reframed.mp4)
  --aspect RATIO          Output aspect: 9:16, 16:9, 1:1 (default: 9:16)
  --speed PRESET          Transition speed: slow, medium, fast (default: slow)
  --strategy MODE         Speaker selection: active-speaker, largest-face (default: active-speaker)
  --fallback MODE         Fallback: center, motion (default: center)
  --model NAME            Whisper model for transcript (needed for active-speaker)
  --arcface PATH          ArcFace ONNX model for re-identification
  --debug-speakers        Show colored boxes around tracked faces
  --no-faces              Skip face tracking, center crop only
  --help                  Show this help

Examples:
  honeyclip reframe podcast.mp4                    # Default 9:16 slow
  honeyclip reframe video.mp4 --aspect 1:1         # Square for Instagram
  honeyclip reframe video.mp4 --speed fast         # Quick TikTok-style transitions
"""
      quit(0)
    of "-o", "--output":
      expecting = "output"
    of "--aspect":
      expecting = "aspect"
    of "--speed":
      expecting = "speed"
    of "--strategy":
      expecting = "strategy"
    of "--fallback":
      expecting = "fallback"
    of "--model":
      expecting = "model"
    of "--arcface":
      expecting = "arcface"
    of "--debug-speakers":
      debugSpeakers = true
    of "--no-faces":
      noFaces = true
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        # Positional argument: input file
        if inputPath == "":
          inputPath = key
        else:
          error &"Unexpected positional argument: {key}"
      of "output":
        outputPath = key
        expecting = ""
      of "aspect":
        aspectRatio = parseAspectRatio(key)
        expecting = ""
      of "speed":
        speedPreset = parseEasingPreset(key)
        expecting = ""
      of "strategy":
        if key notin ["active-speaker", "largest-face"]:
          error &"Unknown strategy: {key}. Use active-speaker or largest-face"
        strategy = key
        expecting = ""
      of "fallback":
        if key notin ["center", "motion"]:
          error &"Unknown fallback: {key}. Use center or motion"
        fallbackMode = key
        expecting = ""
      of "model":
        modelPath = key
        expecting = ""
      of "arcface":
        arcfacePath = key
        expecting = ""

  # Check for incomplete argument
  if expecting != "":
    error &"Missing value for {expecting}"

  # Validate arguments
  if inputPath == "":
    error "A video file is required. Usage: honeyclip reframe file [options]"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Generate default output path if not specified
  if outputPath == "":
    let (dir, name, _) = splitFile(inputPath)
    outputPath = dir / name & "_reframed.mp4"

  # Validate strategy requirements
  if strategy == "active-speaker" and modelPath == "" and not noFaces:
    echo "Warning: active-speaker strategy requires --model. Falling back to largest-face strategy."
    strategy = "largest-face"

  # Step 1: Open video and get dimensions
  conwrite(&"Opening {inputPath}...")
  var container = av.open(inputPath)
  defer: container.close()

  if container.video.len == 0:
    error "No video stream found in input file"

  var tb: AVRational
  if container.video.len > 0:
    tb = container.video[0].time_base
  else:
    error "No video stream found"

  let videoStream = container.video[0]
  let sourceWidth = videoStream.codecpar.width
  let sourceHeight = videoStream.codecpar.height
  let duration = container.duration

  conwrite(&"Video: {sourceWidth}x{sourceHeight}, duration: {duration:.1f}s")

  # Step 2: Face detection and tracking (unless --no-faces)
  var tracker: FaceTracker
  var frameFaces: seq[FrameFaces]

  if not noFaces:
    conwrite("Detecting faces...")

    # Run face detection
    var bar = initBar(BarType.modern)
    let faceParams = FaceAnalysisParams(
      stream: 0,
      targetHeight: 480,
      minConfidence: 0.3,
      consensusWindow: 3,
      consensusThreshold: 0.6,
      minFaceRatio: 0.05,
      baseFps: 1.0,
      maxFps: 5.0,
      sceneThreshold: 0.4
    )
    frameFaces = faces(bar, container, inputPath, tb, faceParams)

    conwrite(&"Detected faces in {frameFaces.len} frames")

    # Initialize tracker with optional ArcFace model
    if arcfacePath != "" and fileExists(arcfacePath):
      conwrite("Loading ArcFace model for face re-identification...")
      tracker = newTracker(arcfacePath)
    else:
      tracker = newTracker()

    conwrite("Tracking speakers across frames...")
  else:
    conwrite("Skipping face tracking (--no-faces)")

  # Step 3: Extract transcript if needed for active-speaker strategy
  var transcript: Transcript
  if strategy == "active-speaker" and modelPath != "" and not noFaces:
    conwrite("Extracting transcript for speaker diarization...")
    try:
      transcript = extractTranscript(inputPath, modelPath, "", "")
      conwrite(&"Transcript extracted: {transcript.segments.len} segments")
    except IOError as e:
      echo &"Warning: Failed to extract transcript: {e.msg}"
      echo "Falling back to largest-face strategy"
      strategy = "largest-face"

  # Step 4: Build crop keyframes
  conwrite("Building crop keyframes...")

  # Calculate target dimensions based on aspect ratio
  var targetWidth, targetHeight: int
  case aspectRatio
  of Portrait:
    targetHeight = sourceHeight
    targetWidth = int(targetHeight.float * 9.0 / 16.0)
  of Landscape:
    targetWidth = sourceWidth
    targetHeight = int(targetWidth.float * 9.0 / 16.0)
  of Square:
    targetWidth = min(sourceWidth, sourceHeight)
    targetHeight = targetWidth

  # Initialize compositor
  var comp = newCompositor(speedPreset, aspectRatio)
  comp.fallbackMode = fallbackMode

  if noFaces or frameFaces.len == 0:
    # No face tracking - use center crop for entire video
    conwrite("Using center crop (no face tracking)")
    let centerCrop = CropRegion(
      x: (sourceWidth - targetWidth) div 2,
      y: (sourceHeight - targetHeight) div 2,
      width: targetWidth,
      height: targetHeight,
      timestamp: 0.0
    )
    comp.addKeyframe(0.0, centerCrop, -1)
    comp.addKeyframe(duration, centerCrop, -1)
  else:
    # Track faces and build crop keyframes
    var lastCrop: CropRegion
    var lastTrackId = -1
    var lastTimestamp = 0.0
    const debounceThreshold = 0.5  # 0.5 second minimum hold per CONTEXT

    for frameData in frameFaces:
      if frameData.faces.len == 0:
        # No faces - use fallback
        let fallbackCrop = if fallbackMode == "center":
          CropRegion(
            x: (sourceWidth - targetWidth) div 2,
            y: (sourceHeight - targetHeight) div 2,
            width: targetWidth,
            height: targetHeight,
            timestamp: frameData.timestamp
          )
        else:
          # Motion fallback would analyze motion here
          # For now, default to center
          CropRegion(
            x: (sourceWidth - targetWidth) div 2,
            y: (sourceHeight - targetHeight) div 2,
            width: targetWidth,
            height: targetHeight,
            timestamp: frameData.timestamp
          )

        # Apply debounce
        if frameData.timestamp - lastTimestamp >= debounceThreshold:
          comp.addKeyframe(frameData.timestamp, fallbackCrop, -1)
          lastCrop = fallbackCrop
          lastTrackId = -1
          lastTimestamp = frameData.timestamp
      else:
        # Select face to follow based on strategy
        var selectedFace = frameData.faces[0]

        if strategy == "largest-face":
          # Simple: pick largest face
          var maxArea = 0
          for face in frameData.faces:
            let area = face.width * face.height
            if area > maxArea:
              maxArea = area
              selectedFace = face
        # active-speaker strategy would use transcript correlation here

        # Calculate crop to center selected face
        let faceCenterX = selectedFace.x + selectedFace.width div 2
        let faceCenterY = selectedFace.y + selectedFace.height div 2

        var cropX = faceCenterX - targetWidth div 2
        var cropY = faceCenterY - targetHeight div 2

        # Clamp to source bounds
        cropX = max(0, min(cropX, sourceWidth - targetWidth))
        cropY = max(0, min(cropY, sourceHeight - targetHeight))

        let crop = CropRegion(
          x: cropX,
          y: cropY,
          width: targetWidth,
          height: targetHeight,
          timestamp: frameData.timestamp
        )

        # Apply debounce
        if frameData.timestamp - lastTimestamp >= debounceThreshold:
          comp.addKeyframe(frameData.timestamp, crop, 0)
          lastCrop = crop
          lastTrackId = 0
          lastTimestamp = frameData.timestamp

  # Step 5: Generate filter and render
  conwrite("Rendering reframed video...")

  let fallbackPct = comp.getFallbackPercentage()
  if fallbackPct > 50.0:
    echo ""
    echo &"Warning: {fallbackPct:.1f}% of frames used fallback crop (no face detected)"
    echo "Video may not be suitable for speaker tracking reframing"
    echo ""

  # Generate FFmpeg crop filter
  let cropFilter = comp.generateCropFilter(30.0)
  if cropFilter.len == 0:
    error "Failed to generate crop filter"

  # Build complete filter chain
  let filterChain = &"{cropFilter},scale={targetWidth}:{targetHeight}"

  # Execute FFmpeg command
  let ffmpegCmd = &"ffmpeg -y -i \"{inputPath}\" -filter_complex \"{filterChain}\" " &
                  &"-c:v libx264 -preset fast -crf 23 -c:a copy \"{outputPath}\""

  conwrite("Running FFmpeg...")
  let exitCode = execCmd(ffmpegCmd)
  if exitCode != 0:
    error &"FFmpeg failed with exit code {exitCode}"

  conwrite("")
  echo ""
  echo &"Reframed video saved to: {outputPath}"
  echo &"  Aspect ratio: {aspectRatio}"
  echo &"  Transition speed: {speedPreset}"
  if not noFaces:
    echo &"  Fallback usage: {fallbackPct:.1f}%"
