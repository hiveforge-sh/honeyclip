
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

#### macOS / Linux

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

#### Windows

**Important:** Windows has two bootstrap scripts:
- `bootstrap.ps1` - PowerShell script (run in PowerShell, NOT Git Bash)
- `bootstrap-windows-gitbash.sh` - Git Bash wrapper (launches PowerShell for you)

**Option 1: From PowerShell (recommended for full automation)**
```powershell
# Open PowerShell as Administrator
.\bootstrap.ps1

# Or launch as admin programmatically:
Start-Process powershell -Verb RunAs -ArgumentList "-File $PWD\bootstrap.ps1"
```

**Option 2: From Git Bash**
```bash
# Wrapper script that launches PowerShell
./bootstrap-windows-gitbash.sh

# Or manually invoke PowerShell
powershell.exe -ExecutionPolicy Bypass -File ./bootstrap.ps1
```

**After bootstrap completes:**
```bash
# Switch to Git Bash for FFmpeg build (requires Unix tools)
nimble makeff

# Build honeyclip (can use PowerShell or Git Bash)
nimble make
```

For better transcription accuracy, use a larger model: `ggml-small.en.bin` (~466MB) or `ggml-medium.en.bin` (~1.5GB).

**Note:** ML features (face detection, engagement scoring) are not available on Windows.

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

## B-Roll

`honeyclip broll` auto-detects narrative-meaningful pause points in your video,
generates short B-roll clips for each (locally via ComfyUI or remotely via Gemini Veo),
and either emits a marker JSON for review or muxes a final video.

### Quick start (local — ComfyUI)

```bash
# Start a ComfyUI server (defaults to http://127.0.0.1:8188).
# Export your workflow as API-format JSON. Mark the prompt, seed, and frame-count
# inputs with placeholders {{PROMPT}}, {{SEED}}, {{LENGTH}}.

honeyclip broll input.mp4 --workflow my-workflow.json
# Writes input_broll.json with detected insertion points and generated clips.

honeyclip broll input.mp4 --workflow my-workflow.json --render -o final.mp4
# Muxes final.mp4 with B-roll inserts; original audio plays underneath.
```

### Quick start (remote — Gemini Veo)

```bash
export GEMINI_API_KEY="your-key-here"
honeyclip broll input.mp4 --backend veo --max-broll 3 --yes
```

You can also store the key in a config file:

- Linux/macOS: `$XDG_CONFIG_HOME/honeyclip/config.toml` (default `~/.config/honeyclip/config.toml`)
- Windows: `%APPDATA%\honeyclip\config.toml`

```toml
[api]
geminiKey = "your-key-here"
comfyuiUrl = "http://127.0.0.1:8188"
```

After creating the file:

```bash
chmod 600 ~/.config/honeyclip/config.toml
```

Add `**/honeyclip/config.toml` to your global `.gitignore`. honeyclip will warn
if the resolved config path falls inside a git repo.

### Backend selection

| Flag value           | Behavior |
|----------------------|----------|
| `--backend auto`     | Tries ComfyUI first; falls back to Veo if a key is set |
| `--backend comfyui`  | Forces ComfyUI; requires `--workflow PATH` |
| `--backend veo`      | Forces Veo; requires `GEMINI_API_KEY` |

### Cost note (Veo)

Veo bills per second of generated video. Each clip is fixed at 8 seconds.

| Tier | Per second | Per 8s clip |
|------|------------|-------------|
| `veo-3.0-fast-generate-001` (default) | $0.15 | $1.20 |
| `veo-3.0-generate-001`                | $0.40 | $3.20 |

Worked example: a 30-minute video with default density (~1 clip per 60s) would request
30 clips x 8s x $0.15/s = **$36**. Use `--max-broll N` to cap.

honeyclip prompts for cost confirmation when running Veo on a TTY. Use `--yes` for
non-interactive runs (CI, scripts).

### SSRF caveat

`--comfy-url` accepts any URL. Default is `http://127.0.0.1:8188`. Do not point it
at internal services unintentionally — honeyclip does not validate the host.

### Output formats

- Default: `input_broll.json` — list of detected insertion points and generated clip paths.
  Reviewable before rendering.
- With `--render`: `input_broll.mp4` — fully muxed output with B-roll inserts spliced
  in, original audio playing underneath. A `_broll.json` sidecar is also written.

### Limits

- Veo clips are always 8s; honeyclip caps requested pauses at 6s and truncates as needed.
- ComfyUI duration depends on your workflow. honeyclip falls back to freeze-pad or
  speed-ramp fitting if the model returns a shorter clip than requested.
- ComfyUI workflow placeholder system is opt-in: only `{{PROMPT}}`, `{{SEED}}`,
  `{{LENGTH}}` are substituted. Any other tokens pass through unchanged.

### Caveat: first network feature

honeyclip is otherwise offline-first. The `broll` subcommand is the only one that
talks to external services (ComfyUI on localhost or Gemini APIs). API keys are
read from env first, config file second, and never written to logs.

## License

[Public Domain (Unlicense)](LICENSE)
