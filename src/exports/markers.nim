## NLE Timeline Marker types and factory functions
##
## This module defines marker data structures for exporting to NLE applications.
## Markers can represent engagement peaks, scene boundaries, and speaker changes,
## with color coding and format-agnostic timing.

import std/strformat

type
  MarkerType* = enum
    mtEngagementPeak  ## High engagement moment
    mtSceneBoundary   ## Visual scene change
    mtSpeakerChange   ## New speaker begins

  Marker* = object
    markerType*: MarkerType
    timestampMs*: int64      ## Position in milliseconds
    durationMs*: int64       ## Marker duration (default 1000ms)
    name*: string            ## Short display name (e.g., "Peak #1")
    comment*: string         ## Detailed description
    color*: string           ## Hex color for display

const
  ColorEngagementPeak* = "#00FF00"  ## Green for engagement peaks
  ColorSceneBoundary* = "#0066FF"   ## Blue for scene boundaries
  ColorSpeakerChange* = "#FFCC00"   ## Yellow for speaker changes

proc getMarkerColor*(mt: MarkerType): string =
  ## Returns hex color for marker type
  case mt
  of mtEngagementPeak: ColorEngagementPeak
  of mtSceneBoundary: ColorSceneBoundary
  of mtSpeakerChange: ColorSpeakerChange

proc labelForScore*(score: float32): string =
  ## Returns "High"/"Medium"/"Low" based on score
  if score >= 80.0:
    "High engagement"
  elif score >= 50.0:
    "Medium engagement"
  else:
    "Low engagement"

proc msToTimecode*(ms: int64, fps: float = 30.0): string =
  ## Format milliseconds as HH:MM:SS:FF timecode
  let totalSeconds = ms div 1000
  let remainderMs = ms mod 1000
  let frames = int((remainderMs.float / 1000.0) * fps)

  let hours = totalSeconds div 3600
  let minutes = (totalSeconds mod 3600) div 60
  let seconds = totalSeconds mod 60

  &"{hours:02}:{minutes:02}:{seconds:02}:{frames:02}"

proc createEngagementMarker*(timestampMs: int64, score: int, rank: int): Marker =
  ## Create an engagement peak marker
  ##
  ## Parameters:
  ##   timestampMs - Position in milliseconds
  ##   score - Engagement score (0-100)
  ##   rank - Ranking position (1 = top)
  let label = labelForScore(score.float32)
  result = Marker(
    markerType: mtEngagementPeak,
    timestampMs: timestampMs,
    durationMs: 1000,
    name: &"Peak #{rank}",
    comment: &"Score: {score}/100 (#{rank}) - {label}",
    color: getMarkerColor(mtEngagementPeak)
  )

proc createSceneMarker*(timestampMs: int64): Marker =
  ## Create a scene boundary marker
  let timecode = msToTimecode(timestampMs)
  result = Marker(
    markerType: mtSceneBoundary,
    timestampMs: timestampMs,
    durationMs: 1000,
    name: "Scene",
    comment: &"Scene boundary at {timecode}",
    color: getMarkerColor(mtSceneBoundary)
  )

proc createSpeakerMarker*(timestampMs: int64, speakerId: int, speakerName: string = ""): Marker =
  ## Create a speaker change marker
  ##
  ## Parameters:
  ##   timestampMs - Position in milliseconds
  ##   speakerId - Speaker identifier (0-based)
  ##   speakerName - Optional speaker name
  let displayName = if speakerName.len > 0: speakerName else: $speakerId
  let nameFormat = if speakerName.len > 0: &"Speaker: {speakerName}" else: &"Speaker {speakerId}"

  result = Marker(
    markerType: mtSpeakerChange,
    timestampMs: timestampMs,
    durationMs: 1000,
    name: nameFormat,
    comment: &"Speaker change to {displayName}",
    color: getMarkerColor(mtSpeakerChange)
  )
