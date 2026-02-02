## libfacedetection FFI wrapper
##
## Provides type-safe interface to libfacedetection CNN-based face detection.
## Uses buffer-based API with automatic cleanup.

type
  FaceRect* = object
    ## Detected face rectangle with confidence score
    x*, y*: int
    width*, height*: int
    confidence*: float  # 0.0-1.0
    angle*: int  # Rotation angle in degrees

# C API imports from facedetectcnn.h
proc facedetect_cnn(result_buffer: ptr cint, rgb_image_data: ptr uint8,
                    width, height, step: cint): cint
    {.importc, header: "facedetectcnn.h".}

const
  DETECT_BUFFER_SIZE = 0x9000  # Required buffer size per libfacedetection docs

proc parseResults(buffer: ptr cint): seq[FaceRect] =
  ## Parse the raw detection buffer into FaceRect sequence
  ## Buffer format: count, then for each face: x, y, w, h, neighbors, angle
  result = @[]

  if buffer == nil:
    return

  # Cast to unchecked array for indexing
  let arr = cast[ptr UncheckedArray[cint]](buffer)
  let count = arr[0].int
  if count <= 0:
    return

  # Each face occupies 6 cints: x, y, width, height, neighbors (confidence), angle
  var offset = 1
  for i in 0 ..< count:
    let
      x = arr[offset].int
      y = arr[offset + 1].int
      w = arr[offset + 2].int
      h = arr[offset + 3].int
      neighbors = arr[offset + 4].int
      angle = arr[offset + 5].int

    # neighbors represents detection confidence - higher values = more confident
    # Normalize to 0.0-1.0 range (typical range is 0-100+)
    let confidence = min(neighbors.float / 100.0, 1.0)

    result.add(FaceRect(
      x: x, y: y,
      width: w, height: h,
      confidence: confidence,
      angle: angle
    ))

    offset += 6

proc detect*(image: ptr uint8, width, height, step: int): seq[FaceRect] =
  ## Detect faces in BGR image data
  ## Returns sequence of detected face rectangles with confidence scores
  ##
  ## Args:
  ##   image: Pointer to BGR image data (not RGB!)
  ##   width: Image width in pixels
  ##   height: Image height in pixels
  ##   step: Row stride in bytes (usually width * 3 for BGR)
  ##
  ## Returns:
  ##   Sequence of FaceRect objects, sorted by confidence (highest first)

  # Allocate detection result buffer
  let buffer = cast[ptr cint](alloc(DETECT_BUFFER_SIZE))
  defer: dealloc(buffer)

  # Run CNN detection
  let numFaces = facedetect_cnn(buffer, image, width.cint, height.cint, step.cint)

  if numFaces <= 0:
    return @[]

  # Parse results from buffer
  result = parseResults(buffer)

proc detect*(image: seq[uint8], width, height: int, channels: int = 3): seq[FaceRect] =
  ## Convenience wrapper for seq[uint8] image data
  ##
  ## Args:
  ##   image: BGR image data as sequence
  ##   width: Image width in pixels
  ##   height: Image height in pixels
  ##   channels: Number of channels (default 3 for BGR)
  ##
  ## Returns:
  ##   Sequence of FaceRect objects

  if image.len != width * height * channels:
    raise newException(ValueError,
      "Image buffer size mismatch: expected " & $(width * height * channels) &
      " bytes, got " & $image.len)

  # Get pointer to sequence data and call pointer-based detect
  let imagePtr = cast[ptr uint8](unsafeAddr image[0])
  return detect(imagePtr, width, height, width * channels)
