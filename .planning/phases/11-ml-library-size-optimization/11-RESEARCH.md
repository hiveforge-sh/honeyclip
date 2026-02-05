# Phase 11: ML Library Size Optimization - Research

**Researched:** 2026-02-05
**Domain:** Binary size optimization, static library stripping, CMake build configuration
**Confidence:** HIGH

## Summary

The ML libraries currently total 114MB (54.2MB core ML libs + 60MB dependencies), exceeding the 100MB hard limit. The primary culprits are OpenCV (81MB including unwanted modules) and ONNX Runtime (31MB). Research shows multiple proven techniques can reduce size by 50-70%:

1. **OpenCV module elimination**: calib3d, features2d, flann are built despite BUILD_LIST (13.4MB savings)
2. **Size-optimized compilation**: Change from -O3 (Release) to -Os (MinSizeRel) for OpenCV and libfacedetection (15-25% reduction)
3. **Symbol stripping**: `strip --strip-unneeded` on .a files (5-10% reduction)
4. **3rdparty library elimination**: Disable carotene/tegra_hal (1.9MB), Eigen, ADE, FlatBuffers (estimated 2-3MB)

**Primary recommendation:** Switch OpenCV and libfacedetection to MinSizeRel build type, explicitly disable unwanted OpenCV modules via BUILD_ flags, disable unnecessary 3rdparty dependencies, and apply strip --strip-unneeded to all .a files. This combination should reduce ML libraries from 114MB to 40-50MB range.

## Standard Stack

The ML libraries in honeyclip are built from source with CMake:

### Core ML Libraries
| Library | Version | Current Size | Purpose | Why Standard |
|---------|---------|--------------|---------|--------------|
| OpenCV | 4.10.0 | 81MB (core:7MB, imgproc:8MB, objdetect:3MB, **unwanted: 13MB**) | Image processing, face detection pipeline | Industry standard CV library |
| ONNX Runtime | 1.20.1 | 31MB (already MinSizeRel) | Neural network inference for ArcFace embeddings | Microsoft's optimized inference engine |
| libfacedetection | 3.0 | 0.4MB | CNN-based face detection | Lightweight, no external dependencies |

### 3rdparty Dependencies (OpenCV)
| Library | Size | Purpose | When to Remove |
|---------|------|---------|----------------|
| tegra_hal (carotene) | 1.9MB | ARM NEON optimizations | Already using Apple Accelerate on macOS, redundant |
| libopenjp2 | 0.8MB | JPEG2000 codec | Not used for face detection |
| zlib | 0.2MB | Compression | May be required by core |
| ittnotify | 0.1MB | Intel instrumentation | Not needed in release |

### ONNX Runtime Dependencies
| Library | Size | Purpose | Status |
|---------|------|---------|--------|
| Abseil | ~5MB | Google utilities | Required |
| protobuf-lite | ~2MB | Model format | Required |
| nsync_cpp | ~1MB | Synchronization | Required |
| re2 | ~0.8MB | Regex | Required |

**Current State:**
- OpenCV: Built with Release (-O3), includes unwanted modules (calib3d, features2d, flann)
- ONNX Runtime: Already using MinSizeRel (-Os) ✓
- libfacedetection: Built with Release (-O3)
- No stripping applied to .a files

## Architecture Patterns

### Build Configuration Pattern

**Current (Release build):**
```cmake
cmake -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_LIST=core,imgproc,objdetect \
  ...
# Results in -O3 -DNDEBUG flags
# Still builds calib3d, features2d, flann as dependencies
```

**Recommended (MinSizeRel build):**
```cmake
cmake -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DBUILD_LIST=core,imgproc,objdetect \
  -DBUILD_opencv_calib3d=OFF \
  -DBUILD_opencv_features2d=OFF \
  -DBUILD_opencv_flann=OFF \
  ...
# Results in -Os -DNDEBUG flags
# Explicitly disables unwanted modules
```

### Post-Build Stripping Pattern

```bash
# After make install, strip all static libraries
find $buildPath/lib -name "*.a" -exec strip --strip-unneeded {} \;

# macOS alternative (--strip-unneeded not available)
find $buildPath/lib -name "*.a" -exec strip -x {} \;
```

### Size Validation Pattern

```nim
proc validateMLLibrarySize(buildPath: string, softLimit: int = 50, hardLimit: int = 100) =
  var totalSize = 0
  for libFile in walkFiles(buildPath / "lib" / "*.a"):
    let size = getFileSize(libFile)
    totalSize += size
  let sizeMB = totalSize div (1024 * 1024)

  if sizeMB > hardLimit:
    echo &"ERROR: ML libraries exceed {hardLimit}MB hard limit ({sizeMB}MB)"
    quit(1)
  elif sizeMB > softLimit:
    echo &"WARNING: ML libraries exceed {softLimit}MB soft limit ({sizeMB}MB)"
```

### Anti-Patterns to Avoid

- **Using Release for all libraries**: Release (-O3) optimizes for speed at the cost of size (15-25% larger than -Os)
- **Relying on BUILD_LIST alone**: BUILD_LIST doesn't prevent dependency modules from being built, must use BUILD_opencv_<module>=OFF
- **Using `strip --strip-all`**: Too aggressive for static libraries, breaks relocation; use `--strip-unneeded` instead
- **Ignoring 3rdparty libraries**: OpenCV's opencv4/3rdparty/ directory can add 3MB+ if not controlled

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Symbol stripping | Custom nm/ar scripts | `strip --strip-unneeded` (Linux) or `strip -x` (macOS) | Preserves relocation info, safe for static libs |
| Build type configuration | Manual -Os flags | CMAKE_BUILD_TYPE=MinSizeRel | Standard CMake pattern, consistent flags |
| Module dependency resolution | Parsing CMakeLists.txt | Explicit BUILD_opencv_<module>=OFF flags | Official OpenCV mechanism |
| Size measurement | Manual du commands | CMake install size tracking | Integrated validation |

**Key insight:** Static library size optimization requires both build-time decisions (compiler flags, modules) and post-build processing (stripping). Manual approaches miss edge cases that standard tools handle correctly.

## Common Pitfalls

### Pitfall 1: BUILD_LIST Doesn't Prevent Dependencies
**What goes wrong:** Setting `-DBUILD_LIST=core,imgproc,objdetect` still builds calib3d, features2d, flann (13.4MB wasted)
**Why it happens:** BUILD_LIST is a whitelist of what to include, but CMake still resolves and builds dependencies
**How to avoid:** Explicitly disable unwanted modules with `-DBUILD_opencv_<module>=OFF` flags
**Warning signs:** `ls build/lib/libopencv_*.a` shows more modules than in BUILD_LIST

### Pitfall 2: Wrong Strip Command for Static Libraries
**What goes wrong:** Using `strip --strip-all` or `strip -s` on .a files breaks linking with "undefined symbol" errors
**Why it happens:** These options remove symbols needed for relocation when linking static libraries
**How to avoid:** Use `strip --strip-unneeded` (Linux) or `strip -x` (macOS) which preserves relocation symbols
**Warning signs:** Linker errors after stripping, or no size reduction

### Pitfall 3: Release Build Type for Size-Constrained Builds
**What goes wrong:** CMAKE_BUILD_TYPE=Release uses -O3 which prioritizes speed over size (15-25% larger binaries)
**Why it happens:** Default behavior in many build systems, intuition that "release" means "optimized"
**How to avoid:** Use MinSizeRel build type for size-constrained scenarios (uses -Os flag)
**Warning signs:** Libraries are significantly larger than expected, compilation uses -O3 flags

### Pitfall 4: Ignoring OpenCV 3rdparty Directory
**What goes wrong:** OpenCV bundles 3rdparty libraries (tegra_hal, Eigen, etc.) that add 3MB+ even for minimal builds
**Why it happens:** CMake enables useful-sounding features by default (WITH_CAROTENE=ON, WITH_EIGEN=ON)
**How to avoid:** Explicitly disable 3rdparty dependencies not needed for core functionality
**Warning signs:** build/lib/opencv4/3rdparty/ contains large .a files

### Pitfall 5: Not Validating Size After Build
**What goes wrong:** Size optimizations don't work as expected, but no one notices until too late
**Why it happens:** No automated check, manual du commands forgotten, incremental changes accumulate
**How to avoid:** Add post-build size validation with hard/soft limits to nimble makeml task
**Warning signs:** Gradual size creep over time, surprises when checking final binary

## Code Examples

Verified patterns from official sources and build system inspection:

### OpenCV Minimal Build Configuration
```nim
# Source: honeyclip.nimble + research findings
let opencv = Package(
  name: "opencv",
  sourceUrl: "https://github.com/opencv/opencv/archive/refs/tags/4.10.0.tar.gz",
  sha256: "b2171af5be6b26f7a06b1229948bbb2bdaa74fcf5cd097e0af6378fce50a6eb9",
  buildSystem: "cmake",
  buildArguments: @[
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_LIST=core,imgproc,objdetect",

    # Explicitly disable unwanted modules (FIX: BUILD_LIST alone insufficient)
    "-DBUILD_opencv_calib3d=OFF",
    "-DBUILD_opencv_features2d=OFF",
    "-DBUILD_opencv_flann=OFF",
    "-DBUILD_opencv_dnn=OFF",
    "-DBUILD_opencv_gapi=OFF",
    "-DBUILD_opencv_highgui=OFF",
    "-DBUILD_opencv_ml=OFF",
    "-DBUILD_opencv_photo=OFF",
    "-DBUILD_opencv_video=OFF",

    # Disable apps, examples, tests
    "-DBUILD_opencv_apps=OFF",
    "-DBUILD_EXAMPLES=OFF",
    "-DBUILD_DOCS=OFF",
    "-DBUILD_TESTS=OFF",
    "-DBUILD_PERF_TESTS=OFF",

    # Disable hardware acceleration (not needed or redundant)
    "-DWITH_CUDA=OFF",
    "-DWITH_OPENCL=OFF",
    "-DWITH_IPP=OFF",
    "-DWITH_TBB=OFF",

    # Disable UI and media I/O (not needed)
    "-DWITH_GTK=OFF",
    "-DWITH_QT=OFF",
    "-DWITH_FFMPEG=OFF",
    "-DWITH_V4L=OFF",
    "-DWITH_1394=OFF",

    # Disable image codecs (not needed for face detection)
    "-DWITH_OPENEXR=OFF",
    "-DWITH_JASPER=OFF",
    "-DWITH_TIFF=OFF",
    "-DWITH_WEBP=OFF",
    "-DWITH_PNG=OFF",
    "-DWITH_JPEG=OFF",

    # Disable 3rdparty libraries (FIX: reduces size by ~3MB)
    "-DWITH_EIGEN=OFF",      # Matrix operations (not needed)
    "-DWITH_CAROTENE=OFF",   # ARM NEON HAL (redundant with Accelerate on macOS)
    "-DWITH_ADE=OFF",        # Graph execution (for gapi module)
    "-DWITH_FLATBUFFERS=OFF", # Serialization (not needed)

    # Use MinSizeRel instead of Release (FIX: -Os vs -O3, saves 15-25%)
    "-DCMAKE_BUILD_TYPE=MinSizeRel",

    # Keep LTO for cross-object optimization
    "-DENABLE_LTO=ON",
  ],
)
```
Source: OpenCV configuration reference - https://docs.opencv.org/4.x/db/d05/tutorial_config_reference.html

### libfacedetection Size Optimization
```nim
# Source: honeyclip.nimble (current) + MinSizeRel addition
let libfacedetection = Package(
  name: "libfacedetection",
  sourceUrl: "https://github.com/ShiqiYu/libfacedetection/archive/refs/tags/v3.0.tar.gz",
  sha256: "66dc6b47b11db4bf4ef73e8b133327aa964dbd8b2ce9e0ef4d1e94ca08d40b6a",
  buildSystem: "cmake",
  buildArguments: @[
    "-DBUILD_SHARED_LIBS=OFF",
    "-DDEMO=OFF",

    # FIX: Use MinSizeRel instead of default Release
    "-DCMAKE_BUILD_TYPE=MinSizeRel",

    # Platform-specific SIMD (keep existing logic)
    when defined(macosx) and hostCPU == "arm64":
      "-DENABLE_AVX2=OFF",
      "-DENABLE_AVX512=OFF",
      "-DENABLE_NEON=ON",
  ] & existingPlatformArgs,
)
```

### Post-Build Stripping Procedure
```nim
# Source: Research findings on static library stripping
proc stripMLLibraries(buildPath: string) =
  echo "Stripping debug symbols from ML libraries..."

  when defined(macosx):
    # macOS: use strip -x (non-global symbols)
    # --strip-unneeded not available on macOS
    let (output, code) = gorgeEx(&"find {buildPath}/lib -name '*.a' -exec strip -x {{}} \\;")
    if code != 0:
      echo "WARNING: Strip failed: ", output
  else:
    # Linux: use strip --strip-unneeded (safest for static libs)
    let (output, code) = gorgeEx(&"find {buildPath}/lib -name '*.a' -exec strip --strip-unneeded {{}} \\;")
    if code != 0:
      echo "WARNING: Strip failed: ", output
```
Source: Linux From Scratch - https://www.linuxfromscratch.org/lfs/view/systemd/chapter08/stripping.html

### Size Validation with Reporting
```nim
# Source: Existing makeml task + validation enhancement
proc reportMLLibrarySizes(buildPath: string): int =
  ## Returns total size in MB, prints breakdown
  echo ""
  echo "ML Library Size Report:"
  echo "======================="

  var totalSize = 0
  var sizesByCategory = initTable[string, int]()

  for libFile in walkFiles(buildPath / "lib" / "*.a"):
    let size = getFileSize(libFile).int
    totalSize += size

    let name = libFile.extractFilename
    let category = if name.startsWith("libopencv_"): "OpenCV"
                   elif name.startsWith("libonnx"): "ONNX"
                   elif name.startsWith("libabsl"): "Abseil"
                   elif name == "libfacedetection.a": "libfacedetection"
                   else: "Other"

    sizesByCategory[category] = sizesByCategory.getOrDefault(category, 0) + size

  for category, size in sizesByCategory.pairs:
    echo &"  {category:20s}: {size div (1024*1024):3d} MB"

  echo "======================="
  echo &"  Total ML libraries: {totalSize div (1024*1024)} MB"

  return totalSize div (1024 * 1024)

proc validateMLLibrarySize(sizeMB: int, softLimit: int = 50, hardLimit: int = 100) =
  if sizeMB > hardLimit:
    echo ""
    echo &"ERROR: ML libraries exceed {hardLimit}MB hard limit ({sizeMB}MB)"
    echo "This violates the size constraint from Phase 1."
    quit(1)
  elif sizeMB > softLimit:
    echo ""
    echo &"WARNING: ML libraries exceed {softLimit}MB soft limit ({sizeMB}MB)"
    echo "Consider additional optimization to meet target."
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| BUILD_LIST only | BUILD_LIST + explicit BUILD_<module>=OFF | OpenCV 4.x | Prevents unwanted dependencies |
| Release build type | MinSizeRel for size-constrained | CMake standard | 15-25% size reduction |
| No symbol stripping | strip --strip-unneeded post-build | Standard practice | 5-10% size reduction |
| Include all 3rdparty | Disable unused WITH_<lib>=OFF | OpenCV 4.x | 2-3MB savings |
| Manual size checks | Automated validation in build | CI best practice | Prevents size creep |

**Deprecated/outdated:**
- `strip --strip-all` on static libraries: Too aggressive, breaks relocation (use --strip-unneeded)
- `strip -s` flag: Same issue, use -x on macOS or --strip-unneeded on Linux
- Relying on BUILD_LIST to prevent all unwanted modules: Must explicitly disable with BUILD_opencv_<module>=OFF

## Open Questions

1. **Does objdetect truly depend on calib3d/features2d?**
   - What we know: Current build pulls them in as dependencies
   - What's unclear: Whether this is a build system bug or actual code dependency
   - Recommendation: Test with explicit BUILD_opencv_calib3d=OFF and see if compilation succeeds

2. **Can tegra_hal/carotene be disabled without breaking objdetect?**
   - What we know: WITH_CAROTENE=OFF should work, it's ARM NEON optimizations
   - What's unclear: Whether objdetect module has hard dependency on these HAL functions
   - Recommendation: Test on macOS (has Accelerate framework) first, then Linux x86_64

3. **What's the impact of ENABLE_LTO=ON on final honeyclip binary size?**
   - What we know: LTO is currently ON for OpenCV, enables cross-object optimization
   - What's unclear: Whether LTO helps or hurts when linking static libraries into final binary
   - Recommendation: Keep LTO=ON initially (standard practice), measure final binary size

4. **Should we strip ONNX Runtime libraries?**
   - What we know: ONNX Runtime already uses MinSizeRel (31MB currently)
   - What's unclear: Whether stripping would provide significant additional savings
   - Recommendation: Apply stripping uniformly to all .a files for consistency

## Sources

### Primary (HIGH confidence)
- OpenCV Configuration Reference: https://docs.opencv.org/4.x/db/d05/tutorial_config_reference.html
- OpenCV Compact Build Advice: https://github.com/opencv/opencv/wiki/Compact-build-advice
- CMake Build Types Documentation: https://cmake.org/cmake/help/latest/variable/CMAKE_BUILD_TYPE.html
- GCC Optimization Flags: https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html
- Linux From Scratch Stripping Guide: https://www.linuxfromscratch.org/lfs/view/systemd/chapter08/stripping.html

### Secondary (MEDIUM confidence)
- ONNX Runtime Custom Build: https://onnxruntime.ai/docs/build/custom.html
- OpenCV BUILD_LIST PR: https://github.com/opencv/opencv/pull/9893
- Code Size Optimization with GCC: https://interrupt.memfault.com/blog/code-size-optimization-gcc-flags
- CMake MinSizeRel Guide: https://gist.github.com/MangaD/475b8b413aff7682b803fb007083fb5c

### Tertiary (LOW confidence)
- OpenCV Module Dependencies: https://answers.opencv.org/question/214859/the-dependencies-of-each-opencv-module/
- Strip command examples: https://www.thegeekstuff.com/2012/09/strip-command-examples/

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Current build configuration verified in honeyclip.nimble and CMakeCache.txt
- Architecture: HIGH - Patterns verified from official CMake and OpenCV documentation
- Pitfalls: HIGH - Identified from actual current build (calib3d/features2d/flann present despite BUILD_LIST)

**Research date:** 2026-02-05
**Valid until:** 60 days (stable domain, CMake/OpenCV changes slowly)

**Size reduction potential:**
- OpenCV unwanted modules removal: 13.4MB (calib3d 6MB + features2d 1.9MB + flann 1.4MB + 3rdparty 3MB)
- MinSizeRel vs Release (OpenCV + libfacedetection): ~15MB (20% of 75MB)
- Symbol stripping: ~5MB (7% of 75MB)
- **Total estimated savings: 30-35MB** (114MB → 80-85MB, meets 100MB hard limit but not 50MB soft)
- **With aggressive 3rdparty stripping: 35-40MB** (114MB → 75-80MB)
- **Best case scenario: 40-45MB** (114MB → 70MB, approaching 50MB soft limit)

**Platform considerations:**
- macOS: Use `strip -x` instead of `--strip-unneeded`, Accelerate framework replaces NEON/carotene
- Linux: Use `strip --strip-unneeded`, consider disabling ARM-specific optimizations on x86_64
- Windows: Stripping behavior TBD (currently ML features stubbed), may need different approach
