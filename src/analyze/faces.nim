## Face detection types and consensus algorithm
##
## Provides face detection types extending libfacedetection FaceRect with
## temporal consensus filtering to reduce false positives.

import std/algorithm
import ../ml/facedetect

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

proc iou(a, b: FaceDetection): float =
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

proc filterBySize(faces: seq[FaceDetection], frameHeight: int,
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
