## Named engagement presets for different content types and platforms
##
## Presets provide sensible defaults for engagement analysis based on
## content type (viral, podcast, tutorial) and platform (tiktok, youtube).

import std/[strformat, strutils, tables]
import ../log

type
  PresetConfig* = object
    ## Engagement analysis configuration for a preset
    threshold*: float32           # Engagement score cutoff (0-100)
    audioWeight*: float32         # Weight for audio signal (0-1)
    motionWeight*: float32        # Weight for motion signal (0-1)
    speechWeight*: float32        # Weight for speech signal (0-1)

# Preset lookup table mapping preset names to configurations
const Presets* = {
  "viral": PresetConfig(
    threshold: 75.0,
    audioWeight: 0.3,
    motionWeight: 0.4,
    speechWeight: 0.3
  ),
  "podcast": PresetConfig(
    threshold: 50.0,
    audioWeight: 0.1,
    motionWeight: 0.1,
    speechWeight: 0.8
  ),
  "tutorial": PresetConfig(
    threshold: 40.0,
    audioWeight: 0.2,
    motionWeight: 0.4,
    speechWeight: 0.4
  ),
  "interview": PresetConfig(
    threshold: 45.0,
    audioWeight: 0.2,
    motionWeight: 0.2,
    speechWeight: 0.6
  ),
  "tiktok": PresetConfig(
    threshold: 80.0,
    audioWeight: 0.3,
    motionWeight: 0.5,
    speechWeight: 0.2
  ),
  "youtube": PresetConfig(
    threshold: 60.0,
    audioWeight: 0.4,
    motionWeight: 0.3,
    speechWeight: 0.3
  ),
  "instagram": PresetConfig(
    threshold: 70.0,
    audioWeight: 0.3,
    motionWeight: 0.4,
    speechWeight: 0.3
  )
}.toTable

proc defaultPresetConfig*(): PresetConfig =
  ## Return default preset configuration with equal weights and threshold 50.0
  result.threshold = 50.0
  result.audioWeight = 0.333
  result.motionWeight = 0.333
  result.speechWeight = 0.333

proc parseEngageValue*(value: string): tuple[threshold: float32, config: PresetConfig] =
  ## Parse engagement value from either numeric threshold or preset name
  ##
  ## First tries to parse as float (e.g., "70" -> threshold 70.0)
  ## If that fails, looks up preset name (e.g., "viral")
  ##
  ## Returns (threshold, config) tuple where:
  ## - For numeric input: threshold from value, config with default weights
  ## - For preset input: threshold and config from preset
  ##
  ## Raises error for unknown preset with helpful message listing available presets

  # Try parsing as numeric threshold first
  try:
    let threshold = parseFloat(value).float32
    var config = defaultPresetConfig()
    config.threshold = threshold
    return (threshold: threshold, config: config)
  except ValueError:
    # Not a number, try preset lookup
    if Presets.hasKey(value):
      let config = Presets[value]
      return (threshold: config.threshold, config: config)
    else:
      # Unknown preset - provide helpful error
      var availablePresets: seq[string] = @[]
      for name in Presets.keys:
        availablePresets.add(name)
      error &"Unknown engagement preset: '{value}'. Available presets: {availablePresets.join(\", \")}"
