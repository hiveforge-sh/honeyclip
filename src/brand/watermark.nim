## Watermark overlay filter generation for FFmpeg
##
## This module provides watermark positioning and overlay filter string generation
## for adding logo/brand images to video output.

import std/[strformat, strutils, os]
import ../render/captions

type
  WatermarkPosition* = enum
    ## Position of watermark on screen
    wpTopLeft = "top-left"
    wpTopRight = "top-right"
    wpBottomLeft = "bottom-left"
    wpBottomRight = "bottom-right"
    wpCenter = "center"

proc parseWatermarkPosition*(s: string): WatermarkPosition =
  ## Parse string to WatermarkPosition enum
  ## Defaults to bottom-right for unknown values
  case s
  of "top-left":
    wpTopLeft
  of "top-right":
    wpTopRight
  of "bottom-left":
    wpBottomLeft
  of "bottom-right":
    wpBottomRight
  of "center":
    wpCenter
  else:
    wpBottomRight  # Default

proc buildWatermarkFilter*(imagePath: string, position: WatermarkPosition, offsetX: int = 10, offsetY: int = 10, scale: float = 0.1, opacity: float = 1.0): string =
  ## Build FFmpeg overlay filter string for watermark positioning
  ## Returns empty string if imagePath is empty
  ##
  ## Examples:
  ##   - Bottom-right with opacity: [1:v]format=rgba,colorchannelmixer=aa=0.7[wm];[0:v][wm]overlay=W-w-10:H-h-10:format=auto
  ##   - Top-left full opacity: [0:v][1:v]overlay=10:10:format=auto
  if imagePath == "":
    return ""

  # Build position expressions using FFmpeg overlay variables
  # W, H = main video dimensions
  # w, h = watermark dimensions
  var x, y: string
  case position
  of wpTopLeft:
    x = $offsetX
    y = $offsetY
  of wpTopRight:
    x = &"W-w-{offsetX}"
    y = $offsetY
  of wpBottomLeft:
    x = $offsetX
    y = &"H-h-{offsetY}"
  of wpBottomRight:
    x = &"W-w-{offsetX}"
    y = &"H-h-{offsetY}"
  of wpCenter:
    x = "(W-w)/2"
    y = "(H-h)/2"

  # Build filter string
  if opacity < 1.0:
    # Apply opacity using colorchannelmixer
    result = &"[1:v]format=rgba,colorchannelmixer=aa={opacity}[wm];[0:v][wm]overlay={x}:{y}:format=auto"
  else:
    # No opacity adjustment needed
    result = &"[0:v][1:v]overlay={x}:{y}:format=auto"

proc buildWatermarkScaleFilter*(scale: float): string =
  ## Build scale2ref filter to scale watermark relative to video dimensions
  ## Returns empty string if scale is invalid (<=0 or >=1)
  ##
  ## Uses scale2ref to scale watermark to a fraction of video height while preserving aspect ratio
  if scale <= 0.0 or scale >= 1.0:
    return ""

  result = &"[1:v]scale2ref=w=oh*mdar:h=main_h*{scale}[wm][base]"
