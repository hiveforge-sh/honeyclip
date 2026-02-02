## Tracking types for multi-face tracking
##
## Provides types for DeepSORT-style persistent face tracking across frames.
## Tracks maintain identity through appearance embeddings and motion prediction.

import ../ml/facedetect

type
  Track* = object
    ## Persistent track for a detected face across frames
    ## Maintains identity through temporary occlusion
    id*: int                    # Unique track ID
    bbox*: FaceRect             # Current bounding box
    embedding*: seq[float32]    # 512-dim ArcFace embedding for re-identification
    timeSinceUpdate*: int       # Frames since last detection match
    hitStreak*: int             # Consecutive detection matches
    age*: int                   # Total frames track has existed
    speakerId*: int             # Speaker diarization ID (-1 if unassigned)

  TrackedFace* = object
    ## Face detection with tracking context
    ## Extends FaceDetection with track association
    x*, y*: int
    width*, height*: int
    confidence*: float
    angle*: int
    frameIndex*: int64
    stable*: bool
    trackId*: int               # Associated track ID
    embedding*: seq[float32]    # Face embedding for re-identification

  TrackingState* = object
    ## Global tracker state managing all active tracks
    tracks*: seq[Track]         # Active tracks
    nextId*: int                # Next track ID to assign
    maxAge*: int                # Frames before track deletion (default 90 = 3s @ 30fps)
    minHits*: int               # Minimum hits before track confirmed (default 3)

  EasingPreset* = enum
    ## Speed presets for reframing transitions
    Slow = "slow"       # Cinematic 1-2 second transitions (default)
    Medium = "medium"   # Balanced 0.5-1 second transitions
    Fast = "fast"       # Social media 0.2-0.5 second transitions

  CropRegion* = object
    ## Crop region for reframing output
    x*, y*: int                 # Top-left corner
    width*, height*: int        # Dimensions
    timestamp*: float64         # When this crop applies (seconds)

proc newTrackingState*(maxAge: int = 90, minHits: int = 3): TrackingState =
  ## Create new tracking state with default parameters
  ##
  ## Args:
  ##   maxAge: Frames before track deletion (default 90 = 3s @ 30fps)
  ##   minHits: Minimum hits before track confirmed (default 3)
  ##
  ## Returns:
  ##   Initialized tracking state
  result = TrackingState(
    tracks: @[],
    nextId: 0,
    maxAge: maxAge,
    minHits: minHits
  )
