# Phase 14: Media Metadata Management - Research

**Researched:** 2026-02-05
**Domain:** Video/audio metadata management, FFmpeg metadata API, configuration file formats
**Confidence:** HIGH

## Summary

Media metadata management involves applying standardized descriptive information (title, author, copyright, description, date) and structural data (chapter markers) to video/audio files in a repeatable, template-driven way. FFmpeg provides comprehensive metadata support through its AVDictionary API and ffmetadata format, with varying compatibility across container formats (MP4, MKV, MOV).

The standard approach is to:
1. Define metadata templates in JSON format (Nim's std/json library provides native support)
2. Parse templates into key-value dictionaries
3. Apply metadata via FFmpeg's AVDictionary API to AVFormatContext (global) and AVStream (per-stream)
4. Support chapter markers via AVChapter structures or ffmetadata files
5. Allow CLI flag overrides for one-off adjustments

**Primary recommendation:** Use JSON for metadata templates (not YAML) to leverage Nim's stdlib, store templates in `.honeyclip-meta.json`, and apply metadata via FFmpeg's existing AVDictionary API which is already partially integrated in honeyclip's av.nim.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg libavformat | 7.0+ | Container metadata API | Industry standard for media metadata, universal support |
| Nim std/json | stdlib | JSON parsing | Built into Nim, zero dependencies, proven in honeyclip codebase |
| FFmpeg AVDictionary | libavutil | Key-value metadata storage | FFmpeg's native metadata representation |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExifTool | 12.76+ | Standalone metadata editing | Reference/validation only, not for integration |
| NimYAML | 2.x | YAML parsing | Optional: if users strongly prefer YAML over JSON |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| std/json | NimYAML | YAML more human-friendly but adds dependency, Nim 2.0+ required |
| std/json | parsecfg (INI-style) | Simpler but less expressive, can't handle nested structures |
| AVDictionary API | ExifTool subprocess | ExifTool powerful but subprocess overhead, cross-platform complexity |

**Installation:**
No additional libraries needed - std/json and FFmpeg already in project.

Optional YAML support:
```bash
nimble install yaml  # Only if YAML support desired
```

## Architecture Patterns

### Recommended Project Structure
```
src/
├── metadata/           # New metadata module
│   ├── types.nim      # MetadataTemplate, ChapterMarker types
│   ├── parser.nim     # JSON/YAML template parsing
│   ├── apply.nim      # FFmpeg metadata application
│   └── template.nim   # Default template definitions
└── cmds/
    └── meta.nim       # CLI command implementation
```

### Pattern 1: Template-Based Metadata Application
**What:** JSON template defines metadata schema, CLI applies to output files
**When to use:** Repeatable workflows where same metadata applies to multiple videos
**Example:**
```nim
# Source: Honeyclip project.nim pattern
type
  MetadataTemplate* = object
    version*: int                           # Schema version
    global*: Table[string, string]          # Container-level metadata
    video*: Table[string, string]           # Video stream metadata
    audio*: Table[string, string]           # Audio stream metadata
    chapters*: seq[ChapterMarker]           # Chapter definitions

  ChapterMarker* = object
    startMs*: int64
    endMs*: int64
    title*: string

# Template loading
proc loadTemplate(path: string): MetadataTemplate =
  let json = parseFile(path)
  result.version = json["version"].getInt(1)
  result.global = parseMetadataDict(json{"global"})
  result.video = parseMetadataDict(json{"video"})
  result.audio = parseMetadataDict(json{"audio"})
  if "chapters" in json:
    result.chapters = parseChapters(json["chapters"])
```

### Pattern 2: Metadata Application via AVDictionary
**What:** Convert template to FFmpeg AVDictionary and apply during encoding
**When to use:** When writing output files with honeyclip render pipeline
**Example:**
```nim
# Source: honeyclip av.nim existing pattern
# Apply global metadata to container
proc applyGlobalMetadata(ctx: ptr AVFormatContext, meta: Table[string, string]) =
  dictToAvdict(addr ctx.metadata, meta)

# Apply stream metadata (already exists in av.nim:324)
proc addStream*(self: var OutputContainer, ..., metadata: Table[string, string]): ... =
  # ... existing code ...
  if metadata.len > 0:
    dictToAvdict(addr stream.metadata, metadata)
```

### Pattern 3: Chapter Marker Application
**What:** Add chapter markers to output via AVChapter structures or ffmetadata file
**When to use:** When creating videos with navigable chapters (tutorials, lectures)
**Example:**
```nim
# Two approaches:

# Approach A: AVChapter API (requires new FFmpeg bindings)
type
  AVChapter* {.importc, header: "<libavformat/avformat.h>".} = object
    id*: int64
    time_base*: AVRational
    start*: int64
    end*: int64
    metadata*: ptr AVDictionary

proc avpriv_new_chapter*(s: ptr AVFormatContext, id: int64,
                         time_base: AVRational, start: int64,
                         end: int64, title: cstring): ptr AVChapter
  {.importc, header: "<libavformat/avformat.h>".}

# Approach B: ffmetadata file (simpler, proven)
proc generateFFMetadata(template: MetadataTemplate): string =
  result = ";FFMETADATA1\n"
  for key, val in template.global:
    result &= &"{key}={escapeMetadata(val)}\n"

  for chapter in template.chapters:
    result &= "\n[CHAPTER]\n"
    result &= "TIMEBASE=1/1000\n"
    result &= &"START={chapter.startMs}\n"
    result &= &"END={chapter.endMs}\n"
    result &= &"title={escapeMetadata(chapter.title)}\n"
```

### Pattern 4: CLI Flag Overrides
**What:** Command-line flags override template values for one-off adjustments
**When to use:** Template provides defaults but user needs per-file customization
**Example:**
```nim
# Source: Similar to honeyclip export platform preset override pattern
proc applyMetadata(template: MetadataTemplate, args: MetaArgs): MetadataTemplate =
  result = template

  # CLI flags override template
  if args.title != "":
    result.global["title"] = args.title
  if args.author != "":
    result.global["artist"] = args.author  # Note: FFmpeg uses "artist" not "author"
  if args.copyright != "":
    result.global["copyright"] = args.copyright
  if args.description != "":
    result.global["description"] = args.description
```

### Anti-Patterns to Avoid
- **Direct AVDictionary manipulation without helpers:** Use existing dictToAvdict/avdict_to_dict helpers from util/dict.nim
- **Hardcoded metadata keys:** Different containers support different keys - make configurable
- **Ignoring character escaping:** Metadata values with special characters (=, ;, #, \, newline) must be escaped in ffmetadata format
- **Assuming universal support:** Not all containers support all metadata fields - validate per-format

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Metadata escaping | Custom string escaping | FFmpeg's built-in escaping or proven pattern | Special chars (=, ;, #, \, newline) need backslash escaping, easy to miss edge cases |
| YAML parsing | Custom YAML parser | NimYAML or stick to JSON | YAML spec is complex (anchors, references, multi-doc), std/json is sufficient |
| Container format detection | Parse file headers | FFmpeg's av_guess_format/avformat_find_stream_info | FFmpeg already handles this robustly |
| Metadata validation | Custom validators per format | Document limitations, let FFmpeg fail gracefully | Format support varies (MP4 vs MKV vs MOV), FFmpeg knows which keys are valid |

**Key insight:** FFmpeg's metadata API is mature and handles format-specific quirks. Building custom validation or encoding logic duplicates FFmpeg's work and introduces bugs.

## Common Pitfalls

### Pitfall 1: Inconsistent Metadata Key Names Across Formats
**What goes wrong:** Using "author" key when FFmpeg expects "artist" (MP4), or "description" vs "comment" (container-dependent)
**Why it happens:** Different container formats evolved with different metadata schemas
**How to avoid:** Maintain a compatibility mapping table:
```nim
const MetadataKeyMapping = {
  "author": "artist",      # MP4/QuickTime uses "artist"
  "date": "creation_time", # FFmpeg prefers ISO 8601 in "creation_time"
}.toTable
```
**Warning signs:** Metadata not appearing in output file, tools like ExifTool showing different keys

### Pitfall 2: UTF-8 Encoding Issues
**What goes wrong:** Non-ASCII characters (é, ñ, 中文) corrupted or rejected by FFmpeg
**Why it happens:** FFmpeg requires UTF-8 but doesn't always validate, some formats have encoding restrictions
**How to avoid:**
- Ensure JSON template files are UTF-8 encoded
- Nim strings are UTF-8 by default, but validate file I/O
- Test with international characters during development
**Warning signs:** Mojibake (�) characters, metadata truncated at non-ASCII chars

### Pitfall 3: Special Character Escaping in ffmetadata Format
**What goes wrong:** Metadata values containing =, ;, #, \, or newlines break ffmetadata parsing
**Why it happens:** These characters have special meaning in INI-style format
**How to avoid:**
```nim
proc escapeMetadata(s: string): string =
  result = ""
  for c in s:
    if c in {'=', ';', '#', '\\', '\n'}:
      result &= '\\'
    result &= c
```
**Warning signs:** FFmpeg errors like "Invalid metadata line", missing metadata in output

### Pitfall 4: Chapter Time Base Confusion
**What goes wrong:** Chapters appear at wrong timestamps or cause FFmpeg errors
**Why it happens:** Chapter times must match container's time base, not always milliseconds
**How to avoid:**
- Use consistent time base in template (recommend TIMEBASE=1/1000 for milliseconds)
- Convert to AVRational when using AVChapter API
- Validate START < END for all chapters
**Warning signs:** Chapters at 0:00:00, FFmpeg warnings about "chapter end before start"

### Pitfall 5: Metadata Loss When Copying Streams
**What goes wrong:** Using `-c copy` with FFmpeg causes metadata to be dropped
**Why it happens:** Some containers store metadata differently, remuxing doesn't preserve all fields
**How to avoid:**
- Use `-map_metadata 0` to explicitly copy metadata from input
- Re-apply metadata after copy operations
- Test with `ffprobe -show_format -show_streams` to verify
**Warning signs:** Metadata present in input but missing in output

## Code Examples

Verified patterns from official sources:

### Applying Metadata via Command Line (for reference)
```bash
# Source: https://wiki.multimedia.cx/index.php/FFmpeg_Metadata
# Source: https://abdus.dev/posts/ffmpeg-metadata/

# Basic metadata
ffmpeg -i input.mp4 \
  -metadata title="My Video" \
  -metadata artist="Author Name" \
  -metadata copyright="Copyright 2026" \
  -metadata description="Video description" \
  -metadata date="2026-02-05" \
  -c copy output.mp4

# Stream-specific metadata (language example)
ffmpeg -i input.mp4 \
  -metadata:s:v:0 language=eng \
  -metadata:s:a:0 language=eng \
  -c copy output.mp4
```

### Chapter Markers via ffmetadata File
```bash
# Source: https://ikyle.me/blog/2020/add-mp4-chapters-ffmpeg
# Source: https://hhsprings.bitbucket.io/docs/programming/examples/ffmpeg/metadata/chapters.html

# 1. Create metadata file
cat > metadata.txt << 'EOF'
;FFMETADATA1
title=Full Video Title
artist=Creator Name

[CHAPTER]
TIMEBASE=1/1000
START=0
END=149999
title=Introduction

[CHAPTER]
TIMEBASE=1/1000
START=150000
END=450000
title=Main Content
EOF

# 2. Apply to video
ffmpeg -i video.mp4 -i metadata.txt \
  -map_metadata 1 \
  -codec copy output.mp4
```

### JSON Template Format (honeyclip-specific)
```json
{
  "version": 1,
  "global": {
    "title": "${VIDEO_TITLE}",
    "artist": "${AUTHOR_NAME}",
    "copyright": "Copyright ${YEAR} ${AUTHOR_NAME}",
    "description": "${VIDEO_DESCRIPTION}",
    "date": "${ISO_DATE}"
  },
  "video": {
    "language": "eng"
  },
  "audio": {
    "language": "eng"
  },
  "chapters": [
    {
      "start_ms": 0,
      "end_ms": 30000,
      "title": "Introduction"
    },
    {
      "start_ms": 30000,
      "end_ms": 120000,
      "title": "Main Content"
    }
  ]
}
```

### Nim Implementation Pattern
```nim
# Source: Adapted from honeyclip av.nim and project.nim patterns

import std/[json, tables, strformat, strutils]
import ffmpeg, util/dict

type
  MetadataTemplate = object
    version: int
    global: Table[string, string]
    video: Table[string, string]
    audio: Table[string, string]
    chapters: seq[ChapterMarker]

  ChapterMarker = object
    startMs, endMs: int64
    title: string

proc loadTemplate(path: string): MetadataTemplate =
  let json = parseFile(path)
  result.version = json["version"].getInt(1)

  # Parse global metadata
  if "global" in json:
    for key, val in json["global"].pairs:
      result.global[key] = val.getStr()

  # Parse stream metadata
  if "video" in json:
    for key, val in json["video"].pairs:
      result.video[key] = val.getStr()

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

proc applyMetadata(formatCtx: ptr AVFormatContext,
                   videoStream: ptr AVStream,
                   audioStream: ptr AVStream,
                   template: MetadataTemplate) =
  # Apply global metadata
  dictToAvdict(addr formatCtx.metadata, template.global)

  # Apply stream metadata
  if videoStream != nil:
    dictToAvdict(addr videoStream.metadata, template.video)
  if audioStream != nil:
    dictToAvdict(addr audioStream.metadata, template.audio)

proc generateFFMetadata(template: MetadataTemplate): string =
  result = ";FFMETADATA1\n"

  # Global metadata
  for key, val in template.global:
    let escaped = val.multiReplace(
      ("\\", "\\\\"),
      ("=", "\\="),
      (";", "\\;"),
      ("#", "\\#"),
      ("\n", "\\n")
    )
    result &= &"{key}={escaped}\n"

  # Chapters
  for chapter in template.chapters:
    result &= "\n[CHAPTER]\n"
    result &= "TIMEBASE=1/1000\n"
    result &= &"START={chapter.startMs}\n"
    result &= &"END={chapter.endMs}\n"
    result &= &"title={chapter.title.multiReplace((\"\\", \"\\\\\"), (\"=\", \"\\=\"))}\n"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual exiftool commands | Template-driven metadata with DAM systems | 2020-2022 | Batch processing, consistency across assets |
| MP4 UserData atoms | QuickTime Keys (mdta) | ~2015 | Better support in Apple ecosystem, extensible |
| Format-specific tools | FFmpeg unified API | Ongoing | Cross-format workflows simplified |
| Command-line flags | JSON/YAML configuration | 2018+ | Version control, reproducibility |

**Deprecated/outdated:**
- **MP3 ID3v1 tags:** Limited to 30-char fields, use ID3v2.4 instead
- **AVI INFO chunk:** Limited metadata support, prefer MKV or MP4
- **Custom metadata formats:** Use standardized schemas (IPTC Video Metadata Hub, Dublin Core)

## Open Questions

Things that couldn't be fully resolved:

1. **Chapter marker format preference**
   - What we know: Both AVChapter API and ffmetadata files work, ffmetadata is simpler
   - What's unclear: Performance implications of AVChapter API vs ffmetadata file approach
   - Recommendation: Start with ffmetadata file approach (proven, simpler, no new FFmpeg bindings needed)

2. **YAML support necessity**
   - What we know: JSON is sufficient, NimYAML requires Nim 2.0+, adds dependency
   - What's unclear: Whether users would strongly prefer YAML over JSON
   - Recommendation: Start with JSON-only, add YAML if users request it

3. **Template variable substitution**
   - What we know: Template needs dynamic values (date, filename, etc.)
   - What's unclear: Full set of useful variables and substitution syntax
   - Recommendation: Support basic substitutions: `${VIDEO_TITLE}`, `${AUTHOR_NAME}`, `${YEAR}`, `${ISO_DATE}`, `${FILENAME}`

4. **Metadata validation per container**
   - What we know: Different containers support different metadata keys
   - What's unclear: Whether to validate/warn before applying or let FFmpeg handle it
   - Recommendation: Document common keys, let FFmpeg silently ignore unsupported keys (graceful degradation)

## Sources

### Primary (HIGH confidence)
- [FFmpeg Metadata - MultimediaWiki](https://wiki.multimedia.cx/index.php/FFmpeg_Metadata) - Comprehensive metadata key reference
- [FFmpeg Public Metadata API](https://ffmpeg.org/doxygen/7.0/group__metadata__api.html) - Official API documentation
- [FFmpeg Formats Documentation](https://ffmpeg.org/ffmpeg-formats.html) - ffmetadata format specification
- [NimYAML Documentation](https://nimyaml.org/) - YAML parsing library for Nim
- [Nim std/json](https://nim-lang.org/docs/json.html) - Standard library JSON module
- [AVChapter Struct Reference](https://ffmpeg.org/doxygen/trunk/structAVChapter.html) - Chapter structure definition

### Secondary (MEDIUM confidence)
- [Adding metadata to videos using ffmpeg](https://abdus.dev/posts/ffmpeg-metadata/) - Practical examples
- [How to Add Chapters to MP4s with FFmpeg](https://ikyle.me/blog/2020/add-mp4-chapters-ffmpeg) - Chapter implementation guide
- [IPTC Video Metadata Hub](https://iptc.org/standards/video-metadata-hub/) - Industry standard schema
- [QuickTime metadata keys - Apple Developer](https://developer.apple.com/documentation/quicktime-file-format/quicktime_metadata_keys) - MP4/MOV metadata reference
- [7 Best Practices For Media Metadata Management](https://massive.io/file-transfer/best-practices-for-metadata-management/) - Professional workflows

### Tertiary (LOW confidence)
- [MKV vs MP4: Best Streaming Format for Professionals 2026](https://www.dacast.com/blog/mkv-vs-mp4-for-video-streaming/) - Container comparison
- [ExifTool Tag Names](https://exiftool.org/TagNames/) - Comprehensive metadata reference (not for integration)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - FFmpeg metadata API well-documented, std/json in stdlib
- Architecture: HIGH - Patterns based on existing honeyclip code (project.nim, av.nim)
- Pitfalls: MEDIUM - Based on web search findings, not direct experience with honeyclip codebase

**Research date:** 2026-02-05
**Valid until:** 2026-09-05 (6 months - stable domain)
