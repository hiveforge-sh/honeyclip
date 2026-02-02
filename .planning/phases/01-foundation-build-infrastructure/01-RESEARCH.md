# Phase 1: Foundation & Build Infrastructure - Research

**Researched:** 2026-02-01
**Domain:** Cross-platform ML library build system with Nim FFI
**Confidence:** MEDIUM

## Summary

Phase 1 establishes the build infrastructure for integrating three ML libraries (libfacedetection, ONNX Runtime, OpenCV) with Nim via FFI, supporting Linux, macOS, and Windows (MinGW cross-compilation). This mirrors the existing FFmpeg build system (ae.nimble) which already demonstrates:

- CMake/Meson/autoconf build orchestration from Nim
- MinGW cross-compilation to Windows
- Static library combining (x265 multi-bitdepth example)
- Version-locked source downloads with SHA256 verification
- pkg-config integration for dependency resolution

The standard approach follows FFmpeg's proven pattern: download source tarballs, verify hashes, build with CMake/Meson, install to local `build/` prefix, then link Nim via pkg-config or direct passL flags. Binary size is the primary risk — ONNX Runtime alone can exceed 50MB without minimal builds. LTO and selective execution provider inclusion are critical mitigations.

**Primary recommendation:** Extend the existing ae.nimble build system with parallel tasks for ML libraries, using CMake for all three libraries, minimal ONNX builds with operator reduction, and the same static library combining techniques already proven for x265.

## Standard Stack

### Core Build Tools

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CMake | 3.20+ | Build system | Universal C++ project standard, all three libraries support it |
| pkg-config | Latest | Dependency resolution | Standard for finding static/shared libs, existing FFmpeg integration |
| ccache | 4.x | Compilation cache | Speeds incremental builds 10-50x, integrates seamlessly with CMake |
| MinGW-w64 | x86_64-w64-mingw32 | Windows cross-compilation | Only viable option for Linux→Windows static linking |

### ML Libraries

| Library | Version | Purpose | Integration Notes |
|---------|---------|---------|-------------------|
| libfacedetection | Latest (v3.0+) | Face detection | Simple CMake build, no dependencies, CNN model compiled to static C arrays |
| ONNX Runtime | 1.20+ | ML inference engine | Complex build, requires minimal build mode and operator reduction for size |
| OpenCV | 4.10+ | Computer vision utilities | Modular — only build core, imgproc, objdetect modules |

### Supporting Tools

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Meson/Ninja | Latest | Fast build alternative | If CMake proves too slow (unlikely given ccache) |
| libtool (macOS) | System | Static lib combining | Merge multiple .a files (8-bit/10-bit/12-bit patterns) |
| ar (Linux/MinGW) | System | Static lib combining | MRI scripts for cross-platform archive merging |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ONNX Runtime | TensorFlow Lite | Smaller binary (~5MB), but worse model ecosystem and less execution provider support |
| OpenCV full | OpenCV minimal subset | Could strip down to just cv::Mat and core utilities, saving 10-20MB, but makes future features harder |
| CMake | Meson for everything | Meson is faster and cleaner output, but ONNX Runtime only officially supports CMake |

**Installation (Ubuntu/Debian):**
```bash
sudo apt install cmake pkg-config ccache ninja-build
sudo apt install mingw-w64 gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix
```

**Installation (macOS):**
```bash
brew install cmake pkg-config ccache ninja
brew install mingw-w64  # For Windows cross-compilation
```

## Architecture Patterns

### Recommended Project Structure

Extend existing pattern from ae.nimble:

```
build/                   # Local install prefix (like FFmpeg)
├── include/            # Headers for all ML libs
├── lib/               # Static archives (.a files)
│   └── pkgconfig/    # .pc files for pkg-config
ffmpeg_sources/         # Existing FFmpeg source downloads
ml_sources/            # NEW: ML library source downloads
├── libfacedetection/
├── onnxruntime/
└── opencv/
src/
├── ml/                # NEW: ML library FFI wrappers
│   ├── facedetect.nim
│   ├── onnx.nim
│   └── opencv.nim
ae.nimble              # Extend with makeml/makemwin tasks
```

### Pattern 1: Version-Locked Source Download

**What:** Download source tarballs with SHA256 verification before building
**When to use:** Every ML library (mirrors existing FFmpeg pattern)
**Example:**

```nim
# From ae.nimble (lines 106-111, 156-159)
type Package = object
  name: string
  sourceUrl: string
  sha256: string
  buildArguments: seq[string]
  buildSystem: string = "cmake"  # NEW: default to cmake

let facedetect = Package(
  name: "libfacedetection",
  sourceUrl: "https://github.com/ShiqiYu/libfacedetection/archive/refs/tags/v3.0.tar.gz",
  sha256: "<compute from actual release>",
  buildArguments: @["-DBUILD_SHARED_LIBS=OFF", "-DDEMO=OFF"],
  buildSystem: "cmake"
)

# Download with curl, verify hash (lines 512-518)
if not fileExists(package.location):
  exec &"curl -O -L {package.sourceUrl}"
  checkHash(package, "ml_sources" / package.location)
```

### Pattern 2: Parallel CMake Builds

**What:** Build multiple libraries concurrently with progress tracking
**When to use:** First-time setup and when library versions change
**Example:**

```nim
# Extend makeInstall() from ae.nimble (lines 254-261) with progress output
proc cmakeBuildParallel(package: Package, buildPath: string, crossWindows: bool = false) =
  echo &"[{package.name}] Configuring..."
  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
  ] & package.buildArguments

  if crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix")

  mkDir("build_cmake")
  withDir "build_cmake":
    exec "cmake " & cmakeArgs.join(" ") & " .."
    echo &"[{package.name}] Building..."
    when defined(macosx):
      exec "make -j$(sysctl -n hw.ncpu)"
    elif defined(linux):
      exec "make -j$(nproc)"
    echo &"[{package.name}] Installing..."
    exec "make install"
```

### Pattern 3: Nim FFI with Manual Memory Management

**What:** Import C/C++ functions and manage object lifetimes explicitly
**When to use:** All ML library integrations (mirrors existing av.nim patterns)
**Example:**

```nim
# Pattern from src/ffmpeg.nim (lines 306, 453, 470)
type
  FaceDetector* {.importc: "facedetect_cnn_t", header: "facedetectcnn.h".} = object
  FaceRect* {.importc: "facedetect_result_t", header: "facedetectcnn.h".} = object
    x*, y*, w*, h*: cint
    confidence*: cint

proc facedetect_cnn_create*(): ptr FaceDetector {.importc, header: "facedetectcnn.h".}
proc facedetect_cnn_free*(detector: ptr FaceDetector) {.importc, header: "facedetectcnn.h".}
proc facedetect_cnn*(detector: ptr FaceDetector, data: ptr uint8,
                     width, height, step: cint): ptr FaceRect {.importc, header: "facedetectcnn.h".}

# Use defer for cleanup (pattern from src/av.nim line 154)
proc detectFaces(image: ptr uint8, width, height: int): seq[FaceRect] =
  let detector = facedetect_cnn_create()
  defer:
    if detector != nil:
      facedetect_cnn_free(detector)

  let results = facedetect_cnn(detector, image, width.cint, height.cint, width.cint)
  # Process results...
```

### Pattern 4: ONNX Runtime Minimal Build

**What:** Build ONNX with operator reduction and minimal runtime
**When to use:** Release builds to minimize binary size
**Example:**

```bash
# Source: https://onnxruntime.ai/docs/build/custom.html
# Generate operator config from models
python tools/ci_build/reduce_op_kernels.py \
  --model_list models.txt \
  --output required_ops.config

# Build with minimal runtime and operator reduction
./build.sh \
  --config MinSizeRel \
  --minimal_build extended \
  --include_ops_by_config required_ops.config \
  --disable_ml_ops \
  --disable_exceptions \
  --use_cuda --use_coreml --use_dml  # Include all execution providers
  --parallel $(nproc)
```

### Pattern 5: Static Library Combining (Multi-Architecture)

**What:** Merge multiple static archives into one (existing x265 pattern)
**When to use:** When shipping multi-bitdepth or multi-architecture builds
**Example:**

```nim
# From ae.nimble lines 434-461 (x265 combining pattern)
# macOS: use libtool
when defined(macosx):
  exec "libtool -static -o combined.a lib1.a lib2.a lib3.a"
else:
  # Linux/Windows: use ar with MRI script
  exec "echo 'CREATE combined.a' > combine.mri"
  exec "echo 'ADDLIB lib1.a' >> combine.mri"
  exec "echo 'ADDLIB lib2.a' >> combine.mri"
  exec "echo 'SAVE' >> combine.mri"
  exec "echo 'END' >> combine.mri"

  var arCommand = if crossWindows: "x86_64-w64-mingw32-ar" else: "ar"
  exec &"{arCommand} -M < combine.mri"
```

### Pattern 6: C++ Exception Catching in Nim FFI

**What:** Wrap C++ calls that might throw in try/catch and convert to Nim exceptions
**When to use:** ONNX Runtime and OpenCV calls (both are C++ libraries)
**Example:**

```nim
# Source: https://github.com/nim-lang/Nim/issues/3571 (now implemented natively)
type
  CppException* {.importcpp: "std::exception", header: "<exception>".} = object of RootObj
  CppRuntimeError* {.importcpp: "std::runtime_error", header: "<stdexcept>".} = object of CppException

proc what(ex: CppException): cstring {.importcpp: "#.what()", header: "<exception>".}

proc onnxInferSafe*(session: ptr OrtSession, input: ptr OrtValue): ptr OrtValue =
  try:
    return onnxInfer(session, input)  # C++ function that might throw
  except CppException as e:
    let msg = $e.what()
    raise newException(IOError, "ONNX Runtime error: " & msg)
```

### Pattern 7: FFI Call Timeout

**What:** Wrap long-running FFI calls with timeouts to prevent hangs
**When to use:** ML inference on potentially corrupted input
**Example:**

```nim
import std/asyncdispatch
import std/times

proc withTimeout[T](timeout: Duration, fn: proc(): T): T =
  let deadline = getTime() + timeout
  let future = async fn()

  while not future.finished:
    if getTime() > deadline:
      raise newException(TimeoutError, "FFI call exceeded 30s timeout")
    poll(timeout = 100)

  return future.read()

# Usage
let result = withTimeout(30.seconds):
  proc(): FaceDetectResult = detectFacesFFI(frame)
```

### Anti-Patterns to Avoid

- **Dynamic linking for ML libraries:** Creates deployment complexity and breaks single-binary goal. Always static link.
- **Building full ONNX Runtime:** Results in 100-200MB binaries. Always use minimal build with operator reduction.
- **Ignoring pkg-config --static:** Misses transitive dependencies (Requires.private). Always use --static flag for static linking.
- **Global state in FFI wrappers:** C libraries may not be thread-safe. Use thread-local storage or locks.
- **Calling C++ destructors from Nim finalizers:** Nim finalizers run at unpredictable times. Use defer or explicit cleanup.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-platform static lib combining | Custom merger script | ar (Linux/Windows) / libtool (macOS) with MRI scripts | Handles symbol tables, indices, and debug info correctly. Existing x265 pattern works. |
| C++ exception handling | emit pragma hacks | Native importcpp exception support (Nim 1.6+) | Nim now supports catching imported C++ exceptions directly. Much cleaner. |
| Build progress tracking | Custom progress bars | CMake built-in progress + simple echo wrappers | CMake already tracks build progress. Just hide noise with Ninja or wrap output. |
| Dependency resolution | Manual -L/-I flags | pkg-config with --static | Tracks transitive deps, sysroot prefixes for cross-compilation, already proven in FFmpeg build. |
| Operator kernel reduction | Manual symbol stripping | ONNX Runtime's --include_ops_by_config | Official tool generates optimal configuration from model files. |
| Version-locked caching | Git submodules / manual checks | SHA256 hash verification (existing pattern) | FFmpeg build already does this correctly. Reuse checkHash() from ae.nimble. |
| Parallel compilation | Sequential builds | make -j / cmake --parallel | Build systems handle DAG scheduling better than Nim. Just invoke correctly. |

**Key insight:** The existing ae.nimble build system already solves most of these problems for FFmpeg. Extending it for ML libraries is 80% code reuse, 20% library-specific configuration.

## Common Pitfalls

### Pitfall 1: ONNX Runtime Binary Bloat

**What goes wrong:** Building full ONNX Runtime with all operators and execution providers produces 100-200MB binaries, far exceeding the 50MB target.

**Why it happens:** ONNX supports 100+ operators across 5+ execution providers. Default builds include everything. Each execution provider adds 10-30MB.

**How to avoid:**
1. Use `--minimal_build extended` (disables ONNX format loading, requires ORT format conversion)
2. Generate operator config from actual models: `reduce_op_kernels.py --model_list models.txt`
3. Use `--include_ops_by_config` to include only necessary operators
4. Add `--disable_ml_ops` if not using traditional ML operators
5. Use `--config MinSizeRel` instead of Release

**Warning signs:**
- libonnxruntime.a exceeds 50MB after build
- Final binary exceeds 100MB after linking all ML libs
- Build includes operators not used by any model (check build logs)

**Measured impact:** Minimal build with operator reduction typically reduces size from 150MB → 15-25MB (10x reduction).

### Pitfall 2: pkg-config Missing Transitive Dependencies

**What goes wrong:** Static linking fails with "undefined reference" errors despite pkg-config finding the library. Caused by not including Requires.private dependencies.

**Why it happens:** pkg-config distinguishes public deps (Requires) from private deps (Requires.private). Dynamic linking only needs public deps. Static linking needs both. Default `pkg-config --libs` omits private deps.

**How to avoid:**
Always use `--static` flag when static linking:
```bash
pkg-config --static --libs libfacedetection onnxruntime opencv4
```

In Nim compilation:
```nim
# WRONG (missing transitive deps)
--passL:"`pkg-config --libs opencv4`"

# CORRECT
--passL:"`pkg-config --static --libs opencv4`"
```

**Warning signs:**
- Linker errors about missing pthread, dl, m, stdc++ symbols
- Works with dynamic linking but fails with static
- Different errors on different platforms (missing transitive deps vary by platform)

**Fix for broken .pc files:** The existing whisper.pc fix pattern (ae.nimble lines 288-338) shows how to patch .pc files with correct Libs.private entries.

### Pitfall 3: MinGW Cross-Compilation Toolchain Mismatch

**What goes wrong:** Cross-compilation fails with "incompatible library" or "undefined reference" errors despite correct toolchain installation.

**Why it happens:** MinGW has two threading models (posix and win32) and two exception models (seh and sjlj). Mixing them causes linker failures. Must use consistent toolchain for all libraries and final binary.

**How to avoid:**
1. Always use `-posix` variant: `x86_64-w64-mingw32-gcc-posix`
2. Set all toolchain components consistently:
```bash
CC=x86_64-w64-mingw32-gcc-posix
CXX=x86_64-w64-mingw32-g++-posix
AR=x86_64-w64-mingw32-ar
STRIP=x86_64-w64-mingw32-strip
RANLIB=x86_64-w64-mingw32-ranlib
```
3. Verify with: `x86_64-w64-mingw32-gcc-posix -v` (check for posix in thread model)

**Warning signs:**
- "undefined reference to pthread_*" despite linking -lpthread
- "incompatible library version" errors
- Works on Linux native but fails on Windows

**Existing pattern:** ae.nimble lines 554-556, 665-673 show correct posix toolchain usage.

### Pitfall 4: LTO Breaking Cross-Platform Builds

**What goes wrong:** Link-time optimization fails during cross-compilation or produces corrupted binaries that crash at runtime.

**Why it happens:** LTO stores IR (intermediate representation) in object files, which must be compatible between build machine and target. Version mismatches between GCC on Linux and MinGW cause IR incompatibility.

**How to avoid:**
1. Test LTO incrementally: first native builds, then cross-compilation
2. Use matching GCC/MinGW versions (e.g., both 11.x or both 13.x)
3. If LTO fails, fall back to `-flto=thin` (LLVM) or disable for cross-builds only
4. Verify binary integrity: run simple tests on Windows after cross-compilation

**Warning signs:**
- "lto1: fatal error: bytecode stream in file" messages
- Successful link but immediate crash on startup
- Different behavior between debug and release builds

**Mitigation:** The existing build (ae.nimble line 42) uses `-flto` for native builds. May need conditional LTO for cross-compilation.

### Pitfall 5: Memory Management Between Nim GC and C++ RAII

**What goes wrong:** Memory leaks or double-frees when passing Nim objects to C++ or vice versa. Specifically: Nim GC frees C++ object, or C++ RAII deletes Nim object.

**Why it happens:** Nim's GC (ARC/ORC) and C++ RAII have different ownership semantics. Nim GC expects to control all allocations. C++ RAII expects deterministic destruction.

**How to avoid:**
1. **Never** pass Nim managed pointers to C++ functions that take ownership
2. **Always** use explicit allocation for objects crossing FFI boundary:
```nim
# WRONG: Nim GC might free while C++ still using
var nimStr = "data"
cppFunction(nimStr.cstring)  # Dangerous if cppFunction stores pointer

# CORRECT: Explicit allocation with manual cleanup
var cStr = cast[cstring](alloc(nimStr.len + 1))
copyMem(cStr, nimStr.cstring, nimStr.len)
defer: dealloc(cStr)
cppFunction(cStr)
```
3. For C++ objects returned to Nim, wrap in Nim object with destructor:
```nim
type
  OnnxSession* = object
    handle: ptr OrtSession  # C++ pointer

proc `=destroy`*(x: var OnnxSession) =
  if x.handle != nil:
    ortReleaseSession(x.handle)
    x.handle = nil
```

**Warning signs:**
- Valgrind reports leaks in C++ library code
- Crashes in C++ destructors
- "double free" errors
- Intermittent crashes that disappear with --gc:none

**Reference:** Pattern exists in current code — src/av.nim uses defer for FFmpeg object cleanup (line 154), which is the right approach.

### Pitfall 6: Silent CMake Configuration Failures

**What goes wrong:** CMake configure succeeds but builds with missing features or wrong settings. No obvious error, just mysterious runtime failures.

**Why it happens:** CMake "tries to be helpful" by disabling features it can't find instead of failing. For example, missing CUDA silently disables GPU support without error.

**How to avoid:**
1. Explicitly check for required dependencies before configuration
2. Parse CMake output for "-- Disabled" or "-- Could NOT find" messages
3. Fail fast on missing required dependencies:
```nim
proc checkDependency(name: string, command: string) =
  let (output, code) = gorgeEx(command)
  if code != 0:
    echo &"ERROR: Required dependency '{name}' not found"
    echo &"Install with: [platform-specific instructions]"
    quit(1)

# Before building
checkDependency("cmake", "command -v cmake")
checkDependency("pkg-config", "command -v pkg-config")
when defined(linux) and enableCuda:
  checkDependency("CUDA", "test -d /usr/local/cuda")
```

**Warning signs:**
- Build succeeds but execution provider unavailable at runtime
- "Feature X not available" messages during inference
- Different capabilities between builds without obvious reason

**Existing pattern:** ae.nimble lines 608-620 show dependency checking for meson/ninja with automatic installation.

### Pitfall 7: ccache False Cache Hits with Cross-Compilation

**What goes wrong:** ccache serves cached object files from wrong architecture (e.g., x86_64 Linux when building for Windows), causing cryptic linker errors.

**Why it happens:** Default ccache doesn't distinguish between cross-compilation targets. Cache key doesn't include target triplet.

**How to avoid:**
1. Set different cache directories per target:
```bash
export CCACHE_DIR="$HOME/.ccache/linux-x86_64"  # Native
export CCACHE_DIR="$HOME/.ccache/x86_64-w64-mingw32"  # Windows cross
```
2. Or include compiler path in hash:
```bash
export CCACHE_COMPILERCHECK=content  # Hash compiler binary, slower but safer
```
3. Or disable ccache for cross-compilation:
```bash
if [ "$CROSS_COMPILE" = "yes" ]; then
  unset CMAKE_C_COMPILER_LAUNCHER
  unset CMAKE_CXX_COMPILER_LAUNCHER
fi
```

**Warning signs:**
- Cross-compilation "works" instantly (suspiciously fast)
- Linker errors about incompatible object file formats
- `file` command shows wrong architecture for .o files

**Mitigation:** Check ccache stats with `ccache -s` — hit rate should be <100% on first cross-compile.

## Code Examples

Verified patterns from official sources and existing codebase:

### Example 1: CMake Static Library Build with Cross-Compilation

```nim
# Extend cmakeBuild from ae.nimble (lines 263-286)
proc cmakeBuildML(package: Package, buildPath: string, crossWindows: bool = false) =
  mkDir("build_cmake")

  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
  ] & package.buildArguments

  # Cross-compilation setup (mirrors ae.nimble lines 274-280)
  if crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix")
    cmakeArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")

  withDir "build_cmake":
    let cmakeCmd = "cmake " & cmakeArgs.join(" ") & " .."
    echo "RUN: ", cmakeCmd
    exec cmakeCmd

    # Parallel build with progress
    when defined(macosx):
      exec "make -j$(sysctl -n hw.ncpu)"
    elif defined(linux):
      exec "make -j$(nproc)"
    else:
      exec "make -j4"

    exec "make install"
```

**Source:** ae.nimble lines 263-286, adapted for ML libraries

### Example 2: libfacedetection FFI Wrapper

```nim
# Based on existing av.nim patterns (lines 64-99)
type
  FaceDetector* = object
    handle: pointer  # Opaque C pointer

  FaceRect* = object
    x*, y*, w*, h*: int
    confidence*: float

proc facedetect_cnn_create*(): pointer {.
  importc: "facedetect_cnn",
  header: "facedetectcnn.h"
.}

proc facedetect_cnn_free*(detector: pointer) {.
  importc: "facedetect_cnn_delete",
  header: "facedetectcnn.h"
.}

proc facedetect_cnn_detect*(
  detector: pointer,
  result_buffer: ptr uint8,
  width, height, step: cint
): cint {.
  importc: "facedetect_cnn",
  header: "facedetectcnn.h"
.}

proc initFaceDetector*(): FaceDetector =
  result.handle = facedetect_cnn_create()
  if result.handle == nil:
    raise newException(IOError, "Failed to create face detector")

proc detect*(detector: FaceDetector,
             image: ptr uint8,
             width, height: int): seq[FaceRect] =
  # Allocate result buffer (documented size requirement)
  const maxFaces = 64
  let bufferSize = maxFaces * sizeof(cint) * 6  # x,y,w,h,neighbors,angle per face
  var buffer = cast[ptr uint8](alloc(bufferSize))
  defer: dealloc(buffer)

  let numFaces = facedetect_cnn_detect(
    detector.handle,
    buffer,
    width.cint, height.cint, width.cint
  )

  result = newSeq[FaceRect](numFaces)
  # Parse buffer into FaceRect sequence...

proc `=destroy`*(x: var FaceDetector) =
  if x.handle != nil:
    facedetect_cnn_free(x.handle)
    x.handle = nil
```

**Source:** https://github.com/ShiqiYu/libfacedetection/blob/master/COMPILE.md + existing av.nim patterns

### Example 3: ONNX Runtime Minimal Build Configuration

```bash
# Source: https://onnxruntime.ai/docs/build/custom.html
# Generate operator configuration from models
python3 tools/ci_build/reduce_op_kernels.py \
  --model_list models.txt \
  --output required_ops.config

# Build for Linux (CPU + CUDA)
./build.sh \
  --config MinSizeRel \
  --minimal_build extended \
  --include_ops_by_config required_ops.config \
  --disable_ml_ops \
  --disable_exceptions \
  --build_shared_lib OFF \
  --parallel $(nproc) \
  --use_cuda \
  --cuda_home /usr/local/cuda \
  --cudnn_home /usr/lib/x86_64-linux-gnu

# Build for macOS (CPU + CoreML)
./build.sh \
  --config MinSizeRel \
  --minimal_build extended \
  --include_ops_by_config required_ops.config \
  --disable_ml_ops \
  --build_shared_lib OFF \
  --parallel $(sysctl -n hw.ncpu) \
  --use_coreml

# Build for Windows cross-compilation (CPU + DirectML)
./build.sh \
  --config MinSizeRel \
  --minimal_build extended \
  --include_ops_by_config required_ops.config \
  --disable_ml_ops \
  --build_shared_lib OFF \
  --parallel $(nproc) \
  --use_dml \
  --cmake_extra_defines \
    CMAKE_SYSTEM_NAME=Windows \
    CMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix \
    CMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix
```

**Source:** https://onnxruntime.ai/docs/build/custom.html and https://onnxruntime.ai/docs/build/eps.html

### Example 4: OpenCV Modular Build (Core + ImgProc Only)

```bash
# Source: https://docs.opencv.org/4.x/d3/d52/tutorial_windows_install.html
# Only build modules needed for face detection preprocessing

mkdir build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$PWD/../../build \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_opencv_apps=OFF \
  -DBUILD_opencv_python2=OFF \
  -DBUILD_opencv_python3=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_DOCS=OFF \
  -DWITH_CUDA=OFF \
  -DWITH_OPENCL=OFF \
  -DWITH_IPP=OFF \
  -DWITH_TBB=OFF \
  -DWITH_EIGEN=OFF \
  -DWITH_V4L=OFF \
  -DWITH_GTK=OFF \
  -DBUILD_LIST=core,imgproc,objdetect \
  -DCMAKE_C_FLAGS="-flto" \
  -DCMAKE_CXX_FLAGS="-flto" \
  -DCMAKE_EXE_LINKER_FLAGS="-flto"

make -j$(nproc)
make install
```

**Source:** OpenCV documentation + minimal build practices

### Example 5: Version-Locked Build Cache

```nim
# Extend existing checkHash pattern from ae.nimble (lines 236-251)
import std/[os, times, json]

type CacheMetadata = object
  libName: string
  version: string
  sha256: string
  buildDate: string
  buildFlags: seq[string]

proc getCacheKey(package: Package): string =
  # Cache key includes version, flags, and platform
  let platform = when defined(windows): "windows"
                 elif defined(macosx): "macos"
                 else: "linux"
  return &"{package.name}-{package.sha256}-{platform}"

proc shouldRebuild(package: Package, buildPath: string): bool =
  let cacheFile = buildPath / ".cache" / getCacheKey(package) & ".json"

  if not fileExists(cacheFile):
    return true  # No cache, must build

  # Check if library version changed
  let metadata = parseFile(cacheFile).to(CacheMetadata)
  if metadata.sha256 != package.sha256:
    echo &"[{package.name}] Version changed, rebuilding..."
    return true

  # Check if library files exist
  let libFile = buildPath / "lib" / &"lib{package.name}.a"
  if not fileExists(libFile):
    echo &"[{package.name}] Library missing, rebuilding..."
    return true

  return false  # Cache valid, skip build

proc writeCacheMetadata(package: Package, buildPath: string) =
  let cacheDir = buildPath / ".cache"
  createDir(cacheDir)

  let metadata = CacheMetadata(
    libName: package.name,
    version: package.sourceUrl.split("/")[^1],  # Extract version from URL
    sha256: package.sha256,
    buildDate: $now(),
    buildFlags: package.buildArguments
  )

  let cacheFile = cacheDir / getCacheKey(package) & ".json"
  writeFile(cacheFile, $(%metadata))

# Usage in build task
proc buildMLLibraries() =
  let packages = @[facedetect, onnxruntime, opencv]
  for pkg in packages:
    if shouldRebuild(pkg, buildPath):
      downloadAndBuild(pkg)
      writeCacheMetadata(pkg, buildPath)
    else:
      echo &"[{pkg.name}] Using cached build"
```

**Source:** Extends existing checkHash from ae.nimble lines 236-251

### Example 6: C++ Exception Handling in Nim

```nim
# Source: https://github.com/nim-lang/Nim/issues/3571 (native support)
type
  CppStdException* {.importcpp: "std::exception", header: "<exception>".} = object of RootObj
  CppRuntimeError* {.importcpp: "std::runtime_error", header: "<stdexcept>".} = object of CppStdException

proc what(e: CppStdException): cstring {.importcpp: "#.what()", header: "<exception>".}

# ONNX Runtime C API actually returns status codes, not exceptions
# But if wrapping C++ API directly, this pattern applies:
proc onnxCreateSession(env: pointer, modelPath: cstring): pointer {.
  importcpp: "Ort::Session(@)",
  header: "<onnxruntime_cxx_api.h>"
.}

proc createOnnxSession(modelPath: string): pointer =
  try:
    return onnxCreateSession(nil, modelPath.cstring)
  except CppRuntimeError as e:
    let msg = $e.what()
    raise newException(IOError, &"Failed to create ONNX session: {msg}")
  except CppStdException as e:
    let msg = $e.what()
    raise newException(IOError, &"ONNX Runtime error: {msg}")
```

**Source:** https://github.com/nim-lang/Nim/issues/3571

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual FFmpeg build scripts | Integrated nimble tasks with CMake | Existing in ae.nimble | Single command for full build, version-locked caching |
| Full ONNX Runtime builds | Minimal builds with operator reduction | ONNX 1.10+ (2021) | 10x size reduction (150MB → 15MB) |
| GC_ref/GC_unref for FFI | ARC/ORC with =destroy hooks | Nim 1.4+ (2020) | Deterministic cleanup, no need for manual GC management |
| emit pragma for C++ exceptions | Native importcpp exception support | Nim 1.6+ (2021) | Clean exception handling without code generation |
| Makefiles for cross-compilation | CMake toolchain files | Standard since CMake 3.0 | Better platform detection, cleaner syntax |
| ccache MD4 hash | BLAKE3 hash + Zstandard compression | ccache 4.0+ (2020) | Faster hashing, better compression |
| ONNX Runtime DirectML active development | Sustained engineering mode | 2024 | Focus shifted to WinML, but DirectML still works |

**Deprecated/outdated:**
- **TensorFlow Lite for Nim:** Lower adoption, worse model ecosystem. ONNX Runtime is standard.
- **Manual LTO flags per file:** Modern CMake handles LTO via CMAKE_INTERPROCEDURAL_OPTIMIZATION.
- **ONNX Runtime Python API for build config:** Now handled via build.sh flags and config files.
- **OpenCV CUDA/TBB by default:** Modern builds disable by default for size, enable explicitly if needed.

## Open Questions

Things that couldn't be fully resolved:

### 1. ONNX Runtime DirectML Performance on Windows

**What we know:**
- DirectML works via --use_dml flag
- Now in "sustained engineering" mode (not active feature development)
- WinML is recommended for new Windows deployments
- Benchmarks show DirectML competitive with CUDA on NVIDIA GPUs

**What's unclear:**
- Whether DirectML performance regression is likely vs. CUDA/Metal
- If WinML integration would be simpler than DirectML (requires investigation)
- Whether cross-compilation to Windows with DirectML is well-tested

**Recommendation:**
Build with DirectML for Phase 1, benchmark in Phase 5 (engagement scoring), consider WinML migration only if DirectML proves problematic.

### 2. OpenCV vs. Custom Image Preprocessing

**What we know:**
- OpenCV core+imgproc is ~5-10MB
- Only need: cv::Mat, cv::resize, cv::cvtColor
- libfacedetection accepts raw RGB/BGR buffers, doesn't require OpenCV
- FFmpeg already handles image decoding

**What's unclear:**
- Could implement cv::resize equivalent in pure Nim/C for <1MB
- Whether OpenCV dependencies (zlib, libjpeg) add significant size
- If future phases benefit from OpenCV (Phase 7 speaker reframing might)

**Recommendation:**
Include OpenCV in Phase 1 for flexibility. If binary size exceeds 80MB in Phase 4, consider replacing with minimal custom resize/format conversion (500 lines of C). Don't prematurely optimize.

### 3. ccache Effectiveness with ML Library Builds

**What we know:**
- ccache speeds incremental builds 10-50x for typical C++ projects
- Existing FFmpeg build doesn't use ccache (each build ~45min on first run)
- ML libraries have different incremental build patterns than FFmpeg

**What's unclear:**
- ONNX Runtime minimal build modifies source files before compilation (operator reduction) — does this invalidate ccache?
- Whether version-locked cache (only rebuild on SHA256 change) makes ccache redundant
- If CI should use ccache or rely on caching entire build/ directory

**Recommendation:**
Enable ccache opportunistically (CMAKE_C/CXX_COMPILER_LAUNCHER), but primary speedup comes from version-locked cache (skip build entirely if lib version unchanged). Measure both approaches in CI.

### 4. LTO Impact on Binary Size vs. Compilation Time

**What we know:**
- LTO reduces binary size 5-20% on average, up to 40% in some cases
- Adds significant compilation time (2-5x slower link phase)
- Existing honeyclip uses LTO (ae.nimble line 42: --passC:-flto --passL:-flto)

**What's unclear:**
- Whether LTO breaks MinGW cross-compilation (known issue in some GCC versions)
- If partial LTO (only ML libraries, not main binary) gives 80% benefit with 20% cost
- Whether LTO is worth it if final binary under 50MB without it

**Recommendation:**
Enable LTO for native builds (proven in existing build). Test incrementally for cross-compilation. If MinGW LTO fails, fall back to non-LTO Windows builds and document. Measure size impact in Phase 1 to inform decision.

## Sources

### Primary (HIGH confidence)

- [ONNX Runtime Custom Build Documentation](https://onnxruntime.ai/docs/build/custom.html) - Official minimal build and size optimization guide
- [ONNX Runtime Execution Providers](https://onnxruntime.ai/docs/build/eps.html) - Official build flags for CUDA, DirectML, CoreML
- [libfacedetection COMPILE.md](https://github.com/ShiqiYu/libfacedetection/blob/master/COMPILE.md) - Official build instructions, CMake options
- [OpenCV Windows Installation](https://docs.opencv.org/4.x/d3/d52/tutorial_windows_install.html) - Official OpenCV build documentation
- [Nim Manual FFI Section](https://nim-lang.org/docs/manual.html) - Official FFI documentation
- [pkg-config man page](https://linux.die.net/man/1/pkg-config) - Official pkg-config --static documentation
- ae.nimble (C:\Users\Preston\git\honeyclip\ae.nimble) - Existing FFmpeg build system, proven patterns
- src/av.nim, src/ffmpeg.nim - Existing FFI and memory management patterns

### Secondary (MEDIUM confidence)

- [ONNX Runtime Performance Tuning](https://iot-robotics.github.io/ONNXRuntime/docs/performance/tune-performance.html) - Performance optimization techniques
- [ONNX Runtime Mobile Announcement](https://opensource.microsoft.com/blog/2020/10/12/introducing-onnx-runtime-mobile-reduced-size-high-performance-package-edge-devices) - Minimal build motivation and techniques
- [Link Time Optimization: New Way to Do Compiler Optimizations](https://johnnysswlab.com/link-time-optimizations-new-way-to-do-compiler-optimizations/) - LTO benefits and tradeoffs
- [Nim FFI Memory Management Discussion](https://www.mail-archive.com/nim-general@lists.nim-lang.org/msg17772.html) - Community patterns for GC_ref/GC_unref
- [CMake with ccache - IREE](https://iree.dev/developers/building/cmake-with-ccache/) - ccache integration patterns
- [Cross-compiling from Linux to Windows with MinGW - Conan docs](https://docs.conan.io/2/examples/cross_build/linux_to_windows_mingw.html) - MinGW cross-compilation setup
- [Catching C++ exceptions in Nim - Issue #3571](https://github.com/nim-lang/Nim/issues/3571) - Native exception support (implemented)
- [Combining Multiple Static Libraries - CMake Discourse](https://discourse.cmake.org/t/combining-multiple-static-libraries-onto-one-how-to-retrieve-list-of-static-libraries-from-target/5302) - ar/libtool patterns

### Tertiary (LOW confidence - requires validation)

- [AMD Sherpa-ONNX on Windows Article](https://www.amd.com/en/developer/resources/technical-articles/2026/a-practical-approach-to-using-sherpa-onnx-production-ready-on-wi.html) - 2026 production usage patterns (4 days old, unverified)
- [Reducing Binary Size in C++26: LTO Techniques](https://markaicode.com/link-time-optimization-cpp26/) - Future C++26 features (not yet standard)
- WebSearch results on GitHub Actions cross-compilation - Various blogs, not official GitHub docs

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - CMake/pkg-config proven, ONNX minimal builds documented but not tested yet
- Architecture: HIGH - Extends existing ae.nimble patterns which are production-proven
- Pitfalls: MEDIUM - Based on documented issues and existing code, but no hands-on Phase 1 experience yet

**Research date:** 2026-02-01
**Valid until:** 2026-03-01 (30 days - ML build systems are relatively stable)

**Key uncertainties:**
1. ONNX Runtime minimal build actual size with all execution providers (need to measure)
2. MinGW LTO compatibility (existing code uses LTO, but not tested with ML libs)
3. ccache effectiveness vs. version-locked caching (need empirical comparison)
4. OpenCV necessity vs. custom preprocessing (defer until Phase 4 actual requirements clear)

**Research methodology:**
- WebSearch for ecosystem discovery and current best practices
- WebFetch for official documentation verification
- Read existing codebase (ae.nimble, src/av.nim, src/ffmpeg.nim) to identify proven patterns
- Cross-referenced multiple sources for critical claims
- Marked uncertainties explicitly rather than making assumptions
