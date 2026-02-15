# Phase 18: Chapter Detection - Research

**Researched:** 2026-02-14
**Domain:** Video chapter generation, scene change detection, engagement peak detection, FFmpeg chapter metadata
**Confidence:** HIGH

## Summary

Chapter detection combines scene change analysis with engagement scoring to automatically generate navigable video chapters. The standard approach uses FFmpeg's `scdet` filter for scene detection, existing engagement scores from Phase 17 for peak detection, and the ffmetadata format for MP4 chapter export. NLE marker export is already implemented in Phase 9.

Honeyclip already has the core components: engagement scoring (`src/analyze/engagement.nim`), marker export infrastructure (`src/exports/markers.nim`), and NLE format exporters (FCP7/FCPXML in `fcp7.nim`/`fcp11.nim`, EDL in `edl.nim`). The new work is: (1) scene detection via FFmpeg filters, (2) peak detection algorithm over engagement timeline, (3) chapter generation combining both signals, and (4) extending metadata module to export chapters.

Two distinct chapter modes: **scene-based** (visual cuts, transitions) and **engagement-based** (high-scoring moments). Both produce chapter markers exportable as MP4 metadata or NLE markers.

**Primary recommendation:** Use FFmpeg `scdet` filter for scene detection (threshold-based, proven), apply peak detection to existing engagement scores (local maxima with minimum spacing), generate chapters via existing metadata module (Phase 14), reuse marker export from Phase 9 for NLE integration.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg scdet filter | 7.0+ | Scene change detection | Built-in, fast, threshold-based detection |
| FFmpeg ffmetadata | 7.0+ | MP4 chapter metadata | Standard format for chapter markers in MP4/MOV |
| Existing engagement scorer | Phase 17 | Engagement timeline | Multi-modal scoring already implemented |
| Existing marker types | Phase 9 | Marker data structures | Already defines MarkerType, color coding |
| Existing metadata module | Phase 14 | Chapter export to MP4 | ChapterMarker type, ffmetadata generation |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| PySceneDetect | 0.6+ | Advanced scene detection | Reference only - FFmpeg sufficient for honeyclip |
| Existing NLE exporters | Phase 9 | FCP/Premiere/Resolve | Already export markers, reuse for chapters |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FFmpeg scdet | PySceneDetect | PySceneDetect has more algorithms but adds Python dependency, subprocess overhead |
| FFmpeg scdet | OpenCV-based detection | More control but slower, requires ML inference, scdet is proven |
| Peak detection | Fixed percentile | Percentile doesn't adapt to engagement distribution, peaks work better |
| ffmetadata | AVChapter API | AVChapter requires new FFmpeg bindings, ffmetadata is proven (Phase 14) |

**Installation:**
No additional dependencies - uses existing FFmpeg, engagement scoring, and metadata modules.

## Architecture Patterns

### Recommended Project Structure
```
src/analyze/
├── engagement.nim      # EXISTING: Engagement timeline
├── scene.nim          # NEW: Scene change detection
└── chapters.nim       # NEW: Chapter generation logic

src/metadata/
├── types.nim          # EXISTING: ChapterMarker type
├── apply.nim          # EXISTING: ffmetadata generation
└── parser.nim         # EXISTING: Template parsing

src/cmds/
└── chapters.nim       # NEW: CLI command for chapter generation
```

### Pattern 1: Scene Detection via FFmpeg scdet Filter
**What:** Use FFmpeg's built-in scene change detector to find visual cuts
**When to use:** Scene-based chapter generation
**Example:**
```nim
# Source: FFmpeg scdet filter documentation
# https://ffmpeg.org/ffmpeg-filters.html#scdet-1

proc detectScenes*(container: InputContainer, path: string,
                   threshold: float = 10.0, minSceneDurationMs: int64 = 5000): seq[int64] =
  ## Detect scene changes using FFmpeg scdet filter
  ## Returns list of scene boundary timestamps in milliseconds
  ##
  ## Args:
  ##   threshold: Scene change threshold (0-100, default 10.0)
  ##              Lower = more sensitive, higher = fewer detections
  ##   minSceneDurationMs: Minimum scene duration to filter short cuts

  # FFmpeg scdet outputs scene scores to stderr or file
  # Filter: scdet=t=0.1:s=1
  #   t = threshold (0.0-1.0, we divide by 100)
  #   s = scene score output (1 = yes)

  var sceneTimes: seq[int64] = @[]

  # Use videoPipeline with scdet filter (similar to motion.nim pattern)
  # Parse metadata from frames or use -f null with -show_frames

  # Filter short scenes
  var filtered: seq[int64] = @[]
  if sceneTimes.len > 0:
    filtered.add(sceneTimes[0])

  for i in 1..<sceneTimes.len:
    if sceneTimes[i] - filtered[^1] >= minSceneDurationMs:
      filtered.add(sceneTimes[i])

  return filtered
```

### Pattern 2: Engagement Peak Detection
**What:** Find local maxima in engagement timeline with minimum spacing
**When to use:** Engagement-based chapter generation
**Example:**
```nim
# Source: Standard peak detection algorithm
# Used in signal processing, time-series analysis

proc detectEngagementPeaks*(timeline: EngagementTimeline,
                             minSpacingMs: int64 = 30000,
                             minScore: float32 = 60.0,
                             maxPeaks: int = 10): seq[int64] =
  ## Find engagement peaks for chapter markers
  ##
  ## Args:
  ##   minSpacingMs: Minimum time between peaks (default 30s)
  ##   minScore: Minimum engagement score threshold
  ##   maxPeaks: Maximum number of peaks to return
  ##
  ## Returns: Timestamps of peak moments in milliseconds

  type Peak = tuple[timestamp: int64, score: float32]
  var candidates: seq[Peak] = @[]

  # Find local maxima (score higher than neighbors)
  for i in 1..<timeline.segments.len - 1:
    let curr = timeline.segments[i]
    let prev = timeline.segments[i-1]
    let next = timeline.segments[i+1]

    if curr.score >= minScore and
       curr.score > prev.score and
       curr.score > next.score:
      candidates.add((curr.startMs, curr.score))

  # Sort by score descending
  candidates.sort(proc(a, b: Peak): int =
    cmp(b.score, a.score))

  # Apply minimum spacing constraint
  var selected: seq[int64] = @[]
  for peak in candidates:
    var tooClose = false
    for existing in selected:
      if abs(peak.timestamp - existing) < minSpacingMs:
        tooClose = true
        break

    if not tooClose:
      selected.add(peak.timestamp)

    if selected.len >= maxPeaks:
      break

  # Return chronologically sorted
  selected.sort()
  return selected
```

### Pattern 3: Chapter Generation Combining Signals
**What:** Merge scene boundaries and engagement peaks into unified chapter list
**When to use:** Generating final chapter markers for export
**Example:**
```nim
# Source: Honeyclip pattern - combines multiple signals like engagement.nim

type ChapterSource* = enum
  csScene         ## From scene change detection
  csEngagement    ## From engagement peak detection
  csManual        ## User-specified via template

type Chapter* = object
  startMs*: int64
  endMs*: int64
  title*: string
  source*: ChapterSource
  score*: float32  # Engagement score if from engagement peak

proc generateChapters*(sceneTimes: seq[int64],
                       engagementPeaks: seq[int64],
                       timeline: EngagementTimeline,
                       mode: string = "combined"): seq[Chapter] =
  ## Generate chapters from scene and engagement signals
  ##
  ## Modes:
  ##   "scene" - Scene boundaries only
  ##   "engagement" - Engagement peaks only
  ##   "combined" - Merge both (default)

  var chapters: seq[Chapter] = @[]

  case mode:
  of "scene":
    for i, time in sceneTimes:
      let endMs = if i < sceneTimes.len - 1: sceneTimes[i+1]
                  else: timeline.duration
      chapters.add(Chapter(
        startMs: time,
        endMs: endMs,
        title: "Scene " & $(i + 1),
        source: csScene
      ))

  of "engagement":
    # Find engagement score at each peak
    for i, peakTime in engagementPeaks:
      # Find segment containing this timestamp
      var score = 0.0f
      for seg in timeline.segments:
        if peakTime >= seg.startMs and peakTime < seg.endMs:
          score = seg.score
          break

      chapters.add(Chapter(
        startMs: peakTime,
        endMs: peakTime + 1000, # 1 second marker
        title: "Peak #" & $(i + 1),
        source: csEngagement,
        score: score
      ))

  of "combined":
    # Merge both sources, deduplicate nearby markers
    # Add scene chapters
    var allMarkers: seq[tuple[time: int64, source: ChapterSource, score: float32]] = @[]

    for time in sceneTimes:
      allMarkers.add((time, csScene, 0.0f))

    for peakTime in engagementPeaks:
      var score = 0.0f
      for seg in timeline.segments:
        if peakTime >= seg.startMs and peakTime < seg.endMs:
          score = seg.score
          break
      allMarkers.add((peakTime, csEngagement, score))

    # Sort by time
    allMarkers.sort(proc(a, b: auto): int = cmp(a.time, b.time))

    # Deduplicate: if scene and engagement marker within 5s, keep engagement
    const DedupeWindowMs = 5000
    var i = 0
    while i < allMarkers.len:
      let marker = allMarkers[i]

      # Check if next marker is within dedupe window
      if i < allMarkers.len - 1:
        let next = allMarkers[i+1]
        if next.time - marker.time < DedupeWindowMs:
          # Keep engagement marker over scene marker
          if marker.source == csEngagement:
            allMarkers.delete(i+1)
          else:
            allMarkers.delete(i)
          continue

      i += 1

    # Convert to chapters
    for i, marker in allMarkers:
      let endMs = if i < allMarkers.len - 1: allMarkers[i+1].time
                  else: timeline.duration

      let title = if marker.source == csEngagement:
                    "Peak #" & $(i+1)
                  else:
                    "Scene " & $(i+1)

      chapters.add(Chapter(
        startMs: marker.time,
        endMs: endMs,
        title: title,
        source: marker.source,
        score: marker.score
      ))

  return chapters
```

### Pattern 4: Chapter Export via Existing Metadata Module
**What:** Convert Chapter objects to ChapterMarker and use Phase 14 metadata export
**When to use:** Exporting chapters to MP4 or standalone ffmetadata file
**Example:**
```nim
# Source: Phase 14 metadata module pattern
# Reuse existing ChapterMarker type and generateFFMetadata

import metadata/types
import metadata/apply

proc exportChaptersToMP4*(chapters: seq[Chapter],
                          videoPath: string,
                          outputPath: string) =
  ## Apply chapters to video as MP4 metadata

  # Convert to metadata ChapterMarker format
  var template = newMetadataTemplate()

  for chapter in chapters:
    template.chapters.add(ChapterMarker(
      startMs: chapter.startMs,
      endMs: chapter.endMs - 1,  # FFmpeg expects END to be last frame
      title: chapter.title
    ))

  # Generate ffmetadata file
  let metadataPath = writeFFMetadataFile(template)

  # Apply to video via FFmpeg
  # ffmpeg -i input.mp4 -i metadata.txt -map_metadata 1 -codec copy output.mp4
  let cmd = &"ffmpeg -i {videoPath} -i {metadataPath} " &
            &"-map_metadata 1 -codec copy {outputPath}"

  discard execShellCmd(cmd)

proc exportChaptersToNLE*(chapters: seq[Chapter],
                          format: string = "fcpxml"): seq[Marker] =
  ## Convert chapters to NLE markers (reuse Phase 9 infrastructure)

  var markers: seq[Marker] = @[]

  for chapter in chapters:
    let markerType = if chapter.source == csEngagement:
                       mtEngagementPeak
                     else:
                       mtSceneBoundary

    markers.add(Marker(
      markerType: markerType,
      timestampMs: chapter.startMs,
      durationMs: chapter.endMs - chapter.startMs,
      name: chapter.title,
      comment: if chapter.source == csEngagement:
                 &"Score: {chapter.score.int}/100"
               else:
                 "Scene boundary",
      color: getMarkerColor(markerType)
    ))

  return markers

  # Then pass to existing NLE exporters:
  # - addMarkersFCPXML() for FCPXML
  # - addMarkersFCP7() for FCP7 XML
  # - addMarkersEDL() for EDL
```

### Anti-Patterns to Avoid
- **Hand-rolling scene detection:** FFmpeg scdet is proven and fast, don't reimplement
- **Fixed chapter intervals:** Chapters at rigid 5-minute marks ignore content structure
- **Ignoring minimum spacing:** Too many chapters (every 10s) defeats navigation purpose
- **Mixing chapter sources without deduplication:** Scene change + engagement peak 2s apart creates redundant markers
- **Forgetting END = last frame:** FFmpeg expects chapter END to be one millisecond before next START

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scene change detection | Custom frame diff algorithm | FFmpeg scdet filter | Handles fades, dissolves, threshold tuning already solved |
| Peak finding | Custom maxima search | Standard local maxima + spacing filter | Edge cases (plateaus, noise) already handled |
| Chapter metadata format | Custom chapter file | FFmpeg ffmetadata (Phase 14) | Standard format, already implemented |
| NLE marker export | New marker exporters | Existing Phase 9 marker infrastructure | FCP/Premiere/Resolve already supported |
| Chapter deduplication | Manual distance checks | Sort + sliding window with threshold | Handles overlapping sources correctly |

**Key insight:** Scene detection and peak finding are solved problems with proven algorithms. FFmpeg's scdet handles visual analysis edge cases (gradual fades, color shifts), and engagement peaks use standard signal processing techniques.

## Common Pitfalls

### Pitfall 1: Scene Detection Threshold Too Sensitive
**What goes wrong:** Every camera movement triggers a chapter, creating hundreds of useless markers
**Why it happens:** Default scdet threshold (10.0) may be too low for handheld or action footage
**How to avoid:**
- Start with threshold=10.0 for clean footage, 15.0 for handheld
- Add `minSceneDurationMs` filter to ignore short cuts
- Test with different video styles (static interview vs vlog vs action)
**Warning signs:** 100+ chapters in a 10-minute video, chapters every 2-3 seconds

### Pitfall 2: Engagement Peaks Too Close Together
**What goes wrong:** Chapters at 0:30, 0:35, 0:42 defeat navigation purpose
**Why it happens:** Engagement scores can have multiple local maxima in short windows
**How to avoid:**
- Enforce `minSpacingMs` of 30-60 seconds between peaks
- Sort candidates by score and greedily select non-overlapping peaks
- Consider limiting total peaks (e.g., max 10-15 per video)
**Warning signs:** User feedback about "too many chapters", chapters hard to distinguish

### Pitfall 3: Chapter Titles Not Descriptive
**What goes wrong:** All chapters named "Chapter 1", "Chapter 2" provide no context
**Why it happens:** Auto-generated titles need more metadata than just sequence number
**How to avoid:**
```nim
# Better chapter titles using engagement context
proc generateChapterTitle(chapter: Chapter, timeline: EngagementTimeline): string =
  if chapter.source == csEngagement:
    let label = labelForScore(chapter.score)  # "High engagement", etc.
    return &"Peak #{chapter.rank} - {label}"
  else:
    # Could use transcript text from segment
    for seg in timeline.segments:
      if chapter.startMs >= seg.startMs and chapter.startMs < seg.endMs:
        let preview = seg.text[0..<min(seg.text.len, 30)]
        return &"Scene: {preview}..."
    return &"Scene {chapter.rank}"
```
**Warning signs:** User feedback about generic titles, chapters not useful for navigation

### Pitfall 4: ffmetadata END Timestamp Off-By-One
**What goes wrong:** FFmpeg rejects chapter metadata or chapters overlap incorrectly
**Why it happens:** ffmetadata expects END to be last frame, not first frame of next chapter
**How to avoid:**
```nim
# WRONG: Uses next chapter start as END
ChapterMarker(startMs: 0, endMs: 30000, title: "Intro")
ChapterMarker(startMs: 30000, endMs: 60000, title: "Main")  # Overlaps!

# CORRECT: END is one millisecond before next START
ChapterMarker(startMs: 0, endMs: 29999, title: "Intro")
ChapterMarker(startMs: 30000, endMs: 59999, title: "Main")
```
**Warning signs:** FFmpeg warnings about overlapping chapters, chapter navigation jumps incorrectly

### Pitfall 5: Ignoring Video Duration for Last Chapter
**What goes wrong:** Last chapter has END = 0 or END > video duration
**Why it happens:** No "next chapter" to define endpoint
**How to avoid:**
```nim
# Use timeline.duration for final chapter
let endMs = if i < chapters.len - 1:
              chapters[i+1].startMs - 1
            else:
              timeline.duration
```
**Warning signs:** Last chapter missing in player, FFmpeg errors about invalid timestamps

## Code Examples

Verified patterns from official sources:

### FFmpeg Scene Detection Command
```bash
# Source: https://ffmpeg.org/ffmpeg-filters.html#scdet-1
# Source: https://rusty.today/posts/ffmpeg-scene-change-detector/

# Detect scenes and output to file
ffmpeg -i input.mp4 -vf scdet=t=0.1:s=1 -f null - 2>&1 | \
  grep lavfi.sdet.scene_score | \
  awk '{print $2, $NF}' > scene_scores.txt

# Common threshold values:
# t=0.08 (8.0) - Very sensitive, many detections
# t=0.10 (10.0) - Default, good for clean cuts
# t=0.15 (15.0) - Less sensitive, major scene changes only
```

### FFmpeg Chapter Metadata Format
```bash
# Source: https://ikyle.me/blog/2020/add-mp4-chapters-ffmpeg
# Source: https://hhsprings.bitbucket.io/docs/programming/examples/ffmpeg/metadata/chapters.html

# Create ffmetadata file
cat > chapters.txt << 'EOF'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=29999
title=Introduction

[CHAPTER]
TIMEBASE=1/1000
START=30000
END=89999
title=Main Content

[CHAPTER]
TIMEBASE=1/1000
START=90000
END=119999
title=Conclusion
EOF

# Apply chapters to MP4
ffmpeg -i input.mp4 -i chapters.txt \
  -map_metadata 1 -codec copy output.mp4
```

### Peak Detection Algorithm
```nim
# Source: Standard signal processing algorithm
# Used in scipy.signal.find_peaks, MATLAB findpeaks

type Peak = tuple[index: int, value: float32]

proc findPeaks(signal: seq[float32],
               minHeight: float32 = 0.0,
               minDistance: int = 1): seq[Peak] =
  ## Find local maxima in signal
  ##
  ## Args:
  ##   minHeight: Minimum peak value
  ##   minDistance: Minimum samples between peaks

  var candidates: seq[Peak] = @[]

  # Find local maxima
  for i in 1..<signal.len - 1:
    if signal[i] >= minHeight and
       signal[i] > signal[i-1] and
       signal[i] > signal[i+1]:
      candidates.add((i, signal[i]))

  # Sort by value descending
  candidates.sort(proc(a, b: Peak): int =
    cmp(b.value, a.value))

  # Apply minimum distance
  var selected: seq[Peak] = @[]
  for peak in candidates:
    var valid = true
    for existing in selected:
      if abs(peak.index - existing.index) < minDistance:
        valid = false
        break

    if valid:
      selected.add(peak)

  return selected
```

### Integration with Existing honeyclip Components
```nim
# Source: Honeyclip existing patterns

import analyze/engagement
import metadata/types
import metadata/apply
import exports/markers

proc generateAndExportChapters*(videoPath: string,
                                 timeline: EngagementTimeline,
                                 mode: string,
                                 outputFormat: string) =
  ## Full chapter generation pipeline

  # 1. Detect scenes (if mode includes scenes)
  var sceneTimes: seq[int64] = @[]
  if mode in ["scene", "combined"]:
    sceneTimes = detectScenes(container, videoPath,
                              threshold=10.0,
                              minSceneDurationMs=5000)

  # 2. Detect engagement peaks (if mode includes engagement)
  var engagementPeaks: seq[int64] = @[]
  if mode in ["engagement", "combined"]:
    engagementPeaks = detectEngagementPeaks(timeline,
                                            minSpacingMs=30000,
                                            minScore=60.0,
                                            maxPeaks=10)

  # 3. Generate chapters
  let chapters = generateChapters(sceneTimes, engagementPeaks,
                                  timeline, mode)

  # 4. Export based on format
  case outputFormat:
  of "mp4":
    exportChaptersToMP4(chapters, videoPath,
                        videoPath.changeFileExt("_chapters.mp4"))

  of "fcpxml", "fcp7", "edl":
    let markers = exportChaptersToNLE(chapters, outputFormat)
    # Use existing Phase 9 NLE exporters
    # addMarkersFCPXML(spine, markers) or similar

  of "json":
    # Export raw chapter data for inspection
    writeFile("chapters.json", chapters.toJson())
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual chapter markers | Auto-generation from scenes/engagement | 2020+ | Saves hours per video, consistent quality |
| PySceneDetect external tool | FFmpeg scdet built-in filter | 2018+ | No Python dependency, faster integration |
| Fixed-interval chapters | Content-aware chapter placement | 2022+ | Better navigation, reflects content structure |
| MP4 chapter atoms | QuickTime chapter track | 2015+ | Better Apple ecosystem support |
| Single chapter source | Multi-modal (scene + engagement) | 2024+ | Captures both visual and content structure |

**Deprecated/outdated:**
- **Fixed 5-minute chapter intervals:** Ignores content structure, poor user experience
- **Manual chapter entry:** Time-consuming, inconsistent, error-prone
- **PySceneDetect for simple detection:** FFmpeg scdet sufficient for most use cases
- **Chapter-only export:** Modern workflows combine chapters + markers for flexibility

## Open Questions

Things that couldn't be fully resolved:

1. **Optimal scene detection threshold for different video styles**
   - What we know: Threshold 8.0-15.0 range works for most content
   - What's unclear: Whether honeyclip should auto-tune threshold based on video analysis
   - Recommendation: Start with single configurable threshold (default 10.0), add auto-tuning if users request it

2. **Chapter title generation strategies**
   - What we know: Can use sequence numbers, engagement labels, transcript text preview
   - What's unclear: Which approach users prefer, whether to support template customization
   - Recommendation: Default to simple titles ("Peak #1", "Scene 2"), add `--chapter-title-format` flag if needed

3. **Combined mode deduplication window**
   - What we know: Need to merge scene + engagement markers that are close together
   - What's unclear: Optimal window size (3s? 5s? 10s?)
   - Recommendation: Start with 5-second window, make configurable via flag

4. **Maximum chapter count limits**
   - What we know: Too many chapters (50+) defeats navigation purpose
   - What's unclear: Ideal max count (10? 15? 20?) and whether to vary by video length
   - Recommendation: Default max 10 chapters, scale with video length (1 per 5 minutes as upper bound)

## Sources

### Primary (HIGH confidence)
- [FFmpeg scdet Filter Documentation](https://ffmpeg.org/ffmpeg-filters.html#scdet-1) - Official scene detection filter reference
- [How to Add Chapters to MP4s with FFmpeg](https://ikyle.me/blog/2020/add-mp4-chapters-ffmpeg) - Practical chapter implementation guide
- [ffmpeg examples - chapters](https://hhsprings.bitbucket.io/docs/programming/examples/ffmpeg/metadata/chapters.html) - ffmetadata format specification
- [FFmpeg Scene Change Detector Examination](https://rusty.today/posts/ffmpeg-scene-change-detector/) - Technical analysis of scdet algorithm
- [PySceneDetect Documentation](https://www.scenedetect.com/) - Reference for scene detection algorithms
- [Adding Chapters to an MP4 file using ffmpeg](https://medium.com/@dathanbennett/adding-chapters-to-an-mp4-file-using-ffmpeg-5e43df269687) - Step-by-step guide
- [FFmpeg Metadata Chapter Generator](https://github.com/ravexina/ffmpeg-metadata-chapter-generator) - Python tool showing ffmetadata patterns

### Secondary (MEDIUM confidence)
- [FCPXML Markers Documentation](https://fcp.cafe/developer-case-studies/fcpxml/) - Final Cut Pro XML marker format
- [Export for Adobe Premiere Pro (markers)](https://www.simonsaysai.com/help/2769987-export-for-adobe-premiere-pro-markers) - Premiere XML marker format
- [DaVinci Resolve EDL Markers](https://www.simonsaysai.com/blog/export-for-blackmagic-davinci-resolve-timeline-markers-bc6678d323ac) - Resolve marker export
- [Video Engagement Prediction Research](https://arxiv.org/html/2410.00289v1) - Academic research on engagement detection
- [Beyond Views: Measuring Engagement](https://arxiv.org/pdf/1709.02541) - Engagement metrics research

### Tertiary (LOW confidence)
- [Video Analytics in 2026](https://www.omnilert.com/blog/video-analytics-key-benefits-and-uses) - Industry trends
- [Short-Form Video Mastery](https://almcorp.com/blog/short-form-video-mastery-tiktok-reels-youtube-shorts-2026/) - Engagement patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - FFmpeg scdet well-documented, existing engagement/metadata modules proven
- Architecture: HIGH - Builds on Phase 9 (markers), Phase 14 (metadata), Phase 17 (engagement)
- Pitfalls: MEDIUM - Based on web research and FFmpeg docs, not direct chapter implementation experience

**Research date:** 2026-02-14
**Valid until:** 2026-08-14 (6 months - stable domain, FFmpeg scdet unchanged since 2018)
