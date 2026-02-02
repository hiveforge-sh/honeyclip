## Binary cache for face detection results
##
## Follows cache.nim pattern but stores in .honeyclip/ folder alongside video
## for better cache locality and persistence across multiple processing runs.

import std/[os, times, streams, strutils, strformat, algorithm, options]
import checksums/sha1
import ffmpeg
import log
import about

type
  CachedFace* = object
    ## Compact face representation for binary storage
    x*, y*, width*, height*: uint16  # Sufficient for 4K (max 65535)
    confidence*: float32
    angle*: int16
    stable*: bool

  FaceCacheEntry* = object
    ## Face detections for a single frame
    frameIndex*: uint32
    timestamp*: float32  # seconds
    faces*: seq[CachedFace]

const
  FACE_CACHE_VERSION = 1'u16  # Increment when binary format changes

proc faceProcTag(path: string, tb: AVRational, args: string): string =
  ## Generate cache key for face detection results
  ## Same pattern as cache.nim procTag but with "faces" kind built-in
  let modTime = getLastModificationTime(path).toUnix().int
  let (_, name, ext) = splitFile(path)
  let key = fmt"{name}{ext}:{modTime:x}:{tb}:{args}"
  return ($secureHash(key))[0..<16].toLowerAscii() & "faces"

proc saveFaceCache(filename: string, data: seq[FaceCacheEntry]) =
  ## Write face cache in binary format
  ##
  ## Format:
  ## - Header: version (uint16), frameCount (uint32)
  ## - Per frame: frameIndex (uint32), timestamp (float32), faceCount (uint16)
  ## - Per face: x, y, width, height (uint16), confidence (float32), angle (int16), stable (uint8)

  let fs = newFileStream(filename, fmWrite)
  if fs == nil:
    raise newException(IOError, "Cannot open file for writing: " & filename)
  defer: fs.close()

  # Write header
  fs.write(FACE_CACHE_VERSION)
  fs.write(data.len.uint32)

  # Write each frame
  for entry in data:
    fs.write(entry.frameIndex)
    fs.write(entry.timestamp)
    fs.write(entry.faces.len.uint16)

    # Write each face in frame
    for face in entry.faces:
      fs.write(face.x)
      fs.write(face.y)
      fs.write(face.width)
      fs.write(face.height)
      fs.write(face.confidence)
      fs.write(face.angle)
      fs.write(if face.stable: 1'u8 else: 0'u8)

proc loadFaceCache(filename: string): seq[FaceCacheEntry] =
  ## Read face cache from binary format
  let fs = newFileStream(filename, fmRead)
  if fs == nil:
    raise newException(IOError, "Cannot open file for reading: " & filename)
  defer: fs.close()

  # Read and verify header
  let version = fs.readUint16()
  if version != FACE_CACHE_VERSION:
    raise newException(ValueError,
      fmt"Cache version mismatch: expected {FACE_CACHE_VERSION}, got {version}")

  let frameCount = fs.readUint32()
  result = newSeq[FaceCacheEntry](frameCount)

  # Read each frame
  for i in 0'u32 ..< frameCount:
    result[i].frameIndex = fs.readUint32()
    result[i].timestamp = fs.readFloat32()
    let faceCount = fs.readUint16()

    result[i].faces = newSeq[CachedFace](faceCount)

    # Read each face in frame
    for j in 0'u16 ..< faceCount:
      result[i].faces[j].x = fs.readUint16()
      result[i].faces[j].y = fs.readUint16()
      result[i].faces[j].width = fs.readUint16()
      result[i].faces[j].height = fs.readUint16()
      result[i].faces[j].confidence = fs.readFloat32()
      result[i].faces[j].angle = fs.readInt16()
      let stableFlag = fs.readUint8()
      result[i].faces[j].stable = stableFlag != 0

proc readFaceCache*(path: string, tb: AVRational, args: string): Option[seq[FaceCacheEntry]] =
  ## Read face detection cache if it exists and is valid
  ##
  ## Args:
  ##   path: Path to video file
  ##   tb: Time base (AVRational) for cache key generation
  ##   args: Detection parameters string for cache key
  ##
  ## Returns:
  ##   Some(data) if cache hit, None if cache miss or error

  let cacheDir = parentDir(path) / ".honeyclip"
  let cacheFile = cacheDir / fmt"{faceProcTag(path, tb, args)}.bin"

  try:
    return some(loadFaceCache(cacheFile))
  except Exception:
    return none(seq[FaceCacheEntry])

type CacheEntry = tuple[path: string, mtime: Time]

proc writeFaceCache*(data: seq[FaceCacheEntry], path: string, tb: AVRational, args: string) =
  ## Write face detection cache with automatic eviction
  ##
  ## Cache location: .honeyclip/ folder alongside video file
  ## Eviction: Keep only 20 most recent cache files per directory

  if data.len == 0:
    return

  let cacheDir = parentDir(path) / ".honeyclip"

  # Create cache directory if it doesn't exist
  try:
    createDir(cacheDir)
  except OSError as e:
    error fmt"Failed to create cache directory: {e.msg}"
    return

  let cacheTag = faceProcTag(path, tb, args)
  let cacheFile = cacheDir / fmt"{cacheTag}.bin"

  # Write cache file
  try:
    saveFaceCache(cacheFile, data)
  except Exception as e:
    error fmt"Cache write failed: {e.msg}"
    return

  # Eviction: limit to 20 face cache files per directory
  var cacheEntries: seq[CacheEntry] = @[]

  try:
    for entry in walkDir(cacheDir):
      if entry.kind == pcFile and entry.path.endsWith(".bin"):
        let info = getFileInfo(entry.path)
        cacheEntries.add((entry.path, info.lastWriteTime))
  except OSError:
    discard

  # Sort by modification time (oldest first) and remove excess files
  if cacheEntries.len > 20:
    cacheEntries.sort(proc(a, b: CacheEntry): int = cmp(a.mtime, b.mtime))

    # Remove oldest files until we're back to 20
    for i in 0 ..< (cacheEntries.len - 20):
      try:
        removeFile(cacheEntries[i].path)
      except OSError:
        discard
