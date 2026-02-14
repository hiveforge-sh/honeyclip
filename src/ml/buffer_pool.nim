## Frame buffer pooling for memory-efficient video processing
##
## Pre-allocates reusable frame buffers to prevent per-frame allocation overhead
## and memory fragmentation. Designed for 4K+ video processing where frames are
## ~25MB each in BGR format (3840 x 2160 x 3 bytes).
##
## Usage:
##   var pool = newBufferPool(3840, 2160, 3, maxBuffers = 16)
##   let buf = pool.acquire()
##   # ... use buffer ...
##   pool.release(buf)

import std/[strformat]
import ../log

type
  FrameBuffer* = object
    ## Pre-allocated frame buffer with metadata
    data*: ptr UncheckedArray[uint8]  # Raw pixel data
    capacity*: int                     # Total bytes allocated
    width*: int                        # Frame width in pixels
    height*: int                       # Frame height in pixels
    channels*: int                     # Number of channels (typically 3 for BGR)
    inUse*: bool                       # Whether buffer is currently acquired

  BufferPool* = object
    ## Pool of pre-allocated frame buffers with acquire/release semantics
    buffers*: seq[FrameBuffer]
    maxBuffers*: int                   # Total buffers in pool
    frameSize*: int                    # Bytes per frame (width * height * channels)
    acquiredCount*: int                # Number of buffers currently in use

proc newBufferPool*(width, height, channels: int, maxBuffers: int = 16): BufferPool =
  ## Create a new buffer pool with pre-allocated frame buffers
  ##
  ## Args:
  ##   width: Frame width in pixels
  ##   height: Frame height in pixels
  ##   channels: Number of channels (typically 3 for BGR)
  ##   maxBuffers: Number of buffers to pre-allocate (default 16)
  ##
  ## Returns:
  ##   Initialized BufferPool with all buffers pre-allocated
  ##
  ## Example:
  ##   # For 4K BGR: 3840 * 2160 * 3 = 24,883,200 bytes (~24MB per buffer)
  ##   # Pool of 16 = ~400MB total
  ##   var pool = newBufferPool(3840, 2160, 3, maxBuffers = 16)

  let frameSize = width * height * channels

  result.maxBuffers = maxBuffers
  result.frameSize = frameSize
  result.acquiredCount = 0
  result.buffers = newSeq[FrameBuffer](maxBuffers)

  # Pre-allocate all buffers
  for i in 0 ..< maxBuffers:
    let data = cast[ptr UncheckedArray[uint8]](alloc(frameSize))
    result.buffers[i].data = data
    result.buffers[i].capacity = frameSize
    result.buffers[i].width = width
    result.buffers[i].height = height
    result.buffers[i].channels = channels
    result.buffers[i].inUse = false

  # Log pool creation for performance debugging
  let bufferMB = frameSize.float / (1024.0 * 1024.0)
  let totalMB = bufferMB * maxBuffers.float
  info fmt"Buffer pool: {maxBuffers} x {bufferMB:.1f}MB = {totalMB:.0f}MB"

proc acquire*(pool: var BufferPool): ptr FrameBuffer =
  ## Acquire an available buffer from the pool
  ##
  ## Args:
  ##   pool: Buffer pool to acquire from
  ##
  ## Returns:
  ##   Pointer to acquired FrameBuffer, or nil if all buffers in use
  ##
  ## The buffer is marked as in-use and must be released via release()
  ## when no longer needed.

  # Find first available buffer
  for i in 0 ..< pool.buffers.len:
    if not pool.buffers[i].inUse:
      pool.buffers[i].inUse = true
      pool.acquiredCount += 1
      return addr pool.buffers[i]

  # All buffers in use
  return nil

proc release*(pool: var BufferPool, buffer: ptr FrameBuffer) =
  ## Release a buffer back to the pool
  ##
  ## Args:
  ##   pool: Buffer pool that owns the buffer
  ##   buffer: Buffer to release (must have been acquired from this pool)
  ##
  ## Marks the buffer as available for future acquire() calls.
  ## Asserts that the buffer belongs to this pool.

  if buffer == nil:
    return

  # Verify buffer belongs to this pool (check pointer range)
  let bufferAddr = cast[int](buffer)
  let poolStart = cast[int](addr pool.buffers[0])
  let poolEnd = poolStart + (pool.buffers.len * sizeof(FrameBuffer))

  if bufferAddr < poolStart or bufferAddr >= poolEnd:
    error "release: buffer does not belong to this pool"

  # Mark as available
  buffer.inUse = false
  pool.acquiredCount -= 1

proc available*(pool: BufferPool): int =
  ## Get number of available (not in-use) buffers
  ##
  ## Args:
  ##   pool: Buffer pool to query
  ##
  ## Returns:
  ##   Number of buffers available for acquire()

  return pool.maxBuffers - pool.acquiredCount

proc resize*(pool: var BufferPool, width, height, channels: int) =
  ## Resize all buffers in the pool
  ##
  ## Args:
  ##   pool: Buffer pool to resize
  ##   width: New frame width
  ##   height: New frame height
  ##   channels: New channel count
  ##
  ## All buffers must be released (acquiredCount == 0) before resizing.
  ## Useful when switching between videos of different resolutions.

  if pool.acquiredCount != 0:
    error fmt"resize: cannot resize pool with {pool.acquiredCount} buffers in use"

  let newFrameSize = width * height * channels

  # Only reallocate if size changed
  if newFrameSize == pool.frameSize:
    # Just update metadata
    for i in 0 ..< pool.buffers.len:
      pool.buffers[i].width = width
      pool.buffers[i].height = height
      pool.buffers[i].channels = channels
    return

  # Reallocate all buffers
  for i in 0 ..< pool.buffers.len:
    # Free old buffer
    if pool.buffers[i].data != nil:
      dealloc(pool.buffers[i].data)

    # Allocate new buffer
    let data = cast[ptr UncheckedArray[uint8]](alloc(newFrameSize))
    pool.buffers[i].data = data
    pool.buffers[i].capacity = newFrameSize
    pool.buffers[i].width = width
    pool.buffers[i].height = height
    pool.buffers[i].channels = channels
    pool.buffers[i].inUse = false

  pool.frameSize = newFrameSize

  # Log resize
  let bufferMB = newFrameSize.float / (1024.0 * 1024.0)
  let totalMB = bufferMB * pool.maxBuffers.float
  info fmt"Buffer pool resized: {pool.maxBuffers} x {bufferMB:.1f}MB = {totalMB:.0f}MB"

proc `=destroy`*(pool: var BufferPool) =
  ## Destructor - frees all allocated buffers
  ##
  ## Called automatically when BufferPool goes out of scope.
  ## Ensures all memory is properly released.

  for i in 0 ..< pool.buffers.len:
    if pool.buffers[i].data != nil:
      dealloc(pool.buffers[i].data)
      pool.buffers[i].data = nil

  pool.buffers.setLen(0)
  pool.acquiredCount = 0
