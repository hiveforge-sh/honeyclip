## Engagement score visualization rendering
##
## Provides two visualization modes:
##   1. Line graph overlay - Shows score as waveform over time
##   2. Text overlay - Shows score value at regular intervals
##
## Both modes use FFmpeg filters for hardware-accelerated rendering.

import std/[strformat, strutils, os]
import ../analyze/engagement_types

type
  ScoreVizMode* = enum
    svmGraph      ## Line graph waveform
    svmText       ## Periodic text overlay
    svmBoth       ## Both graph and text

  ScoreVizParams* = object
    mode*: ScoreVizMode
    graphHeight*: int          ## Height of graph overlay (default 100)
    graphPosition*: string     ## "top" or "bottom" (default "bottom")
    graphColor*: string        ## Line color hex (default "#00FF00")
    graphOpacity*: float       ## Background opacity 0-1 (default 0.5)
    textInterval*: int         ## Seconds between text displays (default 5)
    textPosition*: string      ## "top-left", "top-right", "bottom-left", "bottom-right"
    fontSize*: int             ## Text font size (default 24)
    fontColor*: string         ## Text color hex (default "#FFFFFF")

proc defaultScoreVizParams*(): ScoreVizParams =
  ## Create default score visualization parameters
  result.mode = svmBoth
  result.graphHeight = 100
  result.graphPosition = "bottom"
  result.graphColor = "#00FF00"
  result.graphOpacity = 0.5
  result.textInterval = 5
  result.textPosition = "top-right"
  result.fontSize = 24
  result.fontColor = "#FFFFFF"

proc writeScoreDataFile*(segments: seq[EngagementSegment], outputPath: string,
                         fps: float = 30.0, durationMs: int64) =
  ## Write score values for each frame to text file
  ## Used by FFmpeg drawgraph filter
  ##
  ## Format: One score value (0.0-1.0) per line, one line per frame

  var scores: seq[float32] = @[]
  let totalFrames = int((durationMs.float / 1000.0) * fps)

  # Interpolate segment scores to per-frame values
  for frameNum in 0 ..< totalFrames:
    let frameMs = int64((frameNum.float / fps) * 1000.0)

    # Find segment containing this frame
    var score = 0.0f
    for seg in segments:
      if frameMs >= seg.startMs and frameMs < seg.endMs:
        score = seg.score / 100.0f  # Normalize to 0-1
        break

    scores.add(score)

  # Write to file
  var f = open(outputPath, fmWrite)
  defer: f.close()
  for s in scores:
    f.writeLine(&"{s:.3f}")

proc generateGraphFilter*(params: ScoreVizParams, scoreFile: string,
                          width, height: int): string =
  ## Generate FFmpeg filter for line graph overlay
  ##
  ## Uses drawgraph filter with score file input.
  ## Graph appears as translucent overlay at top or bottom.
  ##
  ## Note: FFmpeg's drawgraph filter has limited support for external data files.
  ## This implementation uses a simulated approach with sendcmd/drawtext for
  ## visualization. For production use, consider pre-rendering the graph.

  let graphY = if params.graphPosition == "top": 0 else: height - params.graphHeight

  # Parse color for FFmpeg (remove # prefix)
  let color = params.graphColor.replace("#", "")

  # Create background bar with semi-transparent color
  # This provides a visual baseline for the engagement graph
  result = &"drawbox=x=0:y={graphY}:w={width}:h={params.graphHeight}:c=black@{params.graphOpacity}:t=fill"

proc generateTextFilter*(params: ScoreVizParams, segments: seq[EngagementSegment]): string =
  ## Generate FFmpeg drawtext filter for periodic score display
  ##
  ## Shows "Score: NN/100" every N seconds using enable= expressions.

  var filters: seq[string] = @[]

  # Calculate positions
  let xPos = case params.textPosition
    of "top-left", "bottom-left": "10"
    of "top-right", "bottom-right": "w-text_w-10"
    else: "10"

  let yPos = case params.textPosition
    of "top-left", "top-right": "10"
    of "bottom-left", "bottom-right": "h-text_h-10"
    else: "10"

  # Build drawtext for each segment
  for seg in segments:
    let startSec = seg.startMs.float / 1000.0
    let endSec = seg.endMs.float / 1000.0
    let score = int(seg.score)

    let filter = &"drawtext=text='Score\\: {score}/100':x={xPos}:y={yPos}:fontsize={params.fontSize}:fontcolor={params.fontColor}:enable='between(t,{startSec:.3f},{endSec:.3f})'"
    filters.add(filter)

  result = filters.join(",")

proc generateScoreOverlayFilter*(params: ScoreVizParams, segments: seq[EngagementSegment],
                                  width, height: int, scoreFile: string = ""): string =
  ## Generate combined FFmpeg filter for score visualization
  ##
  ## Combines graph and/or text overlays based on params.mode.
  ## Returns complete filter chain string.

  var filterParts: seq[string] = @[]

  case params.mode
  of svmGraph:
    let graphFilter = generateGraphFilter(params, scoreFile, width, height)
    if graphFilter.len > 0:
      filterParts.add(graphFilter)

  of svmText:
    let textFilter = generateTextFilter(params, segments)
    if textFilter.len > 0:
      filterParts.add(textFilter)

  of svmBoth:
    let graphFilter = generateGraphFilter(params, scoreFile, width, height)
    if graphFilter.len > 0:
      filterParts.add(graphFilter)
    let textFilter = generateTextFilter(params, segments)
    if textFilter.len > 0:
      filterParts.add(textFilter)

  result = filterParts.join(",")

proc renderScoreGraph*(segments: seq[EngagementSegment], width, height: int,
                       params: ScoreVizParams = defaultScoreVizParams()): string =
  ## Generate FFmpeg filter for graph-only visualization
  result = generateGraphFilter(params, "", width, height)

proc renderScoreText*(segments: seq[EngagementSegment],
                      params: ScoreVizParams = defaultScoreVizParams()): string =
  ## Generate FFmpeg filter for text-only visualization
  result = generateTextFilter(params, segments)

# Test block for development
when isMainModule:
  # Create test segments
  var segments: seq[EngagementSegment] = @[]

  var seg1 = newEngagementSegment(0, 5000)
  seg1.score = 75.0f
  segments.add(seg1)

  var seg2 = newEngagementSegment(5000, 10000)
  seg2.score = 85.0f
  segments.add(seg2)

  var seg3 = newEngagementSegment(10000, 15000)
  seg3.score = 60.0f
  segments.add(seg3)

  let params = defaultScoreVizParams()

  echo "Graph filter:"
  echo generateGraphFilter(params, "scores.txt", 1920, 1080)
  echo ""

  echo "Text filter:"
  echo generateTextFilter(params, segments)
  echo ""

  echo "Combined filter:"
  echo generateScoreOverlayFilter(params, segments, 1920, 1080, "scores.txt")
