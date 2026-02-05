## Test utility functions for tolerance-based assertions
##
## Provides helper functions for floating point comparison with tolerance
## and bounding box comparison for tracking tests.

import ../../src/ml/facedetect

proc checkApprox*(a, b: float, epsilon: float = 1e-6): bool =
  ## Compare two floats with tolerance
  ##
  ## Args:
  ##   a, b: Values to compare
  ##   epsilon: Maximum allowed difference (default 1e-6)
  ##
  ## Returns:
  ##   true if |a - b| < epsilon
  result = abs(a - b) < epsilon

proc checkBboxApprox*(a, b: FaceRect, epsilon: float = 1.0): bool =
  ## Compare two bounding boxes with pixel tolerance
  ##
  ## Args:
  ##   a, b: FaceRects to compare
  ##   epsilon: Maximum allowed pixel difference (default 1.0)
  ##
  ## Returns:
  ##   true if all coordinates differ by less than epsilon
  result = abs(float(a.x - b.x)) < epsilon and
           abs(float(a.y - b.y)) < epsilon and
           abs(float(a.width - b.width)) < epsilon and
           abs(float(a.height - b.height)) < epsilon

proc checkCovariancePositive*(cov: array[6, array[6, float]]): bool =
  ## Verify covariance matrix diagonal elements are positive
  ##
  ## Args:
  ##   cov: 6x6 covariance matrix
  ##
  ## Returns:
  ##   true if all diagonal elements > 0
  result = true
  for i in 0..5:
    if cov[i][i] <= 0.0:
      return false
