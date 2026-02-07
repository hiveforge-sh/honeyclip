# Troubleshooting Guide

This guide helps you diagnose and fix common issues when building, testing, or using honeyclip.

## Table of Contents

- [Build Issues](#build-issues)
  - [FFmpeg Build Failures](#ffmpeg-build-failures)
  - [ML Library Build Failures](#ml-library-build-failures)
  - [Nim Compilation Errors](#nim-compilation-errors)
  - [Cross-Compilation Issues](#cross-compilation-issues)
- [Runtime Issues](#runtime-issues)
  - [Missing Codec Errors](#missing-codec-errors)
  - [Memory Issues](#memory-issues)
  - [File Format Errors](#file-format-errors)
  - [Performance Problems](#performance-problems)
- [Platform-Specific Issues](#platform-specific-issues)
  - [Windows](#windows)
  - [macOS](#macos)
  - [Linux](#linux)
- [CI/CD Issues](#cicd-issues)
- [Development Issues](#development-issues)
  - [Test Failures](#test-failures)
  - [Benchmark Failures](#benchmark-failures)
- [Getting Help](#getting-help)

---

## Build Issues

### FFmpeg Build Failures

#### Problem: `nimble makeff` fails with "command not found"

**Symptoms:**
```
sh: nasm: command not found
```

**Solution:**

Install missing build tools:

**macOS:**
```bash
brew install nasm cmake pkg-config
```

**Ubuntu/Debian:**
```bash
sudo apt-get install nasm cmake pkg-config build-essential
```

**Fedora:**
```bash
sudo dnf install nasm cmake pkgconfig gcc gcc-c++ make
```

**Arch:**
```bash
sudo pacman -S nasm cmake pkgconf base-devel
```

**Windows:**
Run the bootstrap script from **Git Bash** (not PowerShell/CMD):
```bash
./bootstrap.sh
```

---

#### Problem: FFmpeg configure fails with "C compiler test failed"

**Symptoms:**
```
ERROR: C compiler test failed.
```

**Cause:** Wrong GCC version or missing compiler.

**Solution:**

1. **Verify GCC is installed:**
```bash
gcc --version
```

2. **macOS:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

3. **Windows:** Ensure Git Bash is using the correct MinGW:
```bash
# Check GCC path
which gcc
# Should be: /mingw64/bin/gcc or ~/.choosenim/toolchains/mingw64/bin/gcc

# If wrong, add to PATH in ~/.bashrc:
export PATH="$HOME/.choosenim/toolchains/mingw64/bin:$PATH"
```

---

#### Problem: "ar: command not found" during FFmpeg build on Windows

**Symptoms:**
```
ar: command not found
make: *** [libavcodec/ac3_parser.o] Error 127
```

**Cause:** Windows ar.exe has path issues with MSYS paths.

**Solution:**

The repository includes `ar-wrapper.sh` which is automatically used. If you still see this error:

1. **Check the wrapper exists:**
```bash
ls -la ar-wrapper.sh
```

2. **Make it executable:**
```bash
chmod +x ar-wrapper.sh
```

3. **Rebuild:**
```bash
nimble cleanff
nimble makeff
```

---

#### Problem: FFmpeg build takes forever (>2 hours)

**Symptoms:**
FFmpeg compilation stuck at "Building... [no progress]"

**Solution:**

1. **Check available disk space:**
```bash
df -h .
# Need at least 5GB free
```

2. **Disable heavy codecs** (faster build, smaller binary):
```bash
# Disable VP8/VP9
export DISABLE_VPX=1

# Disable SVT-AV1
export DISABLE_SVTAV1=1

# Disable HEVC
export DISABLE_HEVC=1

# Now rebuild
nimble cleanff
nimble makeff
```

3. **Use parallel compilation** (if not already):
```bash
# Edit build-ffmpeg.sh, change:
make -j$(nproc)  # Use all CPU cores
```

---

#### Problem: "undefined reference to `x264_encoder_open`" during linking

**Symptoms:**
```
undefined reference to `x264_encoder_open'
collect2: error: ld returned 1 exit status
```

**Cause:** x264 library not found or built incorrectly.

**Solution:**

1. **Check x264 library exists:**
```bash
ls -la build/lib/libx264.a
```

2. **If missing, rebuild x264:**
```bash
# Clean build directory
rm -rf build/lib/libx264.a build/include/x264.h

# Rebuild FFmpeg (will rebuild x264 too)
nimble cleanff
nimble makeff
```

3. **Check PKG_CONFIG_PATH:**
```bash
# Should include your build/lib/pkgconfig
echo $PKG_CONFIG_PATH
# If not set:
export PKG_CONFIG_PATH="$(pwd)/build/lib/pkgconfig"
```

---

### ML Library Build Failures

#### Problem: `nimble makeml` fails on macOS with "No CMAKE_CXX_COMPILER found"

**Symptoms:**
```
CMake Error: CMAKE_CXX_COMPILER not set
```

**Solution:**

Install Xcode Command Line Tools:
```bash
xcode-select --install

# Verify installation
clang++ --version
```

---

#### Problem: ONNX Runtime build fails with "Could not find a package configuration file"

**Symptoms:**
```
CMake Error at CMakeLists.txt:XX (find_package):
  Could not find a package configuration file provided by "Python3"
```

**Solution:**

Install Python development headers:

**macOS:**
```bash
brew install python3
```

**Ubuntu/Debian:**
```bash
sudo apt-get install python3-dev
```

**Fedora:**
```bash
sudo dnf install python3-devel
```

---

#### Problem: ML libraries not found during compilation (Windows)

**Symptoms:**
```
Error: cannot open file 'build/lib/libfacedetection.a'
```

**Cause:** ML features are not supported on Windows.

**Solution:**

ML features are disabled on Windows due to LTO compilation issues. The code automatically stubs out ML functions:

```bash
# This is expected on Windows:
nimble make
# ML features (engage, reframe) will work but without face detection
```

To verify ML is properly disabled:
```bash
# Should NOT see -d:enable_ml flag
nimble make --verbose
```

---

### Nim Compilation Errors

#### Problem: "Error: undeclared identifier: 'openInput'"

**Symptoms:**
```nim
Error: undeclared identifier: 'openInput'
candidates (edit distance, scope distance); see '--spellSuggest':
 (5, 7): 'getInt'
```

**Cause:** Function name collision between `av.open` and `std/syncio.open`.

**Solution:**

Use module prefix:
```nim
# WRONG:
import av
let input = open("video.mp4")  # Ambiguous!

# CORRECT:
import av
let input = av.open("video.mp4")  # Explicit module
```

---

#### Problem: "Error: expression 'x' has no type (or is ambiguous)"

**Symptoms:**
```nim
Error: expression 'formatContext.nb_streams' has no type (or is ambiguous)
```

**Cause:** Missing FFmpeg type definitions or incorrect FFmpeg version.

**Solution:**

1. **Verify FFmpeg was built:**
```bash
ls -la build/lib/libavformat.a
ls -la build/include/libavformat/avformat.h
```

2. **Check nim.cfg includes FFmpeg paths:**
```bash
cat nim.cfg | grep passC
# Should see: --passC:"-Ibuild/include"
```

3. **Clean and rebuild:**
```bash
nimble clean
nimble make
```

---

#### Problem: "internal error: environment misses" during LTO on Windows

**Symptoms:**
```
internal error: environment misses: gcc: internal compiler error
```

**Cause:** GCC 11.1.0 (bundled with choosenim) has an internal compiler error with LTO.

**Solution:**

LTO is **automatically disabled on Windows** in nim.cfg. If you're seeing this error:

1. **Check nim.cfg:**
```bash
cat nim.cfg | grep lto
# Should see:
# when not defined(windows):
#   --passc:"-flto"
#   --passl:"-flto"
```

2. **Force disable LTO:**
```bash
# Add to nim.cfg:
--passc:"-fno-lto"
--passl:"-fno-lto"
```

3. **Rebuild:**
```bash
nimble clean
nimble make
```

---

### Cross-Compilation Issues

#### Problem: Windows cross-compilation fails with "mingw not found"

**Symptoms:**
```
Error: execution of an external program failed: 'x86_64-w64-mingw32-gcc'
```

**Solution:**

Install MinGW cross-compiler:

**macOS:**
```bash
brew install mingw-w64
```

**Ubuntu/Debian:**
```bash
sudo apt-get install mingw-w64
```

**Fedora:**
```bash
sudo dnf install mingw64-gcc mingw64-gcc-c++
```

---

#### Problem: Cross-compiled Windows binary crashes immediately

**Symptoms:**
Binary runs fine on Linux/macOS but crashes on Windows with "DLL not found"

**Cause:** Missing runtime DLLs (should not happen with static linking).

**Solution:**

1. **Verify static linking:**
```bash
# On Linux, check dependencies:
file honeyclip.exe
# Should say: "PE32+ executable ... statically linked"
```

2. **Test in Windows VM/machine:**
Cross-compiled binaries must be tested on real Windows. Wine is not reliable.

---

## Runtime Issues

### Missing Codec Errors

#### Problem: "Codec not found: hevc"

**Symptoms:**
```
Error: Codec not found: hevc
```

**Cause:** HEVC codec was disabled during FFmpeg build.

**Solution:**

1. **Check enabled codecs:**
```bash
# See what's available:
honeyclip info video.mp4
# Lists available codecs in build
```

2. **Rebuild with HEVC:**
```bash
# Remove disable flag
unset DISABLE_HEVC

# Rebuild FFmpeg
nimble cleanff
nimble makeff

# Rebuild honeyclip
nimble make
```

---

#### Problem: "Decoder not found" for input file

**Symptoms:**
```
Error: Decoder not found for codec 'vp9'
```

**Cause:** Input file uses a codec not compiled into FFmpeg.

**Solution:**

1. **Check input codec:**
```bash
ffprobe input.mp4 2>&1 | grep "Video:"
# Shows codec used (h264, vp9, etc.)
```

2. **Re-encode with supported codec:**
```bash
ffmpeg -i input.mp4 -c:v libx264 -c:a aac output.mp4
honeyclip output.mp4
```

3. **Or rebuild FFmpeg with needed codec:**
```bash
# Enable VP9
unset DISABLE_VPX
nimble cleanff
nimble makeff
nimble make
```

---

### Memory Issues

#### Problem: "Out of memory" or crash with large videos

**Symptoms:**
```
terminate called after throwing an instance of 'std::bad_alloc'
Segmentation fault (core dumped)
```

**Cause:** Processing 4K/8K video exhausts RAM.

**Solution:**

1. **Check available memory:**
```bash
# macOS:
vm_stat | head

# Linux:
free -h
```

2. **Reduce resolution temporarily:**
```bash
# Pre-process to 1080p
ffmpeg -i input.mp4 -vf scale=1920:1080 temp.mp4
honeyclip temp.mp4
```

3. **Process in chunks** (manual workaround):
```bash
# Split video into 10-minute segments
ffmpeg -i input.mp4 -c copy -f segment -segment_time 600 chunk%03d.mp4

# Process each chunk
honeyclip chunk000.mp4
honeyclip chunk001.mp4
# ...

# Concatenate (use concat demuxer)
```

4. **Close other applications** to free RAM.

---

#### Problem: High memory usage during whisper transcription

**Symptoms:**
RAM usage spikes to 8GB+ during `honeyclip transcript`

**Cause:** Larger Whisper models (medium, large) require significant RAM.

**Solution:**

Use smaller model:
```bash
# Download tiny model (75MB, ~1GB RAM usage)
curl -L -o ~/.cache/whisper/ggml-tiny.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin

# Use it
honeyclip transcript input.mp4 tiny
```

Model memory usage:
- **tiny**: ~1GB RAM
- **base**: ~1.5GB RAM
- **small**: ~2.5GB RAM
- **medium**: ~5GB RAM
- **large**: ~10GB RAM

---

### File Format Errors

#### Problem: "Could not open input file"

**Symptoms:**
```
Error: Could not open input file: video.mp4
IOError: Could not open input file: video.mp4
```

**Cause:** File doesn't exist, wrong path, or permission issue.

**Solution:**

1. **Check file exists:**
```bash
ls -la video.mp4
```

2. **Check permissions:**
```bash
chmod 644 video.mp4
```

3. **Try absolute path:**
```bash
honeyclip /full/path/to/video.mp4
```

4. **Test with ffprobe:**
```bash
ffprobe video.mp4
# If this fails, file is corrupt or unsupported format
```

---

#### Problem: "moov atom not found" (MP4 corruption)

**Symptoms:**
```
Error: moov atom not found
```

**Cause:** MP4 file is incomplete or corrupted (often from interrupted recording).

**Solution:**

Attempt to repair:
```bash
# Try to recover with ffmpeg
ffmpeg -i broken.mp4 -c copy fixed.mp4

# If that fails, extract raw stream
ffmpeg -i broken.mp4 -c:v copy -c:a copy -f mpegts temp.ts
ffmpeg -i temp.ts -c copy fixed.mp4
```

---

### Performance Problems

#### Problem: Processing is extremely slow (<0.1x realtime)

**Symptoms:**
30-minute video takes >5 hours to process

**Possible Causes & Solutions:**

1. **Using slow codec preset:**
```bash
# Check current settings
honeyclip info output.mp4 | grep "encoder"

# Use faster preset (add to nim.cfg or modify code):
# Default is "medium", switch to "fast" or "ultrafast" for speed
```

2. **Slow disk (especially external drives):**
```bash
# Test disk speed:
dd if=/dev/zero of=testfile bs=1M count=1024
# Should be >100MB/s for acceptable performance

# Solution: Process on internal SSD
```

3. **CPU throttling (overheating):**
```bash
# macOS: Check CPU usage
top -l 1 | grep "CPU usage"

# Linux: Check temperatures
sensors | grep Core

# Solution: Clean vents, improve cooling
```

4. **Wrong video codec for input:**
```bash
# Check input codec
ffprobe input.mp4 2>&1 | grep "Video:"

# Some codecs (e.g., ProRes, DNxHD) decode slower
# Re-encode to H.264 for faster processing:
ffmpeg -i input.mov -c:v libx264 -preset fast -crf 20 temp.mp4
honeyclip temp.mp4
```

---

#### Problem: High CPU usage with low progress

**Symptoms:**
CPU at 100% but processing stuck at same frame

**Cause:** Likely stuck in infinite loop or deadlock.

**Solution:**

1. **Enable debug output:**
```bash
# Set environment variable for verbose logging
export DEBUG=1
honeyclip input.mp4

# Or use --verbose flag if available
```

2. **Try minimal processing:**
```bash
# Simplest possible edit (info only, no processing)
honeyclip info input.mp4

# If that works, try basic edit:
honeyclip input.mp4 --edit audio:0.1
```

3. **Check for infinite loops in analysis:**
```bash
# Enable logging in src/log.nim (set isDebug = true)
# Rebuild and run to see where it's stuck
```

4. **Report bug** with sample file and command (see [Getting Help](#getting-help)).

---

## Platform-Specific Issues

### Windows

#### Problem: "bash: command not found" when running `nimble makeff`

**Symptoms:**
```
bash: nimble: command not found
```

**Cause:** Running from PowerShell or CMD instead of Git Bash.

**Solution:**

1. **Install Git for Windows** (includes Git Bash):
   Download from https://git-scm.com/download/win

2. **Run from Git Bash:**
   - Launch "Git Bash" from Start Menu
   - Navigate to project: `cd /c/path/to/honeyclip`
   - Run commands: `nimble makeff`

---

#### Problem: Path separator issues (backslash vs forward slash)

**Symptoms:**
```
Error: File not found: C:\path\to\file.mp4
```

**Cause:** Windows uses `\` but Nim/FFmpeg expect `/` or `\\`.

**Solution:**

Use forward slashes or double backslashes:
```bash
# CORRECT:
honeyclip C:/path/to/file.mp4
honeyclip "C:\\path\\to\\file.mp4"

# WRONG:
honeyclip C:\path\to\file.mp4  # Interpreted as escape sequences!
```

Or use MSYS paths in Git Bash:
```bash
honeyclip /c/path/to/file.mp4
```

---

#### Problem: ML features not working (engage, reframe)

**Symptoms:**
```
Warning: Face detection not available on Windows
```

**Cause:** This is **expected behavior** on Windows.

**Solution:**

ML features are disabled on Windows due to LTO compilation issues with the ML libraries. You can still use:
- ✅ Audio-based editing (`--edit audio`)
- ✅ Motion-based editing (`--edit motion`)
- ✅ Subtitle-based editing (`--edit subtitle`)
- ✅ Transcription (`honeyclip transcript`)
- ❌ Face detection (engage, reframe)

For face detection, use Linux or macOS (or WSL2).

**Note:** Native Windows builds are now tested in CI to ensure ML stubs gracefully degrade without crashing.

---

### macOS

#### Problem: "xcrun: error: invalid active developer path"

**Symptoms:**
```
xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)
```

**Cause:** Xcode Command Line Tools not installed or outdated.

**Solution:**

1. **Install/update:**
```bash
xcode-select --install
```

2. **If already installed, reset:**
```bash
sudo xcode-select --reset
```

3. **Verify:**
```bash
clang --version
# Should show Apple clang version
```

---

#### Problem: Library not loaded: libfacedetection.dylib

**Symptoms:**
```
dyld: Library not loaded: @rpath/libfacedetection.dylib
```

**Cause:** Dynamic linking attempted (should be static).

**Solution:**

1. **Check if library is static:**
```bash
file build/lib/libfacedetection.a
# Should say "ar archive"
```

2. **Verify nim.cfg forces static:**
```bash
cat nim.cfg | grep static
# Should see: --passL:"-static-libgcc"
```

3. **Rebuild with static linking:**
```bash
nimble clean
nimble makeml
nimble make
```

---

#### Problem: Code signing issues on macOS 13+

**Symptoms:**
```
"honeyclip" cannot be opened because the developer cannot be verified.
```

**Solution:**

1. **Allow running unsigned binaries:**
```bash
# Right-click binary, select "Open", click "Open" in dialog
# Or use command line:
xattr -d com.apple.quarantine honeyclip
```

2. **Sign the binary (for distribution):**
```bash
codesign -s - honeyclip
```

---

### Linux

#### Problem: "error while loading shared libraries: libgomp.so.1"

**Symptoms:**
```
error while loading shared libraries: libgomp.so.1: cannot open shared object file
```

**Cause:** Missing OpenMP library (required by x265).

**Solution:**

**Ubuntu/Debian:**
```bash
sudo apt-get install libgomp1
```

**Fedora:**
```bash
sudo dnf install libgomp
```

**Arch:**
```bash
sudo pacman -S gcc-libs
```

---

#### Problem: "Permission denied" when writing output

**Symptoms:**
```
Error: Permission denied: /path/to/output.mp4
```

**Solution:**

1. **Check write permissions:**
```bash
ls -la output.mp4
# If file exists and is read-only:
chmod 644 output.mp4
```

2. **Check directory permissions:**
```bash
ls -lad .
# If directory is not writable:
chmod 755 .
```

3. **Use different output path:**
```bash
honeyclip input.mp4 -o ~/Videos/output.mp4
```

---

#### Problem: Font rendering issues in captions

**Symptoms:**
Captions display with missing characters or wrong font

**Cause:** Missing font files or fontconfig cache.

**Solution:**

1. **Install common fonts:**
```bash
# Ubuntu/Debian:
sudo apt-get install fonts-liberation fonts-dejavu

# Fedora:
sudo dnf install liberation-fonts dejavu-fonts

# Arch:
sudo pacman -S ttf-liberation ttf-dejavu
```

2. **Rebuild font cache:**
```bash
fc-cache -fv
```

3. **Specify font explicitly:**
```bash
honeyclip caption input.mp4 --font "DejaVu Sans"
```

---

## CI/CD Issues

### Problem: Smoke tests fail with "binary size exceeds limit"

**Symptoms:**
```
Error: Binary size 105MB exceeds limit of 100MB
```

**Cause:** Binary grew due to added features or debug symbols.

**Solution:**

1. **Check what changed:**
```bash
# Compare with previous build
git diff HEAD~1 src/

# Check for accidental debug flags
cat nim.cfg | grep debug
```

2. **Strip debug symbols:**
```bash
strip honeyclip
ls -lh honeyclip
```

3. **Disable heavy codecs in smoke tests** (already done):
```bash
# Verify smoke.yml has:
export DISABLE_VPX=1
export DISABLE_SVTAV1=1
export DISABLE_HEVC=1
```

4. **Update size limit** if growth is justified:
Edit `.github/workflows/smoke.yml`, increase limit in size check step.

---

### Problem: Benchmark regression detected in CI

**Symptoms:**
```
Error: Performance regression detected!
audio_analysis: 5ms (baseline: 2ms) - 150% slower
```

**Cause:** Code change introduced performance degradation.

**Solution:**

1. **Identify the change:**
```bash
# Check recent commits
git log --oneline -5

# Bisect to find culprit
git bisect start
git bisect bad HEAD
git bisect good <last-known-good-commit>
# Test each commit
```

2. **Profile the slow path:**
```bash
# Enable profiling
nim c --profiler:on --stackTrace:on -r tests/benchmark

# Check profile output
```

3. **Update baseline if intentional:**
If regression is expected (e.g., added quality check), update baseline:
```bash
# Run locally
nimble bench

# Commit new baseline
git add tests/benchmark_results.json
git commit -m "Update benchmark baseline after quality improvements"
```

---

### Problem: Windows cross-compile job fails

**Symptoms:**
```
Error: execution of an external program failed: 'x86_64-w64-mingw32-gcc'
```

**Cause:** MinGW not installed on CI runner.

**Solution:**

1. **Check workflow installs MinGW:**
```yaml
# In .github/workflows/smoke.yml:
- name: Install packages
  run: brew install mingw-w64  # macOS/Linux with Homebrew
```

2. **Or add to matrix:**
```yaml
matrix:
  include:
    - os: ubuntu-24.04
      install: sudo apt-get install mingw-w64
```

---

### Problem: Cache miss on every build

**Symptoms:**
CI rebuilds FFmpeg/ML libraries from scratch every time (slow).

**Cause:** Cache key changed or cache evicted.

**Solution:**

1. **Check cache key:**
```yaml
# Should be based on stable files:
key: ml-build-${{ runner.os }}-${{ hashFiles('honeyclip.nimble') }}
```

2. **Add restore-keys for fallback:**
```yaml
restore-keys: |
  ml-build-${{ runner.os }}-
```

3. **Verify cache is being saved:**
Check CI logs for "Cache saved successfully" message.

---

## Development Issues

### Test Failures

#### Problem: Unit tests fail with "undeclared identifier"

**Symptoms:**
```nim
tests/unit.nim(45, 10) Error: undeclared identifier: 'openInput'
```

**Cause:** Same as [Nim Compilation Errors](#nim-compilation-errors) - name collision.

**Solution:**

Update test to use module prefix:
```nim
# tests/unit.nim
import av

test "Open video file":
  let input = av.open("resources/test.mp4")  # Explicit module
  check input.video.len > 0
```

---

#### Problem: E2E tests fail with "No module named 'av'"

**Symptoms:**
```
ModuleNotFoundError: No module named 'av'
```

**Cause:** PyAV not installed for Python tests.

**Solution:**

Install PyAV:
```bash
pip install av

# Or use virtual environment:
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install av
python tests/test.py
```

---

### Benchmark Failures

#### Problem: Benchmark fails with "File not found: resources/test.mp4"

**Symptoms:**
```
Error: File not found: resources/test.mp4
```

**Solution:**

Benchmarks use test media files. Ensure they exist:
```bash
ls -la resources/
# Should have: test.mp4, test_audio.mp3, etc.
```

If missing, create minimal test file:
```bash
# Generate 5-second test video
ffmpeg -f lavfi -i testsrc=duration=5:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=1000:duration=5 \
       -c:v libx264 -c:a aac resources/test.mp4
```

---

#### Problem: Memory benchmark always returns 0

**Symptoms:**
```
Memory usage: 0 MB (before: 0 MB, after: 0 MB)
```

**Cause:** `getCurrentMemoryMB()` not implemented for platform.

**Solution:**

This is a known limitation on macOS/Windows. Linux uses `/proc/self/statm` which works correctly.

To fix, implement platform-specific memory tracking:

**macOS:**
```nim
when defined(macosx):
  proc getCurrentMemoryMB(): float =
    # Use mach_task_info
    # See: https://stackoverflow.com/questions/63166/how-to-determine-cpu-and-memory-consumption-from-inside-a-process
```

**Windows:**
```nim
when defined(windows):
  proc getCurrentMemoryMB(): float =
    # Use GetProcessMemoryInfo
    # See: https://docs.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-getprocessmemoryinfo
```

---

## Getting Help

If you've tried the solutions above and still have issues:

### 1. Search existing issues

Check if someone already reported it:
- https://github.com/hiveforge-sh/honeyclip/issues

### 2. Gather debug information

Before reporting, collect:

**System info:**
```bash
# OS version
uname -a          # macOS/Linux
ver               # Windows

# Nim version
nim --version

# FFmpeg version (if built)
./build/bin/ffmpeg -version 2>/dev/null || echo "FFmpeg not built"

# GCC version
gcc --version

# Available memory
free -h           # Linux
vm_stat           # macOS
systeminfo        # Windows
```

**Build configuration:**
```bash
cat nim.cfg
cat honeyclip.nimble | grep "^var"
echo "DISABLE_VPX=$DISABLE_VPX"
echo "DISABLE_SVTAV1=$DISABLE_SVTAV1"
echo "DISABLE_HEVC=$DISABLE_HEVC"
```

**Reproduction steps:**
```bash
# Exact commands that fail
honeyclip input.mp4 --edit audio:0.03 -o output.mp4

# Full error output (not truncated)
honeyclip input.mp4 2>&1 | tee error.log
```

### 3. Create minimal reproduction

Try to isolate the issue:

```bash
# Does info work?
honeyclip info input.mp4

# Does simplest edit work?
honeyclip input.mp4 --edit audio

# Does it work with test file?
honeyclip resources/test.mp4

# Does re-encoding input help?
ffmpeg -i input.mp4 -c:v libx264 -c:a aac temp.mp4
honeyclip temp.mp4
```

### 4. Report the bug

Create an issue with:
- Clear title (e.g., "FFmpeg build fails on Ubuntu 24.04 with nasm not found")
- System information (from step 2)
- Reproduction steps (from step 3)
- Expected vs actual behavior
- Full error output (use code blocks)
- Sample file (if possible, upload small test case)

**Template:**
```markdown
## Description
Brief description of the problem.

## Environment
- OS: macOS 14.2 / Ubuntu 24.04 / Windows 11
- Nim version: 2.2.6
- GCC version: 13.2.0
- FFmpeg: built from source / not built yet

## Steps to Reproduce
1. Run `nimble makeff`
2. Error appears: [paste error]

## Expected Behavior
FFmpeg should build successfully.

## Actual Behavior
Build fails with "nasm: command not found"

## Additional Context
[Any other relevant information]
```

### 5. Community channels

- **GitHub Discussions:** https://github.com/hiveforge-sh/honeyclip/discussions
- **Nim Discord:** https://discord.gg/nim (for Nim-specific questions)

---

## Common Quick Fixes

**TL;DR** - Try these first:

```bash
# Clean everything and rebuild
nimble cleanff
nimble clean
rm -rf nimcache/
nimble makeff
nimble make

# Update Nim
choosenim update stable

# Update dependencies
nimble refresh
nimble install -d

# Check file permissions
chmod 755 honeyclip
chmod 644 *.mp4

# Use absolute paths
honeyclip "$(pwd)/input.mp4"

# Enable debug output
export DEBUG=1
honeyclip input.mp4

# Test with minimal file
ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 \
       -f lavfi -i sine=frequency=1000:duration=5 \
       -c:v libx264 -c:a aac test.mp4
honeyclip test.mp4
```

---

## Appendix: Debug Checklist

Before reporting an issue, verify:

- [ ] Using latest version (`git pull`)
- [ ] Dependencies installed (`./bootstrap.sh`)
- [ ] FFmpeg built successfully (`nimble makeff`)
- [ ] Nim compilation successful (`nimble make`)
- [ ] Test file works (`honeyclip resources/test.mp4`)
- [ ] Enough disk space (>5GB free)
- [ ] Enough memory (>4GB available)
- [ ] Using correct terminal (Git Bash on Windows)
- [ ] No spaces in file paths (or properly quoted)
- [ ] Input file is valid (`ffprobe input.mp4`)
- [ ] Output directory is writable (`touch output.mp4`)
- [ ] Tried clean rebuild (`nimble cleanff && nimble makeff`)

If all checkboxes pass and issue persists, it's likely a real bug - please report it!
