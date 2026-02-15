## Caption style preset and override system
##
## This module provides conversion from caption style overrides to CaptionStyle,
## supporting preset loading with field-level overrides.

import ../render/captions

type
  CaptionOverrides* = object
    ## Caption style configuration overrides
    preset*: string
    fontPath*: string
    fontSize*: int
    color*: string
    position*: string

proc parseCaptionPosition*(s: string): CaptionPosition =
  ## Parse string to CaptionPosition enum
  ## Defaults to bottom-center for unknown values
  case s
  of "bottom":
    cpBottomCenter
  of "center":
    cpCenter
  of "top":
    cpTopCenter
  else:
    cpBottomCenter  # Default

proc toCaptionStyle*(overrides: CaptionOverrides): CaptionStyle =
  ## Convert caption overrides to CaptionStyle
  ## Starts with preset, then applies overrides for non-default values

  # Load base preset
  if overrides.preset != "":
    result = getPreset(overrides.preset)
  else:
    result = getPreset("traditional")

  # Apply overrides
  if overrides.fontPath != "":
    result.fontPath = overrides.fontPath

  if overrides.fontSize > 0:
    result.fontSize = overrides.fontSize

  if overrides.color != "":
    result.color = overrides.color

  if overrides.position != "":
    result.position = parseCaptionPosition(overrides.position)
