## OpenCV FFI wrapper
##
## Provides minimal type-safe interface to OpenCV for image processing.
## Covers core Mat operations, resizing, and color conversion.

type
  Mat* = object
    ## OpenCV matrix (image) wrapper
    handle: pointer

  Size* = object
    ## Image dimensions
    width*, height*: int

  ColorConversion* = enum
    ## Color space conversion codes
    COLOR_BGR2RGB = 4
    COLOR_BGR2GRAY = 6
    COLOR_RGB2GRAY = 7
    COLOR_GRAY2BGR = 8

  InterpolationMode* = enum
    ## Interpolation algorithms for resizing
    INTER_NEAREST = 0
    INTER_LINEAR = 1
    INTER_CUBIC = 2
    INTER_AREA = 3
    INTER_LANCZOS4 = 4

# C++ cv::Mat type and functions via importcpp
type
  CvMat {.importcpp: "cv::Mat", header: "opencv2/core.hpp".} = object
    rows: cint
    cols: cint
    data: ptr uint8

# Mat constructors
proc newMat(): CvMat {.importcpp: "cv::Mat()", constructor.}
proc newMat(rows, cols, cvType: cint): CvMat {.importcpp: "cv::Mat(@)", constructor.}
proc newMat(rows, cols, cvType: cint, data: pointer): CvMat
    {.importcpp: "cv::Mat(@)", constructor.}

# Mat operations
proc release(m: var CvMat) {.importcpp: "#.release()".}
proc clone(m: CvMat): CvMat {.importcpp: "#.clone()".}
proc empty(m: CvMat): bool {.importcpp: "#.empty()".}

# Image processing functions
proc cvResize(src, dst: var CvMat, dsize: tuple[width, height: cint],
              fx, fy: cdouble, interpolation: cint)
    {.importcpp: "cv::resize(@)", header: "opencv2/imgproc.hpp".}

proc cvCvtColor(src, dst: var CvMat, code: cint)
    {.importcpp: "cv::cvtColor(@)", header: "opencv2/imgproc.hpp".}

# OpenCV type constants
const
  CV_8UC1 = 0   # 8-bit unsigned, 1 channel (grayscale)
  CV_8UC3 = 16  # 8-bit unsigned, 3 channels (BGR)
  CV_8UC4 = 24  # 8-bit unsigned, 4 channels (BGRA)

proc createMat*(width, height: int, channels: int = 3): Mat =
  ## Create empty Mat with given dimensions
  ##
  ## Args:
  ##   width: Image width in pixels
  ##   height: Image height in pixels
  ##   channels: Number of channels (1=gray, 3=BGR, 4=BGRA)
  ##
  ## Returns:
  ##   Mat with allocated memory

  let cvType = case channels
    of 1: CV_8UC1
    of 3: CV_8UC3
    of 4: CV_8UC4
    else: raise newException(ValueError, "Unsupported channel count: " & $channels)

  var cvMat = newMat(height.cint, width.cint, cvType.cint)
  result.handle = cast[pointer](addr cvMat)

proc fromBuffer*(data: ptr uint8, width, height: int, channels: int = 3): Mat =
  ## Wrap existing buffer as Mat (no copy - buffer must stay alive)
  ##
  ## Args:
  ##   data: Pointer to image data (row-major, no padding)
  ##   width: Image width in pixels
  ##   height: Image height in pixels
  ##   channels: Number of channels (1=gray, 3=BGR, 4=BGRA)
  ##
  ## Returns:
  ##   Mat view of the buffer (does not own data)

  let cvType = case channels
    of 1: CV_8UC1
    of 3: CV_8UC3
    of 4: CV_8UC4
    else: raise newException(ValueError, "Unsupported channel count: " & $channels)

  var cvMat = newMat(height.cint, width.cint, cvType.cint, data)
  result.handle = cast[pointer](addr cvMat)

proc `=destroy`*(m: var Mat) =
  ## Automatic cleanup of Mat
  if m.handle != nil:
    var cvMat = cast[ptr CvMat](m.handle)
    cvMat[].release()
    m.handle = nil

proc data*(m: Mat): ptr uint8 =
  ## Get raw data pointer from Mat
  ##
  ## Returns:
  ##   Pointer to first pixel (row-major order)

  if m.handle == nil:
    return nil

  let cvMat = cast[ptr CvMat](m.handle)
  return cvMat[].data

proc width*(m: Mat): int =
  ## Get Mat width in pixels
  if m.handle == nil:
    return 0
  let cvMat = cast[ptr CvMat](m.handle)
  return cvMat[].cols.int

proc height*(m: Mat): int =
  ## Get Mat height in pixels
  if m.handle == nil:
    return 0
  let cvMat = cast[ptr CvMat](m.handle)
  return cvMat[].rows.int

proc isEmpty*(m: Mat): bool =
  ## Check if Mat is empty (no data)
  if m.handle == nil:
    return true
  let cvMat = cast[ptr CvMat](m.handle)
  return cvMat[].empty()

proc resize*(src: Mat, newWidth, newHeight: int,
             interpolation: InterpolationMode = INTER_LINEAR): Mat =
  ## Resize image to new dimensions
  ##
  ## Args:
  ##   src: Source Mat
  ##   newWidth: Target width in pixels
  ##   newHeight: Target height in pixels
  ##   interpolation: Interpolation algorithm
  ##
  ## Returns:
  ##   New resized Mat

  if src.handle == nil:
    raise newException(ValueError, "Cannot resize empty Mat")

  var srcMat = cast[ptr CvMat](src.handle)[]
  var dstMat = newMat()

  cvResize(srcMat, dstMat, (newWidth.cint, newHeight.cint),
           0.0, 0.0, interpolation.cint)

  # Wrap result in Mat
  result.handle = cast[pointer](alloc0(sizeof(CvMat)))
  cast[ptr CvMat](result.handle)[] = dstMat

proc cvtColor*(src: Mat, conversion: ColorConversion): Mat =
  ## Convert color space
  ##
  ## Args:
  ##   src: Source Mat
  ##   conversion: Color conversion code
  ##
  ## Returns:
  ##   New Mat with converted color space

  if src.handle == nil:
    raise newException(ValueError, "Cannot convert empty Mat")

  var srcMat = cast[ptr CvMat](src.handle)[]
  var dstMat = newMat()

  cvCvtColor(srcMat, dstMat, conversion.cint)

  # Wrap result in Mat
  result.handle = cast[pointer](alloc0(sizeof(CvMat)))
  cast[ptr CvMat](result.handle)[] = dstMat
