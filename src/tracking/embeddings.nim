## Face Embedding Extraction
##
## Provides face re-identification via ArcFace ONNX model.
## Extracts 512-dimensional embeddings for persistent identity tracking.

import std/[math, os]
import ../ml/onnx

type
  FaceEmbedder* = object
    ## Face embedding extractor using ArcFace model
    env: OrtEnv
    session: OrtSession
    inputSize*: int        # Model input size (112 for standard ArcFace)
    embeddingDim*: int     # Output dimension (512 for ArcFace)

  EmbeddingError* = object of CatchableError
    ## Exception raised when embedding extraction fails

proc initEmbedder*(modelPath: string): FaceEmbedder =
  ## Initialize face embedder with ArcFace ONNX model
  ##
  ## Args:
  ##   modelPath: Path to ArcFace .onnx model file
  ##     (e.g., face-recognition-resnet100-arcface-onnx)
  ##
  ## Returns:
  ##   FaceEmbedder with loaded model
  ##
  ## Raises:
  ##   EmbeddingError: If model file doesn't exist or can't be loaded

  if not fileExists(modelPath):
    raise newException(EmbeddingError,
      "ArcFace model not found at: " & modelPath &
      "\nDownload from: https://huggingface.co/garavv/arcface-onnx" &
      "\nor OpenVINO model zoo: face-recognition-resnet100-arcface-onnx")

  try:
    result.env = initOrtEnv("honeyclip-embedder", logLevel = 3)
    result.session = loadModel(result.env, modelPath)
    result.inputSize = 112      # ArcFace standard input
    result.embeddingDim = 512   # ArcFace output dimension
  except OrtError as e:
    raise newException(EmbeddingError,
      "Failed to load ArcFace model: " & e.msg)

proc preprocessFace*(imageData: ptr uint8, x, y, w, h, stride, imgW, imgH: int): seq[float32] =
  ## Preprocess face region for ArcFace inference
  ##
  ## Args:
  ##   imageData: Pointer to image data (BGR format)
  ##   x, y, w, h: Face bounding box
  ##   stride: Row stride in bytes
  ##   imgW, imgH: Full image dimensions
  ##
  ## Returns:
  ##   Flattened float32 array [1, 3, 112, 112] = 37632 elements
  ##   Normalized to [-1, 1] range

  const targetSize = 112
  const channels = 3
  const totalElements = 1 * channels * targetSize * targetSize  # 37632

  result = newSeq[float32](totalElements)

  # Clamp bounding box to image boundaries
  let x0 = max(0, min(x, imgW - 1))
  let y0 = max(0, min(y, imgH - 1))
  let x1 = max(0, min(x + w, imgW))
  let y1 = max(0, min(y + h, imgH))
  let cropW = x1 - x0
  let cropH = y1 - y0

  if cropW <= 0 or cropH <= 0:
    # Invalid crop region, return zeros
    return result

  # Resize and normalize in one pass
  # ArcFace expects: (pixel - 127.5) / 128.0 normalization
  # Input: BGR format (3 channels)
  # Output: RGB format [1, 3, 112, 112] (CHW layout)

  # Cast pointer to UncheckedArray for indexing
  let imageArray = cast[ptr UncheckedArray[uint8]](imageData)

  for outY in 0 ..< targetSize:
    for outX in 0 ..< targetSize:
      # Map output coordinates to input crop region
      let srcX = x0 + (outX * cropW) div targetSize
      let srcY = y0 + (outY * cropH) div targetSize

      # Get pixel from source image (BGR format)
      let pixelOffset = srcY * stride + srcX * 3
      let b = imageArray[pixelOffset + 0].float32
      let g = imageArray[pixelOffset + 1].float32
      let r = imageArray[pixelOffset + 2].float32

      # Convert BGR -> RGB and normalize
      let rNorm = (r - 127.5f) / 128.0f
      let gNorm = (g - 127.5f) / 128.0f
      let bNorm = (b - 127.5f) / 128.0f

      # Store in CHW layout (channel, height, width)
      let outIdx = outY * targetSize + outX
      result[0 * targetSize * targetSize + outIdx] = rNorm  # R channel
      result[1 * targetSize * targetSize + outIdx] = gNorm  # G channel
      result[2 * targetSize * targetSize + outIdx] = bNorm  # B channel

proc extractEmbedding*(embedder: FaceEmbedder, imageData: ptr uint8,
                       x, y, w, h, stride, imgW, imgH: int): seq[float32] =
  ## Extract 512-dim face embedding from image region
  ##
  ## Args:
  ##   embedder: Initialized FaceEmbedder
  ##   imageData: Pointer to image data (BGR format)
  ##   x, y, w, h: Face bounding box
  ##   stride: Row stride in bytes
  ##   imgW, imgH: Full image dimensions
  ##
  ## Returns:
  ##   Normalized 512-dim embedding vector (L2 norm = 1.0)
  ##   Empty sequence if extraction fails

  try:
    # Preprocess face crop to model input format
    let inputData = preprocessFace(imageData, x, y, w, h, stride, imgW, imgH)

    # Create input tensor [1, 3, 112, 112]
    let inputTensor = createTensor(
      cast[ptr float32](unsafeAddr inputData[0]),
      [1'i64, 3'i64, 112'i64, 112'i64]
    )

    # Run inference
    # Model input: "data" shape [1, 3, 112, 112]
    # Model output: "fc1" shape [1, 512]
    let outputs = embedder.session.run(
      [inputTensor],
      ["data"],
      ["fc1"]
    )

    if outputs.len != 1:
      return @[]

    # Extract embedding from output tensor
    # Output is [1, 512] = 512 floats
    result = newSeq[float32](embedder.embeddingDim)
    let outputData = getTensorData[float32](outputs[0])

    # Copy embedding values
    for i in 0 ..< embedder.embeddingDim:
      result[i] = outputData[i]

    # L2 normalization (ensure unit length)
    var norm: float32 = 0.0f
    for val in result:
      norm += val * val
    norm = sqrt(norm)

    if norm > 1e-6:  # Avoid division by zero
      for i in 0 ..< result.len:
        result[i] = result[i] / norm

  except OrtError:
    # Inference failed, return empty embedding
    result = @[]
  except Exception:
    # Any other error, return empty embedding
    result = @[]

proc cosineSimilarity*(a, b: seq[float32]): float =
  ## Compute cosine similarity between two embeddings
  ##
  ## Args:
  ##   a, b: Normalized embedding vectors (L2 norm = 1.0)
  ##
  ## Returns:
  ##   Similarity in range [-1, 1]
  ##   1.0 = identical, 0.0 = orthogonal, -1.0 = opposite
  ##   Per research: similarity > 0.7 indicates same person

  if a.len == 0 or b.len == 0 or a.len != b.len:
    return 0.0

  # Dot product of normalized vectors = cosine similarity
  var dotProduct: float = 0.0
  for i in 0 ..< a.len:
    dotProduct += a[i].float * b[i].float

  # Clamp to [-1, 1] range (handle floating point errors)
  result = max(-1.0, min(1.0, dotProduct))
