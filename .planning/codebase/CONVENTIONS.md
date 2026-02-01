# Coding Conventions

**Analysis Date:** 2026-02-01

## Naming Patterns

**Files:**
- Nim source files use `snake_case`: `audio.nim`, `timeline.nim`, `color.nim`
- Main entry point: `src/main.nim`
- Subcommands: `src/cmds/{command}.nim`
- Modules organized by domain: `src/analyze/`, `src/exports/`, `src/render/`, `src/util/`, `src/palet/`

**Functions:**
- Procs and functions use `camelCase`: `parseColor()`, `initMediaInfo()`, `newAudioIterator()`
- Pure functions (no side effects) declared with `func` keyword: `func toString*(color: RGBColor): string`
- Side-effect procedures declared with `proc` keyword
- Error-handling procs marked `{.noreturn.}`: `proc error*(msg: string) {.noreturn.}` in `src/log.nim`
- Helper/internal functions may use `snake_case`: `parse_thres()`, `split_num_str()`
- Getter functions use naming pattern: `getRes()`, `getFlag()`, `getNumber()`
- Mutation functions prefixed with `mut`: `mutMargin()`, `mutRemoveSmall()` in `src/util/fun.nim`

**Variables:**
- Local variables use `camelCase`: `myInput`, `downloadFormat`, `outputFormat`
- Package-level/module variables use `camelCase`: `isDebug`, `quiet`, `tempDir` (in `src/log.nim`)
- Field names in objects use `snake_case`: `bit_rate`, `ch_layout`, `avg_rate`, `pix_fmt`, `color_range` (FFmpeg interop in `src/media.nim`)
- Tuple unpacking uses lowercase with underscores: `let (dir, name, ext) = splitFile(val)`

**Types:**
- Type names use `PascalCase`: `VideoStream`, `AudioStream`, `SubtitleStream`, `MediaInfo`, `RGBColor`, `AVRational`, `PackedInt`, `BarType`, `Action`
- Enum values use lowercase: `actCut`, `actSpeed`, `actVolume`, `nkNull`, `nkEbu`, `nkPeak`
- Type aliases for distinct types (wrapper types): `type PackedInt* = distinct int64`

## Code Style

**Formatting:**
- No explicit formatter configured (no `.prettierrc`, `.nimpretty.toml` found)
- 2-space indentation used consistently across codebase
- Line continuations use standard Nim style (implicit line continuation in many contexts)
- Multiline procedures: parameters on same line if short, broken to multiple lines with indentation

**Linting:**
- No explicit linting tool configured (no `.nimble` linting task found)
- Nim compiler used with flags: `-d:danger --panics:on` for release builds (see `ae.nimble`)
- Compilation with LTO enabled: `--passC:-flto --passL:-flto`

## Import Organization

**Order:**
1. Standard library imports (`import std/[...]`): Collections, IO, utilities
2. Third-party imports: `import tinyre` (regex library)
3. Local module imports: Project modules using relative or implicit paths
4. Conditional imports: `when not defined(windows): import std/posix_utils`

**Path Aliases:**
- Relative imports using `../` prefix: `import ../av`, `import ../log`
- Implicit imports from modules in same directory: `import color` from sibling
- Aliased imports using `as`: Not extensively used in this codebase

**Examples from codebase:**
- `src/main.nim`: Standard lib first, then local modules (av, log, cli, edit)
- `src/analyze/audio.nim`: Standard lib, then relative imports (`../av`, `../log`, `../cache`)
- `src/palet/edit.nim`: Standard lib, local relative imports, then third-party (`tinyre`)

## Error Handling

**Patterns:**
- Global error handler: `proc error*(msg: string) {.noreturn.}` in `src/log.nim` (line 160)
  - Logs error message to stderr with "Error! " prefix
  - Cleans up temp directory before exiting
  - Styled output (red text) unless NO_COLOR set
  - Always calls `quit(1)` for clean termination
- Warning handler: `proc warning*(msg: string)` (line 148) - non-terminating
- Parse validation errors propagate through `error()` calls with context

**Exception handling:**
- Try-catch blocks used sparingly for specific recovery: `try: ... except ValueError: error(...)` pattern in `src/util/fun.nim` (line 23-26)
- Broad `except:` catches used for fatal conditions (e.g., color parsing)
- Most error paths use `error()` for immediate termination with user message
- No custom exception types; relies on Nim built-in exceptions (ValueError, etc.)

**Error propagation:**
- Command-line parsing errors: Direct `error()` calls with descriptive messages
- FFmpeg errors: `error()` calls like `error "Could not allocate audio FIFO"` (line 60 of `src/analyze/audio.nim`)
- File operations: Direct `error()` with context when files don't exist

## Logging

**Framework:** `console` (stdout/stderr) via `src/log.nim` module

**Output functions:**
- `proc conwrite*(msg: string)`: Progress/status message to stdout, cleared with spaces
- `proc debug*(msg: string)`: Green debug message (if `isDebug = true`)
- `proc warning*(msg: string)`: Warning to stderr with "Warning! " prefix
- `proc error*(msg: string) {.noreturn.}`: Red error message, cleanup, exit

**Patterns:**
- Debug messages use `debug()` when `isDebug` flag set
- Status messages use `conwrite()` for transient progress updates
- Final messages use `echo()` for persistent output
- Color output controlled by `NO_COLOR` environment variable (line 128 of `src/log.nim`)

**Logging in modules:**
- Minimal logging in library modules
- Verbose logging in main pipeline (src/edit.nim, src/main.nim)
- Progress bars managed separately in `src/util/bar.nim`

## Comments

**When to Comment:**
- Comments used for non-obvious logic, not for restating code
- FFmpeg-specific workarounds commented: `# Shortcut: if format and dimensions are the same, return original frame` (src/render/video.nim)
- Compiler directives with explanation: `{.passC: "-ffast-math".}` followed by URL reference
- Algorithm-specific notes (e.g., bit manipulation in PackedInt)

**Documentation Style:**
- Double-hash comments for documentation: `## Get total number of samples (all channels)` in `src/render/audio.nim`
- Single-hash for inline comments: `# Initialize audio FIFO`
- No structured docstring format (no JSDoc-style annotations)

**Examples:**
- `src/analyze/audio.nim`: Algorithm explanation comments for resampling
- `src/log.nim`: Bit-packing explanation in `pack()` function comments
- `src/util/fun.nim`: Parsing logic comments explaining allowed characters

## Function Design

**Size:** Functions kept short, typically 10-50 lines
- Larger functions (100+ lines) are pipeline orchestrators (`src/edit.nim`)
- Helper procedures split out for reusability

**Parameters:**
- Use tuple unpacking for related values: `(PackedInt, PackedInt)` for time ranges
- Named parameters preferred over positional for clarity
- Type-qualified parameters to match FFmpeg C interop: `ptr AVAudioFifo`, `cint`, `ptr uint8`

**Return Values:**
- Single return value (implicit in Nim): `result = ...` pattern used
- Tuple returns for multiple values: `proc parseExportString*(...): (string, string, string)`
- Option types not extensively used; nil checks instead
- Error path returns via `error()` (noreturn)

**Example patterns:**
```nim
# Simple parser with error handling
proc parseTime*(val: string): PackedInt =
  if val == "start":
    return pack(false, 0)
  if val == "end":
    return pack(false, 0x3FFFFFFFFFFFFFFF)
  return parseTimeSimple(val)

# Tuple return
proc parseExportString*(exportStr: string): (string, string, string) =
  var kind = exportStr
  var name = "Auto-Editor Media Group"
  var version = "11"
  # ... processing ...
  return (kind, name, version)

# Mutation function
proc mutMargin*(arr: var seq[bool], startM, endM: int) =
  # ... in-place modification ...
```

## Module Design

**Exports:**
- Public symbols marked with `*`: `proc error*(msg: string)`, `type VideoStream*`
- Private symbols have no `*`: Local procs like `proc findColor(name: string)`
- Module-level constants exported when needed: `const commands*: seq[tuple[...]]` in `src/cli.nim`

**Barrel Files:**
- Not used; imports are explicit from specific modules
- Example: `import std/[os, osproc, parseutils, sequtils, strformat, strutils, terminal, uri]` style

**Namespace organization:**
- Utility functions grouped in `src/util/`: `color.nim`, `fun.nim`, `bar.nim`, `lang.nim`
- Analysis modules: `src/analyze/`: `audio.nim`, `motion.nim`, `subtitle.nim`
- Export/render modules: `src/exports/`, `src/render/`
- Command implementations: `src/cmds/`
- Core pipeline: `src/*.nim`

---

*Convention analysis: 2026-02-01*
