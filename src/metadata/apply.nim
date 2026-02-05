## Metadata application module for FFmpeg integration
##
## Provides:
##   - escapeMetadataValue: Escape special chars for ffmetadata format
##   - generateFFMetadata: Generate ffmetadata INI content
##   - writeFFMetadataFile: Write ffmetadata to temp file
##   - templateToAvdict: Convert template table to AVDictionary
##   - applyToFormatContext: Apply metadata to format context
##   - applyToStream: Apply metadata to stream

import std/[tables, strformat, os]
import types, ../ffmpeg, ../util/dict

proc escapeMetadataValue*(s: string): string =
  ## Escape special characters for ffmetadata INI format
  ## Characters: =, ;, #, \, newline need backslash escaping
  result = ""
  for c in s:
    if c in {'=', ';', '#', '\\'}:
      result.add '\\'
    if c == '\n':
      result.add "\\n"
    else:
      result.add c

proc generateFFMetadata*(tmpl: MetadataTemplate): string =
  ## Generate ffmetadata file content for FFmpeg -i metadata.txt
  ## Format: https://ffmpeg.org/ffmpeg-formats.html#Metadata-1
  result = ";FFMETADATA1\n"

  # Global metadata
  for key, val in tmpl.global:
    result &= &"{key}={escapeMetadataValue(val)}\n"

  # Chapter markers
  for chapter in tmpl.chapters:
    result &= "\n[CHAPTER]\n"
    result &= "TIMEBASE=1/1000\n"
    result &= &"START={chapter.startMs}\n"
    result &= &"END={chapter.endMs}\n"
    result &= &"title={escapeMetadataValue(chapter.title)}\n"

proc writeFFMetadataFile*(tmpl: MetadataTemplate,
                          outputPath: string = ""): string =
  ## Write ffmetadata to file, return path
  ## If outputPath empty, use temp file
  let content = generateFFMetadata(tmpl)
  let path = if outputPath != "": outputPath
             else: getTempDir() / "honeyclip_metadata.txt"
  writeFile(path, content)
  return path

proc templateToAvdict*(dst: ptr ptr AVDictionary,
                       metadata: Table[string, string]) =
  ## Apply metadata table to FFmpeg AVDictionary
  ## Uses existing dictToAvdict from util/dict
  dictToAvdict(dst, metadata)

proc applyToFormatContext*(ctx: ptr AVFormatContext,
                           tmpl: MetadataTemplate) =
  ## Apply global metadata to format context
  templateToAvdict(addr ctx.metadata, tmpl.global)

proc applyToStream*(stream: ptr AVStream,
                    metadata: Table[string, string]) =
  ## Apply metadata to specific stream
  templateToAvdict(addr stream.metadata, metadata)
