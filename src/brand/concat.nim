## FFmpeg concat demuxer file list generation for intro/outro
##
## This module provides concat list building and validation for adding
## intro/outro clips to processed videos.

import std/[strformat, strutils, os, tempfiles, random]

proc validateConcatFiles*(files: seq[string]): seq[string] =
  ## Validate concat file list
  ## Returns list of error messages (empty = valid)
  result = @[]

  for file in files:
    if file != "" and not fileExists(file):
      result.add(&"File not found: {file}")

proc buildConcatList*(introPath, videoPath, outroPath: string, tempDir: string = ""): string =
  ## Build FFmpeg concat demuxer file list
  ## Returns path to temporary concat list file
  ##
  ## File format: each line is "file 'path'" with escaped single quotes
  ## Order: intro (if exists), video (always), outro (if exists)
  randomize()
  let randomSuffix = rand(100000..999999)
  let dir = if tempDir.len > 0: tempDir else: getTempDir()
  let tempFile = joinPath(dir, &"honeyclip_concat_{randomSuffix}.txt")

  var content = ""

  # Helper to escape single quotes in paths
  proc escapePath(path: string): string =
    result = path.replace("'", "'\\''")

  # Add intro if specified and exists
  if introPath != "" and fileExists(introPath):
    content.add(&"file '{escapePath(introPath)}'\n")

  # Always add video
  content.add(&"file '{escapePath(videoPath)}'\n")

  # Add outro if specified and exists
  if outroPath != "" and fileExists(outroPath):
    content.add(&"file '{escapePath(outroPath)}'\n")

  writeFile(tempFile, content)
  result = tempFile

proc cleanupConcatList*(path: string) =
  ## Remove temporary concat list file
  ## Ignores errors if file doesn't exist
  try:
    if fileExists(path):
      removeFile(path)
  except:
    discard
