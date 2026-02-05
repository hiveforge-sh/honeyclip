# Phase 13: Tracker Test Coverage - Research

**Researched:** 2026-02-05
**Domain:** Unit testing for multi-object tracking systems (Kalman filter, assignment algorithm, tracker)
**Confidence:** HIGH

## Summary

This phase adds comprehensive unit tests for the speaker tracking modules located in `src/tracking/`. The system implements a DeepSORT-style tracker with Kalman filtering, Hungarian/greedy assignment, and face embedding-based re-identification. Testing requirements are clear: 80% per-module coverage enforced in CI, with focus on multi-face scenarios, temporal edge cases, and mock embeddings to avoid ONNX dependencies.

The Nim ecosystem uses the standard `unittest` module for testing, with coverage achievable via Coco (LCOV-based) or gcov/lcov directly. The codebase already has substantial unit tests (3189 lines in `tests/unit.nim`) demonstrating patterns: simple `check` assertions, temp file cleanup with `defer`, and FFmpeg integration tests. The tracking modules total 794 lines across 5 files, with well-defined interfaces suitable for unit testing.

**Primary recommendation:** Use Nim's standard `unittest` module with Coco for LCOV-based coverage reporting. Implement synthetic test data generators for multi-face tracking scenarios, mock embedding vectors to eliminate ONNX dependencies, and tolerance-based float comparisons for Kalman filter mathematics.

## Standard Stack

### Core Testing Infrastructure

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| unittest | stdlib | Test framework | Built-in Nim standard library, already used throughout codebase |
| Coco | latest | LCOV code coverage | CLI + library, generates lcov.info and HTML reports automatically |
| nimble | 2.2.2+ | Build tool | Already configured, runs `nimble test` task |

### Supporting Tools

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| gcov/lcov | system | Coverage (alternative) | If Coco unavailable or for CI integration with existing LCOV tools |
| Testament | stdlib | Advanced test runner | Only if need process isolation (not required here) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| unittest | einheit, unittest2 | More features but external dependencies, stdlib sufficient for this phase |
| Coco | gcov/lcov direct | Lower-level but more control over compilation flags, Coco is more ergonomic |

**Installation:**

```bash
# Coco (code coverage)
nimble install coco

# No other dependencies needed - unittest is stdlib
```

**Coverage enforcement in CI:**

Add to `.github/workflows/build.yml` after "Test" step:

```yaml
- name: Generate coverage
  run: |
    nimble install -y coco
    coco --target=tests/unit.nim --cov=src/tracking --compiler="nim c"

- name: Check coverage thresholds
  run: |
    # Parse lcov.info for per-module coverage
    # Fail if any tracking module < 80%
    python3 scripts/check_coverage.py lcov.info 80
```

## Architecture Patterns

### Recommended Test Structure

```
tests/
├── unit.nim                  # Main test suite (existing)
├── test_tracking_kalman.nim  # Kalman filter tests
├── test_tracking_assignment.nim  # Assignment algorithm tests
├── test_tracking_tracker.nim     # Tracker integration tests
└── fixtures/
    ├── synthetic_faces.nim   # Synthetic face generators
    └── mock_embeddings.nim   # Mock embedding vectors
```

### Pattern 1: Synthetic Face Data Generators

**What:** Pure-math generators for FaceRect sequences with controlled motion patterns
**When to use:** All tracker tests requiring multi-face input data
**Example:**

```nim
# fixtures/synthetic_faces.nim
proc generateStraightLineFace*(
  startX, startY, width, height: int,
  velocityX, velocityY: float,
  numFrames: int,
  confidence: float = 0.95
): seq[FaceRect] =
  ## Generate face moving in straight line with constant velocity
  result = newSeq[FaceRect](numFrames)
  for i in 0..<numFrames:
    result[i] = FaceRect(
      x: startX + int(i.float * velocityX),
      y: startY + int(i.float * velocityY),
      width: width,
      height: height,
      confidence: confidence,
      angle: 0
    )

proc generateCrossingPaths*(
  face1Start, face2Start: tuple[x, y: int],
  face1Vel, face2Vel: tuple[x, y: float],
  numFrames: int
): tuple[faces1, faces2: seq[FaceRect]] =
  ## Generate two faces crossing paths
  ## Essential for testing assignment algorithm correctness
  result.faces1 = generateStraightLineFace(
    face1Start.x, face1Start.y, 100, 100,
    face1Vel.x, face1Vel.y, numFrames
  )
  result.faces2 = generateStraightLineFace(
    face2Start.x, face2Start.y, 100, 100,
    face2Vel.x, face2Vel.y, numFrames
  )

proc generateOcclusionScenario*(
  x, y, width, height: int,
  disappearFrame, reappearFrame: int,
  totalFrames: int
): seq[Option[FaceRect]] =
  ## Generate face that disappears for N frames then reappears
  ## Tests track age limits and hit streaks
  result = newSeq[Option[FaceRect]](totalFrames)
  for i in 0..<totalFrames:
    if i < disappearFrame or i >= reappearFrame:
      result[i] = some(FaceRect(x: x, y: y, width: width, height: height,
                                confidence: 0.9, angle: 0))
    else:
      result[i] = none(FaceRect)
```

### Pattern 2: Mock Embeddings

**What:** Deterministic fake embedding vectors avoiding ONNX inference
**When to use:** Tracker tests requiring appearance matching
**Example:**

```nim
# fixtures/mock_embeddings.nim
proc mockEmbedding*(seed: int): seq[float32] =
  ## Generate deterministic 512-dim embedding from seed
  ## Embeddings with same seed are identical (cosine similarity = 1.0)
  ## Different seeds produce orthogonal embeddings (similarity ≈ 0.0)
  result = newSeq[float32](512)
  var rng = initRand(seed)
  var norm: float32 = 0.0

  for i in 0..<512:
    result[i] = rng.rand(2.0) - 1.0  # Range [-1, 1]
    norm += result[i] * result[i]

  # L2 normalize
  norm = sqrt(norm)
  for i in 0..<512:
    result[i] = result[i] / norm

proc mockEmbeddingPair*(similarity: float): tuple[a, b: seq[float32]] =
  ## Generate two embeddings with specific cosine similarity
  ## Useful for testing embedding threshold behavior
  result.a = mockEmbedding(1)
  result.b = mockEmbedding(2)

  # Blend to achieve target similarity
  # similarity = dot(a, b) for normalized vectors
  # Adjust b to be similarity*a + sqrt(1-similarity²)*b_orth
  let alpha = similarity
  let beta = sqrt(max(0.0, 1.0 - similarity * similarity))

  for i in 0..<512:
    result.b[i] = alpha * result.a[i] + beta * result.b[i]
```

### Pattern 3: Tolerance-Based Float Comparisons

**What:** Float comparison with epsilon for Kalman filter math
**When to use:** All tests verifying Kalman state, covariance, or bbox predictions
**Example:**

```nim
proc checkApprox*(a, b: float, epsilon: float = 1e-6): bool =
  ## Check if two floats are approximately equal
  abs(a - b) < epsilon

proc checkBboxApprox*(a, b: FaceRect, epsilon: float = 1.0): bool =
  ## Check if two bboxes are approximately equal
  ## epsilon in pixels (default 1.0 pixel tolerance)
  result = abs(a.x.float - b.x.float) < epsilon and
           abs(a.y.float - b.y.float) < epsilon and
           abs(a.width.float - b.width.float) < epsilon and
           abs(a.height.float - b.height.float) < epsilon

# Usage in tests
test "kalman predict moves bbox by velocity":
  var kf = newKalmanFilter(FaceRect(x: 100, y: 100, width: 50, height: 50))
  kf.state[4] = 10.0  # vx = 10 pixels/frame
  kf.state[5] = 5.0   # vy = 5 pixels/frame

  let predicted = kf.predict()

  # Check position moved by velocity (with tolerance)
  check checkApprox(predicted.x.float, 110.0, epsilon=0.1)
  check checkApprox(predicted.y.float, 105.0, epsilon=0.1)
```

### Pattern 4: End-to-End Multi-Frame Tracker Tests

**What:** Feed sequence of frames through tracker, verify track identity consistency
**When to use:** Integration tests ensuring track IDs remain stable
**Example:**

```nim
test "tracker maintains identity through 30 frames":
  var tracker = newTracker(modelPath="", maxAge=90, minHits=3)

  # Generate single face moving 200 pixels right over 30 frames
  let faceSequence = generateStraightLineFace(
    startX=100, startY=100, width=100, height=100,
    velocityX=200.0/30.0, velocityY=0.0,
    numFrames=30
  )

  var assignedId: int = -1

  for i, face in faceSequence:
    let tracks = tracker.updateTracks(@[face], nil)  # nil frame = no embeddings

    # After minHits=3, should have confirmed track
    if i >= 3:
      let activeTracks = tracker.getActiveTracks()
      check activeTracks.len == 1

      # Track ID should be consistent
      if assignedId < 0:
        assignedId = activeTracks[0].id
      else:
        check activeTracks[0].id == assignedId
```

### Anti-Patterns to Avoid

- **Real ONNX inference in tests:** Never load actual embedding models (slow, hardware-dependent, breaks in CI). Always mock embeddings.
- **Hard-coded float equality:** Never `check kalmanState[0] == 100.0`, always use tolerance-based comparison.
- **Testing FFmpeg subprocess in unit tests:** Tracker tests should not invoke FFmpeg. Test composition logic separately from rendering.
- **Overspecifying Kalman internals:** Test observable behavior (bbox predictions), not internal state vectors unless specifically testing covariance updates.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Code coverage | Custom line counting | Coco with LCOV | Handles Nim line directives, generates HTML reports, integrates with CI |
| Float comparison | abs(a - b) < 0.001 scattered | Centralized `checkApprox` helper | Single source of truth for epsilon, easier to adjust tolerance |
| Test fixtures | Ad-hoc data in each test | Shared generators in `fixtures/` | Reusable, documented patterns, ensures consistency |
| Mock random data | `rand()` directly | Seeded `initRand(seed)` | Deterministic tests, reproducible failures |
| Covariance validation | Manual matrix checks | Established Kalman test patterns | Academic literature has standard validation approaches |

**Key insight:** The Nim ecosystem lacks mature mocking frameworks. Don't attempt to build a general mocking system. Instead, write domain-specific mock generators (face sequences, embeddings) as pure functions.

## Common Pitfalls

### Pitfall 1: Coverage Regression Without Baseline

**What goes wrong:** Adding coverage enforcement in CI without baseline causes immediate failures on existing code
**Why it happens:** Existing tracking modules may not have 80% coverage yet
**How to avoid:**
1. Run coverage locally first: `coco --target=tests/unit.nim --cov=src/tracking`
2. Establish current baseline (e.g., 40%)
3. Add CI step that enforces "no regression" initially
4. Incrementally increase threshold as tests are added
5. Only enforce 80% hard requirement once achieved

**Warning signs:** CI fails on PR that only adds tests (not modifying source)

### Pitfall 2: Testing Implementation Instead of Interface

**What goes wrong:** Tests break when refactoring internal Kalman filter logic, even though public behavior unchanged
**Why it happens:** Over-testing internal state (covariance matrix elements, velocity calculations)
**How to avoid:**
- Test public `predict()` output (FaceRect), not internal `state[4]` directly
- Test public `getBbox()` tuple, not raw `state` array
- Test `iou()` return values, not intermediate rectangle calculations
- Exception: Covariance validation tests explicitly check matrix properties

**Warning signs:** Test named "test kalman state array element 4 equals velocity"

### Pitfall 3: Non-Deterministic Tests with Real ONNX

**What goes wrong:** Tests pass locally but fail in CI due to missing ONNX models or different hardware
**Why it happens:** Tests directly use `initEmbedder()` instead of mocking
**How to avoid:**
- Never call `initEmbedder()` in unit tests
- Create `MockEmbedder` that returns deterministic vectors
- Document in test comment: "Uses mock embeddings, see fixtures/mock_embeddings.nim"
- Integration tests (separate from unit tests) can test real ONNX if model in resources/

**Warning signs:** Test only passes on macOS ARM64 with Metal, fails on Linux CI

### Pitfall 4: Ignoring Track Age Edge Cases

**What goes wrong:** Tests cover happy path (face always detected) but miss edge cases (occlusion, track deletion)
**Why it happens:** Easier to test continuous detection than disappearance/reappearance
**How to avoid:**
- Explicitly test `timeSinceUpdate > maxAge` deletion
- Test `hitStreak < minHits` filtering in `getActiveTracks()`
- Test occlusion scenarios with `generateOcclusionScenario()`
- Test rapid appearance/disappearance (face enters/exits frame edge)

**Warning signs:** Coverage shows `timeSinceUpdate` branches uncovered

### Pitfall 5: Assignment Algorithm Optimality Assumptions

**What goes wrong:** Tests assume greedy assignment always finds optimal solution
**Why it happens:** Code comment says "greedy assignment is optimal for our case"
**How to avoid:**
- Test cases where greedy IS optimal (small N, high cost penalties)
- Test edge case: all costs equal → any assignment valid
- Test edge case: one very low cost → should be selected first
- Don't test cases where greedy != optimal (out of scope, algorithm choice already made)
- Document in test: "Tests greedy algorithm, not Hungarian optimality"

**Warning signs:** Test named "test assignment finds globally optimal solution" (greedy doesn't guarantee this)

## Code Examples

Verified patterns for common test scenarios:

### Kalman Filter: Basic Prediction

```nim
# tests/test_tracking_kalman.nim
import unittest
import ../src/tracking/kalman
import ../src/tracking/types
import ../src/ml/facedetect

proc checkApprox(a, b: float, epsilon: float = 1e-6): bool =
  abs(a - b) < epsilon

test "kalman predict with zero velocity":
  # Initialize filter with stationary bbox
  let initialBbox = FaceRect(x: 100, y: 200, width: 50, height: 50, confidence: 0.9, angle: 0)
  var kf = newKalmanFilter(initialBbox)

  # Predict next position (velocity is zero by default)
  let predicted = kf.predict()

  # Position should not change
  check predicted.x == 100
  check predicted.y == 200
  check predicted.width == 50
  check predicted.height == 50
  check predicted.confidence == 0.5  # Predicted (not detected)

test "kalman predict increases covariance":
  let initialBbox = FaceRect(x: 100, y: 200, width: 50, height: 50, confidence: 0.9, angle: 0)
  var kf = newKalmanFilter(initialBbox, processNoise=0.01)

  # Store initial covariance diagonal
  let initialCov = kf.covariance[0][0]

  # Predict increases uncertainty
  discard kf.predict()

  # Covariance should increase by processNoise
  check checkApprox(kf.covariance[0][0], initialCov + 0.01, epsilon=1e-9)
```

### Kalman Filter: Update Reduces Covariance

```nim
test "kalman update reduces covariance":
  let initialBbox = FaceRect(x: 100, y: 200, width: 50, height: 50, confidence: 0.9, angle: 0)
  var kf = newKalmanFilter(initialBbox, measurementNoise=0.1)

  # Predict increases covariance
  discard kf.predict()
  let covAfterPredict = kf.covariance[0][0]

  # Update with detection reduces covariance
  let detection = FaceRect(x: 102, y: 201, width: 50, height: 50, confidence: 0.95, angle: 0)
  kf.update(detection)

  # Covariance should decrease
  check kf.covariance[0][0] < covAfterPredict
```

### Assignment Algorithm: IoU Computation

```nim
# tests/test_tracking_assignment.nim
import unittest
import ../src/tracking/assignment
import ../src/ml/facedetect

test "iou perfect overlap":
  let a = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
  let b = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

  check iou(a, b) == 1.0

test "iou no overlap":
  let a = FaceRect(x: 0, y: 0, width: 50, height: 50, confidence: 0.9, angle: 0)
  let b = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

  check iou(a, b) == 0.0

test "iou partial overlap":
  let a = FaceRect(x: 0, y: 0, width: 100, height: 100, confidence: 0.9, angle: 0)
  let b = FaceRect(x: 50, y: 50, width: 100, height: 100, confidence: 0.9, angle: 0)

  # Overlap area: 50x50 = 2500
  # Union area: 10000 + 10000 - 2500 = 17500
  # IoU = 2500 / 17500 = 0.142857
  let iouValue = iou(a, b)
  check abs(iouValue - 0.142857) < 0.001
```

### Assignment Algorithm: Cost Matrix with IoU Threshold

```nim
test "cost matrix sets infinite cost for low iou":
  let track = Track(
    id: 0,
    bbox: FaceRect(x: 0, y: 0, width: 50, height: 50, confidence: 0.9, angle: 0),
    embedding: @[],
    timeSinceUpdate: 0,
    hitStreak: 5,
    age: 10,
    speakerId: -1
  )

  # Detection far from track (IoU < 0.5 threshold)
  let detection = FaceRect(x: 200, y: 200, width: 50, height: 50, confidence: 0.9, angle: 0)

  let costMatrix = computeCostMatrix(@[track], @[detection], @[])

  # Cost should be infinite (1e6)
  check costMatrix[0][0] >= 1e5
```

### Tracker: Multi-Frame Identity Consistency

```nim
# tests/test_tracking_tracker.nim
import unittest
import ../src/tracking/tracker
import ../src/tracking/types
import ../src/ml/facedetect

test "tracker maintains single face identity over 30 frames":
  var tracker = newTracker(modelPath="", maxAge=90, minHits=3)

  # Single face moving horizontally
  var trackId: int = -1

  for i in 0..<30:
    let detection = FaceRect(
      x: 100 + i * 5,  # Move 5 pixels right each frame
      y: 100,
      width: 50,
      height: 50,
      confidence: 0.95,
      angle: 0
    )

    discard tracker.updateTracks(@[detection], nil)

    # After minHits=3, track should be confirmed
    if i >= 3:
      let active = tracker.getActiveTracks()
      check active.len == 1

      if trackId < 0:
        trackId = active[0].id
      else:
        # Identity must be stable
        check active[0].id == trackId
```

### Tracker: Face Disappears and Reappears

```nim
test "tracker maintains identity after brief occlusion":
  var tracker = newTracker(modelPath="", maxAge=90, minHits=3)

  let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.95, angle: 0)

  # Establish track (minHits=3 frames)
  for i in 0..<5:
    discard tracker.updateTracks(@[detection], nil)

  let active1 = tracker.getActiveTracks()
  check active1.len == 1
  let originalId = active1[0].id

  # Face disappears for 10 frames (< maxAge=90)
  for i in 0..<10:
    discard tracker.updateTracks(@[], nil)

  # Face reappears
  discard tracker.updateTracks(@[detection], nil)

  let active2 = tracker.getActiveTracks()
  # Track should be recovered with same ID
  # Note: May need 2-3 frames to regain hitStreak >= minHits
  check active2.len <= 1  # Either 0 (rebuilding) or 1 (recovered)
```

### Reframe Modules: Crop Calculation

```nim
# tests/test_reframe_crop.nim
import unittest
import ../src/reframe/crop
import ../src/ml/facedetect

test "crop centers on face":
  let face = FaceRect(x: 500, y: 300, width: 100, height: 100, confidence: 0.9, angle: 0)
  let crop = calculateCrop(face, frameWidth=1920, frameHeight=1080, targetAspect=Portrait)

  # Face center: (500 + 50, 300 + 50) = (550, 350)
  # Medium shot padding: 100 * 2.5 = 250 pixels height
  # Portrait 9:16 → width = 250 * (9/16) = 140 pixels (approx)

  let cropCenterX = crop.x + crop.width div 2
  let cropCenterY = crop.y + crop.height div 2

  # Crop center should match face center (within tolerance)
  check abs(cropCenterX - 550) < 10
  check abs(cropCenterY - 350) < 10
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual coverage tracking | Automated LCOV with Coco | 2023-2024 | Nim ecosystem adopted Python-style coverage tools |
| Hungarian algorithm | Greedy for small N | DeepSORT paper (2017) | Simpler, faster, optimal for typical face counts (1-5) |
| Histogram-based matching | Deep embeddings (ArcFace) | 2019-2020 | Better re-identification accuracy (>0.7 similarity threshold) |
| Full covariance matrix | Diagonal covariance | Recent trackers | Computational efficiency without significant accuracy loss |

**Deprecated/outdated:**
- **unittest module quirks**: Early Nim versions had `doAssert` instead of `check`, current best practice is `check` for informative failures
- **Testament for unit tests**: Testament is for compiler tests, unittest is now standard for application testing
- **Manual GCC coverage flags**: `--passC:--coverage` works but Coco automates the workflow better

## Open Questions

Things that couldn't be fully resolved:

1. **Coverage tool choice: Coco vs gcov/lcov**
   - What we know: Both work, Coco is more ergonomic, gcov/lcov gives more control
   - What's unclear: Whether CI environment (GitHub Actions) has LCOV pre-installed
   - Recommendation: Try Coco first (simpler), fall back to gcov/lcov if issues

2. **Branch vs line coverage**
   - What we know: LCOV reports both, standard practice is line coverage
   - What's unclear: Whether 80% should be line or branch coverage
   - Recommendation: Start with line coverage (easier to reason about), consider branch coverage for critical logic (assignment algorithm)

3. **Kalman covariance matrix validation depth**
   - What we know: Should test symmetry and positive definiteness for correctness
   - What's unclear: Whether determinant checks are necessary given simplified diagonal covariance
   - Recommendation: Test diagonal elements > 0, skip determinant (always positive for diagonal)

4. **Performance benchmark time limits**
   - What we know: Should verify Kalman update timing, tracker handles N faces/frame
   - What's unclear: What absolute time limits make sense given CI hardware variability
   - Recommendation: Use relative benchmarks (tracker with 5 faces should take < 5x tracker with 1 face), not absolute limits

## Sources

### Primary (HIGH confidence)

- **Nim unittest module**: https://nim-lang.org/docs/unittest.html - Official standard library documentation
- **Coco coverage tool**: https://github.com/samuelroy/coco - Code coverage for Nim with CLI and library interface
- **HookRace Blog - Nim Code Coverage**: https://hookrace.net/blog/nim-code-coverage/ - Practical guide to gcov/lcov with Nim
- **Kalman filter validation (Academic)**: https://www.prismmodelchecker.org/papers/faoc-kf.pdf - Quantitative verification methods for Kalman filters
- **NIS testing for Kalman filters**: https://kalman-filter.com/normalized-innovation-squared/ - Statistical validation with chi-squared distribution
- **Hungarian algorithm reference**: https://en.wikipedia.org/wiki/Hungarian_algorithm - O(n³) optimal assignment algorithm
- **MOTChallenge benchmarks**: https://motchallenge.net/ - Multi-object tracking standardized evaluation

### Secondary (MEDIUM confidence)

- **yglukhov/coverage library**: https://github.com/yglukhov/coverage - Alternative coverage library requiring code annotations
- **mocknim framework**: https://github.com/mem-memov/mocknim - Mocking framework for Nim (limited adoption)
- **unittest2 evolution**: https://github.com/status-im/nim-unittest2 - Enhanced unittest (Status.im project, production-tested)
- **DeepSORT implementation**: https://github.com/nwojke/deep_sort - Original DeepSORT with appearance embeddings

### Tertiary (LOW confidence)

- **SDTracker synthetic data**: https://ar5iv.labs.arxiv.org/html/2303.14653 - Synthetic-to-real MOT training (research paper)
- **Multi-Object Tracking review**: https://sertiscorp.medium.com/multi-object-tracking-a-review-6aaeea495209 - Medium article on MOT techniques

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - unittest is stdlib, Coco is documented and maintained, existing codebase proves patterns work
- Architecture: HIGH - Test structure follows existing `tests/unit.nim` patterns, synthetic generators are straightforward
- Pitfalls: HIGH - Common testing mistakes documented in Kalman filter literature and MOT papers
- Coverage tools: MEDIUM - Coco is newer (2020s), less battle-tested than gcov/lcov, but simpler workflow

**Research date:** 2026-02-05
**Valid until:** ~60 days (stable domain - Nim stdlib and testing practices evolve slowly)

**Key findings verified by:**
- Reading existing `tests/unit.nim` (3189 lines) for established patterns
- Examining tracking modules source code (794 lines across 5 files)
- Checking `.github/workflows/build.yml` for CI structure
- Consulting Nim unittest documentation for standard assertions
- Academic literature for Kalman filter validation approaches
