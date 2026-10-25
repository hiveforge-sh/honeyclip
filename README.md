
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
- **Audio enhancement** � Denoise, de-hum, de-ess and loudness-normalize with `enhance`
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

## Audio Enhancement

`honeyclip enhance` cleans up speech audio: noise reduction, hum removal,
de-essing and loudness normalization to -16 LUFS. It writes the input video
with the cleaned audio swapped in (video stream copied, not re-encoded), or just
the cleaned WAV with `--audio-only`.

```bash
honeyclip enhance input.mp4
# Writes input.enhanced.mp4

honeyclip enhance input.mp4 --audio-only -o cleaned.wav
```

Audio files (`.wav`, `.mp3`, `.m4a`, `.flac`, ...) are accepted too and produce a WAV.

By default each stage is `auto`: honeyclip scans the audio for 50/60 Hz hum,
sibilance and a high noise floor, and only runs the stages the audio needs.
Loudness normalization (two-pass `loudnorm`) always runs.

**Requirement:** the enhancement chain runs through an `ffmpeg` command-line
program. honeyclip's bundled FFmpeg build has no CLI, so install a system
`ffmpeg` on your `PATH` (or point `HONEYCLIP_FFMPEG` at one). Lookup order:
`HONEYCLIP_FFMPEG`, then `build/ffmpeg`, then `PATH`.

### Backends

| `--backend`  | What it uses | Needs |
|--------------|--------------|-------|
| `auto` (default) | DeepFilterNet if installed, else ElevenLabs if a key is set | One of the two below; otherwise exits 1 with instructions |
| `local`      | [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet), runs on your machine | `pip install deepfilternet` (Python 3 on `PATH` as `python3` or `python`) |
| `elevenlabs` | ElevenLabs Voice Isolator API | `ELEVENLABS_API_KEY` |
| `ffmpeg`     | FFmpeg-only chain (`afftdn` denoise, hum notch, de-ess, loudnorm); no neural model, no network | Just `ffmpeg` |

ElevenLabs key: set it in the environment, or put it in the config file.

```bash
export ELEVENLABS_API_KEY="your-key-here"
```

- Linux/macOS: `$XDG_CONFIG_HOME/honeyclip/config.toml` (default `~/.config/honeyclip/config.toml`)
- Windows: `%APPDATA%\honeyclip\config.toml`

```toml
[elevenlabs]
apiKey = "your-key-here"
```

Restrict the file with `chmod 600 ~/.config/honeyclip/config.toml` and keep it
out of version control. The key is sent only to ElevenLabs as a request header
and is never logged.

### Stage control

`--denoise`, `--voice-isolation`, `--de-reverb`, `--de-ess` and `--hum-removal`
each take `on`, `off` or `auto` (default `auto`).

```bash
honeyclip enhance talk.mp4 --hum-removal=on --de-ess=off
honeyclip enhance talk.mp4 --denoise=off --voice-isolation=off   # only hum/de-ess/loudness
```

The neural backends are the denoise/voice-isolation step: with `--denoise=off` the
local backend does not run DeepFilterNet, and the ElevenLabs backend makes no API
call (and asks no cost question) when both `--denoise` and `--voice-isolation`
resolve to off. De-reverb and voice isolation are never chosen by `auto`; request
them explicitly.

### Cost (ElevenLabs)

The API is billed at roughly **$0.10 per minute** of audio. Runs estimated at
$1.00 or less (10 minutes) go ahead. Above that, honeyclip asks for confirmation
on a terminal and **refuses to run** non-interactively (scripts, CI) unless you
pass `--yes`. The check happens before anything is uploaded.

```bash
honeyclip enhance talk.mp4 --backend=elevenlabs --yes
```

### Options

```
--backend=BACKEND       auto | local | elevenlabs | ffmpeg (default: auto)
--denoise=MODE          on | off | auto (default: auto)
--voice-isolation=MODE  on | off | auto (default: auto)
--de-reverb=MODE        on | off | auto (default: auto)
--de-ess=MODE           on | off | auto (default: auto)
--hum-removal=MODE      on | off | auto (default: auto)
--audio-only            Write the cleaned WAV instead of a video
-o, --output PATH       Output path (default: {input}.enhanced.{ext})
--yes                   Skip the ElevenLabs cost confirmation
-q, --quiet             Suppress progress output
--debug                 Show debug information
```

Exit codes: `0` success, `1` backend unavailable, enhancement failed or cost not
confirmed, `2` bad arguments.

### Notes

- The audio is resampled to 48 kHz mono for processing and restored to the source
  sample rate and channel count afterwards. In an `.mp4`/`.mov` output the audio is
  re-encoded as AAC 192k; the video stream is copied.
- Inputs longer than one hour (or over 500 MB) are split at silences, enhanced in
  pieces and rejoined with crossfades. The same applies to API uploads.
- Neither neural backend is bundled. DeepFilterNet is a separate Python install, and
  ElevenLabs is a network service: like `broll`, using it sends your audio off
  machine. `--backend=local` and `--backend=ffmpeg` stay fully offline.

## License

[Public Domain (Unlicense)](LICENSE)
