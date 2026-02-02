<p align="center">
  <h1 align="center">honeyclip</h1>
  <p align="center"><em>Extract the sweetest moments from your video</em></p>
</p>

---

[![Actions Status](https://img.shields.io/github/actions/workflow/status/hiveforge-sh/honeyclip/build.yml?style=flat)](https://github.com/hiveforge-sh/honeyclip/actions)
[![Nim](https://img.shields.io/badge/nim-%23FFE953.svg?style=flat&logo=nim&logoColor=black)](https://nim-lang.org)

**honeyclip** is a command-line video editing tool that automatically removes silent sections and analyzes engagement. Built on the foundation of [auto-editor](https://github.com/WyattBlue/auto-editor), it adds ML-powered engagement analysis, speaker tracking, and smart clip extraction.

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

See [Installing](https://auto-editor.com/installing) for detailed instructions.

### Build from source

```bash
# Install dependencies and build FFmpeg (first time only, takes 1-2 hours)
nimble makeff

# Build honeyclip
nimble make
```

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

## Documentation

- [All Options](https://auto-editor.com/ref/options)
- [Documentation](https://auto-editor.com/docs)

## Credits

honeyclip is built on the excellent [auto-editor](https://github.com/WyattBlue/auto-editor) by WyattBlue, licensed under the [Public Domain](LICENSE).

## License

[Public Domain (Unlicense)](LICENSE)
