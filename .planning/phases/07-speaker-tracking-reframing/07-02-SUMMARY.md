---
phase: 07-speaker-tracking-reframing
plan: 02
subsystem: ml-inference
tags: [arcface, onnx, face-recognition, embeddings, cosine-similarity, speaker-tracking]

# Dependency graph
requires:
  - phase: 01-foundation-build-infrastructure
    provides: ONNX Runtime wrapper with inference API
  - phase: 04-face-detection-infrastructure
    provides: Face detection and FaceRect types
provides:
  - Face embedding extraction via ArcFace ONNX model
  - 512-dimensional normalized embeddings for face re-identification
  - Cosine similarity matching (>0.7 threshold = same person)
  - Graceful degradation when model unavailable
affects: [07-03-kalman-tracking, 07-04-hungarian-assignment, speaker-reframing]

# Tech tracking
tech-stack:
  added: [ArcFace ResNet100 ONNX model integration]
  patterns:
    - Face embedding extraction with BGR->RGB preprocessing
    - L2 normalization for unit-length embeddings
    - ONNX Runtime tensor data access pattern (getTensorData)

key-files:
  created:
    - src/tracking/embeddings.nim
  modified:
    - src/ml/onnx.nim (added GetTensorMutableData API)
    - tests/unit.nim (added embedding tests)

key-decisions:
  - "ArcFace ResNet100 112x112 input size (standard, efficient for 1-5fps extraction)"
  - "Cosine similarity >0.7 threshold for same person (per research)"
  - "Empty embedding return on failure enables graceful degradation to IoU-only tracking"
  - "getTensorData[T] helper added to onnx.nim for type-safe tensor access"

patterns-established:
  - "Embedding extraction: preprocessFace -> createTensor -> inference -> L2 normalize"
  - "Graceful error handling: return empty seq on ONNX errors, caller handles"
  - "Face preprocessing: crop -> resize 112x112 -> BGR->RGB -> normalize (pixel-127.5)/128.0"

# Metrics
duration: 5.3min
completed: 2026-02-02
---

# Phase 07 Plan 02: Face Embedding Extraction Summary

**ArcFace ONNX embedding extraction with 512-dim normalized vectors enabling persistent identity tracking across occlusions via cosine similarity matching**

## Performance

- **Duration:** 5.3 min
- **Started:** 2026-02-02T23:00:45Z
- **Completed:** 2026-02-02T23:06:04Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- FaceEmbedder extracts 512-dim embeddings from face regions using ArcFace ResNet100 ONNX model
- Cosine similarity matching enables re-identification after occlusion (>0.7 = same person)
- Preprocessing pipeline converts BGR to RGB with standard ArcFace normalization
- Unit tests validate similarity calculations and preprocessing without requiring model file

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement ArcFace embedding extraction** - `8028dd7` (feat)
2. **Task 2: Add embedding unit tests** - `759efec` (test)

## Files Created/Modified
- `src/tracking/embeddings.nim` - Face embedding extraction via ONNX ArcFace model
- `src/ml/onnx.nim` - Added GetTensorMutableData API and getTensorData helper for tensor access
- `tests/unit.nim` - Embedding unit tests for cosine similarity and preprocessing

## Decisions Made
- **ArcFace ResNet100 with 112x112 input:** Standard size balances quality and speed for 1-5fps extraction rate (per Phase 4 adaptive sampling)
- **Cosine similarity >0.7 threshold:** Research-backed threshold for same-person matching, enables robust re-identification
- **Empty embedding on error:** Graceful degradation returns empty seq[float32] on ONNX errors, allows IoU-only tracking fallback
- **getTensorData helper in onnx.nim:** Type-safe tensor access pattern for extracting inference results

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added GetTensorMutableData to ONNX API**
- **Found during:** Task 1 (extractEmbedding implementation)
- **Issue:** OrtValue.handle is private, no way to extract tensor data from inference output
- **Fix:** Added GetTensorMutableData to OrtApi definition and getTensorData[T] helper proc for type-safe access
- **Files modified:** src/ml/onnx.nim
- **Verification:** nim check passes, getTensorData[float32] compiles and provides UncheckedArray access
- **Committed in:** 8028dd7 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix - ONNX wrapper was incomplete, missing tensor data extraction. Required for any inference output access.

## Issues Encountered
None - implementation followed research patterns, ONNX API extension straightforward.

## User Setup Required

**Model file required for runtime use.** Face embedding extraction needs ArcFace ONNX model:

**Download location:**
- Option 1: https://huggingface.co/garavv/arcface-onnx
- Option 2: OpenVINO model zoo (face-recognition-resnet100-arcface-onnx)

**Model specifications:**
- Input: "data" shape [1, 3, 112, 112] (RGB, CHW layout)
- Output: "fc1" shape [1, 512] (normalized embedding)
- Format: ONNX (onnxruntime 1.14+ compatible)

**Graceful degradation:** If model missing, embeddings.nim raises EmbeddingError with download instructions. Tracker can fall back to IoU-only matching.

## Next Phase Readiness

**Ready for Kalman filter implementation:**
- Face embedding extraction complete
- Cosine similarity matching validated
- Integration point: Kalman tracker can extract embeddings during update() for appearance-based data association

**Blockers:** None

**Considerations for Phase 07-03 (Kalman Filter):**
- Embeddings should be extracted at 1-5fps (matches face detection rate from Phase 4)
- Track objects should store latest embedding for re-identification after occlusion
- Cost matrix computation needs weighted combination: 0.7 * IoU + 0.3 * cosine_distance

---
*Phase: 07-speaker-tracking-reframing*
*Completed: 2026-02-02*
