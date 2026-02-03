# Changelog

## 0.2.0 (In Development)

Major feature release adding engagement analysis and speaker reframing.

### New Commands
- `transcript` — Extract transcripts with word-level timestamps and speaker diarization (SRT/VTT/JSON export)
- `caption` — Generate and render styled captions, burn into video or export for NLEs
- `engage` — Analyze video engagement using audio, motion, speech, and face signals
- `clips` — Detect optimal clip boundaries, rank by engagement, batch export
- `reframe` — Auto-reframe video to center active speaker (in progress)

### Improvements
- Face detection with adaptive frame sampling and multi-frame consensus
- Percentile-based engagement scoring (0-100 scale)
- Hook detection for speech content analysis
- CMX3600 EDL export for clip lists
- Speaker diarization via pyannote.audio integration

## 0.1.0

Initial release of honeyclip.

- ML library build infrastructure (libfacedetection, OpenCV, ONNX Runtime)
- Nim FFI wrappers for ML libraries
- Automatic silence removal
- Multi-format NLE export (Premiere, Resolve, FCP, etc.)
