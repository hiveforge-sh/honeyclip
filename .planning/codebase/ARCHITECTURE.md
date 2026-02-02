# Architecture

**Analysis Date:** 2026-02-01

## Pattern Overview

**Overall:** Multi-stage CLI pipeline with layered processing

**Key Characteristics:**
- Command-line entry point with subcommand routing
- FFmpeg bindings for media I/O
- Timeline-based clip editing model
- Modular analysis backends for detection (audio, motion, subtitles)
- Multiple export formats for NLE integration
- Filter graph-based processing

## Layers

**CLI & Argument Parsing:**
- Purpose: Parse user input and route to execution paths
- Location: `src/main.nim` (entry point), `src/cli.nim` (command definitions)
- Contains: Argument parsing, option validation, help text
- Depends on: Nothing (entry layer)
- Used by: All other layers

**Media Input Layer:**
- Purpose: Open, read, and extract metadata from media files
- Location: `src/av.nim`, `src/media.nim`
- Contains: FFmpeg wrapper (`InputContainer`), stream enumeration
- Depends on: FFmpeg C bindings
- Used by: Analysis layer, Edit layer

**Analysis Layer:**
- Purpose: Detect regions of interest (silence, motion, subtitles)
- Location: `src/analyze/` (audio.nim, motion.nim, subtitle.nim)
- Contains: Signal processors, filter graphs, decision algorithms
- Depends on: FFmpeg for decoding/filtering, audio resampling
- Used by: Edit layer

**Expression Parser (Palet):**
- Purpose: Parse and evaluate `--edit` expressions for detection logic
- Location: `src/palet/` (lexer.nim, edit.nim)
- Contains: Tokenizer, expression AST, filter composition
- Depends on: Analysis layer (imports audio/motion/subtitle modules)
- Used by: Edit layer

**Timeline Construction:**
- Purpose: Build clip sequences from detection results
- Location: `src/timeline.nim`, `src/edit.nim`
- Contains: Timeline data structures (v1, v2, v3 formats), clip merging, effect assignment
- Depends on: Media layer, Analysis layer, Palet layer
- Used by: Export and Render layers

**Export Layer:**
- Purpose: Generate NLE project files (XML, JSON, proprietary formats)
- Location: `src/exports/` (fcp7.nim, fcp11.nim, json.nim, shotcut.nim, kdenlive.nim)
- Contains: Format-specific writers, metadata serialization
- Depends on: Timeline layer
- Used by: Main execution path or file output

**Render Layer:**
- Purpose: Transcode video/audio to final output file
- Location: `src/render/` (format.nim, video.nim, audio.nim, subtitle.nim)
- Contains: Encoder setup, frame processing, audio resampling
- Depends on: Media layer, Timeline layer, FFmpeg bindings
- Used by: Main execution path

**Utility Layer:**
- Purpose: Cross-cutting concerns
- Location: `src/util/` (color.nim, bar.nim, fun.nim, lang.nim, rules.nim, dict.nim)
- Contains: Color parsing, progress bars, codec rules, language codes
- Depends on: Standard library
- Used by: All layers

## Data Flow

**Media Analysis Path:**

1. CLI parses arguments (`src/main.nim`)
2. `av.open()` opens media file, creates `InputContainer` (`src/av.nim`)
3. `initMediaInfo()` extracts stream metadata (`src/media.nim`)
4. `interpretEdit()` evaluates `--edit` expression (`src/palet/edit.nim`)
   - Tokenizes expression with `lexer` (`src/palet/lexer.nim`)
   - Routes to audio/motion/subtitle analysis based on expression
   - Each analyzer reads frames and produces boolean array of "loud" regions
5. `initLinearTimeline()` converts boolean array to timeline clips (`src/timeline.nim`)
6. Actions applied to ranges (cut, speed, volume) based on `--cut`, `--keep`, `--set-speed` flags
7. Timeline effects deduplicated and indexed

**Export Path:**

1. CLI checks export type (json, premiere, final-cut-pro, shotcut, kdenlive)
2. Corresponding exporter called with timeline (`src/exports/*`)
3. Timeline serialized to target format
4. File written to output

**Render Path:**

1. Timeline prepared for rendering
2. `makeMedia()` opens output file (`src/render/format.nim`)
3. For each stream type (video/audio/subtitle):
   - Create encoder with specified codec
   - Create frame iterator that processes timeline clips
   - Write frames to output
4. File finalized and closed

**State Management:**

- **Immutable input**: `InputContainer` opened once, never modified
- **Mutable processing**: `mainArgs` holds all runtime configuration
- **Persistent timeline**: `v3` timeline object passed between export/render
- **Frame caching**: Filter graphs hold transient frame data

## Key Abstractions

**InputContainer:**
- Purpose: Represents an open media file with stream organization
- Examples: `src/av.nim` (definition and methods)
- Pattern: Encapsulates FFmpeg format/packet context and auto-categorizes streams by type

**MediaInfo:**
- Purpose: Metadata about input file (duration, codecs, dimensions, languages)
- Examples: `src/media.nim`
- Pattern: Immutable data object extracted once per input file

**Timeline (v1, v2, v3):**
- Purpose: Multi-version timeline model supporting different complexity levels
- Examples: `src/timeline.nim`
- Pattern: v1 (simple chunks), v2 (clips with effects), v3 (multi-track with shared effect pool)

**Action:**
- Purpose: Operation applied to a time range
- Examples: `src/log.nim` (ActionKind enum and Action union)
- Pattern: Tagged union - cut, speed, varispeed, or volume with optional value

**Graph:**
- Purpose: FFmpeg filter graph abstraction for video/audio processing
- Examples: `src/graph.nim`
- Pattern: Reference type with lazy configuration, push/pull frame API

**AudioProcessor/VideoProcessor:**
- Purpose: Stateful decoders for extracting analysis data
- Examples: `src/analyze/audio.nim`, `src/analyze/motion.nim`
- Pattern: Manages FFmpeg codec context, filter graph, and FIFO buffers

## Entry Points

**Main Binary (`src/main.nim`):**
- Location: `src/main.nim` (proc `main()`)
- Triggers: Direct invocation of honeyclip binary
- Responsibilities:
  1. Parse CLI arguments into `mainArgs`
  2. Dispatch to subcommands or main edit path
  3. Handle URL download via yt-dlp if input is HTTP/HTTPS
  4. Call `editMedia(args)` for main editing flow

**editMedia() (`src/edit.nim`):**
- Location: `src/edit.nim` (proc `editMedia()`)
- Triggers: Called from main after argument parsing
- Responsibilities:
  1. Detect input type (media file, JSON timeline, or stdin)
  2. If media: analyze with FFmpeg and build timeline
  3. If JSON: deserialize existing timeline
  4. Apply argument overrides (margins, ranges, speeds)
  5. Route to export or render based on `--export`
  6. Call `makeMedia()` for final rendering

**Subcommands (`src/cmds/`):**
- Location: `src/cmds/` (info.nim, cache.nim, levels.nim, whisper.nim, desc.nim, subdump.nim)
- Triggers: `honeyclip {command} [args]`
- Responsibilities: Utility operations (metadata display, caching, speech-to-text)

## Error Handling

**Strategy:** Fail-fast with user-facing error messages

**Patterns:**
- `error()` proc logs error and halts execution (`src/log.nim`)
- FFmpeg errors wrapped with context (e.g., codec initialization failures)
- Validation at parse time (malformed arguments, missing options)
- Graceful file I/O with clear messages on missing inputs/outputs
- Silent pass-through for optional analyses (e.g., if subtitle stream doesn't match pattern)

## Cross-Cutting Concerns

**Logging:**
- Framework: Custom logging via `src/log.nim`
- Approach: `conwrite()` for info, `debug()` conditional on `isDebug` flag, `error()` for failures
- Progress reporting: `Bar` type in `src/util/bar.nim` for frame-by-frame updates

**Validation:**
- Time ranges validated at parse (negative offsets handled with array length logic)
- Codec names resolved via FFmpeg and validated against container rules
- Sample rates and resolutions checked for minimum values

**Authentication:**
- Not applicable - local processing only

**Codec Resolution:**
- `setVideoCodec()` and `setAudioCodec()` in `src/edit.nim` normalize codec names
- Container rules define supported codecs (`src/util/rules.nim`)
- "auto" codec selection based on input stream or container default

---

*Architecture analysis: 2026-02-01*
