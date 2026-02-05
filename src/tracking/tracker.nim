## DeepSORT-style multi-face tracker
##
## Implements persistent face tracking across frames using Kalman filter
## prediction and face embeddings for re-identification. Handles occlusion
## and identity preservation through optimal assignment.

import std/[options, sequtils]
import ./types
import ./kalman
import ./embeddings
import ./assignment
import ../ml/facedetect
import ../ffmpeg
import ../transcript/types

type
  FaceTracker* = object
    ## Multi-face tracker with persistent identity
    state*: TrackingState
    embedder*: Option[FaceEmbedder]    # Optional face embedder
    kalmanFilters*: seq[KalmanFilter]  # Kalman filters for each track
    iouThreshold*: float               # IoU match threshold (default 0.5)
    embeddingThreshold*: float         # Cosine similarity threshold (default 0.7)

  TrackerError* = object of CatchableError
    ## Exception raised when tracker operations fail

proc newTracker*(modelPath: string = "", maxAge: int = 90, minHits: int = 3): FaceTracker =
  ## Initialize face tracker with optional embedding model
  ##
  ## Args:
  ##   modelPath: Path to ArcFace ONNX model (empty = IoU-only tracking)
  ##   maxAge: Frames before track deletion (default 90 = 3s @ 30fps)
  ##   minHits: Minimum hits before track confirmed (default 3)
  ##
  ## Returns:
  ##   Initialized FaceTracker
  ##
  ## Note:
  ##   If modelPath is empty or model fails to load, tracker operates in
  ##   IoU-only mode (spatial proximity only, no appearance matching)

  result.state = newTrackingState(maxAge, minHits)
  result.kalmanFilters = @[]
  result.iouThreshold = 0.5
  result.embeddingThreshold = 0.7

  # Try to load embedder if model path provided
  if modelPath != "":
    try:
      result.embedder = some(initEmbedder(modelPath))
    except EmbeddingError:
      # Gracefully degrade to IoU-only mode
      result.embedder = none(FaceEmbedder)
  else:
    result.embedder = none(FaceEmbedder)

proc updateTracks*(tracker: var FaceTracker, detections: seq[FaceRect],
                  frame: ptr AVFrame): seq[Track] =
  ## Update tracks with new detections from current frame
  ##
  ## Implements DeepSORT tracking-by-detection pipeline:
  ## 1. Predict track positions using Kalman filter
  ## 2. Extract embeddings for new detections
  ## 3. Compute cost matrix (IoU + appearance)
  ## 4. Solve assignment with Hungarian algorithm
  ## 5. Update matched tracks
  ## 6. Create new tracks for unmatched detections
  ## 7. Delete stale tracks
  ##
  ## Args:
  ##   tracker: Face tracker to update
  ##   detections: New face detections from current frame
  ##   frame: Current video frame for embedding extraction
  ##
  ## Returns:
  ##   Updated list of active tracks

  # Step 1: Predict new positions for existing tracks
  # Ensure we have Kalman filters for all tracks
  while tracker.kalmanFilters.len < tracker.state.tracks.len:
    let track = tracker.state.tracks[tracker.kalmanFilters.len]
    tracker.kalmanFilters.add(newKalmanFilter(track.bbox))

  var predictedBboxes = newSeq[FaceRect](tracker.state.tracks.len)
  for i in 0 ..< tracker.state.tracks.len:
    # Predict next position using Kalman filter
    predictedBboxes[i] = tracker.kalmanFilters[i].predict()

  # Step 2: Extract embeddings for detections (if embedder available)
  var detectionEmbeddings = newSeq[seq[float32]](detections.len)
  if tracker.embedder.isSome and frame != nil:
    let embedder = tracker.embedder.get()
    for i, det in detections:
      # Extract face embedding from frame
      # Frame format: linesize[0] = stride, data[0] = BGR data
      let stride = frame.linesize[0]
      let imageData = frame.data[0]
      let width = frame.width
      let height = frame.height

      detectionEmbeddings[i] = embedder.extractEmbedding(
        imageData, det.x, det.y, det.width, det.height,
        stride, width, height
      )

  # Step 3: Compute cost matrix
  let costMatrix = computeCostMatrix(
    tracker.state.tracks,
    detections,
    detectionEmbeddings
  )

  # Step 4: Hungarian assignment
  let matches = hungarianAssignment(costMatrix, threshold = 1e5)

  # Track which detections and tracks were matched
  var matchedDetections = newSeq[bool](detections.len)
  var matchedTracks = newSeq[bool](tracker.state.tracks.len)

  # Step 5: Update matched tracks
  for (trackIdx, detIdx) in matches:
    matchedTracks[trackIdx] = true
    matchedDetections[detIdx] = true

    # Update Kalman filter with detection
    tracker.kalmanFilters[trackIdx].update(detections[detIdx])

    # Update track state
    tracker.state.tracks[trackIdx].bbox = detections[detIdx]
    tracker.state.tracks[trackIdx].timeSinceUpdate = 0
    tracker.state.tracks[trackIdx].hitStreak += 1
    tracker.state.tracks[trackIdx].age += 1

    # Update embedding with temporal smoothing (0.9 old + 0.1 new)
    if detectionEmbeddings[detIdx].len > 0:
      if tracker.state.tracks[trackIdx].embedding.len == 0:
        # First embedding for this track
        tracker.state.tracks[trackIdx].embedding = detectionEmbeddings[detIdx]
      else:
        # Temporal smoothing
        for i in 0 ..< tracker.state.tracks[trackIdx].embedding.len:
          tracker.state.tracks[trackIdx].embedding[i] =
            0.9f * tracker.state.tracks[trackIdx].embedding[i] +
            0.1f * detectionEmbeddings[detIdx][i]

  # Step 6: Create new tracks for unmatched detections
  for detIdx, detection in detections:
    if not matchedDetections[detIdx]:
      # Create new track
      var newTrack = Track(
        id: tracker.state.nextId,
        bbox: detection,
        embedding: if detIdx < detectionEmbeddings.len: detectionEmbeddings[detIdx] else: @[],
        timeSinceUpdate: 0,
        hitStreak: 1,
        age: 1,
        speakerId: -1
      )
      tracker.state.tracks.add(newTrack)

      # Create Kalman filter for new track
      tracker.kalmanFilters.add(newKalmanFilter(detection))

      tracker.state.nextId += 1

  # Step 7: Handle unmatched tracks (increment timeSinceUpdate)
  # Note: Only iterate over original tracks (not newly added ones)
  # matchedTracks was sized for original track count before Step 6 added new tracks
  for trackIdx in 0 ..< matchedTracks.len:
    if not matchedTracks[trackIdx]:
      tracker.state.tracks[trackIdx].timeSinceUpdate += 1
      if tracker.state.tracks[trackIdx].hitStreak > 0:
        tracker.state.tracks[trackIdx].hitStreak -= 1

  # Step 8: Delete stale tracks (timeSinceUpdate > maxAge)
  # Need to delete both tracks and their corresponding Kalman filters
  var i = 0
  while i < tracker.state.tracks.len:
    if tracker.state.tracks[i].timeSinceUpdate > tracker.state.maxAge:
      tracker.state.tracks.delete(i)
      tracker.kalmanFilters.delete(i)
    else:
      i += 1

  # Return all tracks
  result = tracker.state.tracks

proc getActiveTracks*(tracker: FaceTracker): seq[Track] =
  ## Get confirmed active tracks (hitStreak >= minHits)
  ##
  ## Filters out newly detected faces that may be false positives.
  ## Per research, require confirmation over multiple frames.
  ##
  ## Args:
  ##   tracker: Face tracker
  ##
  ## Returns:
  ##   Sequence of confirmed tracks only

  result = tracker.state.tracks.filterIt(it.hitStreak >= tracker.state.minHits)

proc getActiveSpeaker*(tracker: FaceTracker, timestamp: float64,
                      transcript: Transcript): Option[Track] =
  ## Find active speaker at given timestamp using transcript diarization
  ##
  ## Matches speaker from transcript to face track using largest face heuristic.
  ## Per research Pattern 3: largest face during speaking segment likely = speaker.
  ##
  ## Args:
  ##   tracker: Face tracker with current tracks
  ##   timestamp: Timestamp in seconds
  ##   transcript: Transcript with speaker diarization
  ##
  ## Returns:
  ##   Track of active speaker, or none if no match

  # Convert timestamp to milliseconds for transcript lookup
  let timestampMs = (timestamp * 1000.0).int64

  # Find speaker at this timestamp from transcript
  var activeSpeakerId = -1
  for segment in transcript.segments:
    if timestampMs >= segment.startMs and timestampMs <= segment.endMs:
      activeSpeakerId = segment.speaker
      break

  if activeSpeakerId < 0:
    return none(Track)

  # Get confirmed tracks only
  let confirmedTracks = tracker.getActiveTracks()
  if confirmedTracks.len == 0:
    return none(Track)

  # Match using largest face heuristic
  # Score = face area * confidence * stability
  var bestTrack: Track
  var maxScore = 0.0
  var foundMatch = false

  for track in confirmedTracks:
    let faceArea = track.bbox.width * track.bbox.height
    let score = faceArea.float * track.bbox.confidence *
                min(track.hitStreak.float / 10.0, 1.0)

    if score > maxScore:
      maxScore = score
      bestTrack = track
      foundMatch = true

  if foundMatch:
    result = some(bestTrack)
  else:
    result = none(Track)
