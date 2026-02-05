## Mock embedding generators for tracker tests
## Avoids ONNX inference dependency

import std/[math, random]
import ../../src/tracking/embeddings  # For cosineSimilarity

proc mockEmbedding*(seed: int): seq[float32] =
  ## Generate deterministic 512-dim normalized embedding from seed
  ## Same seed = identical embedding (cosine similarity = 1.0)
  ## Different seeds = approximately orthogonal (similarity ~ 0.0)
  result = newSeq[float32](512)
  var rng = initRand(seed)
  var norm: float32 = 0.0

  for i in 0..<512:
    result[i] = rng.rand(2.0).float32 - 1.0f32  # Range [-1, 1]
    norm += result[i] * result[i]

  # L2 normalize to unit length
  norm = sqrt(norm)
  if norm > 1e-6:
    for i in 0..<512:
      result[i] = result[i] / norm

proc mockEmbeddingPair*(targetSimilarity: float): tuple[a, b: seq[float32]] =
  ## Generate two embeddings with approximately target cosine similarity
  ## Useful for testing embedding threshold behavior
  ##
  ## Args:
  ##   targetSimilarity: Desired cosine similarity in [-1, 1]
  ##
  ## Returns:
  ##   Two normalized embeddings with approximately target similarity
  result.a = mockEmbedding(1)
  let orthogonal = mockEmbedding(2)

  result.b = newSeq[float32](512)

  # Blend: b = alpha*a + beta*orthogonal
  let alpha = targetSimilarity.float32
  let beta = sqrt(max(0.0, 1.0 - targetSimilarity * targetSimilarity)).float32

  var norm: float32 = 0.0
  for i in 0..<512:
    result.b[i] = alpha * result.a[i] + beta * orthogonal[i]
    norm += result.b[i] * result.b[i]

  # Re-normalize
  norm = sqrt(norm)
  if norm > 1e-6:
    for i in 0..<512:
      result.b[i] = result.b[i] / norm

proc mockEmbeddingSequence*(seed: int, numFrames: int, drift: float = 0.01): seq[seq[float32]] =
  ## Generate sequence of embeddings with small frame-to-frame drift
  ## Simulates natural face embedding variation over time
  ##
  ## Args:
  ##   seed: Base seed for first embedding
  ##   numFrames: Number of frames to generate
  ##   drift: Per-frame drift factor (default 0.01 = 1% change per frame)
  ##
  ## Returns:
  ##   Sequence of embeddings, each slightly different from previous
  result = newSeq[seq[float32]](numFrames)
  let base = mockEmbedding(seed)
  var rng = initRand(seed + 1000)

  for i in 0..<numFrames:
    result[i] = newSeq[float32](512)
    var norm: float32 = 0.0

    for j in 0..<512:
      # Small random noise added each frame
      let noise = (rng.rand(2.0).float32 - 1.0f32) * drift.float32
      result[i][j] = base[j] + noise * i.float32
      norm += result[i][j] * result[i][j]

    # Re-normalize
    norm = sqrt(norm)
    for j in 0..<512:
      result[i][j] = result[i][j] / norm
