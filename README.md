
<img src="gh-social-header.jpg" alt="honeyclip - the best moments, extracted">


<p align="center">
  <a href="https://github.com/hiveforge-sh/honeyclip/actions"><img src="https://img.shields.io/github/actions/workflow/status/hiveforge-sh/honeyclip/build.yml?style=flat" alt="Build Status"></a>
  <a href="https://nim-lang.org"><img src="https://img.shields.io/badge/nim-%23FFE953.svg?style=flat&logo=nim&logoColor=black" alt="Nim"></a>
</p>

**honeyclip** is a command-line video editing tool that automatically removes silent sections and analyzes engagement. It features ML-powered engagement analysis, speaker tracking, and smart clip extraction.

## Features

- **Automatic silence removal** — Cut dead air with a single command
- **ML-powered engagement scoring** — Find the most engaging moments with the `engage` command
- **Smart clip extraction** — Automatically detect and export the best clips with `clips`
- **Speaker tracking & reframing** — Auto-center speakers for vertical video with `reframe`
- **Transcript extraction** — Word-level timestamps with speaker diarization via `transcript`
- **Caption rendering** — Burn styled captions into video with `caption`
- **Multi-format export** — Premiere, DaVinci Resolve, Final Cut Pro, and more

## Quick Start

```bash
# Remove silence from a video
honeyclip path/to/your/video.mp4

# Add padding around cuts for smoother edits
honeyclip example.mp4 --margin 0.2sec

# Export to Adobe Premiere
honeyclip example.mp4 --export premiere
```

## Installation

### Build from source

**Requirements:**
- Nim 2.2.2+
- cmake, nasm, pkg-config
- For Windows: Git Bash (provides required Unix tools)
- For Windows cross-compile: mingw-w64
- For ML features: cmake, python3

```bash
# Run bootstrap script to install system dependencies
./bootstrap.sh

# Build FFmpeg and codecs (first time only)
nimble makeff

# Build ML libraries (macOS/Linux only)
nimble makeml

# Build honeyclip
nimble make

# Download Whisper model for speech analysis
mkdir -p ~/.cache/whisper
curl -L -o ~/.cache/whisper/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

For better transcription accuracy, use a larger model: `ggml-small.en.bin` (~466MB) or `ggml-medium.en.bin` (~1.5GB).

**Windows users:** Run `nimble makeff` from **Git Bash**, not PowerShell or CMD. The FFmpeg build requires Unix tools (sed, make, etc.) that Git Bash provides. ML features are not available on Windows.

## Editing Methods

```bash
# Audio-based cuts (default)
honeyclip example.mp4

# Motion-based cuts
honeyclip example.mp4 --edit motion:threshold=0.02

# Combine methods
honeyclip example.mp4 --edit "(or audio:0.03 motion:0.06)"

# Use dB threshold
honeyclip example.mp4 --edit audio:-19dB
```

## Export Formats

```bash
honeyclip example.mp4 --export premiere      # Adobe Premiere Pro
honeyclip example.mp4 --export resolve       # DaVinci Resolve
honeyclip example.mp4 --export final-cut-pro # Final Cut Pro
honeyclip example.mp4 --export shotcut       # ShotCut
honeyclip example.mp4 --export kdenlive      # Kdenlive
honeyclip example.mp4 --export clip-sequence # Individual clips
```

## Manual Editing

```bash
# Cut out the first 30 seconds
honeyclip example.mp4 --cut-out 0,30sec

# Keep only a specific section
honeyclip example.mp4 --edit none --add-in 30sec,60sec
```

## License

[Public Domain (Unlicense)](LICENSE)
