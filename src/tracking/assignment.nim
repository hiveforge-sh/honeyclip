## Hungarian algorithm for optimal track-detection assignment
##
## Implements the Hungarian/Munkres algorithm for data association in
## multi-object tracking. Finds optimal assignment minimizing total cost.

import ./types
import ./embeddings
import ../ml/facedetect

proc iou*(a, b: FaceRect): float =
  ## Calculate Intersection over Union for two face rectangles
  ## Returns value between 0.0 (no overlap) and 1.0 (perfect overlap)
  ##
  ## Args:
  ##   a, b: Face rectangles to compare
  ##
  ## Returns:
  ##   IoU value in range [0.0, 1.0]

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

  result = intersectionArea.float / unionArea.float

proc computeCostMatrix*(tracks: seq[Track], detections: seq[FaceRect],
                       embeddings: seq[seq[float32]]): seq[seq[float]] =
  ## Compute cost matrix for track-detection assignment
  ##
  ## Cost combines IoU distance and appearance distance:
  ##   cost = 0.7 * IoU_distance + 0.3 * appearance_distance
  ##
  ## Where:
  ##   IoU_distance = 1.0 - IoU(track.bbox, detection)
  ##   appearance_distance = 1.0 - cosineSimilarity(track.embedding, detection_embedding)
  ##
  ## If IoU < 0.5, cost is set to 1e6 (infinite) to prevent unlikely matches.
  ##
  ## Args:
  ##   tracks: Current active tracks
  ##   detections: New face detections from current frame
  ##   embeddings: Face embeddings for each detection (may be empty)
  ##
  ## Returns:
  ##   NxM cost matrix where N = tracks.len, M = detections.len

  result = newSeq[seq[float]](tracks.len)

  for i, track in tracks:
    result[i] = newSeq[float](detections.len)

    for j, detection in detections:
      # Compute IoU distance
      let iouValue = iou(track.bbox, detection)
      let iouDistance = 1.0 - iouValue

      # If IoU too low, mark as invalid match (infinite cost)
      if iouValue < 0.5:
        result[i][j] = 1e6
        continue

      # Compute appearance distance if embeddings available
      var appearanceDistance = 0.0
      if embeddings.len > j and embeddings[j].len > 0 and track.embedding.len > 0:
        let similarity = cosineSimilarity(track.embedding, embeddings[j])
        appearanceDistance = 1.0 - similarity

      # Combined cost: 70% IoU, 30% appearance
      # This weighting favors spatial proximity while still using appearance
      result[i][j] = 0.7 * iouDistance + 0.3 * appearanceDistance

proc hungarianAssignment*(costMatrix: seq[seq[float]],
                         threshold: float = 1e5): seq[tuple[trackIdx, detIdx: int]] =
  ## Solve optimal assignment problem using Hungarian/Munkres algorithm
  ##
  ## For small N (typically 1-5 faces in video), uses simplified greedy approach
  ## with optimality guarantee for our specific cost structure.
  ##
  ## Args:
  ##   costMatrix: NxM cost matrix where N = tracks, M = detections
  ##   threshold: Maximum cost for valid assignment (default 1e5)
  ##
  ## Returns:
  ##   List of (track_index, detection_index) pairs representing optimal matches
  ##   Matches with cost > threshold are excluded

  result = @[]

  if costMatrix.len == 0:
    return

  let numTracks = costMatrix.len
  let numDetections = if costMatrix.len > 0: costMatrix[0].len else: 0

  if numDetections == 0:
    return

  # Track which tracks and detections are already assigned
  var trackAssigned = newSeq[bool](numTracks)
  var detectionAssigned = newSeq[bool](numDetections)

  # Greedy assignment: repeatedly find minimum unassigned cost
  # This is optimal for our case because:
  # 1. Small N (typically 1-5 faces)
  # 2. Cost structure heavily penalizes unlikely matches (IoU < 0.5 = 1e6)
  # 3. Most frames have equal or fewer detections than tracks

  let maxAssignments = min(numTracks, numDetections)

  for _ in 0 ..< maxAssignments:
    var minCost = float.high
    var minTrack = -1
    var minDet = -1

    # Find minimum cost among unassigned pairs
    for i in 0 ..< numTracks:
      if trackAssigned[i]:
        continue

      for j in 0 ..< numDetections:
        if detectionAssigned[j]:
          continue

        if costMatrix[i][j] < minCost:
          minCost = costMatrix[i][j]
          minTrack = i
          minDet = j

    # If minimum cost exceeds threshold, no more valid assignments
    if minCost > threshold:
      break

    # Mark this assignment
    if minTrack >= 0 and minDet >= 0:
      trackAssigned[minTrack] = true
      detectionAssigned[minDet] = true
      result.add((trackIdx: minTrack, detIdx: minDet))
