## Platform preset configurations for social media export
##
## Provides encoding presets optimized for different social media platforms:
##   - Instagram Reels (9:16, 5Mbps)
##   - TikTok (9:16, 3Mbps)
##   - YouTube Shorts (9:16, 10Mbps)
##   - Instagram Feed (1:1, 5Mbps)
##   - Facebook (16:9, 4Mbps)
##   - Twitter/X (16:9, 5Mbps)
##
## All presets use H.264/AAC for maximum compatibility.

import std/[options, algorithm, tables]
import ../reframe/crop

export AspectRatio

type
  PlatformPreset* = object
    ## Encoding configuration for a social media platform
    name*: string           # Display name
    aspect*: AspectRatio    # Target aspect ratio
    width*, height*: int    # Target resolution
    codec*: string          # Video codec (libx264)
    fps*: int               # Target framerate
    bitrate*: int           # Video bitrate in kbps
    audioCodec*: string     # Audio codec (aac)
    audioBitrate*: int      # Audio bitrate in kbps

# Platform presets table with configurations from RESEARCH.md
let platformPresets* = {
  "instagram-reels": PlatformPreset(
    name: "Instagram Reels",
    aspect: Portrait,
    width: 1080, height: 1920,
    codec: "libx264", fps: 30,
    bitrate: 5000,  # 5 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "tiktok": PlatformPreset(
    name: "TikTok",
    aspect: Portrait,
    width: 1080, height: 1920,
    codec: "libx264", fps: 30,
    bitrate: 3000,  # 3 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "youtube-shorts": PlatformPreset(
    name: "YouTube Shorts",
    aspect: Portrait,
    width: 1080, height: 1920,
    codec: "libx264", fps: 30,
    bitrate: 10000,  # 10 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "instagram-feed": PlatformPreset(
    name: "Instagram Feed",
    aspect: Square,
    width: 1080, height: 1080,
    codec: "libx264", fps: 30,
    bitrate: 5000,  # 5 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "facebook": PlatformPreset(
    name: "Facebook",
    aspect: Landscape,
    width: 1280, height: 720,
    codec: "libx264", fps: 30,
    bitrate: 4000,  # 4 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "twitter": PlatformPreset(
    name: "X (Twitter)",
    aspect: Landscape,
    width: 1280, height: 720,
    codec: "libx264", fps: 30,
    bitrate: 5000,  # 5 Mbps
    audioCodec: "aac", audioBitrate: 128
  )
}.toTable

proc getPreset*(name: string): Option[PlatformPreset] =
  ## Lookup platform preset by name
  ##
  ## Args:
  ##   name: Preset name (e.g., "instagram-reels", "tiktok")
  ##
  ## Returns:
  ##   Some(preset) if found, None if not found
  if name in platformPresets:
    result = some(platformPresets[name])
  else:
    result = none(PlatformPreset)

proc listPresets*(): seq[string] =
  ## Return sorted list of available preset names
  ##
  ## Returns:
  ##   Alphabetically sorted list of preset names
  result = @[]
  for key in platformPresets.keys:
    result.add(key)
  result.sort()

proc aspectToString*(aspect: AspectRatio): string =
  ## Convert aspect ratio to folder name string
  ##
  ## Args:
  ##   aspect: Target aspect ratio
  ##
  ## Returns:
  ##   "16x9", "9x16", or "1x1" for folder naming
  case aspect:
  of Landscape: "16x9"
  of Portrait: "9x16"
  of Square: "1x1"
