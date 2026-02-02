# Codebase Structure

**Analysis Date:** 2026-02-01

## Directory Layout

```
auto-editor/
├── src/                      # All Nim source code
│   ├── main.nim             # Entry point, CLI routing
│   ├── edit.nim             # Main editing orchestration
│   ├── av.nim               # FFmpeg I/O wrapper
│   ├── media.nim            # Media metadata structures
│   ├── timeline.nim         # Timeline data structures
│   ├── ffmpeg.nim           # FFmpeg C bindings wrapper
│   ├── log.nim              # Logging and type definitions
│   ├── graph.nim            # FFmpeg filter graph abstraction
│   ├── cache.nim            # Caching for analysis results
│   ├── preview.nim          # Debug preview functionality
│   ├── resampler.nim        # Audio resampling utilities
│   ├── wavutil.nim          # WAV file utilities
│   ├── cli.nim              # Command definitions
│   ├── about.nim            # Version string
│   │
│   ├── analyze/             # Media analysis modules
│   │   ├── audio.nim        # Audio silence detection
│   │   ├── motion.nim       # Video motion detection
│   │   └── subtitle.nim     # Subtitle pattern matching
│   │
│   ├── palet/               # Expression parser and evaluation
│   │   ├── lexer.nim        # Tokenizer for edit expressions
│   │   └── edit.nim         # Expression evaluator and filter composition
│   │
│   ├── render/              # Output rendering
│   │   ├── format.nim       # Main render orchestration
│   │   ├── video.nim        # Video transcoding
│   │   ├── audio.nim        # Audio transcoding and mixing
│   │   └── subtitle.nim     # Subtitle muxing
│   │
│   ├── exports/             # NLE project file generators
│   │   ├── fcp7.nim         # Final Cut Pro 7 XML export
│   │   ├── fcp11.nim        # Final Cut Pro 11/FCPXML export
│   │   ├── json.nim         # JSON timeline export
│   │   ├── shotcut.nim      # Shotcut MLT export
│   │   └── kdenlive.nim     # Kdenlive project export
│   │
│   ├── imports/             # Timeline deserialization
│   │   └── json.nim         # JSON timeline parsing
│   │
│   ├── cmds/                # Subcommands
│   │   ├── cache.nim        # Cache management
│   │   ├── info.nim         # Media information display
│   │   ├── levels.nim       # Audio level visualization
│   │   ├── whisper.nim      # Speech-to-text interface
│   │   ├── desc.nim         # Metadata description
│   │   └── subdump.nim      # Subtitle extraction
│   │
│   └── util/                # Shared utilities
│       ├── color.nim        # RGB color parsing
│       ├── bar.nim          # Progress bar display
│       ├── fun.nim          # Functional utilities (TimeCode, splitNumStr, etc)
│       ├── lang.nim         # ISO 639 language code definitions
│       ├── rules.nim        # Container codec rules
│       └── dict.nim         # Dictionary utilities
│
├── tests/                   # Test suites
│   ├── unit.nim             # Nim unit tests
│   └── test.py              # Python end-to-end tests
│
├── resources/               # Test media and data
│   ├── *.wav, *.mp4         # Sample media files
│   └── subtitles/           # Sample subtitle files
│
├── ae.nimble                # Nimble package definition
├── CLAUDE.md                # Developer instructions
└── README.md                # Project documentation
```

## Directory Purposes

**src/:**
- Purpose: All production Nim source code
- Contains: Modules organized by functional area (analysis, rendering, export)
- Key files: `main.nim` (entry), `edit.nim` (orchestration), `av.nim` (FFmpeg binding)

**src/analyze/:**
- Purpose: Analysis backends for detecting regions to edit
- Contains: Audio loudness, video motion, subtitle text matching
- Key files: `audio.nim` (largest, ~214 lines, uses resampling)

**src/palet/:**
- Purpose: Domain-specific language for edit expressions
- Contains: Lexer and parser for `--edit` parameter
- Key files: `edit.nim` (388 lines, composition logic)

**src/render/:**
- Purpose: Final output generation via FFmpeg encoding
- Contains: Video/audio transcoding, subtitle muxing
- Key files: `audio.nim` (939 lines, audio processing pipeline)

**src/exports/:**
- Purpose: NLE project file generation
- Contains: Format-specific XML/JSON writers for Premiere, Final Cut, Shotcut, Kdenlive
- Key files: `kdenlive.nim` (579 lines, complex project structure)

**src/imports/:**
- Purpose: Deserialization of previously-exported timelines
- Contains: JSON timeline parsing only
- Key files: `json.nim` (deserializes v1/v2/v3 formats)

**src/cmds/:**
- Purpose: CLI subcommands for utility operations
- Contains: Cache management, metadata display, whisper integration
- Key files: None particularly large; feature-specific implementations

**src/util/:**
- Purpose: Cross-cutting shared code
- Contains: Color parsing, progress bars, codec validation, timecode utilities
- Key files: `bar.nim` (201 lines, complex progress visualization)

**tests/:**
- Purpose: Test coverage for core functionality
- Contains: Unit tests in Nim, E2E tests in Python
- Key files: `unit.nim` (covers AVRational, colors, subtitles, timecodes)

**resources/:**
- Purpose: Test media and fixture data
- Contains: Sample WAV, MP4 files for E2E testing
- Key files: Referenced in `tests/test.py`

## Key File Locations

**Entry Points:**
- `src/main.nim`: Argument parsing, subcommand routing, yt-dlp integration
- `src/edit.nim`: Main editing orchestration, export/render dispatch

**Configuration:**
- `ae.nimble`: Build configuration, FFmpeg compilation flags
- `CLAUDE.md`: Developer build instructions

**Core Logic:**
- `src/av.nim`: FFmpeg wrapper (open, stream iteration, codec context)
- `src/media.nim`: MediaInfo structures for metadata
- `src/timeline.nim`: Timeline data models (v1, v2, v3)
- `src/ffmpeg.nim`: FFmpeg C bindings and utilities

**Testing:**
- `tests/unit.nim`: Nim unit tests for AVRational, colors, subtitles
- `tests/test.py`: Python end-to-end tests (requires `av` package)

## Naming Conventions

**Files:**
- snake_case: `audio.nim`, `fcp7.nim`, `motion.nim`
- Organized by module/purpose, not by function
- Submodule structure matches directory (e.g., `analyze/audio.nim`)

**Directories:**
- snake_case lowercase: `analyze/`, `palet/`, `render/`, `exports/`
- Single-word or hyphenated: `src/` (root), `cmds/` (subcommands)

**Procedures (functions):**
- camelCase: `editMedia()`, `initMediaInfo()`, `makeMedia()`, `parseExportString()`
- Exported procs marked with `*` suffix: `proc open*()`

**Types:**
- PascalCase: `VideoStream`, `AudioStream`, `InputContainer`, `MediaInfo`, `Action`
- Enum variants: lowercase `actCut`, `actSpeed`, `nkEbu`, `nkPeak`

**Variables:**
- camelCase: `hasLoud`, `actionIndex`, `tlV3`, `myInput`
- Mutable: lowercase plural for sequences: `clips`, `tracks`, `streams`

## Where to Add New Code

**New Feature (e.g., new analysis type):**
- Primary code: `src/analyze/{analysis_type}.nim` (new file)
- Expression support: Add case to `src/palet/edit.nim` evaluator
- Tests: Add cases to `tests/unit.nim` or `tests/test.py`
- Export: Likely needed in `src/exports/*` if timeline structure changes

**New Export Format:**
- Implementation: `src/exports/{format_name}.nim` (new file)
- Import: Add case to `src/edit.nim` export dispatcher
- Registration: Add to export format detection in `setOutput()` in `src/edit.nim`

**New Render Component:**
- Implementation: `src/render/{component}.nim` (new or extend existing)
- Integration: Wire into `makeMedia()` in `src/render/format.nim`

**New Utility Function:**
- Shared helpers: `src/util/{category}.nim`
- Example: Timecode parsing in `src/util/fun.nim`
- Time-based functions: `src/util/fun.nim` (contains `toTimecode()`, `parseTime()`)

**New Subcommand:**
- Implementation: `src/cmds/{command}.nim` (new file)
- Registration: Add to `commands` const in `src/cli.nim`
- Main dispatch: Wire into `cmdHandlers` seq in `src/main.nim`

## Special Directories

**Cached Analysis:**
- Location: OS temp directory (configurable via `--temp-dir`)
- Generated: Yes (frame caches during analysis)
- Committed: No (temporary, cleaned up after run)
- Purpose: Speed up re-analysis of same file with different parameters

**Build Artifacts:**
- FFmpeg source builds in `vendor/` or similar (created by `nimble makeff`)
- Auto-editor binary in project root after `nimble make`
- Not committed to git

## Design Patterns

**Module Organization:**
- Each analysis method in own file (`analyze/audio.nim`, `analyze/motion.nim`)
- Exporter per format (`exports/fcp7.nim`, `exports/shotcut.nim`)
- Render logic split by type (`render/video.nim`, `render/audio.nim`)

**Type Composition:**
- Variant types for actions: `Action` with `kind` discriminator
- Metadata objects: `VideoStream`, `AudioStream` with stream-specific fields
- Timeline versions: v1 (simple chunks), v2 (clips + effects), v3 (multi-track)

**Data Flow:**
- Immutable input: `InputContainer` read-only
- Build-up: Timeline constructed from analysis results
- Dispatch: Timeline routed to export (JSON/XML writers) or render (transcoder)

---

*Structure analysis: 2026-02-01*
