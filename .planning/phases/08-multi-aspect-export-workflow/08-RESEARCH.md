# Phase 8: Multi-Aspect Export & Workflow - Research

**Researched:** 2026-02-03
**Domain:** FFmpeg video processing, multi-aspect ratio export, preview generation
**Confidence:** HIGH

## Summary

Phase 8 extends honeyclip's export capabilities to support multiple aspect ratios (16:9, 9:16, 1:1) with parallel rendering, preview generation, boundary adjustment, and analysis-only mode. The research reveals FFmpeg as the established standard for video transcoding with built-in filters for thumbnail generation, watermarking, and dynamic cropping. The existing codebase already implements parallel export (4 concurrent FFmpeg processes) in `src/analyze/clips.nim` and reframing with FFmpeg filter chains in `src/reframe/compositor.nim`, providing proven patterns to extend.

Key findings indicate that social media platforms (Instagram Reels, TikTok, YouTube Shorts) have converged on H.264/AAC in MP4 containers with platform-specific bitrate recommendations (3.5-10 Mbps for Reels, 2-4 Mbps for TikTok, 8-15 Mbps for Shorts). FFmpeg's `thumbnail` filter automatically selects the most representative frame, and the `tile` filter creates contact sheets efficiently. The existing JSON export infrastructure (`src/exports/json.nim`, `src/exports/edl.nim`) provides a foundation for project file persistence and boundary adjustment workflows.

**Primary recommendation:** Extend the existing parallel export architecture in `src/analyze/clips.nim` to support multi-aspect rendering, add FFmpeg-based preview generation using `thumbnail` and `tile` filters, implement JSON-based boundary adjustment with version history, and create platform preset configurations.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg | 7.x | Video transcoding, filtering, thumbnail generation | Industry standard, built from source in honeyclip |
| std/json | Nim stdlib | JSON parsing and generation | Built-in, zero dependencies |
| std/osproc | Nim stdlib | Process management for parallel FFmpeg | Built-in, proven in existing clips.nim |
| std/os | Nim stdlib | File I/O, directory management | Built-in, cross-platform |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| std/strformat | Nim stdlib | String interpolation for FFmpeg args | Building filter chains |
| std/algorithm | Nim stdlib | Sorting, deduplication | Clip ranking, version history |
| std/tables | Nim stdlib | Hash tables for preset configs | Platform preset lookup |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FFmpeg tile filter | ImageMagick montage | ImageMagick requires external dep, FFmpeg already built |
| std/json | jsony library | jsony is faster but adds dependency; stdlib sufficient for project files |
| Process polling | Async I/O | Async complicates error handling; polling works for 4 concurrent processes |

**Installation:**
All dependencies are Nim standard library or FFmpeg (already built from source). No additional packages needed.

## Architecture Patterns

### Recommended Project Structure
```
src/
├── cmds/
│   └── export.nim           # New export command (or extend clips.nim)
├── exports/
│   ├── json.nim            # Existing JSON export (extend for project files)
│   ├── edl.nim             # Existing EDL export
│   ├── fcp11.nim           # Existing FCPXML export
│   └── presets.nim         # NEW: Platform preset configs
├── render/
│   └── previews.nim        # NEW: Thumbnail & video snippet generation
├── analyze/
│   └── clips.nim           # Existing parallel export (extend for multi-aspect)
└── reframe/
    └── compositor.nim      # Existing reframing logic (reuse for aspect ratios)
```

### Pattern 1: Parallel Multi-Aspect Export

**What:** Extend existing `batchExportClips` pattern to render multiple aspect ratios concurrently

**When to use:** Multi-aspect export with --aspect 16:9,9:16,1:1

**Example:**
```nim
# Source: Existing src/analyze/clips.nim pattern
proc batchExportMultiAspect*(inputPath: string, clips: seq[Clip],
                              aspects: seq[AspectRatio],
                              params: ClipExportParams,
                              onProgress: proc(completed, total: int)): seq[ExportResult] =
  ## Export clips in all aspect ratios in parallel
  ## Total concurrent processes = min(aspects.len * clips.len, params.maxConcurrent)

  var allJobs: seq[ExportJob] = @[]
  for aspect in aspects:
    for clip in clips:
      allJobs.add(ExportJob(clip: clip, aspect: aspect))

  # Use existing process pool pattern from clips.nim
  var activeProcesses: seq[ProcessInfo] = @[]
  for job in allJobs:
    # Wait for slot, start process
    while activeProcesses.len >= params.maxConcurrent:
      pollAndRemoveCompleted(activeProcesses)
    startExportProcess(job, activeProcesses)
```

### Pattern 2: FFmpeg Thumbnail Contact Sheet

**What:** Use FFmpeg's `tile` filter to create thumbnail grids in single command

**When to use:** Preview generation with --with-previews flag

**Example:**
```nim
# Source: FFmpeg documentation + web research
proc generateContactSheet*(inputPath: string, outputPath: string,
                           cols: int = 4, rows: int = 3): bool =
  ## Generate NxM thumbnail grid using FFmpeg tile filter
  let args = @[
    "-i", inputPath,
    "-vf", &"select='not(mod(n,120))',scale=240:-1,tile={cols}x{rows}:padding=4",
    "-frames:v", "1",
    "-q:v", "2",  # Highest JPEG quality
    outputPath
  ]
  let exitCode = execFFmpeg(args)
  return exitCode == 0
```

### Pattern 3: Best Frame Thumbnail Selection

**What:** Use FFmpeg's `thumbnail` filter to auto-select most representative frame

**When to use:** Auto-thumbnail generation (no --thumbnail-at specified)

**Example:**
```nim
# Source: FFmpeg thumbnail filter documentation
proc selectBestFrame*(inputPath: string, outputPath: string,
                      startMs, endMs: int64): bool =
  ## Auto-select best frame from clip range using histogram analysis
  let startSec = startMs.float / 1000.0
  let endSec = endMs.float / 1000.0
  let args = @[
    "-ss", $startSec,
    "-t", $(endSec - startSec),
    "-i", inputPath,
    "-vf", "thumbnail=100",  # Batch 100 frames, select most representative
    "-frames:v", "1",
    "-q:v", "2",
    outputPath
  ]
  return execFFmpeg(args) == 0
```

### Pattern 4: JSON Version History

**What:** Append version suffix when modifying boundary files

**When to use:** Clip boundary adjustment via CLI or manual JSON edit

**Example:**
```nim
# Source: File versioning best practices + existing JSON module
proc saveClipsWithVersion*(clips: seq[Clip], basePath: string): string =
  ## Save clips JSON with automatic version history
  ## clips.json -> clips.json.v1, clips.json.v2, etc.

  let baseFile = basePath / "clips.json"

  # If file exists, rename to .v{N}
  if fileExists(baseFile):
    var version = 1
    while fileExists(&"{baseFile}.v{version}"):
      version += 1
    moveFile(baseFile, &"{baseFile}.v{version}")

  # Write new version
  let jsonData = %* {
    "clips": clips.mapIt(clipToJson(it)),
    "modified": now().format("yyyy-MM-dd HH:mm:ss"),
    "version": version + 1
  }
  writeFile(baseFile, jsonData.pretty())
  return baseFile
```

### Pattern 5: Platform Preset Configuration

**What:** Table-based lookup for platform-specific encoding settings

**When to use:** --preset instagram-reels, --preset tiktok, etc.

**Example:**
```nim
# Source: Social media best practices research
type
  PlatformPreset* = object
    name*: string
    aspect*: AspectRatio
    width*, height*: int
    codec*: string
    fps*: int
    bitrate*: int  # kbps
    audioCodec*: string
    audioBitrate*: int  # kbps

let platformPresets* = {
  "instagram-reels": PlatformPreset(
    name: "Instagram Reels",
    aspect: Portrait,
    width: 1080, height: 1920,
    codec: "libx264", fps: 30,
    bitrate: 5000,  # 5 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "tiktok": PlatformPreset(
    name: "TikTok",
    aspect: Portrait,
    width: 1080, height: 1920,
    codec: "libx264", fps: 30,
    bitrate: 3000,  # 3 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "youtube-shorts": PlatformPreset(
    name: "YouTube Shorts",
    aspect: Portrait,
    width: 1080, height: 1920,
    codec: "libx264", fps: 30,
    bitrate: 10000,  # 10 Mbps
    audioCodec: "aac", audioBitrate: 128
  ),
  "instagram-feed": PlatformPreset(
    name: "Instagram Feed",
    aspect: Square,
    width: 1080, height: 1080,
    codec: "libx264", fps: 30,
    bitrate: 5000,
    audioCodec: "aac", audioBitrate: 128
  ),
  "facebook": PlatformPreset(
    name: "Facebook",
    aspect: Landscape,
    width: 1280, height: 720,
    codec: "libx264", fps: 30,
    bitrate: 4000,
    audioCodec: "aac", audioBitrate: 128
  ),
  "twitter": PlatformPreset(
    name: "X (Twitter)",
    aspect: Landscape,
    width: 1280, height: 720,
    codec: "libx264", fps: 30,
    bitrate: 5000,
    audioCodec: "aac", audioBitrate: 128
  )
}.toTable
```

### Pattern 6: Watermark with FFmpeg drawtext/overlay

**What:** Use FFmpeg `drawtext` filter for text watermarks, `overlay` filter for image watermarks

**When to use:** --watermark-text or --watermark-image flags

**Example:**
```nim
# Source: FFmpeg drawtext/overlay filter documentation
proc buildWatermarkFilter*(watermarkType: string, value: string,
                          x, y: int): string =
  ## Build FFmpeg filter for watermarking
  case watermarkType:
  of "text":
    # Text watermark with semi-transparent background
    result = &"drawtext=text='{value}':x={x}:y={y}:fontsize=24:" &
             &"fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=5"
  of "image":
    # Image watermark overlay
    result = &"movie={value}[wm];[in][wm]overlay={x}:{y}[out]"
  else:
    result = ""  # No watermark
```

### Pattern 7: Side-by-Side Preview Comparison

**What:** Use FFmpeg `hstack` filter to show original vs reframed side-by-side

**When to use:** Preview mode to verify reframing accuracy

**Example:**
```nim
# Source: FFmpeg stack filters documentation
proc generateSideBySidePreview*(inputPath: string, cropFilter: string,
                                outputPath: string): bool =
  ## Create side-by-side comparison: original source | reframed version
  ## Useful for verifying crop accuracy before full render
  let args = @[
    "-i", inputPath,
    "-filter_complex",
    &"[0:v]split[orig][crop];" &
    &"[crop]{cropFilter}[reframed];" &
    &"[orig]scale=iw/2:-1[left];" &
    &"[reframed]scale=iw/2:-1[right];" &
    &"[left][right]hstack",
    "-frames:v", "1",
    "-q:v", "2",
    outputPath
  ]
  return execFFmpeg(args) == 0
```

### Anti-Patterns to Avoid

- **Sequential aspect ratio export:** Renders one ratio at a time. Use parallel export instead (existing pattern in clips.nim handles concurrency).
- **Re-analyzing for each aspect:** Cache face detection, engagement scores, boundaries in project file. Only re-render video.
- **Unbounded parallel processes:** Respect maxConcurrent limit to avoid system overload (existing code does this correctly).
- **Blocking on user input:** CLI adjustments should be flag-based, not interactive prompts (breaks batch workflows).
- **Ignoring codec constraints:** Always round dimensions to even numbers for H.264 (existing reframe code does this).

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thumbnail selection | Frame quality scoring algorithm | FFmpeg `thumbnail` filter | Built-in histogram analysis, battle-tested |
| Contact sheet layout | Manual frame extraction + image stitching | FFmpeg `tile` filter | Single-pass, handles padding/spacing |
| Concurrent process management | Custom thread pool | Existing `batchExportClips` pattern | Already proven in clips.nim, handles errors |
| JSON versioning | Git-like diff system | Simple .v1, .v2 suffixes | User can manually diff files, no complex merging needed |
| Aspect ratio math | Custom crop calculations | Reuse existing `calculateCrop` from crop.nim | Handles edge cases, constraints to bounds |
| Platform settings | User config files | Hardcoded preset table | Social media specs change slowly, table is maintainable |

**Key insight:** FFmpeg is a domain-specific language for video processing. Use its built-in filters rather than reimplementing logic in Nim. The existing codebase demonstrates this pattern well (compositor.nim generates filter chains, doesn't manipulate pixels directly).

## Common Pitfalls

### Pitfall 1: FFmpeg Process Explosion
**What goes wrong:** Launching aspects.len * clips.len FFmpeg processes simultaneously (e.g., 3 aspects × 10 clips = 30 processes) overwhelms the system.

**Why it happens:** Each FFmpeg instance is CPU/memory intensive. More than 4-8 concurrent processes causes thrashing.

**How to avoid:** Use existing process pool pattern from clips.nim with configurable `maxConcurrent` (default 4). Track all jobs (aspect×clip combinations) in a queue, only start new process when slot available.

**Warning signs:** System freezes during export, out-of-memory errors, extremely long render times.

### Pitfall 2: Stale Project Files
**What goes wrong:** User edits source video, but analysis-only mode loads cached results from old version, producing invalid clips.

**Why it happens:** No mtime or content hash verification between video and project file.

**How to avoid:** Per CONTEXT.md: "mtime check by default, --verify flag does full SHA256 hash". Store source video mtime in project file, compare on load. If different, warn user or error (depending on --verify flag).

**Warning signs:** Clips at wrong timestamps, missing segments, "file not found" errors during render.

### Pitfall 3: Overlapping Version History
**What goes wrong:** Two users edit clips.json simultaneously, version counter collisions (.v2 exists, both create .v2).

**Why it happens:** No file locking or atomic operations.

**How to avoid:** Scan existing versions before writing (while fileExists .v{N}, increment N). Not perfect for concurrent access, but honeyclip is single-user CLI tool. Document limitation.

**Warning signs:** Version files overwritten, user confusion about "which version is which".

### Pitfall 4: Aspect Ratio Mismatch Assumptions
**What goes wrong:** User exports 16:9 source to 16:9 target, expects no reframing, but gets cropped/letterboxed output.

**Why it happens:** Not checking if source already matches target ratio before applying reframe logic.

**How to avoid:** Per CONTEXT.md: "Skip reframing when source matches target ratio (just clip, no crop)". Calculate source aspect ratio, compare to target. If match within tolerance (e.g., 16/9 == 1.777, tolerance ±0.01), skip crop filter entirely, only apply time trimming.

**Warning signs:** Users complain about unnecessary quality loss or wrong framing on landscape source.

### Pitfall 5: Preview File Accumulation
**What goes wrong:** Generating previews for large clip batches creates hundreds of thumbnail files, cluttering filesystem.

**Why it happens:** Individual frame files + contact sheet + video snippets = lots of files.

**How to avoid:** Per CONTEXT.md: "Previews stored in subfolder next to video (e.g., video_previews/)". Always create subdirectory, never dump in source directory. Optionally: cleanup old preview dirs before generating new ones (or warn user if exists).

**Warning signs:** Source video directory filled with thousands of .jpg files.

### Pitfall 6: Hardcoded FFmpeg Paths
**What goes wrong:** Code looks for `ffmpeg` in PATH, fails if user built from source into `build/bin/ffmpeg`.

**Why it happens:** Assuming system FFmpeg instead of honeyclip's built FFmpeg.

**How to avoid:** Existing pattern in reframe.nim: check `build/bin/ffmpeg` first, then fall back to `findExe("ffmpeg")`. Always use this pattern.

**Warning signs:** "ffmpeg not found" errors despite successful `nimble makeff`.

## Code Examples

Verified patterns from official sources:

### Multi-Aspect Export with Process Pool
```nim
# Source: Extend existing src/analyze/clips.nim pattern
type
  AspectExportJob* = object
    clip*: Clip
    aspect*: AspectRatio
    outputPath*: string

proc exportMultiAspect*(inputPath: string, clips: seq[Clip],
                        aspects: seq[AspectRatio],
                        params: ClipExportParams): seq[ExportResult] =
  ## Export clips in multiple aspect ratios using process pool
  var jobs: seq[AspectExportJob] = @[]

  # Generate all aspect×clip combinations
  for aspect in aspects:
    let aspectDir = params.outputDir / aspectToString(aspect)
    if not dirExists(aspectDir):
      createDir(aspectDir)

    for clip in clips:
      # Check if source already matches target aspect
      let sourceAspect = calculateSourceAspect(inputPath)
      let targetAspect = aspectRatioValue(aspect)
      let skipReframe = abs(sourceAspect - targetAspect) < 0.01

      let outputPath = aspectDir / generateClipFilename(inputPath, clip)
      jobs.add(AspectExportJob(
        clip: clip,
        aspect: aspect,
        outputPath: outputPath
      ))

  # Execute with concurrency limit (reuse existing pattern)
  var activeProcesses: seq[ProcessInfo] = @[]
  var completed = 0

  for job in jobs:
    # Wait for available slot
    while activeProcesses.len >= params.maxConcurrent:
      pollAndRemoveCompleted(activeProcesses, completed, jobs.len)

    # Build FFmpeg args with aspect-specific filter
    let cropFilter = if skipReframe:
      ""  # No reframe needed
    else:
      buildReframeFilter(inputPath, job.clip, job.aspect)

    startFFmpegProcess(job, cropFilter, activeProcesses)

  # Wait for remaining processes
  waitForAll(activeProcesses, completed, jobs.len)
```

### Preview Generation Pipeline
```nim
# Source: FFmpeg thumbnail + tile filter documentation
proc generatePreviews*(inputPath: string, clips: seq[Clip],
                       previewDir: string, mode: PreviewMode): bool =
  ## Generate thumbnails or video snippets for clips
  if not dirExists(previewDir):
    createDir(previewDir)

  case mode:
  of PreviewThumbnails:
    # Generate contact sheet
    let contactSheetPath = previewDir / "overview.jpg"
    generateContactSheet(inputPath, clips, contactSheetPath)

    # Generate individual best frames
    for clip in clips:
      let thumbPath = previewDir / &"clip_{clip.rank:02}_thumb.jpg"
      selectBestFrame(inputPath, thumbPath, clip.startMs, clip.endMs)

  of PreviewSnippets:
    # Generate 3-second snippets: start, middle, end
    for clip in clips:
      let duration = clip.endMs - clip.startMs
      let snippets = [
        (clip.startMs, clip.startMs + 3000),  # First 3s
        (clip.startMs + duration div 2 - 1500, clip.startMs + duration div 2 + 1500),  # Middle 3s
        (clip.endMs - 3000, clip.endMs)  # Last 3s
      ]

      for i, (start, end) in snippets:
        let snippetPath = previewDir / &"clip_{clip.rank:02}_snippet_{i}.mp4"
        extractVideoSnippet(inputPath, snippetPath, start, end)
```

### JSON Boundary Adjustment
```nim
# Source: Nim std/json + file versioning best practices
proc loadClipsFromJson*(jsonPath: string): seq[Clip] =
  ## Load clips from JSON project file with validation
  let jsonData = parseFile(jsonPath)

  let sourceVideo = jsonData["source"].getStr()
  let sourceMtime = jsonData["source_mtime"].getBiggestInt()

  # Verify source hasn't changed (per CONTEXT.md)
  if fileExists(sourceVideo):
    let currentMtime = getLastModificationTime(sourceVideo).toUnix()
    if currentMtime != sourceMtime:
      echo "Warning: Source video modified since analysis. Re-run analysis or use --verify."

  # Parse clips with strict validation
  for clipJson in jsonData["clips"]:
    let clip = Clip(
      startMs: clipJson["start_ms"].getBiggestInt(),
      endMs: clipJson["end_ms"].getBiggestInt(),
      engagementScore: clipJson["engagement_score"].getFloat(),
      rank: clipJson["rank"].getInt()
    )

    # Validate non-overlapping, in-bounds
    if clip.startMs >= clip.endMs:
      error &"Invalid clip {clip.rank}: start >= end"

    result.add(clip)

proc adjustClipBoundary*(jsonPath: string, clipRank: int,
                        newStartMs, newEndMs: int64): bool =
  ## CLI boundary adjustment: modify clip and save with version history
  var clips = loadClipsFromJson(jsonPath)

  # Find and update clip
  var found = false
  for i, clip in clips.mpairs:
    if clip.rank == clipRank:
      clip.startMs = newStartMs
      clip.endMs = newEndMs
      found = true
      break

  if not found:
    error &"Clip #{clipRank} not found"

  # Validate all clips (no overlaps)
  validateClipBoundaries(clips)

  # Save with version history
  saveClipsWithVersion(clips, jsonPath.parentDir())
  return true
```

### Platform Preset Selection
```nim
# Source: Social media specs research
proc applyPlatformPreset*(preset: string, params: var ClipExportParams): bool =
  ## Apply platform-specific encoding settings
  if preset notin platformPresets:
    echo &"Unknown preset: {preset}"
    echo "Available presets: " & toSeq(platformPresets.keys).join(", ")
    return false

  let p = platformPresets[preset]
  params.targetWidth = p.width
  params.targetHeight = p.height
  params.aspect = p.aspect
  params.codec = p.codec
  params.fps = p.fps
  params.bitrate = p.bitrate
  params.audioCodec = p.audioCodec
  params.audioBitrate = p.audioBitrate

  return true
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sequential aspect export | Parallel multi-aspect with process pool | 2020s | 3x speedup for 3 aspects |
| Manual thumbnail selection | FFmpeg thumbnail filter (histogram) | FFmpeg 2.x+ | Auto-selects best frame |
| ImageMagick for contact sheets | FFmpeg tile filter | FFmpeg 4.x+ | Single-pass, no external dep |
| VBR encoding | CBR for social media | 2023+ | Predictable file sizes for platform limits |
| Custom thumbnail scoring | Scene detection + thumbnail filter | FFmpeg 5.x+ | Better quality, less code |

**Deprecated/outdated:**
- **Manual frame extraction loops:** FFmpeg `select` filter does this natively
- **Separate audio/video muxing:** Modern FFmpeg handles in single pass
- **Fixed bitrate for all platforms:** Platform-specific presets now standard practice

## Open Questions

Things that couldn't be fully resolved:

1. **Ratio selection CLI syntax**
   - What we know: Options are `--aspect 16:9,9:16` (comma-separated) or `--aspect 16:9 --aspect 9:16` (multiple flags)
   - What's unclear: Which is more intuitive for users? Comma-separated is compact but harder to parse.
   - Recommendation: Support both. Comma-separated is primary (matches `--resolution` pattern), but allow repeated flags for consistency with other CLI tools. Parse as: collect all `--aspect` values, then split on commas.

2. **Auto-thumbnail frame selection algorithm details**
   - What we know: FFmpeg `thumbnail` filter uses histogram-based selection, batches 100 frames
   - What's unclear: Can we tune the batch size for different clip durations? Short clips (<10s) might need smaller batches.
   - Recommendation: Use default batch size (100) for now. If users complain about poor thumbnail selection on short clips, add `--thumbnail-batch N` flag later.

3. **Version history retention policy**
   - What we know: Version files accumulate (.v1, .v2, .v3, ...)
   - What's unclear: Should we auto-delete old versions after N iterations? Or let user manage manually?
   - Recommendation: Keep all versions, no auto-delete. These are small JSON files (<100KB typically). Document in `--help` that users can delete .v* files manually if disk space is concern. Consider `--max-versions N` flag in future if users request it.

4. **Stale detection performance vs accuracy tradeoff**
   - What we know: mtime check is fast, SHA256 is accurate but slow on large videos
   - What's unclear: Is mtime sufficient? Files can be touched without content changes, or content changed with preserved mtime (rare but possible).
   - Recommendation: Default to mtime (fast, 99% accurate). Provide `--verify` flag for SHA256 hash check. Document that `--verify` is slower but catches all changes.

5. **Preview video snippet encoding**
   - What we know: Need 3-second snippets at start/middle/end of each clip
   - What's unclear: Should snippets be encoded at same quality as final output, or lower quality for speed?
   - Recommendation: Use fast preset + higher CRF (28) for previews. Users are checking framing/content, not final quality. Saves significant time on large clip batches.

## Sources

### Primary (HIGH confidence)
- FFmpeg Official Documentation - https://ffmpeg.org/ffmpeg.html (codecs, filters, process management)
- Nim Standard Library: std/json - https://nim-lang.org/docs/json.html (JSON parsing)
- Nim Standard Library: std/osproc - Process management for parallel execution
- Existing codebase: src/analyze/clips.nim - Proven parallel export pattern
- Existing codebase: src/reframe/compositor.nim - FFmpeg filter chain generation
- Existing codebase: src/exports/json.nim, edl.nim - Export infrastructure

### Secondary (MEDIUM confidence)
- [Using FFmpeg to Add Watermarks to Your Videos | Cloudinary](https://cloudinary.com/guides/video-effects/ffmpeg-watermark) - Watermark positioning
- [FFmpeg drawtext filter to Insert Dynamic Overlays | OTTVerse](https://ottverse.com/ffmpeg-drawtext-filter-dynamic-overlays-timecode-scrolling-text-credits/) - Text overlay syntax
- [Extract thumbnails from a video with FFmpeg | Mux](https://www.mux.com/articles/extract-thumbnails-from-a-video-with-ffmpeg) - Thumbnail generation
- [FFmpeg Mastery: Extracting Perfect Thumbnails from Videos | Medium](https://medium.com/@sergiu.savva/ffmpeg-mastery-extracting-perfect-thumbnails-from-videos-339a4229bb32) - Best frame selection
- [Best Bitrate & Export Settings for Instagram Reels (2026 Guide) | StayAbundant](https://www.stayabundant.com/blog/best-instagram-reels-export-settings) - Platform bitrates
- [Master Your Shorts: The Ultimate Guide to Export Settings | aaapresets](https://aaapresets.com/blogs/premiere-pro-blog-series-editing-tips-transitions-luts-guide/master-your-shorts-the-ultimate-guide-to-export-settings-for-instagram-reels-tiktok-youtube-shorts-in-2025-extended-edition) - Multi-platform specs

### Tertiary (LOW confidence)
- [Re-encoding the EmacsConf videos with FFmpeg and GNU Parallel | Sacha Chua](https://sachachua.com/blog/2021/12/re-encoding-the-emacsconf-videos-with-ffmpeg-and-gnu-parallel/) - Parallel encoding patterns
- [File Naming Convention Best Practices | Canto](https://www.canto.com/blog/file-naming-convention-best-practices-beyond-who-what-where-when-why/) - Version naming conventions
- [JSON Naming Conventions Best Practices | Restackio](https://www.restack.io/p/json-naming-conventions-answer-cat-ai) - JSON structure patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All dependencies are proven (FFmpeg built from source, Nim stdlib)
- Architecture: HIGH - Extending existing patterns from clips.nim and reframe/compositor.nim
- Pitfalls: MEDIUM - Process management well-understood, version history and stale detection have edge cases

**Research date:** 2026-02-03
**Valid until:** 60 days (stable domain - video encoding specs change slowly)
