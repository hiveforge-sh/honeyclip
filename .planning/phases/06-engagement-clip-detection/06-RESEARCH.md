# Phase 6: Engagement Clip Detection - Research

**Researched:** 2026-02-02
**Domain:** Scene-aware clip extraction with engagement ranking for short-form content
**Confidence:** HIGH

## Summary

Phase 6 implements automatic detection of optimal clip boundaries and ranking by engagement score for batch export. The domain involves three technical areas: (1) scene boundary detection using FFmpeg's scdet filter, (2) clip ranking with overlap penalty to promote variety, and (3) efficient batch export using parallel FFmpeg processes or segment muxer.

The codebase already provides: engagement scoring with per-segment scores (Phase 5), FFmpeg scdet filter integration (used in faces.nim for adaptive sampling), transcript with sentence boundaries, and H.264 rendering infrastructure. Phase 6 combines these with clip boundary logic (scene changes + engagement drops + speech alignment), ranking algorithm (score-based with overlap penalty), and batch export workflow (detect → preview → export).

**Primary recommendation:** Use scdet filter for scene detection (threshold 0.4), combine with engagement drop threshold (~20 points) and sentence boundaries for clip splits, rank with overlap penalty (IoU > 0.3 reduces score), generate both H.264 MP4 clips and metadata (JSON + CMX3600 EDL), parallelize renders with 2-4 concurrent FFmpeg processes.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg scdet filter | 7.x | Scene change detection | Built-in FFmpeg filter, already used in faces.nim, efficient frame-based scoring |
| Nim stdlib json | 2.2.2+ | Metadata export | Built-in, sufficient for clip metadata with engagement breakdown |
| Nim stdlib os | 2.2.2+ | Process spawning for parallel render | Native process management, spawn multiple FFmpeg instances |
| FFmpeg segment muxer | 7.x | Batch clip extraction | 60-80% faster than multiple commands via single-pass processing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Nim stdlib osproc | 2.2.2+ | Process output capture | Monitor FFmpeg render progress for parallel jobs |
| Existing engagement.nim | Phase 5 | Per-segment scores | Already produces EngagementSegment objects with scores |
| Existing av.nim | - | H.264 encoder setup | initEncoder("libx264") or initEncoder(AV_CODEC_ID_H264) |
| CMX3600 EDL format | SMPTE 258M | Industry-standard interchange | Most widely compatible EDL format, 999 event limit sufficient |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FFmpeg scdet | OpenCV scene detection | OpenCV adds ML dependency, scdet is faster and sufficient for cuts/fades |
| Parallel FFmpeg | FFmpeg segment muxer | Segment muxer faster for contiguous segments, parallel better for ranked top-N clips |
| CMX3600 EDL | Final Cut Pro XML | XML more expressive but CMX3600 is "lowest common denominator" - broader compatibility |

**Installation:**
No additional dependencies required - all components available in FFmpeg (already built), Nim stdlib, or existing codebase (Phase 5 engagement scoring).

## Architecture Patterns

### Recommended Project Structure
```
src/
├── analyze/
│   └── clips.nim            # Clip boundary detection combining scene/engagement/speech
├── cmds/
│   └── clips.nim            # CLI command for clip detection & batch export
└── exports/
    ├── engagement_edl.nim   # CMX3600 EDL export with engagement metadata
    └── engagement_json.nim  # Already exists from Phase 5 (extend for clip list)
```

### Pattern 1: Multi-Signal Boundary Detection
**What:** Combine scene changes, engagement drops, and sentence boundaries to determine clip splits
**When to use:** Always - single signal produces poor boundaries (mid-sentence cuts, ignores engagement)
**Example:**
```nim
type
  ClipBoundary* = object
    timestampMs*: int64
    reason*: BoundaryReason  # SceneChange, EngagementDrop, SpeechBoundary

  BoundaryReason* = enum
    SceneChange       # scdet filter detected visual cut
    EngagementDrop    # Score dropped > threshold (e.g., 20 points)
    SpeechBoundary    # Sentence end, prevents mid-sentence cuts

proc detectBoundaries*(timeline: EngagementTimeline,
                       sceneChanges: seq[float64],  # Timestamps from scdet
                       engagementDropThreshold: float32 = 20.0): seq[ClipBoundary] =
  ## Combine signals: prefer scene changes, add engagement drops, refine with speech
  var boundaries: seq[ClipBoundary] = @[]

  # Add scene changes as primary boundaries
  for sceneTs in sceneChanges:
    boundaries.add(ClipBoundary(
      timestampMs: (sceneTs * 1000).int64,
      reason: SceneChange
    ))

  # Add engagement drops (major score changes)
  for i in 1 ..< timeline.segments.len:
    let scoreDrop = timeline.segments[i-1].score - timeline.segments[i].score
    if scoreDrop >= engagementDropThreshold:
      boundaries.add(ClipBoundary(
        timestampMs: timeline.segments[i].startMs,
        reason: EngagementDrop
      ))

  # Sort and merge nearby boundaries (within 2 seconds)
  boundaries.sort((a, b) => cmp(a.timestampMs, b.timestampMs))
  boundaries = mergeNearbyBoundaries(boundaries, windowMs = 2000)

  # Refine to align with sentence boundaries (avoid mid-sentence cuts)
  boundaries = alignToSentences(boundaries, timeline.segments)
```

### Pattern 2: Overlap-Aware Ranking
**What:** Rank clips by engagement score, penalize overlaps to promote variety
**When to use:** Always - prevents selecting 5 clips from same 2-minute segment
**Example:**
```nim
proc calculateIoU*(clipA, clipB: tuple[startMs, endMs: int64]): float32 =
  ## Calculate Intersection over Union (IoU) for two time ranges
  let intersectionStart = max(clipA.startMs, clipB.startMs)
  let intersectionEnd = min(clipA.endMs, clipB.endMs)
  let intersection = max(0, intersectionEnd - intersectionStart)

  let unionStart = min(clipA.startMs, clipB.startMs)
  let unionEnd = max(clipA.endMs, clipB.endMs)
  let union = unionEnd - unionStart

  if union == 0:
    return 0.0
  return intersection.float32 / union.float32

proc rankClips*(clips: seq[Clip], topN: int = 5,
                overlapThreshold: float32 = 0.3,
                overlapPenalty: float32 = 30.0): seq[Clip] =
  ## Rank clips with overlap penalty to promote variety
  var ranked: seq[Clip] = @[]
  var candidates = clips
  candidates.sort((a, b) => cmp(b.engagementScore, a.engagementScore))

  for candidate in candidates:
    if ranked.len >= topN:
      break

    # Calculate overlap penalty with already-selected clips
    var adjustedScore = candidate.engagementScore
    for selected in ranked:
      let iou = calculateIoU(
        (candidate.startMs, candidate.endMs),
        (selected.startMs, selected.endMs)
      )
      if iou > overlapThreshold:
        adjustedScore -= overlapPenalty * iou

    # Add if still has positive adjusted score
    if adjustedScore > 0 or ranked.len == 0:
      var rankedClip = candidate
      rankedClip.adjustedScore = adjustedScore
      ranked.add(rankedClip)

  ranked.sort((a, b) => cmp(b.adjustedScore, a.adjustedScore))
```

### Pattern 3: Parallel Batch Export
**What:** Spawn multiple FFmpeg processes to render clips concurrently
**When to use:** For top-N ranked clips (not contiguous segments)
**Example:**
```nim
import std/[osproc, os, strformat]

proc exportClipParallel*(inputPath: string, clip: Clip,
                        outputPath: string, codec: string = "libx264") =
  ## Spawn FFmpeg process to extract single clip
  let startTime = clip.startMs / 1000.0
  let duration = (clip.endMs - clip.startMs) / 1000.0

  let cmd = &"ffmpeg -ss {startTime} -t {duration} -i \"{inputPath}\" " &
            &"-c:v {codec} -preset fast -crf 23 " &
            &"-c:a aac -b:a 128k " &
            &"-movflags +faststart " &
            &"\"{outputPath}\""

  discard execProcess(cmd)

proc batchExportClips*(inputPath: string, clips: seq[Clip],
                       outputDir: string, maxConcurrent: int = 4) =
  ## Export clips in parallel with limited concurrency
  var processes: seq[Process] = @[]
  var completed = 0

  for i, clip in clips:
    let outputPath = outputDir / &"clip_{i+1}_{clip.startMs}ms-{clip.endMs}ms.mp4"

    # Wait for slot if at max concurrency
    while processes.len >= maxConcurrent:
      processes = processes.filterIt(it.running())
      if processes.len >= maxConcurrent:
        os.sleep(100)  # Check every 100ms

    # Start new render
    let process = startProcess("ffmpeg", args=[...])
    processes.add(process)

  # Wait for remaining processes
  for p in processes:
    discard p.waitForExit()
```

### Anti-Patterns to Avoid
- **Sequential renders:** Exporting clips one-by-one when they could be parallel - wastes CPU
- **Ignoring speech boundaries:** Cutting mid-sentence produces awkward clips
- **No overlap penalty:** Selecting 5 clips from same segment lacks variety
- **Re-encoding with `-c copy`:** Keyframe-only cuts produce inaccurate boundaries for short clips

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scene detection | Frame difference loop | FFmpeg scdet filter | scdet uses optimized histogram/pixel matching, handles fades/dissolves, already integrated in codebase |
| EDL generation | Custom text formatting | CMX3600 template | EDL has strict format (timecode, reel names, event numbers) - easy to get wrong |
| Parallel process management | Manual fork/wait | Nim osproc + semaphore pattern | Process cleanup, zombie handling, exit codes require care |
| Clip overlap detection | Nested time range loops | IoU (Intersection over Union) | IoU is standard metric, handles edge cases (partial overlap, containment) |
| Video segment extraction | Manual packet reading | FFmpeg segment muxer or -ss/-t flags | Keyframe seeking, timestamp rounding, A/V sync require expertise |

**Key insight:** Scene detection and video segmentation are FFmpeg's core strengths - don't reimplement frame processing when scdet filter and muxers exist.

## Common Pitfalls

### Pitfall 1: Inaccurate Clip Boundaries with Stream Copy
**What goes wrong:** Using `-c copy` with `-ss`/`-t` produces clips that start/end at nearest keyframe, not exact timestamp
**Why it happens:** Stream copy skips decoding, can only cut at I-frames (keyframes), which may be seconds apart
**How to avoid:** Always re-encode clips with libx264 for frame-accurate boundaries (required for 15-60 second clips)
**Warning signs:** Clips start/end at wrong points, duration doesn't match expected length

### Pitfall 2: Mid-Sentence Cuts
**What goes wrong:** Clips cut in the middle of a sentence, sound unnatural
**Why it happens:** Scene changes and engagement drops don't align with speech boundaries
**How to avoid:** After detecting boundaries, extend/trim to nearest sentence end using transcript
**Warning signs:** Clips start with "...and then he" or end mid-word

### Pitfall 3: Overlapping Top Clips (No Variety)
**What goes wrong:** Top 5 clips all come from same 2-minute high-engagement segment
**Why it happens:** Sorting by score alone doesn't consider temporal diversity
**How to avoid:** Apply overlap penalty (IoU-based score reduction for clips overlapping with higher-ranked ones)
**Warning signs:** User exports 5 clips that feel like the same moment repeated

### Pitfall 4: FFmpeg Process Leaks
**What goes wrong:** Parallel renders spawn processes that don't get cleaned up, eventually exhaust process limit
**Why it happens:** Exception during render leaves zombie processes, forgot to call waitForExit
**How to avoid:** Use defer blocks for process cleanup, check running() status, limit max concurrent processes
**Warning signs:** "too many open files" error, ps shows many zombie ffmpeg processes

### Pitfall 5: Scene Detection Too Sensitive
**What goes wrong:** scdet detects hundreds of "scenes" from camera shake, lighting changes, faces moving
**Why it happens:** Default scdet threshold (0.4) may be too low for handheld video
**How to avoid:** Tune threshold based on video type (0.4 for cuts, 0.6+ for handheld), combine with minimum clip duration filter
**Warning signs:** Clips are 2-3 seconds long, boundaries every few seconds

### Pitfall 6: Target Duration Without Flexibility
**What goes wrong:** Forcing clips to be exactly 30 seconds produces awkward cuts
**Why it happens:** Rigid duration constraint conflicts with natural content boundaries
**How to avoid:** Use target range (15-60 seconds), allow clips to end early if engagement drops
**Warning signs:** Clips have abrupt endings, user complains about unnatural pacing

## Code Examples

Verified patterns from FFmpeg documentation and existing codebase:

### Scene Detection with scdet Filter
```bash
# Extract scene change timestamps (used in adaptive sampling pattern)
# From faces.nim lines 191-199
ffmpeg -i input.mp4 \
  -vf "fps=5,scale=-1:480,format=bgr24,scdet=t=0.4:s=12" \
  -f null -

# Parse scdet metadata from frame metadata:
# lavfi.scd.score = 0.0-1.0 (scene change score)
# lavfi.scd.time = timestamp when score > threshold
```

### H.264 Encoding for Maximum Compatibility
```nim
# From av.nim patterns - initialize H.264 encoder
let (codec, encoderCtx) = initEncoder("libx264")

# Social media optimal settings (from research)
encoderCtx.bit_rate = 4_500_000  # 4.5 Mbps for 1080p30
encoderCtx.width = 1920
encoderCtx.height = 1080
encoderCtx.time_base = AVRational(num: 1, den: 30)
encoderCtx.framerate = AVRational(num: 30, den: 1)
encoderCtx.gop_size = 60  # Keyframe every 2 seconds (30fps * 2)
encoderCtx.max_b_frames = 2
encoderCtx.pix_fmt = AV_PIX_FMT_YUV420P

# Set H.264 profile for compatibility
let opts = newDictionary()
opts["profile"] = "high"
opts["level"] = "4.1"
opts["preset"] = "fast"
opts["crf"] = "23"  # Constant quality
opts["movflags"] = "+faststart"  # Enable streaming

if avcodec_open2(encoderCtx, codec, opts.addr) < 0:
  error "Could not open H.264 encoder"
```

### CMX3600 EDL Format
```nim
# CMX3600 EDL structure (from research)
proc exportCMX3600EDL*(clips: seq[Clip], outputPath: string, sourceName: string) =
  ## Export clips as CMX3600 EDL
  ## Format: SMPTE 258M-2004 standard
  var lines: seq[string] = @[]

  lines.add("TITLE: Engagement Clips")
  lines.add("")

  for i, clip in clips:
    let eventNum = (i + 1).toString.align(3, '0')  # 001, 002, etc.
    let reelName = sourceName[0..min(7, sourceName.len-1)].toUpperAscii()  # Max 8 chars

    let sourceIn = formatTimecode(clip.startMs)
    let sourceOut = formatTimecode(clip.endMs)
    let recordIn = formatTimecode(0)  # Start at 00:00:00:00
    let recordOut = formatTimecode(clip.endMs - clip.startMs)

    # Event line format:
    # EVENT REEL    EDIT_TYPE TRANSITION SOURCE_IN  SOURCE_OUT RECORD_IN  RECORD_OUT
    lines.add(&"{eventNum}  {reelName}  V     C        {sourceIn} {sourceOut} {recordIn} {recordOut}")
    lines.add(&"* ENGAGEMENT_SCORE: {clip.engagementScore:.1f}")
    lines.add(&"* FROM CLIP: {clip.text[0..min(60, clip.text.len-1)]}")
    lines.add("")

  writeFile(outputPath, lines.join("\n"))

proc formatTimecode*(ms: int64): string =
  ## Format milliseconds as SMPTE timecode HH:MM:SS:FF (at 30fps)
  let totalFrames = (ms * 30) div 1000
  let frames = totalFrames mod 30
  let totalSeconds = totalFrames div 30
  let seconds = totalSeconds mod 60
  let totalMinutes = totalSeconds div 60
  let minutes = totalMinutes mod 60
  let hours = totalMinutes div 60
  &"{hours:02}:{minutes:02}:{seconds:02}:{frames:02}"
```

### Parallel Batch Export Pattern
```nim
# Pattern from research: limit concurrent FFmpeg processes
import std/[osproc, os]

proc batchExport*(clips: seq[Clip], maxConcurrent: int = 4) =
  var activeProcesses: seq[tuple[process: Process, clipIndex: int]] = @[]

  for i, clip in clips:
    # Wait for available slot
    while activeProcesses.len >= maxConcurrent:
      # Check for completed processes
      var stillRunning: seq[tuple[process: Process, clipIndex: int]] = @[]
      for (p, idx) in activeProcesses:
        if p.running():
          stillRunning.add((p, idx))
        else:
          let exitCode = p.waitForExit()
          if exitCode != 0:
            echo &"Warning: Clip {idx} export failed with code {exitCode}"
      activeProcesses = stillRunning

      if activeProcesses.len >= maxConcurrent:
        os.sleep(100)  # Poll every 100ms

    # Start new export
    let process = startExport(clip, i)
    activeProcesses.add((process, i))

  # Wait for remaining
  for (p, idx) in activeProcesses:
    discard p.waitForExit()
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual clip selection | AI-powered clip detection | 2023-2024 | Tools like CapCut, Reap auto-detect engaging moments from long videos |
| Fixed 30-second clips | Variable-length with target range | 2025 | Platforms prioritize "meaningful watch time" over length; pacing matters more |
| TikTok: as short as possible | TikTok: 24-38 seconds optimal | 2026 | Algorithm evolved; 11-18s for virality, 21-34s for storytelling |
| Reels: 15-30 seconds | Reels: 7-45 seconds range | 2026 | Faster scrolling; 7-15s for trends, 30-45s for tips |
| YouTube Shorts: 60s max | YouTube Shorts: 50-58s optimal | 2026 | Maximize watch time without hitting limit |
| Min-max normalization | Percentile normalization | Phase 5 | More robust to outlier frames (black frames, flashes) |
| Word-level scores | Sentence-level scores | Phase 5 | Matches user perception, reduces jitter |

**Deprecated/outdated:**
- **Stream copy for short clips:** `-c copy` produces keyframe-only cuts (inaccurate for 15-60s clips)
- **Single signal boundary detection:** Scene changes alone ignore engagement, engagement alone ignores visual cuts
- **Sequential batch export:** 60-80% slower than parallel or segment muxer approaches

## Open Questions

Things that couldn't be fully resolved:

1. **Optimal engagement drop threshold for clip splits**
   - What we know: Should be significant enough to indicate content shift (research suggests ~20 points on 0-100 scale)
   - What's unclear: May vary by video type (interview vs action), no authoritative source
   - Recommendation: Start with 20.0 points, make configurable via flag, tune based on user feedback

2. **Parallel render concurrency level**
   - What we know: Nim osproc + manual process management, FFmpeg is CPU-bound for encoding
   - What's unclear: Optimal level depends on CPU cores, RAM, video resolution
   - Recommendation: Default to 4 concurrent processes, cap at 50% of CPU cores, make configurable

3. **EDL variant selection (CMX3600 vs alternatives)**
   - What we know: CMX3600 is "lowest common denominator", 999 event limit, 4-channel audio
   - What's unclear: Whether newer formats (GVG, Sony 9100) provide value for engagement metadata
   - Recommendation: Use CMX3600 (broadest compatibility), add engagement score as comments (* lines)

4. **Handling videos with no reasonable clips**
   - What we know: Some videos may have uniformly low engagement or no scene changes
   - What's unclear: Should we export anyway, error out, or return empty list?
   - Recommendation: Return empty list with warning "No clips met criteria (min score: X, min duration: Y)"

5. **Face priority weight in ranking**
   - What we know: User decision from CONTEXT.md says "configurable via flag"
   - What's unclear: Default weight, whether to boost ranking directly or use in score calculation
   - Recommendation: Apply face boost during scoring (already done in Phase 5), use configurable flag to enable/disable

## Sources

### Primary (HIGH confidence)
- [FFmpeg scdet filter documentation](https://ayosec.github.io/ffmpeg-filters-docs/6.0/Filters/Video/scdet.html) - Scene detection threshold settings, metadata output
- [FFmpeg Formats Documentation](https://ffmpeg.org/ffmpeg-formats.html) - Segment muxer capabilities
- [CMX 3600 EDL Format Overview](https://edlmax.com/EdlMaxHelp/Edl/Edl_Overview.htm) - Technical specifications, line format
- [H.264 Video Encoding Settings](https://www.lighterra.com/papers/videoencodingh264/) - Profile, level, quality settings
- [Nim threadpool documentation](https://nim-lang.org/docs/threadpool.html) - Parallel processing API
- Existing codebase: `src/analyze/faces.nim` (scdet filter usage), `src/analyze/engagement.nim` (scoring), `src/av.nim` (encoder setup)

### Secondary (MEDIUM confidence)
- [Ideal Video Length for TikTok, Reels & YouTube Shorts in 2026](https://joyspace.ai/ideal-video-length-social-platform-2026) - Platform-specific optimal lengths
- [FFmpeg: How to Split Video Efficiently](https://www.codegenes.net/blog/ffmpeg-how-to-split-video-efficiently/) - Segment muxer performance (60-80% faster)
- [Best Video Format & Codec for Social Media](https://pixflow.net/blog/the-creators-cheat-sheet-best-video-formats-codecs-for-social-media/) - H.264 MP4 compatibility
- [Batch Processing with FFmpeg](https://www.ffmpeg.media/articles/batch-processing-automate-multiple-files) - Parallel processing patterns

### Tertiary (LOW confidence)
- [Video clip overlap detection research](https://ieeexplore.ieee.org/document/4812560/) - Near-duplicate detection algorithms (IoU-based)
- [Vid2Seq research](https://research.google/blog/vid2seq-a-pretrained-visual-language-model-for-describing-multi-event-videos/) - Event boundary detection with speech alignment
- [Notes on scene detection with FFMPEG](https://gist.github.com/dudewheresmycode/054c8de34762091b43530af248b369e7) - Community best practices

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components exist in FFmpeg (scdet), Nim stdlib, or Phase 5 codebase
- Architecture: HIGH - Patterns verified with existing faces.nim (scdet), engagement.nim (scoring), av.nim (encoding)
- Pitfalls: HIGH - Scene detection sensitivity, stream copy inaccuracy, process leaks documented in FFmpeg/Nim communities
- Clip ranking: MEDIUM - IoU-based overlap penalty is research-backed but not authoritatively documented for video
- Optimal thresholds: MEDIUM - Platform length recommendations verified, engagement drop threshold extrapolated

**Research date:** 2026-02-02
**Valid until:** 2026-03-02 (30 days - stable domain, platform lengths evolve quarterly)
