## JSON template parser with variable substitution
##
## Provides:
##   - loadTemplate: Parse JSON files to MetadataTemplate
##   - substituteVariables: Replace ${VAR} placeholders with values
##   - findTemplate: Discover .honeyclip-meta.json files
##
## Supported variables:
##   - ${VIDEO_TITLE} - filename without extension
##   - ${AUTHOR_NAME} - from param or HONEYCLIP_AUTHOR env var
##   - ${YEAR} - current year (4 digits)
##   - ${ISO_DATE} - current date in ISO 8601 format (YYYY-MM-DD)
##   - ${FILENAME} - filename with extension

import std/[json, tables, os, times, strutils]
import types

proc loadTemplate*(path: string): MetadataTemplate =
  ## Load metadata template from JSON file
  result = newMetadataTemplate()

  let json = parseFile(path)
  result.version = json{"version"}.getInt(1)

  # Parse global metadata
  if "global" in json:
    for key, val in json["global"].pairs:
      result.global[key] = val.getStr()

  # Parse video stream metadata
  if "video" in json:
    for key, val in json["video"].pairs:
      result.video[key] = val.getStr()

  # Parse audio stream metadata
  if "audio" in json:
    for key, val in json["audio"].pairs:
      result.audio[key] = val.getStr()

  # Parse chapters
  if "chapters" in json:
    for chap in json["chapters"].items:
      result.chapters.add ChapterMarker(
        startMs: chap["start_ms"].getBiggestInt(),
        endMs: chap["end_ms"].getBiggestInt(),
        title: chap["title"].getStr()
      )

proc substituteVariables*(tmpl: MetadataTemplate,
                          videoPath: string,
                          authorName: string = ""): MetadataTemplate =
  ## Substitute template variables with actual values
  ##
  ## Variables:
  ##   - ${VIDEO_TITLE}: filename without extension
  ##   - ${AUTHOR_NAME}: authorName param or HONEYCLIP_AUTHOR env var
  ##   - ${YEAR}: current year
  ##   - ${ISO_DATE}: current date in YYYY-MM-DD format
  ##   - ${FILENAME}: filename with extension
  let now = now()
  let filename = extractFilename(videoPath)
  let title = filename.changeFileExt("")
  let author = if authorName != "": authorName
               else: getEnv("HONEYCLIP_AUTHOR", "")

  proc substitute(s: string): string =
    result = s
    result = result.replace("${VIDEO_TITLE}", title)
    result = result.replace("${AUTHOR_NAME}", author)
    result = result.replace("${YEAR}", $now.year)
    result = result.replace("${ISO_DATE}", now.format("yyyy-MM-dd"))
    result = result.replace("${FILENAME}", filename)

  result = tmpl
  for key in result.global.keys:
    result.global[key] = substitute(result.global[key])
  for key in result.video.keys:
    result.video[key] = substitute(result.video[key])
  for key in result.audio.keys:
    result.audio[key] = substitute(result.audio[key])
  for i in 0..<result.chapters.len:
    result.chapters[i].title = substitute(result.chapters[i].title)

proc findTemplate*(videoPath: string): string =
  ## Discover .honeyclip-meta.json template file
  ##
  ## Search order:
  ##   1. Same directory as video
  ##   2. Home directory
  ##
  ## Returns: template path or empty string if not found

  # Check same directory as video
  let dir = parentDir(videoPath)
  let local = dir / ".honeyclip-meta.json"
  if fileExists(local):
    return local

  # Check home directory
  let home = getHomeDir() / ".honeyclip-meta.json"
  if fileExists(home):
    return home

  return ""  # No template found
