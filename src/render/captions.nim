## Caption styling system with ASS subtitle generation
##
## This module provides:
## - CaptionStyle type for configuring caption appearance
## - Style presets (traditional, modern/tiktok)
## - Speaker color palette for visual differentiation
## - ASS subtitle file generation with word-level timing (karaoke tags)

import std/strformat

type
  CaptionPosition* = enum
    ## Position of caption text on screen
    cpBottomCenter = "bottom-center"  # Traditional subtitle position (default)
    cpTopCenter = "top-center"        # Avoid bottom UI elements
    cpCenter = "center"               # TikTok/Reels style

  CaptionStyle* = object
    ## Complete styling configuration for captions

    # Font settings
    fontPath*: string        # Full path to TTF/OTF file
    fontName*: string        # Font name for NLE export
    fontSize*: int           # Font size in pixels (48-72 typical)

    # Colors
    color*: string           # Primary text color (hex #RRGGBB)
    speakerColors*: seq[string]  # Override color per speaker

    # Outline
    outline*: bool
    outlineWidth*: int       # Width in pixels (3-5 typical)
    outlineColor*: string    # Hex color

    # Shadow
    shadow*: bool
    shadowX*: int            # Horizontal offset in pixels
    shadowY*: int            # Vertical offset in pixels
    shadowColor*: string     # Hex color

    # Background box
    backgroundBox*: bool
    boxColor*: string        # Color with alpha (e.g., "black@0.6")
    boxPadding*: int         # Padding in pixels

    # Position
    position*: CaptionPosition
    marginBottom*: int       # Distance from bottom edge in pixels
    marginTop*: int          # Distance from top edge in pixels

    # Word highlighting
    highlightEnabled*: bool  # Enable word-by-word reveal via karaoke tags

const
  # Speaker color palette - visually distinct colors
  SpeakerColorPalette* = [
    "#00d4ff",  # Speaker 0: Cyan
    "#ff6b6b",  # Speaker 1: Red/Pink
    "#4ecb71",  # Speaker 2: Green
    "#ffe66d",  # Speaker 3: Yellow
    "#a29bfe"   # Speaker 4: Purple
  ]

proc getSpeakerColor*(speaker: int): string =
  ## Get color for speaker index
  ## Returns white (#ffffff) for invalid/unassigned speakers
  if speaker >= 0 and speaker < SpeakerColorPalette.len:
    result = SpeakerColorPalette[speaker]
  else:
    result = "#ffffff"

proc getDefaultFontPath*(): string =
  ## Get platform-specific default font path
  when defined(windows):
    result = "C:/Windows/Fonts/arialbd.ttf"
  elif defined(linux):
    result = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
  elif defined(macosx):
    result = "/Library/Fonts/Arial Bold.ttf"
  else:
    result = ""

proc getPreset*(name: string): CaptionStyle =
  ## Get predefined caption style
  ## Available presets: "traditional", "modern", "tiktok" (alias for modern)

  case name
  of "traditional":
    result = CaptionStyle(
      fontPath: getDefaultFontPath(),
      fontName: "Arial Bold",
      fontSize: 60,
      color: "#ffffff",
      speakerColors: @[],
      outline: true,
      outlineWidth: 4,
      outlineColor: "#000000",
      shadow: false,
      shadowX: 0,
      shadowY: 0,
      shadowColor: "#000000",
      backgroundBox: false,
      boxColor: "",
      boxPadding: 0,
      position: cpBottomCenter,
      marginBottom: 150,
      marginTop: 0,
      highlightEnabled: false
    )

  of "modern", "tiktok":
    result = CaptionStyle(
      fontPath: getDefaultFontPath(),
      fontName: "Arial Bold",
      fontSize: 72,
      color: "#000000",
      speakerColors: @[],
      outline: false,
      outlineWidth: 0,
      outlineColor: "#000000",
      shadow: false,
      shadowX: 0,
      shadowY: 0,
      shadowColor: "#000000",
      backgroundBox: true,
      boxColor: "yellow@0.8",
      boxPadding: 20,
      position: cpCenter,
      marginBottom: 0,
      marginTop: 0,
      highlightEnabled: false
    )

  else:
    # Default to traditional
    result = getPreset("traditional")
