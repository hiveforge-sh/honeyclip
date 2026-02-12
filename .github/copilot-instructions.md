# Copilot Instructions for honeyclip

honeyclip is a command-line video editing tool written in Nim that automatically removes silent sections from videos and analyzes engagement. It features ML-powered engagement analysis, speaker tracking, and smart clip extraction.

## Development Philosophy (READ FIRST)

### Cross-Platform First
**Every feature must work on Windows, macOS, and Linux or gracefully degrade.** When developing:
- Test cross-compilation (`nimble windows`) before marking work complete
- Use `when defined(windows)` / `when not defined(windows)` for platform-specific code
- Provide clear error messages for unsupported features rather than silent failures
- Windows is a **first-class platform**, not an afterthought

### Local-First Architecture
**Prefer local computation over remote services.** This codebase:
- Builds FFmpeg from source for full control and reproducibility
- Bundles ML models locally (libfacedetection, ONNX, Whisper)
- Avoids cloud dependencies (no AWS/GCP/Azure services)
- Uses local Python virtual environments (`.venv/`) for isolation

### Performance & Quality Balance
**Speed is a feature, but quality is non-negotiable.** Users need control over both:
- **Performance optimization must never degrade quality without explicit user choice**
- Expose quality/speed tradeoffs via presets: `--preset fast|balanced|best`
- Document performance impact of quality settings (codec presets, ML model sizes)
- Use release builds (`-d:danger --panics:on`) with LTO for production
- Profile hot paths before optimizing (measure, don't guess)
- Prefer native FFmpeg operations over frame-by-frame processing in Nim
- Cache expensive computations (see `src/cache.nim` pattern)
- GPU acceleration planned (Phase 15 roadmap) - see `.planning/ROADMAP.md`

**Existing quality controls:**
- `--vprofile` - Video encoder profile (h264: baseline/main/high)
- Codec selection - Enable/disable codecs via feature flags (VP8/9, HEVC, SVT-AV1)
- Whisper models - User chooses model size (base: fast/ggml-medium: accurate)
- Audio/motion thresholds - `--edit audio:0.03` (higher = stricter cut detection)
- Analysis confidence - Face detection, engagement scoring thresholds

**Missing (Phase 22 roadmap):**
- Quality preset system (`--preset fast`: x264 ultrafast, base whisper, etc.)
- Quality metrics validation (PSNR, VMAF) in benchmarks
- Speed/quality documentation table showing tradeoffs

## Build, Test, and Lint

### Build Commands

```bash
# First-time setup: Build FFmpeg and codec libraries (takes 1-2 hours)
nimble makeff

# Build ML libraries (libfacedetection, OpenCV, ONNX Runtime) - macOS/Linux only
nimble makeml

# Compile honeyclip binary (release build with LTO)
nimble make

# Cross-compile for Windows (requires mingw-w64)
nimble makeffwin  # Build FFmpeg first
nimble windows    # Then compile binary
```

### Testing

```bash
# Run all unit tests
nimble test

# Run a specific test by editing tests/unit.nim and commenting out other test suites

# Run Python end-to-end tests (requires: pip install av)
python3 tests/test.py

# Coverage report (Linux only)
nimble coverage

# Performance benchmarks
nimble bench  # First run establishes baseline, subsequent runs detect regressions

# Performance validation (E2E quality & speed tests)
nimble validateperf
```

**See `tests/BENCHMARK_QUICKSTART.md` for benchmark usage guide.**
**See `tests/PERFORMANCE_VALIDATION.md` for validation suite documentation.**

### Build Feature Flags

Set these environment variables **before** `nimble makeff`:

- `DISABLE_VPX=1` - Skip VP8/VP9 codec
- `DISABLE_SVTAV1=1` - Skip SVT-AV1 encoder
- `DISABLE_HEVC=1` - Skip H.265 codec
- `DISABLE_WHISPER=1` - Skip whisper.cpp speech-to-text
- `ENABLE_12BIT=1` - Enable 12-bit x265
- `ENABLE_CUDA=1` - Enable CUDA for whisper (Linux only)

### Other Tasks

```bash
nimble cleanff        # Clean FFmpeg build artifacts
nimble zshcomplete   # Generate zsh completions
```

## High-Level Architecture

### Core Pipeline Flow

1. **Media Input** (`src/av.nim`) - FFmpeg bindings read input media (video/audio/subtitles)
2. **Analysis** (`src/analyze/`) - Detect audio levels, motion, faces, or extract subtitles
3. **Expression Evaluation** (`src/palet/`) - Parse and evaluate `--edit` expressions to determine what to keep/cut
4. **Timeline Building** (`src/timeline.nim`) - Construct sequence of clips from analysis results
5. **Rendering** (`src/render/`) - Process and output final video/audio
6. **Export** (`src/exports/`) - Generate NLE project files (Premiere, Resolve, etc.)

### Module Organization

- **Entry point**: `src/main.nim` - Command dispatcher and CLI argument handling
- **Analysis modules**: `src/analyze/` - Audio levels, motion detection, face detection, engagement scoring
- **Subcommands**: `src/cmds/` - Individual command implementations (`cache`, `caption`, `clips`, `engage`, `info`, `levels`, `reframe`, `subdump`, `transcript`, `whisper`)
- **ML modules**: `src/ml/` - Face detection (libfacedetection), ONNX Runtime, OpenCV
- **Expression parser**: `src/palet/` - Lexer and parser for `--edit` expressions
- **Exporters**: `src/exports/` - NLE format generators (FCP7, FCP11, EDL, AAF, Kdenlive, Shotcut)
- **Renderers**: `src/render/` - Audio/video/caption/subtitle processing
- **Utilities**: `src/util/` - Colors, parsing helpers, progress bars, language detection

### Key Data Structures

Defined in `src/media.nim`:

- `VideoStream` - Video stream metadata (dimensions, frame rate, codec, color space)
- `AudioStream` - Audio stream metadata (sample rate, channels, codec)
- `SubtitleStream` - Subtitle stream metadata
- `MediaInfo` - Container for all streams and metadata

### Expression Parser (`src/palet/`)

The `--edit` flag accepts expressions that determine which parts of video to keep:

- **Lexer** (`lexer.nim`) - Tokenizes expression strings
- **Parser** (`lexer.nim`) - Builds expression AST
- **Evaluator** (`edit.nim`) - Interprets expressions and returns boolean arrays indicating keep/cut decisions

Examples:
- `audio` - Keep frames above audio threshold (default)
- `motion:threshold=0.02` - Keep frames with motion above threshold
- `(or audio:0.03 motion:0.06)` - Logical combination of methods
- `audio:-19dB` - Use dB threshold instead of 0-1 scale

## Conventions and Patterns

### Naming Conventions

- **Files**: `snake_case.nim` (e.g., `audio.nim`, `timeline.nim`)
- **Functions**: `camelCase` for most procs (e.g., `parseColor()`, `initMediaInfo()`)
  - Pure functions use `func` keyword, side-effect procedures use `proc`
  - Helper/internal functions may use `snake_case`
  - Mutation functions prefixed with `mut` (e.g., `mutMargin()`, `mutRemoveSmall()`)
- **Types**: `PascalCase` (e.g., `VideoStream`, `MediaInfo`, `RGBColor`)
- **Enum values**: lowercase (e.g., `actCut`, `actSpeed`, `nkNull`)
- **Variables**: `camelCase` for locals, `snake_case` for FFmpeg interop fields

### Error Handling

- **Fatal errors**: Use `error(msg)` from `src/log.nim` - prints to stderr and exits with cleanup
- **Warnings**: Use `warning(msg)` - prints to stderr but continues
- **Debug**: Use `debug(msg)` when `isDebug = true`
- **No custom exceptions** - Use Nim built-in exceptions and catch sparingly

### Public API

- Public symbols marked with `*`: `proc error*(msg: string)`, `type VideoStream*`
- Private symbols have no `*`
- Module exports are explicit - no barrel files

### FFmpeg Integration

- FFmpeg built from source with curated codec set to minimize binary size
- Disabled codecs listed in `honeyclip.nimble` (search for `disableDecoders`, `disableEncoders`)
- FFmpeg bindings in `src/av.nim` use C interop types (`ptr AVFormatContext`, `cint`, `ptr uint8`)
- Always check for `nil` after FFmpeg allocation calls

### Testing Strategy

- **Unit tests** (`tests/unit.nim`): AVRational arithmetic, color parsing, subtitle extraction, encoder init, timecode parsing
- **E2E tests** (`tests/test.py`): CLI argument parsing, media processing workflows, export format generation
- Test media files in `resources/`
- Coverage target: 80% (enforced in CI for Linux builds)

### Platform Differences

- **Windows**: LTO disabled (GCC 11.1.0 ICE), ML features stubbed out
- **macOS/Linux**: Full ML support, LTO enabled
- **Windows builds**: Must use Git Bash for `nimble makeff` (requires Unix tools)

## Cross-Platform Compatibility (CRITICAL)

**Always ensure Windows compatibility or graceful fallback when making changes.**

When developing on macOS/Linux:
- Test that code compiles on Windows (use `nimble windows` for cross-compilation)
- Wrap platform-specific features with `when` conditionals
- Provide graceful fallbacks or clear error messages for unsupported features
- ML features should degrade gracefully when `enable_ml` is not defined

Example patterns:
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
    warning "Face detection not available on Windows"
    return @[]

# Conditional compilation
when defined(windows):
  # Windows-specific implementation
else:
  # Unix implementation
```

### Platform Limitations Reference

- **Windows**: No LTO (GCC ICE), no ML features (face detection, ONNX), requires Git Bash for FFmpeg build
- **macOS/Linux**: Full feature set with LTO and ML support
- **CUDA**: Linux only (via `ENABLE_CUDA=1`)

## Important Implementation Details

### Import Order

1. Standard library (`import std/[...]`)
2. Third-party libraries (`import tinyre`)
3. Local modules (relative or implicit)
4. Conditional imports (`when not defined(windows): import std/posix_utils`)

### Progress Reporting

- Use `conwrite()` from `src/log.nim` for transient progress messages (cleared with spaces)
- Use `echo()` for persistent output
- Progress bars managed separately in `src/util/bar.nim`

### Subcommand Pattern

New subcommands should:
1. Create `src/cmds/{command}.nim`
2. Export `proc main*(args: seq[string])`
3. Register in `cmdHandlers` array in `src/main.nim`
4. Add to `commands` array in `src/cli.nim`

### Memory Management

- FFmpeg resources require explicit cleanup (call `av_*_free()`)
- Temp files managed via `tempDir` in `src/log.nim`
- Cleanup happens in `error()` before exit

## Running Individual Tests

Nim doesn't have built-in test filtering. To run a specific test:

1. Open `tests/unit.nim`
2. Comment out unwanted test suites
3. Run `nimble test`

Example:
```nim
# suite "AVRational tests":
#   test "AVRational arithmetic": ...

suite "Color parsing tests":
  test "Parse hex colors": ...
```

## CI/CD

See `.github/workflows/build.yml` for:
- Matrix builds: Ubuntu (x86_64, ARM64), macOS (Intel, Apple Silicon), Windows
- ML library caching strategy
- Coverage thresholds (80% on Linux)
- Binary size limits (100MB hard limit)
- CUDA support on Linux builds only

**Smoke tests** (`.github/workflows/smoke.yml`):
- Fast validation on every PR (disables heavy codecs: VP8/9, SVT-AV1, HEVC)
- Runs on Ubuntu, macOS, and cross-compiled Windows
- E2E tests with Python (`tests/test.py`)

## Benchmarking & Performance

The project has a comprehensive benchmarking infrastructure:

- **Microbenchmarks** (`nimble bench`): Fast component-level benchmarks with regression detection
  - Audio analysis, media info parsing, timeline building, etc.
  - Baseline stored in `tests/benchmark_results.json`
  - See `tests/BENCHMARK_QUICKSTART.md` for usage guide

- **E2E validation** (`nimble validateperf`): Full pipeline quality & speed tests
  - Real video processing workflows
  - Quality validation (hash-based, PSNR where applicable)
  - Performance thresholds for realistic workloads
  - See `tests/PERFORMANCE_VALIDATION.md` for details

### Future Profiling Improvements

Recommended additions:
1. **Profiling workflow**:
   - Add `nimble profile` task: compile with `--profiler:on --stackTrace:on`
   - Document platform tools: Valgrind (Linux), Instruments (macOS), WPA (Windows)
   - Use `--define:memProfiler` for memory tracking
   - Profile against 4K video files (detect memory leaks)

2. **CI integration**:
   - Run `nimble bench` in CI to detect regressions automatically
   - Track performance trends over time (plot in GitHub Actions artifacts)
   - Add `nimble validateperf` to CI matrix (currently manual)

3. **Platform-specific benchmarks**:
   - Compare performance across Linux, macOS, and Windows
   - Measure impact of LTO and ML features on macOS/Linux vs Windows
   - Benchmark CUDA path on Linux (when `ENABLE_CUDA=1`)

### Cross-Platform Validation
**CURRENT:** Windows builds cross-compile from Linux (not tested on real Windows)

Recommended additions:
1. **Windows native CI runner**:
   - Add `runs-on: windows-latest` job to smoke.yml
   - Test ML stub behavior (engage/reframe commands should not crash)
   - Validate Git Bash requirement is documented properly

2. **Platform-specific test fixtures**:
   - Path separators: Test `\` vs `/` handling
   - Line endings: CRLF vs LF in generated files
   - File permissions: Windows lacks execute bit

3. **Feature matrix documentation**:
   ```markdown
   | Feature        | Linux | macOS | Windows |
   |----------------|-------|-------|---------|
   | LTO            | ✅    | ✅    | ❌      |
   | ML (face)      | ✅    | ✅    | ❌      |
   | CUDA           | ✅    | ❌    | ❌      |
   | Metal          | ❌    | ✅    | ❌      |
   ```

### Development Automation
**MISSING:** Pre-commit hooks, linting, formatting enforcement

Recommended additions:
1. **Pre-commit hooks** (`.pre-commit-config.yaml`):
   - Format Nim code with nimpretty (if used)
   - Check for platform-specific code without `when` guards
   - Validate cross-compilation (`nimble windows`) before push
   - Run unit tests locally before push

2. **Linting task** (`nimble lint`):
   - No official Nim linter exists, but check:
     - `nim check` for type errors
     - Warnings enabled: `--warnings:on`
     - Hint suppression patterns documented

3. **Local development validation** (`nimble check-all`):
   ```bash
   nimble test          # Unit tests
   nimble windows       # Cross-compile check
   python3 tests/test.py # E2E tests
   nimble bench         # Performance regression check
   ```

### Documentation Improvements

Recommended additions:
1. **More architecture diagrams**:
   - Pipeline flow diagram (visual)
   - FFmpeg binding patterns and safety rules
   - Expression parser internals (lexer → parser → evaluator)
   - Export format generators (how NLE XMLs are built)

**Note:** `PERFORMANCE.md`, `ARCHITECTURE.md`, and `TROUBLESHOOTING.md` already exist with comprehensive guides.

### Caching Strategy
**CURRENT:** FFmpeg/ML sources cached in CI, but rebuild times still long

Recommended additions:
1. **Build artifact sharing**:
   - Pre-built FFmpeg libraries for common platforms (GitHub Releases)
   - Download instead of building for development (save 1-2 hours)
   - Keep source build for CI/reproducibility

2. **Incremental compilation**:
   - Nim's incremental compilation works but not documented
   - `nimble make` could use `--incremental:on` for faster rebuilds
   - Cache `nimcache/` directory in CI

3. **Smart invalidation**:
   - Only rebuild FFmpeg if `build-ffmpeg.sh` changes
   - Only rebuild ML libs if versions change in `honeyclip.nimble`

### Testing Improvements
**CURRENT:** Unit tests exist, E2E tests minimal, no integration tests

Recommended additions:
1. **Integration test suite**:
   - Test full pipeline with real video files
   - Validate NLE exports work in actual editors (Premiere, Resolve)
   - Test all subcommands end-to-end

2. **Platform-specific test matrix**:
   - Test ML stubbing on Windows (should not crash)
   - Test CUDA paths on Linux
   - Test Metal paths on macOS

3. **Property-based testing**:
   - Use Nim's `unittest2` or add hypothesis-style testing
   - Fuzz expression parser with random inputs
   - Validate timeline builder with random clip sequences

### Future Roadmap Integration
Per `.planning/ROADMAP.md`, v2.0 includes:
- **Phase 15:** GPU acceleration (CUDA/Metal) - requires platform-specific testing
- **Phase 16:** Batch processing - needs template validation across platforms
- **Phase 19:** Progress tracking - must work in Windows CMD/PowerShell
- **Phase 22:** Quality presets - **CRITICAL for speed/quality balance**

**Phase 22 Quality Preset Requirements:**
- `--preset fast`: Optimize for speed (ultrafast x264, base whisper, skip ML)
  - Target: 10x realtime on modern CPU (30min video in 3min)
  - Quality floor: PSNR >28dB, acceptable for drafts
- `--preset balanced`: Default (main profile, small whisper, basic ML)
  - Target: 2x realtime (30min video in 15min)
  - Quality target: PSNR >32dB, production-ready
- `--preset best`: Optimize for quality (veryslow, medium whisper, full ML)
  - Target: 0.5x realtime (30min video in 60min)
  - Quality target: PSNR >38dB, archival/broadcast quality

When implementing roadmap features, remember:
- GPU code must have CPU fallback (quality must match, speed differs)
- Templates (TOML) must use cross-platform paths
- Progress bars must detect terminal capabilities (Windows CMD vs Git Bash)
- **Quality validation required for all presets** - automated tests verify minimums
