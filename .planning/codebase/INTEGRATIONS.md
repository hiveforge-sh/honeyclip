# External Integrations

**Analysis Date:** 2026-02-01

## APIs & External Services

**None detected.**

Auto-editor is a self-contained, offline-first CLI tool. It does not call any external APIs or cloud services.

## Data Storage

**Databases:**
- None. Application is stateless with respect to persistent data storage.

**File Storage:**
- Local filesystem only
  - Input media: User-provided files (any format supported by FFmpeg)
  - Output media: User-specified output path via `--output` flag
  - Cache location: System temp directory (`getTempDir()`) in subdirectory `ae-{version}/`
  - Cache key format: SHA1 hash of (filename, modification time, timebase, analysis method, args)

**Caching:**
- Local file-based cache (not a service)
  - Location: `{temp}/ae-{version}/` (e.g., `/tmp/ae-29.5.0/` on Linux)
  - Format: Binary files (`.bin`) containing float32 analysis results
  - Key: 16-character hex hash + codec identifier (e.g., `abc123def456789a.audio`)
  - Implemented in `src/cache.nim`: `readCache()`, `writeCache()`
  - Caching of analysis results (audio levels, motion detection, subtitle data) to avoid re-analyzing same file

## Authentication & Identity

**Auth Provider:**
- Not applicable. No authentication mechanism.

**Identity Management:**
- Not applicable. Single-user CLI tool.

## Monitoring & Observability

**Error Tracking:**
- None. Errors logged to stderr/console only.

**Logs:**
- Console output via logging framework in `src/log.nim`
- Verbosity controlled at runtime (no external log aggregation)
- Error messages printed to stderr with context

**What's Logged:**
- Analysis progress (audio/motion/subtitle detection)
- FFmpeg configuration details and codec info
- Cache hits/misses
- Processing statistics

## CI/CD & Deployment

**Hosting:**
- Not applicable. Standalone CLI distributed as single binary.
- Released as compiled binaries for Linux, macOS, Windows

**CI Pipeline:**
- GitHub Actions (referenced in README: `.github/workflows/build.yml`)
- Builds cross-platform binaries
- Test execution (unit tests via `nimble test`, E2E via `python3 tests/test.py`)

**Binary Distribution:**
- Source code: GitHub repository
- Pre-built binaries: Not specified in codebase (external release process)

## Environment Configuration

**Required env vars:**
- None at runtime (tool is configuration-free)

**Build-time env vars (optional):**
- `DISABLE_VPX=1` - Skip VP8/VP9 codec
- `DISABLE_SVTAV1=1` - Skip SVT-AV1 encoder
- `DISABLE_HEVC=1` - Skip H.265 codec
- `DISABLE_WHISPER=1` - Skip whisper.cpp speech-to-text
- `ENABLE_12BIT=1` - Enable 12-bit x265
- `ENABLE_CUDA=1` - Enable CUDA for whisper (Linux only)

**Secrets location:**
- Not applicable. No secrets, credentials, or API keys used.

## Webhooks & Callbacks

**Incoming:**
- None detected.

**Outgoing:**
- None detected.

## Media Processing Integrations

**Input Format Support:**
All formats/codecs supported by FFmpeg 8.0.1 custom build:
- Video: H.264, H.265, VP8, VP9, AV1, ProRes, DNxHD/DNxHR, and many others
- Audio: AAC, MP3, Opus, FLAC, WAV, and many others
- Container: MP4, MOV, MKV, WebM, AVI, etc.

**Output Format Support:**
User-selectable encoder + container:
- Video encoders: libx264 (H.264), libx265 (H.265), libsvtav1 (AV1), others from FFmpeg
- Audio encoders: libopus, libmp3lame, PCM, etc.
- Container formats: Controlled by FFmpeg muxer selection

**Export Format Integrations:**
Non-video exports (XML/JSON project files for NLE):
- Adobe Premiere Pro 7-CC (`src/exports/fcp7.nim`, `src/exports/fcp11.nim`)
- Final Cut Pro 7 and 11 (FCP XML format)
- DaVinci Resolve (XML format compatible with `src/exports/shotcut.nim`)
- Kdenlive (MLT XML format - `src/exports/kdenlive.nim`)
- JSON format (`src/exports/json.nim`) for custom tooling

**Analysis Integrations:**
- Audio loudness analysis (FFmpeg + custom DSP in `src/analyze/audio.nim`)
- Motion detection (FFmpeg motion filter + pixel analysis in `src/analyze/motion.nim`)
- Subtitle detection and extraction (FFmpeg subtitle decoder + parsing in `src/analyze/subtitle.nim`)
- Optional: Speech-to-text via whisper.cpp (C++ library, not external API)

## Build Dependencies (External Sources)

**Source downloads:**
All dependencies downloaded from upstream sources at build time:
- FFmpeg: https://ffmpeg.org/releases/
- x264: https://code.videolan.org/videolan/x264/
- x265: https://bitbucket.org/multicoreware/x265_git/
- libopus: https://ftp.osuosl.org/pub/xiph/releases/opus/
- lame: http://deb.debian.org/debian/pool/main/l/lame/
- libvpx: https://github.com/webmproject/libvpx/
- dav1d: https://code.videolan.org/videolan/dav1d/
- libsvtav1: https://gitlab.com/AOMediaCodec/SVT-AV1/
- whisper.cpp: https://github.com/ggml-org/whisper.cpp/
- nv-codec-headers: https://github.com/FFmpeg/nv-codec-headers/

**Verification:**
- All sources verified via SHA256 checksum before building
- Checksums hardcoded in `ae.nimble`
- Build fails if checksum mismatch detected

---

*Integration audit: 2026-02-01*
