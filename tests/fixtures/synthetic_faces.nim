## Synthetic face data generators for tracking tests
##
## Provides deterministic face sequence generators for testing
## Kalman filter and assignment algorithms.

import std/[random, options]
import ../../src/ml/facedetect

proc generateStraightLineFace*(startX, startY, width, height: int,
                               velocityX, velocityY: float,
                               numFrames: int,
                               confidence: float = 0.95): seq[FaceRect] =
  ## Generate a face moving in a straight line
  ##
  ## Args:
  ##   startX, startY: Initial position
  ##   width, height: Face dimensions (constant)
  ##   velocityX, velocityY: Pixels per frame
  ##   numFrames: Number of frames to generate
  ##   confidence: Detection confidence (default 0.95)
  ##
  ## Returns:
  ##   Sequence of FaceRects at each frame position
  result = newSeq[FaceRect](numFrames)
  for i in 0 ..< numFrames:
    result[i] = FaceRect(
      x: startX + int(float(i) * velocityX),
      y: startY + int(float(i) * velocityY),
      width: width,
      height: height,
      confidence: confidence,
      angle: 0
    )

proc generateCrossingPaths*(face1Start, face2Start: tuple[x, y: int],
                            face1Vel, face2Vel: tuple[x, y: float],
                            numFrames: int,
                            faceSize: int = 100): tuple[faces1, faces2: seq[FaceRect]] =
  ## Generate two faces crossing paths
  ##
  ## Args:
  ##   face1Start, face2Start: Initial positions of each face
  ##   face1Vel, face2Vel: Velocities (pixels per frame) for each face
  ##   numFrames: Number of frames to generate
  ##   faceSize: Width and height of faces (default 100)
  ##
  ## Returns:
  ##   Tuple of two FaceRect sequences
  result.faces1 = newSeq[FaceRect](numFrames)
  result.faces2 = newSeq[FaceRect](numFrames)

  for i in 0 ..< numFrames:
    result.faces1[i] = FaceRect(
      x: face1Start.x + int(float(i) * face1Vel.x),
      y: face1Start.y + int(float(i) * face1Vel.y),
      width: faceSize,
      height: faceSize,
      confidence: 0.92,
      angle: 0
    )
    result.faces2[i] = FaceRect(
      x: face2Start.x + int(float(i) * face2Vel.x),
      y: face2Start.y + int(float(i) * face2Vel.y),
      width: faceSize,
      height: faceSize,
      confidence: 0.88,
      angle: 0
    )

proc generateOcclusionScenario*(x, y, width, height: int,
                                disappearFrame, reappearFrame, totalFrames: int,
                                confidence: float = 0.9): seq[Option[FaceRect]] =
  ## Generate a face that disappears temporarily (occlusion)
  ##
  ## Args:
  ##   x, y, width, height: Face position and dimensions
  ##   disappearFrame: Frame when face disappears
  ##   reappearFrame: Frame when face reappears
  ##   totalFrames: Total frames in sequence
  ##   confidence: Detection confidence (default 0.9)
  ##
  ## Returns:
  ##   Sequence of Option[FaceRect] - none() during occlusion
  result = newSeq[Option[FaceRect]](totalFrames)
  let face = FaceRect(
    x: x, y: y,
    width: width, height: height,
    confidence: confidence,
    angle: 0
  )

  for i in 0 ..< totalFrames:
    if i >= disappearFrame and i < reappearFrame:
      result[i] = none(FaceRect)
    else:
      result[i] = some(face)

proc generateNoisyPath*(startX, startY, width, height: int,
                        velocityX, velocityY: float,
                        numFrames: int,
                        noiseStdDev: float = 2.0,
                        seed: int64 = 42): seq[FaceRect] =
  ## Generate a face moving with Gaussian noise on position
  ##
  ## Args:
  ##   startX, startY: Initial position
  ##   width, height: Face dimensions
  ##   velocityX, velocityY: Mean velocity per frame
  ##   numFrames: Number of frames
  ##   noiseStdDev: Standard deviation of position noise (default 2.0)
  ##   seed: Random seed for reproducibility (default 42)
  ##
  ## Returns:
  ##   Sequence of FaceRects with noisy positions
  var rng = initRand(seed)
  result = newSeq[FaceRect](numFrames)

  for i in 0 ..< numFrames:
    # Add Gaussian-like noise using Box-Muller approximation
    let noiseX = (rng.rand(2.0) - 1.0) * noiseStdDev
    let noiseY = (rng.rand(2.0) - 1.0) * noiseStdDev

    result[i] = FaceRect(
      x: max(0, startX + int(float(i) * velocityX + noiseX)),
      y: max(0, startY + int(float(i) * velocityY + noiseY)),
      width: width,
      height: height,
      confidence: 0.9,
      angle: 0
    )

when isMainModule and defined(testing):
  # Sanity tests for generators
  import std/strformat

  # Test generateStraightLineFace
  let straightLine = generateStraightLineFace(100, 100, 50, 50, 5.0, 2.0, 20)
  assert straightLine.len == 20, fmt"Expected 20 frames, got {straightLine.len}"
  assert straightLine[0].x == 100
  assert straightLine[0].y == 100
  assert straightLine[19].x == 100 + 19 * 5  # 195
  assert straightLine[19].y == 100 + 19 * 2  # 138

  # Test generateCrossingPaths
  let crossing = generateCrossingPaths(
    face1Start = (x: 0, y: 500),
    face2Start = (x: 1000, y: 500),
    face1Vel = (x: 10.0, y: 0.0),
    face2Vel = (x: -10.0, y: 0.0),
    numFrames = 50
  )
  assert crossing.faces1.len == 50
  assert crossing.faces2.len == 50
  assert crossing.faces1[0].x == 0
  assert crossing.faces2[0].x == 1000

  # Test generateOcclusionScenario
  let occlusion = generateOcclusionScenario(100, 100, 50, 50, 10, 20, 30)
  assert occlusion.len == 30
  assert occlusion[5].isSome
  assert occlusion[15].isNone
  assert occlusion[25].isSome

  # Verify FaceRect fields are valid
  for face in straightLine:
    assert face.x >= 0, "x should be non-negative"
    assert face.y >= 0, "y should be non-negative"
    assert face.width > 0, "width should be positive"
    assert face.height > 0, "height should be positive"

  echo "All synthetic_faces tests passed!"
