# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Auto-editor is a command-line video editing tool written in Nim that automatically removes silent sections from videos. It builds FFmpeg from source with a curated set of codecs.

## Build Commands

```bash
# Build FFmpeg and dependencies from source (required first time, takes 1-2 hours)
nimble makeff

# Compile auto-editor binary (release build with LTO)
nimble make

# Run Nim unit tests
nimble test

# Run Python end-to-end tests (requires: pip install av)
python3 tests/test.py

# Cross-compile FFmpeg for Windows
nimble makeffwin

# Cross-compile auto-editor.exe for Windows (after makeffwin)
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

**Subcommands** in `src/cmds/`: `cache`, `desc`, `info`, `levels`, `subdump`, `whisper`

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

The build deliberately disables unused FFmpeg codecs to reduce binary size. See disabled codec lists in `ae.nimble` if you need to enable additional formats.

## Requirements

- Nim 2.2.2+
- cmake, nasm, pkg-config
- For Windows cross-compile: mingw-w64
