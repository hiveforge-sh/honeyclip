## Crop region calculation for speaker framing
##
## Calculates crop regions that center speakers with medium shot framing
## (head and shoulders visible). Handles edge cases like faces near boundaries.

import std/math
import ../ml/facedetect
import ../tracking/types
import ./easing

export CropRegion

type
  AspectRatio* = enum
    ## Target aspect ratio for reframing
    Landscape = "16:9"   # 16:9 horizontal
    Portrait = "9:16"    # 9:16 vertical (social media)
    Square = "1:1"       # 1:1 square

proc aspectRatioValue*(aspect: AspectRatio): float =
  ## Get numeric aspect ratio value (width/height)
  ##
  ## Returns:
  ##   Aspect ratio as float (width / height)
  case aspect:
  of Landscape: 16.0 / 9.0
  of Portrait: 9.0 / 16.0
  of Square: 1.0

proc mediumShotPadding*(faceHeight: int): int =
  ## Calculate vertical padding for medium shot framing
  ##
  ## Medium shot framing shows head and shoulders, providing context
  ## while keeping the face prominent. Standard interview/podcast style.
  ##
  ## Args:
  ##   faceHeight: Height of detected face bounding box
  ##
  ## Returns:
  ##   Total height including padding (face + head room + shoulders)
  ##
  ## Formula: faceHeight * 2.5 (face + headroom + shoulders)
  int(faceHeight.float * 2.5)

proc calculateCrop*(face: FaceRect, frameWidth, frameHeight: int,
                   targetAspect: AspectRatio): CropRegion =
  ## Calculate crop region centered on face with medium shot framing
  ##
  ## Centers the crop on the face while maintaining target aspect ratio
  ## and constraining to frame boundaries. Applies medium shot padding
  ## to keep head and shoulders visible.
  ##
  ## Args:
  ##   face: Detected face bounding box
  ##   frameWidth: Source frame width in pixels
  ##   frameHeight: Source frame height in pixels
  ##   targetAspect: Target aspect ratio for crop
  ##
  ## Returns:
  ##   Crop region that frames the face with proper padding
  ##
  ## Handles edge cases:
  ##   - Face near frame boundaries (constrains to valid region)
  ##   - Face larger than target crop (centers face, may clip edges)

  # Calculate face center point
  let faceCenterX = face.x + face.width div 2
  let faceCenterY = face.y + face.height div 2

  # Calculate crop dimensions with medium shot padding
  let cropHeight = mediumShotPadding(face.height)
  let aspectValue = aspectRatioValue(targetAspect)
  let cropWidth = int(cropHeight.float * aspectValue)

  # Center crop on face
  var cropX = faceCenterX - cropWidth div 2
  var cropY = faceCenterY - cropHeight div 2

  # Constrain to frame boundaries
  # Prevent crop from extending outside source frame
  if cropX < 0:
    cropX = 0
  if cropY < 0:
    cropY = 0
  if cropX + cropWidth > frameWidth:
    cropX = frameWidth - cropWidth
  if cropY + cropHeight > frameHeight:
    cropY = frameHeight - cropHeight

  # Handle case where crop is larger than frame
  # Fall back to maximum possible crop
  var finalWidth = cropWidth
  var finalHeight = cropHeight
  if cropWidth > frameWidth:
    finalWidth = frameWidth
    cropX = 0
  if cropHeight > frameHeight:
    finalHeight = frameHeight
    cropY = 0

  result = CropRegion(
    x: cropX,
    y: cropY,
    width: finalWidth,
    height: finalHeight,
    timestamp: 0.0  # Set by caller
  )

proc calculateFallbackCrop*(frameWidth, frameHeight: int,
                           targetAspect: AspectRatio): CropRegion =
  ## Calculate center crop when no face detected
  ##
  ## Provides graceful fallback when face detection fails (screen share,
  ## B-roll, temporary occlusion). Centers the crop on the frame.
  ##
  ## Args:
  ##   frameWidth: Source frame width in pixels
  ##   frameHeight: Source frame height in pixels
  ##   targetAspect: Target aspect ratio for crop
  ##
  ## Returns:
  ##   Centered crop region at target aspect ratio

  let aspectValue = aspectRatioValue(targetAspect)

  # Calculate crop dimensions maintaining aspect ratio
  # Fit to frame while maintaining target aspect
  var cropWidth: int
  var cropHeight: int

  let frameAspect = frameWidth.float / frameHeight.float

  if frameAspect > aspectValue:
    # Frame is wider than target - fit height
    cropHeight = frameHeight
    cropWidth = int(cropHeight.float * aspectValue)
  else:
    # Frame is taller than target - fit width
    cropWidth = frameWidth
    cropHeight = int(cropWidth.float / aspectValue)

  # Center the crop
  let cropX = (frameWidth - cropWidth) div 2
  let cropY = (frameHeight - cropHeight) div 2

  result = CropRegion(
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
    timestamp: 0.0  # Set by caller
  )

proc interpolateCrop*(start, finish: CropRegion, t: float,
                     preset: EasingPreset): CropRegion =
  ## Interpolate between two crop regions with easing
  ##
  ## Creates smooth transitions between crop positions using cubic-bezier
  ## easing curves. Prevents jarring "snap" between speakers.
  ##
  ## Args:
  ##   start: Starting crop region
  ##   finish: Ending crop region
  ##   t: Time parameter in range [0, 1]
  ##   preset: Easing preset (Slow, Medium, Fast)
  ##
  ## Returns:
  ##   Interpolated crop region at parameter t

  # Apply easing to linear time parameter
  let easedT = easingFunction(t, preset)

  # Interpolate each field
  result = CropRegion(
    x: int(lerp(start.x.float, finish.x.float, easedT)),
    y: int(lerp(start.y.float, finish.y.float, easedT)),
    width: int(lerp(start.width.float, finish.width.float, easedT)),
    height: int(lerp(start.height.float, finish.height.float, easedT)),
    timestamp: lerp(start.timestamp, finish.timestamp, t)  # Linear time, not eased
  )

proc shouldSwitchTarget*(currentTarget, newTarget: CropRegion,
                        threshold: float = 20.0): bool =
  ## Determine if crop target should change
  ##
  ## Implements debouncing to prevent flicker in rapid dialogue.
  ## Only switches if the new target differs significantly from current.
  ##
  ## Args:
  ##   currentTarget: Current crop region
  ##   newTarget: Proposed new crop region
  ##   threshold: Minimum pixel distance to trigger switch (default 20.0)
  ##
  ## Returns:
  ##   true if switch warranted, false to hold current target
  ##
  ## Note: Caller must also implement 0.5 second minimum hold time
  ## (per CONTEXT.md) in addition to this spatial check

  # Calculate center point distance
  let currentCenterX = currentTarget.x + currentTarget.width div 2
  let currentCenterY = currentTarget.y + currentTarget.height div 2
  let newCenterX = newTarget.x + newTarget.width div 2
  let newCenterY = newTarget.y + newTarget.height div 2

  let deltaX = (newCenterX - currentCenterX).float
  let deltaY = (newCenterY - currentCenterY).float
  let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

  # Switch if distance exceeds threshold
  result = distance > threshold
