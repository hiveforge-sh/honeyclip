## Kalman filter for face tracking motion prediction
##
## Implements simplified Kalman filter for tracking face bounding boxes
## through temporary occlusion using constant velocity model.

import ./types
import ../ml/facedetect

type
  KalmanFilter* = object
    ## Simplified Kalman filter for bbox tracking
    ## State: [x, y, width, height, vx, vy]
    ## Uses diagonal covariance for computational efficiency
    state*: array[6, float]             # Position, size, and velocity
    covariance*: array[6, array[6, float]]  # Uncertainty matrix
    processNoise*: float                # Noise added during prediction (default 0.01)
    measurementNoise*: float            # Detection noise (default 0.1)

proc newKalmanFilter*(bbox: FaceRect, processNoise: float = 0.01,
                      measurementNoise: float = 0.1): KalmanFilter =
  ## Initialize Kalman filter from first detection
  ##
  ## Args:
  ##   bbox: Initial face detection
  ##   processNoise: Noise added during prediction (default 0.01)
  ##   measurementNoise: Detection noise (default 0.1)
  ##
  ## Returns:
  ##   Initialized Kalman filter with zero velocity
  result = KalmanFilter(
    processNoise: processNoise,
    measurementNoise: measurementNoise
  )

  # Initialize state: position and size from bbox, zero velocity
  result.state[0] = bbox.x.float
  result.state[1] = bbox.y.float
  result.state[2] = bbox.width.float
  result.state[3] = bbox.height.float
  result.state[4] = 0.0  # vx
  result.state[5] = 0.0  # vy

  # Initialize covariance diagonal to 1.0 (initial uncertainty)
  for i in 0..5:
    for j in 0..5:
      if i == j:
        result.covariance[i][j] = 1.0
      else:
        result.covariance[i][j] = 0.0

proc predict*(kf: var KalmanFilter): FaceRect =
  ## Predict next position using constant velocity model
  ## Increases uncertainty due to process noise
  ##
  ## Args:
  ##   kf: Kalman filter to predict from
  ##
  ## Returns:
  ##   Predicted bounding box with confidence 0.5 (predicted, not detected)

  # Apply constant velocity model
  kf.state[0] += kf.state[4]  # x += vx
  kf.state[1] += kf.state[5]  # y += vy
  # width and height remain constant

  # Increase covariance diagonal by process noise (uncertainty grows)
  for i in 0..5:
    kf.covariance[i][i] += kf.processNoise

  # Return predicted bbox
  result = FaceRect(
    x: kf.state[0].int,
    y: kf.state[1].int,
    width: kf.state[2].int,
    height: kf.state[3].int,
    confidence: 0.5,  # Predicted, not detected
    angle: 0
  )

proc update*(kf: var KalmanFilter, detection: FaceRect) =
  ## Update filter state with new detection
  ## Reduces uncertainty by incorporating measurement
  ##
  ## Args:
  ##   kf: Kalman filter to update
  ##   detection: New detection to incorporate

  # Store previous position for velocity calculation
  let prevX = kf.state[0]
  let prevY = kf.state[1]

  # Simplified Kalman gain (diagonal covariance only)
  # K = P / (P + R) for each state variable
  for i in 0..3:  # Update position and size, not velocity directly
    let P = kf.covariance[i][i]
    let R = kf.measurementNoise
    let K = P / (P + R)

    # Measurement for each state variable
    var measurement: float
    case i
    of 0: measurement = detection.x.float
    of 1: measurement = detection.y.float
    of 2: measurement = detection.width.float
    of 3: measurement = detection.height.float
    else: measurement = 0.0

    # Update state: state = state + K * (measurement - state)
    kf.state[i] = kf.state[i] + K * (measurement - kf.state[i])

    # Reduce covariance: P = (1 - K) * P
    kf.covariance[i][i] = (1.0 - K) * P

  # Update velocity from position change
  kf.state[4] = kf.state[0] - prevX  # vx = dx
  kf.state[5] = kf.state[1] - prevY  # vy = dy

proc getBbox*(kf: KalmanFilter): tuple[x, y, w, h: int] =
  ## Get current bounding box from filter state
  ##
  ## Args:
  ##   kf: Kalman filter
  ##
  ## Returns:
  ##   Tuple of (x, y, width, height)
  result = (
    x: kf.state[0].int,
    y: kf.state[1].int,
    w: kf.state[2].int,
    h: kf.state[3].int
  )
