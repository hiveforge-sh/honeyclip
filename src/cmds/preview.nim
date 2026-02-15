import std/[strformat, strutils, os]
import ../log
import ../util/fun
import ../render/proxy

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var outputPath: string = ""
  var quietMode: bool = false

  # Parse arguments
  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip preview file [options]

Generate 720p proxy preview for fast review

Arguments:
  file                    Input video file

Options:
  -o, --output PATH       Output file path (default: {input}_proxy.mp4)
  -q, --quiet             Suppress progress output
  --help                  Show this help

Examples:
  honeyclip preview video.mp4                    # Generate proxy
  honeyclip preview video.mp4 -o proxy.mp4       # Custom output path
"""
      quit(0)
    of "-o", "--output":
      expecting = "output"
    of "-q", "--quiet":
      quietMode = true
      quiet = true
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        # Positional argument: input file
        if inputPath == "":
          inputPath = key
        else:
          error &"Unexpected positional argument: {key}"
      of "output":
        outputPath = key
        expecting = ""

  # Check for incomplete argument
  if expecting != "":
    error &"Missing value for {expecting}"

  # Validate arguments
  if inputPath == "":
    error "A video file is required. Usage: honeyclip preview file [options]"

  if not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Generate proxy
  let result = generateProxy(inputPath, outputPath, quietMode)

  if not result.success:
    error result.error

  # Print summary if not quiet
  if not quietMode:
    echo ""
    echo &"Proxy created: {result.outputPath} ({result.speedFactor:.1f}x realtime)"
