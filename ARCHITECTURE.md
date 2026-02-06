# Architecture

This document provides a technical deep-dive into honeyclip's architecture, explaining how video processing flows through the system, how components interact, and the key design decisions behind the implementation.

## Table of Contents

- [System Overview](#system-overview)
- [Core Pipeline Flow](#core-pipeline-flow)
- [Module Architecture](#module-architecture)
- [Key Data Structures](#key-data-structures)
- [FFmpeg Integration](#ffmpeg-integration)
- [Expression Parser (Palet)](#expression-parser-palet)
- [Timeline System](#timeline-system)
- [Rendering Pipeline](#rendering-pipeline)
- [Export System](#export-system)
- [ML Integration](#ml-integration)
- [Cross-Platform Considerations](#cross-platform-considerations)
- [Design Patterns](#design-patterns)

## System Overview

honeyclip is a command-line video editing tool that automatically processes videos based on user-defined criteria (audio levels, motion, engagement, etc.). The architecture follows a **pipeline pattern** where data flows through distinct stages of transformation.

### High-Level Architecture

```
┌─────────────┐
│   CLI       │  Parse arguments, dispatch to subcommands
│  (main.nim) │
└──────┬──────┘
       │
       ├──────────────────────────────────────────────────┐
       │                                                   │
       ▼                                                   ▼
┌──────────────┐                                   ┌──────────────┐
│ Subcommands  │                                   │ Core Pipeline│
│ (cmds/*)     │                                   │              │
└──────────────┘                                   └──────┬───────┘
  │                                                       │
  │  - info       (metadata extraction)                   │
  │  - levels     (audio level analysis)                  │
  │  - transcript (speech-to-text)                        │
  │  - engage     (engagement scoring)                    │
  │  - export     (NLE project generation)                │
  │  - clips      (smart clip extraction)                 │
  │  - reframe    (intelligent cropping)                  │
  │  - caption    (subtitle rendering)                    │
  │  - whisper    (transcription)                         │
  │  - cache      (manage analysis cache)                 │
  │                                                       │
  └───────────────────────────────────────────────────────┘
```

### Core Pipeline Flow

The main video processing pipeline (default behavior) follows these stages:

```
Input Video
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. MEDIA INPUT (src/av.nim)                                 │
│    - Open video file with FFmpeg                            │
│    - Detect streams (video/audio/subtitle)                  │
│    - Extract metadata (resolution, framerate, duration)     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. ANALYSIS (src/analyze/*)                                 │
│    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│    │ Audio Levels │  │    Motion    │  │   Subtitles  │   │
│    │ (audio.nim)  │  │ (motion.nim) │  │(subtitle.nim)│   │
│    └──────────────┘  └──────────────┘  └──────────────┘   │
│           │                 │                 │             │
│           └─────────────────┴─────────────────┘             │
│                           │                                 │
│                 ┌─────────▼─────────┐                       │
│                 │  Engagement Score  │                       │
│                 │  (engagement.nim)  │                       │
│                 └────────────────────┘                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. EXPRESSION EVALUATION (src/palet/*)                      │
│    - Parse --edit expression (e.g., "audio:0.03")           │
│    - Evaluate against analysis data                         │
│    - Generate boolean array (keep/cut for each frame)       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. TIMELINE BUILDING (src/timeline.nim)                     │
│    - Convert boolean array to clip sequences                │
│    - Apply margin (merge nearby cuts)                       │
│    - Apply actions (cut/speed/varispeed)                    │
│    - Generate v3 timeline structure                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. RENDERING (src/render/*)                                 │
│    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│    │    Video     │  │    Audio     │  │   Subtitles  │   │
│    │ (video.nim)  │  │ (audio.nim)  │  │(subtitle.nim)│   │
│    └──────────────┘  └──────────────┘  └──────────────┘   │
│           │                 │                 │             │
│           └─────────────────┴─────────────────┘             │
│                           │                                 │
│                 ┌─────────▼─────────┐                       │
│                 │  Mux to Container  │                       │
│                 │   (format.nim)     │                       │
│                 └────────────────────┘                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                   Output Video
```

## Module Architecture

### Directory Structure

```
src/
├── main.nim              # Entry point, command dispatch
├── cli.nim               # CLI argument parsing
├── av.nim                # FFmpeg bindings (core I/O)
├── media.nim             # MediaInfo data structures
├── timeline.nim          # Timeline/clip management
├── edit.nim              # Main editing logic
├── log.nim               # Logging and error handling
├── cache.nim             # Analysis result caching
│
├── cmds/                 # Subcommand implementations
│   ├── info.nim          # Show media metadata
│   ├── levels.nim        # Audio level analysis
│   ├── transcript.nim    # Generate transcripts
│   ├── whisper.nim       # Whisper speech-to-text
│   ├── engagement.nim    # Engagement scoring
│   ├── clips.nim         # Extract smart clips
│   ├── reframe.nim       # Intelligent cropping
│   ├── caption.nim       # Burn-in subtitles
│   ├── exportcmd.nim     # NLE project export
│   ├── cache.nim         # Cache management
│   └── ...
│
├── analyze/              # Analysis modules
│   ├── audio.nim         # Audio level detection
│   ├── motion.nim        # Motion detection
│   ├── subtitle.nim      # Subtitle extraction
│   ├── engagement.nim    # Engagement scoring
│   ├── faces.nim         # Face detection (ML)
│   ├── clips.nim         # Clip extraction logic
│   ├── presets.nim       # Engagement presets
│   └── hooks.nim         # Custom analysis hooks
│
├── palet/                # Expression parser
│   ├── lexer.nim         # Tokenizer and parser
│   └── edit.nim          # Expression evaluator
│
├── render/               # Rendering modules
│   ├── video.nim         # Video stream processing
│   ├── audio.nim         # Audio stream processing
│   ├── subtitle.nim      # Subtitle rendering
│   ├── captions.nim      # Caption burn-in
│   ├── format.nim        # Container muxing
│   └── previews.nim      # Preview generation
│
├── exports/              # NLE project generators
│   ├── fcp7.nim          # Final Cut Pro 7 XML
│   ├── fcp11.nim         # Final Cut Pro X FCPXML
│   ├── edl.nim           # CMX3600 EDL
│   ├── aaf.nim           # AAF (Avid/Media Composer)
│   ├── kdenlive.nim      # Kdenlive MLT XML
│   ├── shotcut.nim       # Shotcut MLT XML
│   ├── markers.nim       # Marker export
│   └── project.nim       # Common project types
│
├── ml/                   # Machine learning (macOS/Linux only)
│   ├── facedetect.nim    # libfacedetection bindings
│   ├── onnx.nim          # ONNX Runtime bindings
│   └── opencv.nim        # OpenCV bindings
│
├── reframe/              # Intelligent cropping
│   ├── crop.nim          # Crop calculation
│   └── ...
│
├── transcript/           # Transcription
│   ├── srt.nim           # SRT subtitle format
│   └── ...
│
└── util/                 # Utilities
    ├── color.nim         # Color parsing and conversion
    ├── bar.nim           # Progress bars
    ├── lang.nim          # Language detection
    └── ...
```

### Module Dependency Graph

```
                           main.nim
                              │
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
    cli.nim               cmds/*              edit.nim
        │                     │                     │
        │                     │                     │
        │          ┌──────────┴──────────┐          │
        │          │                     │          │
        ▼          ▼                     ▼          ▼
    av.nim    analyze/*              palet/*    timeline.nim
        │          │                     │          │
        │          │                     │          │
        └──────────┴─────────┬───────────┴──────────┘
                             │
                             ▼
                        media.nim
                             │
                             ▼
                        ffmpeg.nim
                        (FFmpeg C API)
```

Key dependency rules:
- **ffmpeg.nim** is the lowest level (raw C bindings)
- **av.nim** wraps FFmpeg in safe Nim abstractions
- **media.nim** defines data structures (no FFmpeg calls)
- **analyze/** depends on av.nim but not timeline.nim
- **palet/** is independent (pure parser/evaluator)
- **render/** depends on timeline.nim and av.nim

## Key Data Structures

### MediaInfo (`src/media.nim`)

The central data structure representing all metadata about an input video:

```nim
type MediaInfo* = object
  path*: string                    # Input file path
  v*: seq[VideoStream]             # Video streams
  a*: seq[AudioStream]             # Audio streams
  s*: seq[SubtitleStream]          # Subtitle streams
  d*: seq[DataStream]              # Data streams (attachments)
  timebase*: AVRational            # Common timebase (usually 1/30000)
  chapters*: seq[Chapter]          # Chapter markers
  bitrate*: int64                  # Overall bitrate
  duration*: int64                 # Duration in timebase units
```

### VideoStream

```nim
type VideoStream* = object
  index*: int                      # Stream index in container
  width*, height*: int             # Resolution
  fps*: AVRational                 # Frame rate (e.g., {num: 30, den: 1})
  codec*: string                   # Codec name (e.g., "h264")
  bitrate*: int64                  # Video bitrate
  colorSpace*: AVColorSpace        # Color space (BT.601, BT.709, etc.)
  colorRange*: AVColorRange        # Full or limited range
  pixelFormat*: AVPixelFormat      # Pixel format (yuv420p, rgb24, etc.)
  sar*: AVRational                 # Sample aspect ratio (usually 1:1)
```

### AudioStream

```nim
type AudioStream* = object
  index*: int                      # Stream index in container
  sampleRate*: int                 # Sample rate (e.g., 48000)
  channels*: int                   # Channel count
  channelLayout*: string           # Layout name (e.g., "stereo")
  codec*: string                   # Codec name (e.g., "aac")
  bitrate*: int64                  # Audio bitrate
  sampleFormat*: AVSampleFormat    # Sample format (s16, fltp, etc.)
```

### Timeline v3 (`src/timeline.nim`)

The timeline represents the final edit as a sequence of clips:

```nim
type v3* = object
  tb*: AVRational                  # Timebase for all timestamps
  bg*: RGBColor                    # Background color
  sr*: cint                        # Sample rate for audio
  layout*: string                  # Audio channel layout
  res*: (int, int)                 # Output resolution (width, height)
  v*: seq[seq[Clip]]               # Video layers (tracks)
  a*: seq[seq[Clip]]               # Audio layers (tracks)
  s*: seq[seq[Clip]]               # Subtitle layers (tracks)
  langs*: seq[Lang]                # Languages (for multi-track)
  effects*: seq[seq[Action]]       # Global effects table
  clips2*: seq[Clip2]              # Linear edit representation
```

### Clip

Individual clip in a timeline layer:

```nim
type Clip* = object
  src*: ptr string                 # Pointer to source file path
  start*: int64                    # Start time in timeline (timebase units)
  dur*: int64                      # Duration (timebase units)
  offset*: int64                   # Offset into source file (timebase units)
  effects*: uint32                 # Index into Timeline.effects
  stream*: int32                   # Source stream index
```

### Action

Actions define what happens to a clip (cut, speed change, etc.):

```nim
type ActionKind* = enum
  actNil,                          # No change (passthrough)
  actCut,                          # Remove (speed = infinity)
  actSpeed,                        # Change speed (preserve pitch)
  actVarispeed                     # Change speed (vary pitch)

type Action* = object
  case kind*: ActionKind
  of actNil, actCut:
    discard
  of actSpeed, actVarispeed:
    speed*: float64                # Speed multiplier (0.5 = half speed, 2.0 = double)
```

## FFmpeg Integration

honeyclip builds FFmpeg from source with a curated set of codecs to minimize binary size and ensure reproducibility. The integration follows a **safe wrapper** pattern.

### FFmpeg Binding Layers

```
Application Code (high-level)
        │
        ▼
┌─────────────────────────────────────┐
│  av.nim (Safe Nim wrappers)         │
│  - InputContainer                    │
│  - open(), close()                   │
│  - Error handling with exceptions    │
│  - Resource cleanup (RAII-style)     │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│  ffmpeg.nim (Raw C bindings)        │
│  - AVFormatContext                   │
│  - AVCodecContext                    │
│  - AVPacket, AVFrame                 │
│  - All av_* functions                │
└────────────────┬────────────────────┘
                 │
                 ▼
        FFmpeg C Libraries
    (built from source in build/)
```

### Safe Wrapper Pattern

**Problem:** FFmpeg uses raw pointers and requires manual memory management.

**Solution:** av.nim wraps FFmpeg in safe abstractions:

```nim
# src/av.nim - Safe wrapper
type InputContainer* = object
  formatContext*: ptr AVFormatContext
  packet*: ptr AVPacket
  video*: seq[ptr AVStream]
  audio*: seq[ptr AVStream]
  # ...

proc open*(filename: string): InputContainer =
  result = InputContainer()
  result.packet = av_packet_alloc()  # Allocate packet
  
  # Open input with error handling
  if avformat_open_input(addr result.formatContext, filename.cstring, nil, nil) != 0:
    raise newException(IOError, "Could not open input file: " & filename)
  
  # Find streams
  if avformat_find_stream_info(result.formatContext, nil) < 0:
    avformat_close_input(addr result.formatContext)  # Cleanup on error
    raise newException(IOError, "Could not find stream information")
  
  # Categorize streams
  for i in 0 ..< result.formatContext.nb_streams.int:
    let stream: ptr AVStream = result.formatContext.streams[i]
    case stream.codecpar.codecType
    of AVMEDIA_TYPE_VIDEO:
      result.video.add(stream)
    of AVMEDIA_TYPE_AUDIO:
      result.audio.add(stream)
    # ...
```

### Resource Management Rules

**Critical safety patterns:**

1. **Always check for nil** after FFmpeg allocations:
```nim
let packet = av_packet_alloc()
if packet == nil:
  error "Could not allocate packet"
```

2. **Always cleanup** FFmpeg resources (no garbage collection):
```nim
# Cleanup pattern
av_packet_free(addr packet)
avformat_close_input(addr formatContext)
avcodec_free_context(addr codecContext)
```

3. **Use exceptions for errors** (not error codes):
```nim
# FFmpeg returns < 0 on error
let ret = avcodec_send_packet(ctx, packet)
if ret < 0:
  error &"Failed to send packet: {av_err2str(ret)}"
```

4. **Module prefix for name collisions**:
```nim
# av.open() conflicts with std/syncio.open()
import av
let input = av.open("video.mp4")  # Use module prefix
```

### Common FFmpeg Patterns

**Opening a file:**
```nim
proc openVideo(path: string): MediaInfo =
  let input = av.open(path)
  defer: input.close()  # Ensure cleanup
  
  # Extract metadata
  result.v = input.video.mapIt(extractVideoInfo(it))
  result.a = input.audio.mapIt(extractAudioInfo(it))
```

**Reading packets:**
```nim
while av_read_frame(input.formatContext, packet) >= 0:
  defer: av_packet_unref(packet)  # Unreference after processing
  
  # Process packet
  if packet.stream_index == videoStreamIndex:
    processVideoPacket(packet)
```

**Decoding frames:**
```nim
let decoder = initDecoder(stream.codecpar)
defer: avcodec_free_context(addr decoder)

while av_read_frame(formatContext, packet) >= 0:
  if avcodec_send_packet(decoder, packet) < 0:
    error "Failed to send packet to decoder"
  
  let frame = av_frame_alloc()
  defer: av_frame_free(addr frame)
  
  while avcodec_receive_frame(decoder, frame) >= 0:
    processFrame(frame)
```

## Expression Parser (Palet)

The `--edit` flag accepts expressions that determine which parts of video to keep. The parser (`src/palet/`) is a **two-stage compiler**: lexer → parser.

### Expression Language

**Grammar:**
```
expression := atom | list
atom       := number | symbol
list       := '(' expression* ')'
symbol     := identifier (':' param)*
param      := identifier '=' value | value
```

**Examples:**
- `audio` - Keep frames above audio threshold
- `audio:0.03` - Audio with custom threshold
- `motion:threshold=0.02` - Motion with named parameter
- `(or audio:0.03 motion:0.06)` - Logical OR
- `(and audio motion)` - Logical AND
- `audio:-19dB` - Decibel threshold

### Parsing Pipeline

```
Input String: "(or audio:0.03 motion:0.02)"
      │
      ▼
┌─────────────────────────────────────────────────┐
│ 1. LEXER (lexer.nim)                            │
│    Tokenizes input into stream of tokens        │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
      [Lparen, Sym("or"), Sym("audio"), Colon, 
       Num("0.03"), Sym("motion"), Colon, 
       Num("0.02"), Rparen]
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│ 2. PARSER (lexer.nim)                           │
│    Builds AST from token stream                 │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
      ExprList([
        ExprSym("or"),
        ExprList([ExprSym("audio"), ExprNum(0.03)]),
        ExprList([ExprSym("motion"), ExprNum(0.02)])
      ])
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│ 3. EVALUATOR (edit.nim)                         │
│    Interprets AST against analysis data         │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
      Boolean Array: [true, true, false, true, ...]
      (keep frame 0, 1, skip 2, keep 3, ...)
```

### Lexer Implementation

The lexer is a **character-by-character scanner**:

```nim
type TokenKind = enum
  Lparen, Rparen,  # ( )
  Sym,             # Identifier (audio, motion, etc.)
  Num,             # Number (0.03, -19dB, etc.)
  Colon,           # :
  Comma,           # ,
  Equal,           # =
  Eof              # End of input

type Lexer = object
  text: string
  pos: uint32
  char: char
```

**Token scanning:**
1. Skip whitespace and comments (`;` to end of line)
2. Recognize single-char tokens: `(){}[],:=`
3. Scan numbers: digits, `.`, `-`, unit suffixes (`dB`, `s`, `ms`, etc.)
4. Scan symbols: alphanumeric + `_`, `-`, `%`

### Parser Implementation

The parser uses **recursive descent** to build an AST:

```nim
proc parseExpr(p: var Parser): Expr =
  case p.currentToken.kind
  of Lparen:
    # Parse list: (sym arg1 arg2 ...)
    p.advance()
    var elements: seq[Expr]
    while p.currentToken.kind != Rparen:
      elements.add(p.parseExpr())
    p.expect(Rparen)
    return ExprList(elements)
  
  of Sym:
    # Parse symbol with optional parameters
    let sym = p.getTokenText()
    p.advance()
    if p.currentToken.kind == Colon:
      # Symbol with parameter: audio:0.03
      p.advance()
      let param = p.parseExpr()
      return ExprList([ExprSym(sym), param])
    return ExprSym(sym)
  
  of Num:
    # Parse number
    let num = p.getTokenText()
    p.advance()
    return ExprNum(num)
  
  else:
    error "Unexpected token"
```

### Evaluator Implementation

The evaluator **interprets the AST** against analysis data:

```nim
proc evaluateEdit*(expr: Expr, info: MediaInfo, analysisData: AnalysisCache): seq[bool] =
  case expr.kind
  of ExprSym:
    # Lookup method (audio, motion, subtitle, etc.)
    let method = getSymbol(expr)
    case method
    of "audio":
      return analyzeAudio(info, threshold = 0.04)  # Default threshold
    of "motion":
      return analyzeMotion(info, threshold = 0.02)
    of "subtitle":
      return analyzeSubtitles(info)
    # ...
  
  of ExprList:
    # Function call: (or audio motion)
    let fn = expr.elements[0].getSymbol()
    let args = expr.elements[1..^1]
    
    case fn
    of "or":
      # Logical OR: keep if ANY method says keep
      let results = args.mapIt(evaluateEdit(it, info, analysisData))
      return zipOr(results)
    
    of "and":
      # Logical AND: keep if ALL methods say keep
      let results = args.mapIt(evaluateEdit(it, info, analysisData))
      return zipAnd(results)
    
    of "not":
      # Logical NOT: invert result
      let result = evaluateEdit(args[0], info, analysisData)
      return result.mapIt(not it)
    
    # ...
```

## Timeline System

The timeline system (`src/timeline.nim`) converts boolean arrays into structured clip sequences. This is where the **cut/speed/margin logic** happens.

### Timeline Evolution

honeyclip has evolved through 3 timeline versions:

**v1:** Simple chunk-based (deprecated)
```nim
type v1 = object
  chunks: seq[(start, end, speed)]
  source: string
```

**v2:** Clips with effects (deprecated)
```nim
type v2 = object
  clips: seq[Clip2]
  effects: seq[seq[Action]]
```

**v3:** Multi-track timeline (current)
```nim
type v3 = object
  v: seq[seq[Clip]]     # Video tracks (layers)
  a: seq[seq[Clip]]     # Audio tracks (layers)
  s: seq[seq[Clip]]     # Subtitle tracks (layers)
  effects: seq[seq[Action]]
```

### Boolean Array to Timeline

**Input:** Boolean array from expression evaluator
```
[true, true, true, false, false, true, true, true]
 keep  keep  keep  cut   cut   keep  keep  keep
```

**Step 1: Chunkify** (group consecutive values)
```
Chunks:
  [0-2]: keep   (3 frames)
  [3-4]: cut    (2 frames)
  [5-7]: keep   (3 frames)
```

**Step 2: Apply margin** (merge nearby chunks if gap < margin)
```
Margin = 2 frames
  Gap between chunk 1 and 3 = 2 frames
  → Merge: [0-7]: keep (8 frames)
```

**Step 3: Convert to clips** (apply actions)
```
Clips:
  Clip 0: start=0, dur=8, offset=0, effects=nil
```

**Output:** Timeline v3 with clips

### Timeline Building Algorithm

```nim
proc buildTimeline(keepArr: seq[bool], margin: int64, actions: Actions): v3 =
  # 1. Chunkify: Group consecutive true/false
  var chunks: seq[(start: int64, end: int64, keep: bool)]
  var current = keepArr[0]
  var start = 0
  
  for i, keep in keepArr:
    if keep != current:
      chunks.add((start, i - 1, current))
      current = keep
      start = i
  chunks.add((start, keepArr.len - 1, current))
  
  # 2. Apply margin: Merge nearby chunks
  mutMargin(chunks, margin)
  
  # 3. Remove small chunks
  mutRemoveSmall(chunks, minLength = 10)  # Skip tiny chunks
  
  # 4. Convert to clips with actions
  var clips: seq[Clip]
  var timelinePos = 0
  
  for chunk in chunks:
    let dur = chunk.end - chunk.start + 1
    let action = if chunk.keep: actions.whenNormal else: actions.whenSilent
    
    case action.kind
    of actCut:
      # Skip this chunk entirely
      discard
    
    of actSpeed:
      # Add clip with speed adjustment
      let adjustedDur = int64(dur.float / action.speed)
      clips.add(Clip(
        start: timelinePos,
        dur: adjustedDur,
        offset: chunk.start,
        effects: actions.normalEffects
      ))
      timelinePos += adjustedDur
    
    of actNil:
      # Add clip unchanged
      clips.add(Clip(
        start: timelinePos,
        dur: dur,
        offset: chunk.start,
        effects: 0
      ))
      timelinePos += dur
  
  result.v.add(clips)  # Add to first video track
```

### Multi-Track Support

Timelines can have multiple layers (tracks) for complex edits:

```
Timeline:
  Video Track 0: [Clip A]─────[Clip B]─────[Clip C]
  Video Track 1:         [Overlay]
  Audio Track 0: [Audio A]────[Audio B]────[Audio C]
  Audio Track 1:                    [Music]
```

This enables:
- **Picture-in-picture** (multiple video tracks)
- **Background music** (additional audio tracks)
- **Subtitle layers** (multiple subtitle tracks)

## Rendering Pipeline

The rendering pipeline (`src/render/`) processes the timeline and outputs the final video.

### Rendering Architecture

```
Timeline v3
    │
    ▼
┌─────────────────────────────────────────────────┐
│  RENDER DISPATCHER (main render loop)           │
│  - Iterate through timeline                     │
│  - Dispatch to video/audio/subtitle renderers   │
└────┬────────────────────────────────────┬───────┘
     │                                    │
     ▼                                    ▼
┌─────────────────┐              ┌─────────────────┐
│ Video Renderer  │              │ Audio Renderer  │
│ (video.nim)     │              │ (audio.nim)     │
├─────────────────┤              ├─────────────────┤
│ - Decode frames │              │ - Decode samples│
│ - Apply filters │              │ - Apply filters │
│ - Encode output │              │ - Encode output │
└────┬────────────┘              └────┬────────────┘
     │                                │
     └────────────────┬───────────────┘
                      ▼
             ┌─────────────────┐
             │ Format Muxer    │
             │ (format.nim)    │
             ├─────────────────┤
             │ - Mux streams   │
             │ - Write to file │
             └─────────────────┘
                      │
                      ▼
                Output File
```

### Video Rendering

**Key operations:**
1. **Seek to offset** in source file
2. **Decode frames** from source
3. **Apply filters** (speed change, color correction, etc.)
4. **Encode frames** to output codec
5. **Write packets** to muxer

**Speed changes** are handled by FFmpeg filters:
```nim
# Create filter graph for 2x speed (preserve pitch)
let filterGraph = "setpts=0.5*PTS,atempo=2.0"
```

**Frame processing loop:**
```nim
for clip in timeline.v[0]:  # First video track
  # Seek to clip start in source
  av_seek_frame(input, clip.offset, AVSEEK_FLAG_BACKWARD)
  
  # Decode and encode frames
  var framesEncoded = 0
  while framesEncoded < clip.dur:
    if av_read_frame(input, packet) < 0:
      break
    
    if avcodec_send_packet(decoder, packet) < 0:
      error "Failed to decode"
    
    while avcodec_receive_frame(decoder, frame) >= 0:
      # Apply effects (speed, filters, etc.)
      applyEffects(frame, clip.effects)
      
      # Encode frame
      if avcodec_send_frame(encoder, frame) < 0:
        error "Failed to encode"
      
      while avcodec_receive_packet(encoder, outPacket) >= 0:
        av_interleaved_write_frame(output, outPacket)
      
      framesEncoded += 1
```

### Audio Rendering

Audio rendering is similar but operates on **samples** instead of frames:

```nim
for clip in timeline.a[0]:  # First audio track
  # Decode samples
  while samplesDecoded < clip.dur * sampleRate:
    # Read, decode, apply effects, encode
    processAudioSamples(clip)
```

**Speed changes** require **pitch correction**:
- `actSpeed`: Change speed, preserve pitch (uses FFmpeg `atempo` filter)
- `actVarispeed`: Change speed, vary pitch (change playback rate)

### Subtitle Rendering

Subtitles can be:
1. **Burned-in** (rasterized onto video) - `src/render/captions.nim`
2. **Muxed** (separate subtitle stream) - `src/render/subtitle.nim`

**Burn-in pipeline:**
```
SRT file → Parse → libass → Render to bitmap → Overlay on video
```

## Export System

The export system (`src/exports/`) generates **NLE project files** for video editing software.

### Supported Formats

| Format | File Extension | Software | Status |
|--------|---------------|----------|--------|
| **FCP7** | `.xml` | Final Cut Pro 7 | Stable |
| **FCPXML** | `.fcpxml` | Final Cut Pro X | Stable |
| **EDL** | `.edl` | CMX3600 EDL (industry standard) | Stable |
| **AAF** | `.aaf` | Avid Media Composer, Premiere Pro | Beta |
| **Kdenlive** | `.kdenlive` | Kdenlive | Stable |
| **Shotcut** | `.mlt` | Shotcut | Stable |
| **JSON** | `.json` | Custom honeyclip format | Stable |
| **Markers** | `.csv`, `.txt` | Various | Stable |

### Export Architecture

```
Timeline v3
    │
    ▼
┌─────────────────────────────────────────────────┐
│  EXPORT DISPATCHER (exports/project.nim)        │
│  - Determine format from --export flag          │
│  - Validate timeline compatibility              │
└────┬────────────────────────────────────────────┘
     │
     ├──► FCP7 Exporter (fcp7.nim)       → .xml
     ├──► FCPXML Exporter (fcp11.nim)    → .fcpxml
     ├──► EDL Exporter (edl.nim)         → .edl
     ├──► AAF Exporter (aaf.nim)         → .aaf
     ├──► Kdenlive Exporter (kdenlive.nim) → .kdenlive
     ├──► Shotcut Exporter (shotcut.nim) → .mlt
     └──► JSON Exporter (json.nim)       → .json
```

### Export Pattern

All exporters follow a common pattern:

```nim
proc exportFCP7*(timeline: v3, output: string) =
  # 1. Create XML document
  var xml = newXmlTree("xmeml", [
    xmlAttr("version", "5")
  ])
  
  # 2. Add project metadata
  xml.add(newXmlTree("project", [
    newXmlTree("name", [newText("honeyclip export")])
  ]))
  
  # 3. Convert timeline to sequence
  var sequence = newXmlTree("sequence")
  for i, layer in timeline.v:
    sequence.add(videoTrackToXml(layer, i))
  for i, layer in timeline.a:
    sequence.add(audioTrackToXml(layer, i))
  
  # 4. Write to file
  writeFile(output, $xml)
```

### EDL Format Example

EDL (Edit Decision List) is the **simplest** format (text-based):

```
TITLE: honeyclip export

001  AX       V     C        00:00:00:00 00:00:05:00 00:00:00:00 00:00:05:00
* FROM CLIP NAME: input.mp4
* SOURCE FILE: input.mp4

002  AX       V     C        00:00:10:00 00:00:15:00 00:00:05:00 00:00:10:00
* FROM CLIP NAME: input.mp4
* SOURCE FILE: input.mp4
```

**Format breakdown:**
- `001` - Edit number
- `AX` - Reel name (source)
- `V` - Video track
- `C` - Cut transition
- `00:00:00:00 00:00:05:00` - Source IN/OUT (timecode)
- `00:00:00:00 00:00:05:00` - Record IN/OUT (timeline position)

### XML Format Example (FCP7)

FCP7 XML is more complex but supports **more features**:

```xml
<xmeml version="5">
  <project>
    <name>honeyclip export</name>
    <children>
      <sequence>
        <name>Main Sequence</name>
        <rate>
          <timebase>30</timebase>
          <ntsc>FALSE</ntsc>
        </rate>
        <media>
          <video>
            <track>
              <clipitem id="clip-1">
                <name>input.mp4</name>
                <start>0</start>
                <end>150</end>
                <in>0</in>
                <out>150</out>
                <file id="file-1">
                  <pathurl>file:///path/to/input.mp4</pathurl>
                </file>
              </clipitem>
            </track>
          </video>
        </media>
      </sequence>
    </children>
  </project>
</xmeml>
```

## ML Integration

Machine learning features (`src/ml/`) are **macOS/Linux only** due to compilation issues with ML libraries on Windows.

### ML Architecture

```
┌─────────────────────────────────────────────────┐
│  ML-Enabled Features (when defined(enable_ml))  │
├─────────────────────────────────────────────────┤
│  - engage (engagement scoring)                  │
│  - reframe (intelligent cropping)               │
│  - Face detection in analysis                   │
└────┬────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────┐
│  ML Bindings (src/ml/)                          │
├─────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐            │
│  │ libfacedetect│  │     ONNX     │            │
│  │ (facedetect) │  │   Runtime    │            │
│  └──────────────┘  └──────────────┘            │
│         │                  │                    │
│         └──────────┬───────┘                    │
│                    │                            │
│            ┌───────▼────────┐                   │
│            │    OpenCV      │                   │
│            │  (image ops)   │                   │
│            └────────────────┘                   │
└─────────────────────────────────────────────────┘
                     │
                     ▼
          Native ML Libraries
    (built from source in ml_sources/)
```

### Platform-Specific Compilation

```nim
# src/ml/facedetect.nim
when defined(enable_ml):
  import opencv, onnx
  
  proc detectFaces*(frame: ptr AVFrame): seq[FaceBox] =
    # Use libfacedetection
    let img = frameToMat(frame)
    let faces = runFaceDetector(img)
    return faces

else:
  # Stub implementation for Windows
  proc detectFaces*(frame: ptr AVFrame): seq[FaceBox] =
    warning "Face detection not available on Windows"
    return @[]
```

### Engagement Scoring

Engagement scoring combines multiple signals:

```nim
proc calculateEngagement*(info: MediaInfo, preset: Preset): seq[float] =
  let audioLevels = analyzeAudio(info)        # Weight: 30%
  let motionScores = analyzeMotion(info)      # Weight: 40%
  
  when defined(enable_ml):
    let facialScores = analyzeFaces(info)     # Weight: 30%
  else:
    let facialScores = newSeq[float](audioLevels.len)  # All zeros
  
  # Weighted combination
  var engagement = newSeq[float](audioLevels.len)
  for i in 0 ..< engagement.len:
    engagement[i] = 
      preset.weights.audio * audioLevels[i] +
      preset.weights.motion * motionScores[i] +
      preset.weights.facial * facialScores[i]
  
  return engagement
```

## Cross-Platform Considerations

honeyclip supports **Windows, macOS, and Linux** with graceful degradation.

### Platform Support Matrix

| Feature | Linux | macOS | Windows |
|---------|-------|-------|---------|
| **Core Video Editing** | ✅ | ✅ | ✅ |
| **Audio Processing** | ✅ | ✅ | ✅ |
| **Subtitle Rendering** | ✅ | ✅ | ✅ |
| **LTO (Link-Time Optimization)** | ✅ | ✅ | ❌ (GCC ICE) |
| **ML Features** | ✅ | ✅ | ❌ (stub) |
| **Face Detection** | ✅ | ✅ | ❌ |
| **ONNX Runtime** | ✅ | ✅ | ❌ |
| **CUDA Acceleration** | ✅ | ❌ | ❌ |
| **Metal Acceleration** | ❌ | ✅ (planned) | ❌ |

### Conditional Compilation

```nim
# Platform-specific imports
when not defined(windows):
  import std/posix_utils

# Feature detection
when defined(enable_ml):
  import ml/facedetect
  proc detectFaces() = ...
else:
  proc detectFaces() = 
    warning "Face detection not available"
    return @[]

# OS-specific code
when defined(windows):
  # Windows-specific implementation
  proc findGcc(): string =
    # Use choosenim's bundled MinGW
    return joinPath(getHomeDir(), ".choosenim/toolchains/mingw64/bin/gcc.exe")
else:
  # Unix implementation
  proc findGcc(): string =
    return "gcc"
```

### Build System

The build system (`honeyclip.nimble`) handles cross-compilation:

```nim
task windows, "Cross-compile for Windows":
  when defined(windows):
    # Native Windows build (no LTO)
    exec "nim c -d:enable_whisper -o:honeyclip.exe src/main.nim"
  else:
    # Cross-compile from Linux/macOS
    exec "nim c --os:windows --cpu:amd64 " &
         "-d:mingw -d:enable_whisper " &
         "-o:honeyclip.exe src/main.nim"
```

## Design Patterns

### Error Handling

honeyclip uses **fail-fast error handling** with global cleanup:

```nim
# src/log.nim
var tempDir*: string  # Global temp directory

proc error*(msg: string) {.noreturn.} =
  stderr.writeLine("Error: " & msg)
  
  # Cleanup temp files
  if tempDir != "" and dirExists(tempDir):
    removeDir(tempDir)
  
  quit(1)
```

**Usage:**
```nim
if stream == nil:
  error "Could not find video stream"  # Exits immediately
```

### Progress Reporting

Progress is reported via **transient console output**:

```nim
# src/log.nim
proc conwrite*(msg: string) =
  # Write message, then clear it on next call
  stdout.write(msg)
  stdout.write("\r")
  stdout.flushFile()
```

**Usage:**
```nim
for i, frame in frames:
  conwrite &"Processing frame {i}/{frames.len}"
echo ""  # Final newline (persistent)
```

### Resource Cleanup

FFmpeg resources are cleaned up with **defer** pattern:

```nim
proc processVideo(path: string) =
  let input = av.open(path)
  defer: input.close()  # Always cleanup
  
  let packet = av_packet_alloc()
  defer: av_packet_free(addr packet)
  
  # Process video...
  # Even if error occurs, cleanup happens
```

### Module Exports

Modules use **explicit exports** (no barrel files):

```nim
# Public symbols marked with *
proc error*(msg: string) {.noreturn.} = ...
type VideoStream* = object

# Private symbols have no *
proc internalHelper() = ...
```

### Naming Conventions

- **Files:** `snake_case.nim` (e.g., `audio_levels.nim`)
- **Types:** `PascalCase` (e.g., `VideoStream`, `MediaInfo`)
- **Functions:** `camelCase` (e.g., `parseColor`, `initMediaInfo`)
  - Pure functions: `func` keyword
  - Side effects: `proc` keyword
  - Mutation: `mut` prefix (e.g., `mutMargin`, `mutRemoveSmall`)
- **Enum values:** `lowercase` (e.g., `actCut`, `actSpeed`)
- **Variables:** `camelCase` for locals, `snake_case` for FFmpeg interop

### Testing Strategy

```
tests/
├── unit.nim          # Unit tests (Nim standard unittest)
│   ├── AVRational tests
│   ├── Color parsing tests
│   ├── Subtitle extraction tests
│   └── Encoder initialization tests
│
├── test.py           # E2E tests (Python + PyAV)
│   ├── CLI argument parsing
│   ├── Media processing workflows
│   └── Export format validation
│
├── benchmark.nim     # Performance benchmarks
│   ├── Audio analysis benchmark
│   ├── Media info benchmark
│   └── Timeline building benchmark
│
└── BENCHMARK*.md     # Benchmark documentation
```

## Summary

honeyclip's architecture follows these core principles:

1. **Pipeline Pattern** - Data flows through distinct stages (input → analysis → evaluation → timeline → rendering → output)
2. **Safe Wrappers** - FFmpeg's unsafe C API is wrapped in safe Nim abstractions
3. **Explicit Cleanup** - Resources are manually managed with defer patterns
4. **Fail-Fast Errors** - Errors terminate immediately with cleanup
5. **Cross-Platform First** - Windows/macOS/Linux are all first-class (graceful degradation)
6. **Local-First** - All processing happens locally (no cloud dependencies)
7. **Performance & Quality Balance** - Speed optimizations preserve quality by default

The modular design allows:
- **Easy testing** (each module is independent)
- **Parallel development** (modules have clear boundaries)
- **Feature flags** (ML features compile conditionally)
- **Export flexibility** (multiple NLE formats from same timeline)

For more details, see:
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development workflow and standards
- [PERFORMANCE.md](PERFORMANCE.md) - Speed/quality tradeoffs
- [tests/BENCHMARKS.md](tests/BENCHMARKS.md) - Benchmark system details
