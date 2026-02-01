# Technology Stack

**Analysis Date:** 2026-02-01

## Languages

**Primary:**
- Nim 2.2.2+ - Core application logic, FFmpeg bindings, media processing pipeline
- C/C++ (via FFmpeg) - Video/audio codec implementations and processing

**Secondary:**
- Python 3.x - End-to-end testing and test utilities
- Bash - Build scripts and cross-platform compilation

## Runtime

**Environment:**
- Nim compiler and runtime
- FFmpeg 8.0.1 (built from source with curated codec set)

**Package Manager:**
- Nimble (Nim's package manager)
- Lockfile: `.nimble` file pins key dependencies to specific commits/versions

## Frameworks

**Core:**
- FFmpeg 8.0.1 - Audio/video decoding, encoding, format handling, filtering
  - Built from source with custom codec configuration to minimize binary size
  - Statically linked into auto-editor binary

**Testing:**
- Nim unittest - Unit test framework (built-in)
- PyAV (av) 10.x - Python binding for FFmpeg, used in E2E tests
- Custom test harness - `tests/test.py` for integration testing

**Build/Dev:**
- Nimble - Task runner and build automation
- CMake 3.5+ - Builds x265 encoder with multi-bit-depth support
- Meson - Builds dav1d AV1 decoder
- Autoconf/Automake - Builds FFmpeg dependencies (libopus, lame, libvpx, etc.)

## Key Dependencies

**Critical:**
- tinyre#77469f5 - Regex library for expression parsing (pinned to specific git commit)
- checksums (Nim stdlib) - SHA1 hashing for cache key generation
- FFmpeg libraries (built in-house):
  - libavutil - Core media utilities
  - libavformat - Format/container handling
  - libavcodec - Audio/video codecs
  - libswscale - Image scaling and format conversion
  - libswresample - Audio resampling

**Infrastructure (optional, feature-gated):**
- libx264 1.0 - H.264 encoder
- libx265 4.1 - H.265/HEVC encoder (supports 8/10/12-bit pixel formats via multi-bit-depth linking)
- libvpx 1.15.2 - VP8/VP9 codec (disabled by default via `DISABLE_VPX` flag)
- libsvtav1 3.1.0 - SVT-AV1 encoder (disabled by default via `DISABLE_SVTAV1` flag)
- dav1d 1.5.2 - AV1 decoder
- libopus 1.6 - Opus audio codec
- lame 3.100 - MP3 encoder
- whisper.cpp 1.8.2 - OpenAI Whisper speech-to-text (disabled by default via `DISABLE_WHISPER` flag)
- nv-codec-headers 13.0.19.0 - NVIDIA NVENC/NVDEC headers (non-macOS only)

**Optional acceleration:**
- CUDA 12.8 - GPU acceleration for whisper.cpp (Linux only, enabled via `ENABLE_CUDA` flag)
- Metal (macOS) - GPU acceleration via Metal framework (auto-enabled on macOS)
- Neon (ARM) - SIMD optimizations on ARM architectures (auto-enabled)

## Configuration

**Environment:**
- Feature flags set as environment variables before build:
  - `DISABLE_VPX=1` - Skip VP8/VP9 codec
  - `DISABLE_SVTAV1=1` - Skip SVT-AV1 encoder
  - `DISABLE_HEVC=1` - Skip H.265 codec
  - `DISABLE_WHISPER=1` - Skip whisper.cpp speech-to-text
  - `ENABLE_12BIT=1` - Enable 12-bit x265 (disabled by default for binary size)
  - `ENABLE_CUDA=1` - Enable CUDA for whisper (Linux only)

**Build:**
- `ae.nimble` - Primary build config defining tasks and FFmpeg sources
- FFmpeg source packages downloaded and verified via SHA256
- Patches applied from `patches/` directory per codec (e.g., `patches/whisper.patch`)
- PKG_CONFIG_PATH configured dynamically during build to find compiled dependencies

## Platform Requirements

**Development:**
- Nim 2.2.2+
- cmake (3.5+)
- nasm - Assembler for x265/x264 optimizations
- pkg-config - Dependency discovery
- Python 3.x with pip
- meson and ninja (installed via pip if missing)
- GCC/Clang toolchain

**Production:**
- Linux (x86_64, aarch64, arm), macOS (Intel/Apple Silicon), Windows (via MinGW cross-compile)
- Single statically-linked binary, no runtime dependencies beyond OS libc

**Deployment Target:**
- Linux: x86_64, aarch64, armv7l
- macOS: 10.9+ (Intel and Apple Silicon)
- Windows: 7+ (64-bit, built via `nimble makeffwin` then `nimble windows` cross-compile)

---

*Stack analysis: 2026-02-01*
