# Contributing to honeyclip

Thank you for your interest in contributing to honeyclip! This guide will help you get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Development Standards](#development-standards)
- [Platform Support](#platform-support)
- [Getting Help](#getting-help)

---

## Code of Conduct

This project adheres to the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## Getting Started

### Prerequisites

**All Platforms:**
- Nim 2.2.2+ ([install via choosenim](https://nim-lang.org/install.html))
- Git
- cmake, nasm, pkg-config

**Platform-Specific:**
- **macOS:** Xcode Command Line Tools, Homebrew (optional)
- **Linux:** build-essential (gcc, g++, make)
- **Windows:** Git Bash (provides Unix tools for FFmpeg build)

### Quick Setup

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/honeyclip.git
   cd honeyclip
   ```

2. **Run the bootstrap script:**
   ```bash
   ./bootstrap.sh  # macOS/Linux
   # or
   ./bootstrap.ps1  # Windows (PowerShell)
   ```
   
   This installs system dependencies automatically.

3. **Build FFmpeg from source (required first time, takes 1-2 hours):**
   ```bash
   nimble makeff
   ```
   
   **Windows users:** Run this in **Git Bash**, not PowerShell.

4. **Build ML libraries (macOS/Linux only):**
   ```bash
   nimble makeml
   ```
   
   **Note:** ML features are not supported on Windows due to LTO build issues.

5. **Build honeyclip:**
   ```bash
   nimble make
   ```

6. **Install Git hooks (recommended):**
   ```bash
   ./scripts/install-hooks.sh
   ```
   
   This installs pre-commit hooks that validate code quality before committing. See [scripts/git-hooks/README.md](scripts/git-hooks/README.md) for details.

7. **Verify installation:**
   ```bash
   ./honeyclip --help
   nimble test
   ```

**Troubleshooting:** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common build issues.

---

## Development Workflow

### Branch Strategy

- `master` - Stable, production-ready code
- `feature/your-feature-name` - New features
- `fix/issue-description` - Bug fixes
- `docs/topic` - Documentation updates

### Development Cycle

```bash
# 1. Create feature branch
git checkout -b feature/your-feature-name

# 2. Make changes
# ... edit code ...

# 3. Run tests
nimble test
python3 tests/test.py

# 4. Run benchmarks (check for regressions)
nimble bench

# 5. Commit with descriptive message
git add -A
git commit -m "Add feature: description

- Bullet point of changes
- Another change
- Fixes #123"
# Note: Pre-commit hook runs automatically (if installed)

# 6. Push and create PR
git push origin feature/your-feature-name
```

**Pre-commit hooks:** If installed, the hook automatically runs before each commit to validate:
- File size limits (no large binaries)
- Secrets detection (no API keys)
- Nim syntax check
- Unit tests
- Platform guard validation

Skip the hook if needed: `git commit --no-verify` (use sparingly!)

### Commit Message Format

```
Brief summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.

- Bullet points for multiple changes
- Reference issues: Fixes #123, Closes #456
- Cross-platform notes if relevant
```

**Good examples:**
```
Add motion detection benchmark

- Implements motion analysis timing
- Tests with 1080p test video
- Validates performance threshold (50ms target)
```

```
Fix Windows cross-compilation for ML stubs

- Add when defined(windows) guards
- Provide graceful error messages
- Update .github/copilot-instructions.md

Fixes #234
```

---

## Making Changes

### Before You Start

1. **Check existing issues** - Someone may already be working on it
2. **Open an issue** for large changes to discuss approach first
3. **Keep changes focused** - One feature/fix per PR

### Code Guidelines

#### Cross-Platform First (CRITICAL)

**Every change must work on Windows, macOS, and Linux or gracefully degrade.**

```nim
# ✅ GOOD: Platform-specific with fallback
when not defined(windows):
  import std/posix_utils
  proc getMemoryUsage(): float = ...
else:
  proc getMemoryUsage(): float = 
    warning "Memory tracking not available on Windows"
    return 0.0

# ❌ BAD: Assumes Unix
import std/posix_utils  # Breaks on Windows!
```

**Always:**
- Use `when defined(windows)` / `when not defined(windows)` for platform-specific code
- Test cross-compilation: `nimble windows` (requires mingw-w64)
- Provide clear error messages for unsupported features
- Document platform limitations in code comments

#### Performance & Quality Balance

**Speed optimizations must never degrade quality without explicit user choice.**

```nim
# ✅ GOOD: Expose tradeoff to user
if args.preset == "fast":
  useX264Preset("ultrafast")  # Document: faster but larger files
elif args.preset == "best":
  useX264Preset("veryslow")   # Document: slower but optimal compression

# ❌ BAD: Hidden quality degradation
# Always use ultrafast to be fast (user has no control!)
```

**Always:**
- Document performance impact in PERFORMANCE.md
- Add benchmark for performance-critical changes
- Validate quality doesn't regress (use hash checks, PSNR)
- Prefer native FFmpeg operations over frame-by-frame Nim processing

#### Local-First Architecture

**Prefer local computation over remote services.**

```nim
# ✅ GOOD: Local processing
let result = analyzeVideoLocally(inputFile)

# ❌ BAD: Cloud dependency without good reason
let result = await apiCall("https://cloud-service.com/analyze", inputFile)
```

**Always:**
- Build dependencies from source (FFmpeg, ML libs)
- Bundle models locally when possible
- Avoid external API calls unless absolutely necessary
- Use local Python virtual environments (`.venv/`)

### Naming Conventions

- **Files:** `snake_case.nim` (e.g., `audio.nim`, `timeline.nim`)
- **Functions:** `camelCase` (e.g., `parseColor()`, `initMediaInfo()`)
  - Pure functions: `func` keyword
  - Side effects: `proc` keyword
  - Mutations: `mut` prefix (e.g., `mutMargin()`)
- **Types:** `PascalCase` (e.g., `VideoStream`, `MediaInfo`)
- **Enum values:** lowercase (e.g., `actCut`, `actSpeed`)
- **Variables:** `camelCase` for locals, `snake_case` for FFmpeg interop

### Error Handling

```nim
# Fatal errors (cleanup and exit)
if container == nil:
  error "Could not open input file"

# Warnings (continue execution)
if format == "unknown":
  warning "Unknown format, attempting to process anyway"

# Debug (when --debug flag)
debug &"Processing frame {frameNum}"
```

**Never:**
- Use custom exceptions (use Nim built-ins)
- Silent failures (always log errors/warnings)
- Crash without cleanup (temp files, FFmpeg resources)

### Memory Management

FFmpeg resources require explicit cleanup:

```nim
# ✅ GOOD: Cleanup
let packet = av_packet_alloc()
defer: av_packet_free(addr packet)

let container = av.open(filename)
defer: avformat_close_input(addr container.formatContext)

# Process...

# ❌ BAD: Leak
let packet = av_packet_alloc()
# ... no cleanup, memory leak!
```

### Documentation

- **Public APIs:** Add doc comments (`##`)
- **Complex logic:** Explain why, not what
- **Platform-specific:** Note Windows/macOS/Linux differences
- **Performance:** Document time/memory characteristics

```nim
proc analyzeEngagement*(video: VideoStream, threshold: float32): seq[Segment] =
  ## Analyze video engagement using multi-modal scoring.
  ##
  ## Combines audio levels, motion detection, and speech patterns to identify
  ## engaging segments above the threshold.
  ##
  ## Performance: ~10-30 seconds per 30-minute video on modern CPU.
  ## Platform: Face detection not available on Windows (requires ML libraries).
  ##
  ## Args:
  ##   video: Input video stream
  ##   threshold: Engagement score cutoff (0-100)
  ##
  ## Returns:
  ##   Sequence of engaging segments with timestamps
```

---

## Testing

### Running Tests

```bash
# Unit tests (Nim)
nimble test

# End-to-end tests (Python)
python3 tests/test.py

# Coverage (Linux only)
nimble coverage

# Benchmarks (performance regression detection)
nimble bench
```

### Writing Tests

**Unit tests** go in `tests/unit.nim`:

```nim
suite "Your feature tests":
  test "Should do expected thing":
    let result = yourFunction(input)
    check result == expected
```

**E2E tests** go in `tests/test.py`:

```python
def test_your_feature():
    """Test feature end-to-end via CLI"""
    result = subprocess.run([
        "./honeyclip", "input.mp4",
        "--your-flag", "value"
    ], capture_output=True)
    assert result.returncode == 0
    assert os.path.exists("output.mp4")
```

### Benchmarks

Add benchmarks for performance-critical code:

```nim
# In tests/benchmark.nim
proc benchYourFeature(): BenchmarkResult =
  result = runBenchmark("your_feature") do():
    # Your code here
    let output = processVideo(input)
    
  # Validate quality
  if fileExists("output.mp4"):
    result.outputHash = hashFile("output.mp4")
```

Then add call in `main()` and update `BENCHMARKS.md`.

### Test Requirements

**Before submitting PR:**
- ✅ All existing tests pass
- ✅ New tests added for new features
- ✅ Benchmarks show no regression (or justified)
- ✅ Cross-platform compatibility verified

---

## Pull Request Process

### 1. Pre-Submission Checklist

- [ ] Code follows [Development Standards](#development-standards)
- [ ] All tests pass (`nimble test` and `python3 tests/test.py`)
- [ ] Benchmarks run without regression (`nimble bench`)
- [ ] Cross-platform compatibility checked (`nimble windows` compiles)
- [ ] Documentation updated (README, PERFORMANCE.md, code comments)
- [ ] Commit messages are descriptive
- [ ] Changes are focused (one feature/fix per PR)

### 2. Create Pull Request

1. Push your branch to your fork
2. Go to https://github.com/hiveforge-sh/honeyclip
3. Click "New Pull Request"
4. Select your branch
5. Fill out the PR template:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Performance improvement
- [ ] Documentation update
- [ ] Breaking change

## Testing Done
- Tested on: macOS/Linux/Windows
- Unit tests: pass/fail
- E2E tests: pass/fail
- Benchmarks: no regression / X% faster/slower (reason)

## Cross-Platform Notes
Any platform-specific behavior or limitations

## Related Issues
Fixes #123
```

### 3. Review Process

- Maintainers will review within 3-5 business days
- CI must pass (tests, benchmarks, cross-compile)
- Address feedback in new commits (don't force-push)
- Once approved, maintainers will merge

### 4. After Merge

- Delete your feature branch
- Pull latest master: `git pull upstream master`
- Your contribution will be in the next release! 🎉

---

## Development Standards

### Performance Philosophy

From `.github/copilot-instructions.md`:

> **Speed is a feature, but quality is non-negotiable.** Users need control over both.

Every performance optimization must:
1. **Preserve quality** by default (or require explicit `--preset fast`)
2. **Be measurable** (add benchmark, document impact)
3. **Degrade gracefully** across platforms

### Quality Validation

For changes affecting output:

```bash
# 1. Generate reference output (before your changes)
git checkout master
nimble make
./honeyclip test.mp4 -o reference.mp4

# 2. Test your changes
git checkout your-branch
nimble make
./honeyclip test.mp4 -o output.mp4

# 3. Validate quality
ffmpeg-quality-metrics reference.mp4 output.mp4 -m psnr ssim

# Expected: PSNR >40 dB, SSIM >0.99 (lossless operations)
```

### Code Style

- **Indentation:** 2 spaces (no tabs)
- **Line length:** 100 characters (120 max)
- **Imports:** Group by stdlib, third-party, local
- **Comments:** Explain *why*, not *what*

**Format before committing:**
```bash
# Nim has no official formatter yet
# Follow existing code style in the file
```

---

## Platform Support

### Windows Compatibility

**CRITICAL:** Windows is a **first-class platform**.

When adding features:
- ✅ Test cross-compilation: `nimble windows`
- ✅ Provide graceful fallback for ML features
- ✅ Use `when defined(windows)` for platform code
- ✅ Test in Git Bash (FFmpeg build requires it)

**Known limitations:**
- LTO disabled (GCC 11.1.0 ICE)
- No ML features (face detection, ONNX)
- Must use Git Bash for `nimble makeff`

### Cross-Platform Testing

**Before submitting:**

```bash
# 1. Test on your platform
nimble test

# 2. Cross-compile for Windows (Linux/macOS)
nimble makeffwin  # If FFmpeg changes
nimble windows

# 3. Verify compilation succeeds
ls honeyclip.exe
```

**Ideal (if you have access):**
- Test on actual Windows machine
- Test on macOS (Intel and Apple Silicon)
- Test on Linux (x86_64 and ARM64)

---

## Troubleshooting

### FFmpeg Build Fails

**Error:** `configure: error: nasm not found`
```bash
# macOS
brew install nasm

# Linux (Ubuntu/Debian)
sudo apt install nasm

# Windows (in Git Bash)
# Download from https://www.nasm.us/
```

**Error:** `Project requires meson`
```bash
pip3 install meson ninja
```

### Nim Compilation Fails

**Error:** `undeclared identifier: 'X'`
- Check imports (may need platform-specific `when` guard)
- Verify FFmpeg/ML libraries built (`nimble makeff`, `nimble makeml`)

**Error:** `Cannot open: build/lib/libX.a`
- Clean and rebuild: `nimble cleanff && nimble makeff`
- On Windows: Ensure Git Bash was used for `nimble makeff`

### Tests Fail

**Python tests fail:**
```bash
# Install dependencies
pip3 install av pytest

# Run with verbose output
python3 tests/test.py -v
```

**Benchmark fails (hash mismatch):**
- Expected on first run (establishes baseline)
- After changes: Your output differs from baseline
  - Intended: Update baseline (commit `benchmark_results.json`)
  - Bug: Fix the quality regression

### Windows-Specific Issues

**`nimble makeff` fails in PowerShell:**
- **Solution:** Use Git Bash instead (provides Unix tools)

**ML features crash:**
- **Solution:** ML not supported on Windows (expected behavior)
- **Verify:** Error message should say "not available on Windows"

---

## Getting Help

### Resources

- **Documentation:**
  - [README.md](README.md) - Project overview
  - [PERFORMANCE.md](PERFORMANCE.md) - Speed/quality guide
  - [tests/BENCHMARKS.md](tests/BENCHMARKS.md) - Benchmark system
  - [.github/copilot-instructions.md](.github/copilot-instructions.md) - Development guide

- **Code:**
  - [src/main.nim](src/main.nim) - Entry point
  - [src/cli.nim](src/cli.nim) - Command-line interface
  - [Architecture overview](.github/copilot-instructions.md#high-level-architecture)

### Ask Questions

1. **Check existing issues:** https://github.com/hiveforge-sh/honeyclip/issues
2. **Open new issue:** Use "Question" label
3. **Discussion:** Start a discussion for open-ended topics

### Reporting Bugs

Include in bug reports:
- Platform (macOS/Linux/Windows)
- Nim version (`nim --version`)
- Steps to reproduce
- Expected vs actual behavior
- Error messages (full output with `--debug`)

```bash
# Get debug output
./honeyclip input.mp4 --debug > debug.log 2>&1
```

---

## Development Tips

### Fast Iteration

```bash
# Quick compile (debug build, no LTO)
nim c src/main.nim

# Run immediately
./main input.mp4

# Or combined
nim c -r src/main.nim input.mp4
```

### IDE Setup

**VS Code:**
- Install "Nim" extension
- Install "nimsuggest" for autocomplete: `nimble install nimsuggest`

**Vim/Neovim:**
- Use nimlsp or nimsuggest integration

### Debugging

```nim
# Print debugging
debug "Value: " & $myVar

# Compile with stack traces
nim c --stackTrace:on --lineTrace:on src/main.nim

# Run with debugger (gdb/lldb)
gdb ./honeyclip
(gdb) run input.mp4
```

### Working with FFmpeg

```nim
# Always check return values
let ret = av_read_frame(container, packet)
if ret < 0:
  error &"Failed to read frame: {av_err2str(ret)}"

# Always cleanup
defer: av_packet_unref(packet)
defer: avformat_close_input(addr container)

# Check for nil after allocation
let packet = av_packet_alloc()
if packet == nil:
  error "Could not allocate packet"
```

---

## Project Structure

```
honeyclip/
├── .github/
│   ├── copilot-instructions.md   # AI assistant development guide
│   └── workflows/                # CI/CD pipelines
├── src/
│   ├── main.nim                  # Entry point
│   ├── cli.nim                   # Command-line parsing
│   ├── av.nim                    # FFmpeg bindings
│   ├── analyze/                  # Analysis modules (audio, motion, faces)
│   ├── cmds/                     # Subcommand implementations
│   ├── exports/                  # NLE format generators
│   ├── ml/                       # ML features (face detection, ONNX)
│   ├── palet/                    # Expression parser (--edit flag)
│   ├── render/                   # Audio/video/subtitle processing
│   └── util/                     # Utilities (colors, progress bars)
├── tests/
│   ├── unit.nim                  # Nim unit tests
│   ├── test.py                   # Python E2E tests
│   ├── benchmark.nim             # Performance benchmarks
│   └── resources/                # Test media files
├── resources/                    # Sample videos for testing
├── PERFORMANCE.md                # Speed/quality documentation
├── CONTRIBUTING.md               # This file
└── honeyclip.nimble              # Build configuration
```

---

## Release Process

(For maintainers)

1. Update version in `honeyclip.nimble`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.2.0`
4. Push tag: `git push origin v1.2.0`
5. CI builds binaries and creates GitHub Release
6. Announce in discussions

---

## License

By contributing, you agree that your contributions will be licensed under the [Unlicense](LICENSE) (Public Domain).

---

**Thank you for contributing to honeyclip!** 🎬✨
