
<img src="gh-social-header.jpg" alt="honeyclip - the best moments, extracted">


<p align="center">
  <a href="https://github.com/hiveforge-sh/honeyclip/actions"><img src="https://img.shields.io/github/actions/workflow/status/hiveforge-sh/honeyclip/build.yml?style=flat" alt="Build Status"></a>
  <a href="https://nim-lang.org"><img src="https://img.shields.io/badge/nim-%23FFE953.svg?style=flat&logo=nim&logoColor=black" alt="Nim"></a>
</p>

**honeyclip** is a command-line video editing tool that automatically removes silent sections and analyzes engagement. It features ML-powered engagement analysis, speaker tracking, and smart clip extraction.

## Features

- **Automatic silence removal** — Cut dead air with a single command
- **ML-powered engagement scoring** — Find the most engaging moments (coming soon)
- **Speaker tracking & reframing** — Auto-center speakers for vertical video (coming soon)
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
# Install dependencies and build FFmpeg (first time only, takes 1-2 hours)
nimble makeff

# Build honeyclip
nimble make
```

**Windows users:** Run `nimble makeff` from **Git Bash**, not PowerShell or CMD. The FFmpeg build requires Unix tools (sed, make, etc.) that Git Bash provides.

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
