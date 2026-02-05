## Metadata template types for honeyclip
##
## Provides:
##   - MetadataTemplate: Container for global, video, audio metadata and chapters
##   - ChapterMarker: Chapter boundaries with titles
##   - Factory and merge functions for template creation and CLI overrides

import std/tables

type
  ChapterMarker* = object
    startMs*, endMs*: int64
    title*: string

  MetadataTemplate* = object
    version*: int                      # Schema version (1)
    global*: Table[string, string]     # Container-level: title, artist, copyright, etc.
    video*: Table[string, string]      # Video stream metadata
    audio*: Table[string, string]      # Audio stream metadata
    chapters*: seq[ChapterMarker]      # Chapter markers

proc newMetadataTemplate*(): MetadataTemplate =
  ## Create a new empty metadata template with version 1
  result.version = 1
  result.global = initTable[string, string]()
  result.video = initTable[string, string]()
  result.audio = initTable[string, string]()
  result.chapters = @[]

proc defaultTemplate*(): MetadataTemplate =
  ## Create a default template with standard variable placeholders
  result = newMetadataTemplate()
  result.global["title"] = "${VIDEO_TITLE}"
  result.global["artist"] = "${AUTHOR_NAME}"
  result.global["copyright"] = "Copyright ${YEAR} ${AUTHOR_NAME}"
  result.global["date"] = "${ISO_DATE}"

proc merge*(base: MetadataTemplate, overrides: Table[string, string]): MetadataTemplate =
  ## Merge CLI overrides into template's global metadata
  ## Used to apply --meta-title, --meta-author flags
  result = base
  for key, val in overrides:
    result.global[key] = val
