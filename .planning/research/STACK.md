# Stack Research

**Domain:** Video Engagement Analysis for CLI Tool
**Researched:** 2026-02-01
**Confidence:** MEDIUM-HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **FFmpeg** | 8.0.1 (existing) | Video decoding, audio processing | Already integrated, proven reliable, provides all A/V decoding needs |
| **whisper.cpp** | 1.8.2 (existing) | Speech-to-text transcription | Already integrated, local processing, cross-platform, excellent accuracy |
| **libfacedetection** | v3.0 | Face detection | Pure C++, no dependencies, 1000 FPS on CPU, BSD-3 license, cross-platform including ARM |
| **ONNX Runtime** | 1.23.2+ | Neural network inference engine | Industry standard, cross-platform, CPU/GPU support, C++ API, MIT license |
| **OpenCV** | 4.13+ | Video frame processing, tracking | Most mature option, extensive docs, C++ native, Apache 2.0 license |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **Falcon Speaker Diarization** | Latest (via SDK) | Speaker identification in audio | When need speaker tracking; Apache 2.0, free tier 250 min/month |
| **SCRFD (ONNX)** | Latest models | Alternative face detection | If need facial landmarks; part of InsightFace, very accurate |
| **RetinaFace (ONNX)** | Latest models | Alternative face detection with landmarks | If need 5-point facial landmarks for alignment |
| **UniFace** | 1.0.0+ | Unified face analysis (detection, landmarks, attributes) | If need age/gender/emotion; Apache 2.0, ONNX-optimized |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Nim C++ interop** | Bind C++ libraries to Nim | Use `importc` pragma, extern "C" blocks for FFmpeg-style libs |
| **cmake** | Build C++ dependencies | Already used for whisper.cpp, x265, etc. |
| **ONNX model hub** | Download pre-trained models | InsightFace, UniFace provide production-ready ONNX models |

## Installation

```bash
# Core (add to ae.nimble as new packages)
# libfacedetection - compile as static library
git clone https://github.com/ShiqiYu/libfacedetection
cd libfacedetection
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF ..
make && make install

# ONNX Runtime - download pre-built or compile
wget https://github.com/microsoft/onnxruntime/releases/download/v1.23.2/onnxruntime-linux-x64-1.23.2.tgz
# Extract and link

# OpenCV - system package or compile from source
apt-get install libopencv-dev  # Linux
brew install opencv  # macOS
# Or compile for static linking

# Supporting - download ONNX models
wget https://github.com/deepinsight/insightface/releases/download/v0.7/scrfd_10g_bnkps.onnx
wget https://github.com/deepinsight/insightface/releases/download/v0.7/retinaface_r50_v1.onnx

# Falcon (optional, requires API key)
# Free tier: 250 min/month, paid: 25,000 min/month
# https://picovoice.ai/pricing/
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **libfacedetection** | MediaPipe Face Landmarker | Never - MediaPipe deprecated C++ support, only Android/Python/Web in 2026 |
| **libfacedetection** | dlib face detection | If need facial landmarks (68-point); slower than libfacedetection but more features |
| **ONNX Runtime + models** | OpenCV DNN module | If minimizing dependencies; OpenCV DNN works but ONNX gives more model flexibility |
| **Falcon Diarization** | pyannote.audio | Never for this project - Python-only, no C/C++ bindings |
| **Heuristic engagement scoring** | ML-based engagement model | ML model if high accuracy needed, but heuristics sufficient for MVP (face presence, motion, audio energy) |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **MediaPipe (original)** | AutoFlip deprecated March 2023, C++ support ended | OpenCV tracking + custom reframing logic |
| **Cloud APIs (Azure, Google, AWS)** | Project requirement: local-only processing | Local ONNX models with ONNX Runtime |
| **Python-based solutions** | Nim project, deployment complexity | C/C++ libraries via Nim FFI |
| **TensorFlow/PyTorch runtime** | Heavy dependencies, complex builds | ONNX Runtime (lightweight, cross-platform) |
| **FaceONNX** | .NET only (requires .NET runtime) | libfacedetection or ONNX Runtime with SCRFD/RetinaFace |

## Stack Patterns by Feature

### Face Detection & Tracking
**Pattern:** libfacedetection for detection → OpenCV tracking API for frame-to-frame tracking
- **Why:** libfacedetection is fastest for initial detection (1000 FPS claim)
- **Implementation:** Detect every N frames, track between detections
- **Fallback:** Re-detect if tracking quality drops

### Speaker Diarization
**Pattern:** whisper.cpp for transcription → Falcon for speaker segmentation → Merge outputs
- **Why:** whisper.cpp already integrated; Falcon is only viable C/C++ diarization option
- **Alternative (no speakers):** Voice Activity Detection (VAD) via audio energy analysis
- **Limitation:** Falcon free tier = 250 min/month; may need fallback for heavy users

### Engagement Scoring (MVP)
**Pattern:** Heuristic combination of signals
```
engagement_score = weighted_sum(
  face_presence_ratio,      # % frames with detected face
  audio_energy_normalized,  # speech vs silence ratio
  motion_score,             # existing motion detection
  speech_density            # words per minute from whisper
)
```
- **Why:** No clear open-source C++ engagement ML model available
- **Research flag:** Consider training custom model if heuristics insufficient

### Auto-Reframing for Vertical
**Pattern:** Face detection → Bounding box tracking → Smart crop with smoothing
- **Why:** AutoFlip deprecated; rebuild similar logic with OpenCV
- **Algorithm:**
  1. Detect face(s) in frame
  2. Calculate center-of-mass of face bounding boxes
  3. Apply Kalman filter for smooth camera motion
  4. Crop to vertical aspect ratio centered on smoothed point
  5. Add letterbox if content doesn't fit

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| **ONNX Runtime 1.23+** | ONNX opset 7-21 | Models from InsightFace (opset 11) fully compatible |
| **OpenCV 4.13+** | C++11 minimum, C++20 supported | Nim compiles to C++, compatibility verified |
| **libfacedetection 3.0** | Any C++ compiler | No external dependencies, easy integration |
| **whisper.cpp 1.8.2** | FFmpeg 8.0.1 | Already proven compatible in existing build |
| **Falcon SDK** | Linux, macOS, Windows, Raspberry Pi | Cross-platform C API confirmed |

## Integration Strategy with Nim/FFmpeg

### Approach 1: Direct C Bindings (Recommended)
```nim
# Example: libfacedetection binding
{.passL: "-lfacedetection".}

type
  FaceRect* {.importc: "facedetect_result", header: "facedetectcnn.h".} = object
    x*, y*, w*, h*: cint
    confidence*: cint

proc facedetect_cnn*(
  result_buffer: ptr UncheckedArray[byte],
  gray_image_data: ptr UncheckedArray[byte],
  width, height, step: cint
): cint {.importc: "facedetect_cnn", header: "facedetectcnn.h".}
```

### Approach 2: ONNX Runtime for Models
```nim
# ONNX Runtime C API binding
type
  OrtSession* = pointer
  OrtEnv* = pointer

proc createEnv*(log_level: cint, env: ptr OrtEnv): cint
  {.importc: "OrtCreateEnv", header: "onnxruntime_c_api.h".}
```

### Approach 3: OpenCV via nimcv (if needed)
- **Note:** Existing Nim OpenCV bindings are incomplete
- **Alternative:** Direct bindings for only needed functions (e.g., tracking API)
- **Fallback:** Custom C++ wrapper compiled as static lib, thin Nim binding

## Cross-Platform Considerations

### Linux
- All libraries available via source compilation
- ONNX Runtime has official pre-built binaries
- OpenCV available in most distro repos

### macOS
- libfacedetection: compile from source (no dependencies)
- ONNX Runtime: official pre-built binaries for arm64/x64
- OpenCV: Homebrew or compile from source
- Falcon SDK: official support confirmed

### Windows (cross-compile)
- libfacedetection: MinGW compatible (pure C++)
- ONNX Runtime: official Windows builds available
- OpenCV: compile with MinGW (same as current FFmpeg build)
- Falcon SDK: official Windows support confirmed

### ARM/Raspberry Pi
- libfacedetection: explicitly tested on RPi 4 B
- ONNX Runtime: ARM64 builds available
- OpenCV: widely used on ARM, available
- Falcon SDK: official RPi support confirmed

## Confidence Assessment

| Component | Confidence | Rationale |
|-----------|-----------|-----------|
| **Face Detection** | HIGH | libfacedetection actively maintained, BSD-3 license, proven cross-platform |
| **ONNX Runtime** | HIGH | Microsoft-backed, v1.23.2 confirmed stable, C++ API documented |
| **Speaker Diarization** | MEDIUM | Falcon is only C/C++ option; Apache 2.0 but has usage limits (250 min free) |
| **Engagement Scoring** | MEDIUM-LOW | No established open-source ML model for C++; heuristic approach untested |
| **Auto-Reframing** | MEDIUM | AutoFlip deprecated; need to rebuild logic, but algorithm well-documented |
| **OpenCV Integration** | HIGH | OpenCV 4.13+ stable, widely used, but Nim bindings require custom work |

## Open Questions & Research Flags

### Critical Gaps
1. **Falcon licensing for commercial use**: Free tier sufficient? Usage limits acceptable?
   - **Mitigation:** Implement fallback VAD-based segmentation for over-limit scenarios

2. **Engagement scoring accuracy**: Heuristic vs ML model
   - **Research needed:** Literature review of engagement detection algorithms
   - **Fallback:** Ship heuristic MVP, gather data for ML model v2

3. **Nim/C++ interop complexity**: Custom bindings maintenance burden
   - **Mitigation:** Minimize binding surface area, only essential functions
   - **Alternative:** Write thin C wrapper layer if Nim FFI proves problematic

### Non-Critical
4. **ONNX model licensing**: InsightFace models are research-permissive, verify commercial use OK
5. **Performance benchmarks**: Face detection FPS on target hardware unknown
   - **Action:** Benchmark libfacedetection vs SCRFD on representative video

## Sources

**Face Detection:**
- [libfacedetection GitHub](https://github.com/ShiqiYu/libfacedetection) - HIGH confidence, official source
- [OpenCV Face Detection Guide](https://docs.opencv.org/4.x/da/d60/tutorial_face_main.html) - HIGH confidence, official docs
- [FaceONNX](https://github.com/FaceONNX/FaceONNX) - MEDIUM confidence, .NET-specific but validates ONNX approach
- [SCRFD InsightFace](https://github.com/deepinsight/insightface/tree/master/detection/scrfd) - HIGH confidence, official model repo
- [UniFace Library](https://yakhyo.github.io/uniface/) - MEDIUM confidence, recent (Nov 2025) open-source release

**Speaker Diarization:**
- [Falcon Speaker Diarization GitHub](https://github.com/Picovoice/falcon) - HIGH confidence, official source, Apache 2.0 confirmed
- [Picovoice Pricing](https://picovoice.ai/pricing/) - HIGH confidence, official pricing page
- [Whisper.cpp + Falcon Integration Guide](https://picovoice.ai/blog/whisper-cpp-speaker-diarization/) - HIGH confidence, official tutorial
- [Best Speaker Diarization Models 2026](https://brasstranscripts.com/blog/speaker-diarization-models-comparison) - MEDIUM confidence, comparison validates Falcon claims

**Auto-Reframing:**
- [AutoFlip Research Paper](https://research.google/blog/autoflip-an-open-source-framework-for-intelligent-video-reframing/) - HIGH confidence, official Google Research
- [AutoFlip Deprecation Notice](https://mediapipe.readthedocs.io/en/latest/solutions/autoflip.html) - HIGH confidence, official MediaPipe docs
- [MediaPipe Face Landmarker](https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker) - HIGH confidence, official docs (Android/Python/Web only)

**ONNX Runtime:**
- [ONNX Runtime Releases](https://github.com/microsoft/onnxruntime/releases) - HIGH confidence, official GitHub
- [ONNX Runtime C++ Guide](https://onnxruntime.ai/docs/get-started/with-cpp.html) - HIGH confidence, official docs

**OpenCV:**
- [OpenCV 4.11 Release](https://opencv.org/blog/opencv-4-11-is-now-available/) - HIGH confidence, official blog
- [OpenCV Releases](https://github.com/opencv/opencv/releases) - HIGH confidence, official GitHub

**Engagement Analysis:**
- [Learner Engagement Analysis (ArXiv)](https://arxiv.org/html/2412.00429v1) - MEDIUM confidence, recent research (Dec 2024)
- [ViBED-Net: Video Based Engagement Detection](https://www.researchgate.net/publication/396747366_ViBED-Net_Video_Based_Engagement_Detection_Network_Using_Face-Aware_and_Scene-Aware_Spatiotemporal_Cues) - MEDIUM confidence, academic research

**Nim Integration:**
- [nimffmpeg GitHub](https://github.com/mashingan/nimffmpeg) - MEDIUM confidence, demonstrates FFmpeg binding pattern
- [Nim C Interop Guide](https://gist.github.com/zacharycarter/846869eb3423e20af04dea226b65c18f) - MEDIUM confidence, community guide

---
*Stack research for: Auto-Editor Engagement Analysis Features*
*Researched: 2026-02-01*
*Next step: Roadmap creation with phase structure based on dependencies*
