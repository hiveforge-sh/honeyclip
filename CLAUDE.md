# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

honeyclip is a command-line video editing tool written in Nim that automatically removes silent sections from videos and analyzes engagement. It features ML-powered engagement analysis, speaker tracking, and smart clip extraction. It builds FFmpeg from source with a curated set of codecs.

## Build Commands

```bash
# Build FFmpeg and dependencies from source (required first time, takes 1-2 hours)
nimble makeff

# Build ML libraries (libfacedetection, OpenCV, ONNX Runtime)
nimble makeml

# Compile honeyclip binary (release build with LTO)
nimble make

# Run Nim unit tests
nimble test

# Run Python end-to-end tests (requires: pip install av)
python3 tests/test.py

# Cross-compile FFmpeg for Windows
nimble makeffwin

# Cross-compile honeyclip.exe for Windows (after makeffwin)
nimble windows

# Clean FFmpeg build artifacts
nimble cleanff
```

## Build Feature Flags

Set as environment variables before `nimble makeff`:
- `DISABLE_VPX=1` - Skip VP8/VP9 codec
- `DISABLE_SVTAV1=1` - Skip SVT-AV1 encoder
- `DISABLE_HEVC=1` - Skip H.265 codec
- `DISABLE_WHISPER=1` - Skip whisper.cpp speech-to-text
- `ENABLE_12BIT=1` - Enable 12-bit x265
- `ENABLE_CUDA=1` - Enable CUDA for whisper (Linux only)

## Architecture

**Entry point**: `src/main.nim`

**Core pipeline**:
1. FFmpeg bindings (`src/av.nim`) read input media
2. Analysis modules (`src/analyze/`) detect audio levels, motion, or subtitles
3. Expression parser (`src/palet/`) evaluates `--edit` expressions
4. Timeline (`src/timeline.nim`) builds clip sequences
5. Renderers (`src/render/`) output processed video/audio
6. Exporters (`src/exports/`) generate NLE project files

**ML modules** in `src/ml/`:
- `facedetect.nim` - Face detection via libfacedetection
- `onnx.nim` - ONNX Runtime inference
- `opencv.nim` - OpenCV image processing

**Subcommands** in `src/cmds/`: `cache`, `caption`, `clips`, `desc`, `engage`, `info`, `levels`, `reframe`, `subdump`, `transcript`, `whisper`

**Key data structures** in `src/media.nim`: `VideoStream`, `AudioStream`, `SubtitleStream`, `MediaInfo`

## Testing

Unit tests (`tests/unit.nim`) cover:
- AVRational arithmetic
- Color parsing
- Subtitle extraction
- Encoder initialization
- Timecode parsing

E2E tests (`tests/test.py`) validate:
- CLI argument parsing
- Media processing workflows
- Export format generation

Test media files are in `resources/`.

## Codec Configuration

The build deliberately disables unused FFmpeg codecs to reduce binary size. See disabled codec lists in `honeyclip.nimble` if you need to enable additional formats.

## Requirements

- Nim 2.2.2+
- cmake, nasm, pkg-config
- meson, ninja (for dav1d)
- For Windows cross-compile: mingw-w64
- For ML features: cmake, python3 (for ONNX Runtime build)

### Quick Setup

Run the bootstrap script to install all dependencies:

```bash
./bootstrap.sh
```

This script automatically detects your OS and installs:
- **macOS**: Uses Homebrew (`brew install`)
- **Linux**: Uses apt (Debian/Ubuntu), dnf (Fedora), or pacman (Arch)
- **Windows**: Uses pip (run in Git Bash)
- **Nim**: Via choosenim if not already installed

## Windows Native Build

Building natively on Windows requires:

1. **Nim via choosenim**: Install from https://nim-lang.org/install.html
   - choosenim bundles MinGW-w64 at `~/.choosenim/toolchains/mingw64/`
   - The build system automatically uses this GCC to avoid PATH conflicts

2. **Git Bash** (from Git for Windows): Provides Unix tools (bash, tar, curl)

3. **Python 3.14+** with meson/ninja: `pip install meson ninja`

4. **Pre-built FFmpeg libraries**: Run `nimble makeff` in Git Bash first
   - This builds FFmpeg and codec libraries into `build/`

5. **Build honeyclip**: `nimble make`

**Known limitations on Windows:**
- LTO is disabled due to GCC 11.1.0 internal compiler error (binary is larger)
- ML features (face detection, ONNX) are stubbed out due to LTO issues with the ML libraries
- The `engage` and `reframe` commands work but without ML-based face detection
