## Export command - Unified CLI for multi-aspect export, previews, and boundary adjustment
##
## This command ties together all Phase 8 export workflow features:
##   - EXPRT-01: Multi-aspect export via --aspect flag
##   - EXPRT-03: Preview generation via --preview flag
##   - EXPRT-04: Boundary adjustment via --adjust flag
##   - EXPRT-05: Analysis-only mode via --analyze-only flag
##
## Platform presets provide quick encoding configurations for social media.

import std/[strformat, strutils, os, json, tables, algorithm, times, options]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../analyze/clips
import ../exports/[edl, presets, project, fcp11]
import ../render/previews
import ../reframe/crop

proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var projectPath: string = ""
  var outputDir: string = ""

  # Mode flags
  var analyzeOnly: bool = false
  var generatePreviewsFlag: bool = false
  var previewMode: PreviewMode = PreviewThumbnails

  # Aspect ratio selection (support both --aspect 16:9,9:16 and repeated flags)
  var aspects: seq[AspectRatio] = @[]
  var presetName: string = ""

  # Boundary adjustment
  var adjustClip: int = 0
  var adjustStart: int64 = -1
  var adjustEnd: int64 = -1

  # Other options
  var topN: int = 5
  var concurrent: int = 4
  var dryRun: bool = false
  var freshAnalysis: bool = false
  var verifyHash: bool = false

  # Parse arguments
  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip export [options]

Export clips with multi-aspect support, previews, and boundary adjustment

Modes:
  --analyze-only        Export project files (JSON, EDL, FCPXML) without rendering video
  --preview             Generate preview thumbnails/snippets before full render
  --adjust RANK         Adjust boundaries of clip #RANK (use with --start and --end)

Input:
  --project PATH        Load existing project/clips JSON file
  file                  Input video file (for reference in exports)

Aspect Ratios:
  --aspect RATIO        Output aspect: 16:9, 9:16, 1:1 (can repeat or comma-separate)
                        Default: export all three ratios
  --preset NAME         Platform preset: instagram-reels, tiktok, youtube-shorts,
                        instagram-feed, facebook, twitter

Adjustment:
  --start MS            New start time in milliseconds (use with --adjust)
  --end MS              New end time in milliseconds (use with --adjust)

Output:
  -o, --output DIR      Output directory (default: video_export/)
  -n, --top N           Number of top clips (default: 5)
  --concurrent N        Max parallel renders (default: 4)

Control:
  --dry-run             Show planned actions without executing
  --fresh               Force re-analysis (ignore cached data)
  --verify              Use SHA256 hash for stale detection (slower)
  --help                Show this help

Examples:
  honeyclip export video.mp4 --project clips.json --analyze-only
  honeyclip export video.mp4 --project clips.json --preview
  honeyclip export video.mp4 --project clips.json --aspect 9:16 --preset tiktok
  honeyclip export --project clips.json --adjust 2 --start 5000 --end 15000
"""
      quit(0)
    of "--analyze-only":
      analyzeOnly = true
    of "--preview":
      generatePreviewsFlag = true
    of "--preview-mode":
      expecting = "preview-mode"
    of "--aspect":
      expecting = "aspect"
    of "--preset":
      expecting = "preset"
    of "--project":
      expecting = "project"
    of "--adjust":
      expecting = "adjust"
    of "--start":
      expecting = "start"
    of "--end":
      expecting = "end"
    of "-o", "--output":
      expecting = "output"
    of "-n", "--top":
      expecting = "top"
    of "--concurrent":
      expecting = "concurrent"
    of "--dry-run":
      dryRun = true
    of "--fresh":
      freshAnalysis = true
    of "--verify":
      verifyHash = true
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        if inputPath == "":
          inputPath = key
        else:
          error &"Unexpected argument: {key}"
      of "aspect":
        # Parse comma-separated or single aspect
        for a in key.split(","):
          case a.strip()
          of "16:9", "16/9": aspects.add(Landscape)
          of "9:16", "9/16": aspects.add(Portrait)
          of "1:1": aspects.add(Square)
          else: error &"Unknown aspect ratio: {a}"
        expecting = ""
      of "preset":
        presetName = key
        expecting = ""
      of "project":
        projectPath = key
        expecting = ""
      of "adjust":
        adjustClip = parseInt(key)
        expecting = ""
      of "start":
        adjustStart = parseInt(key).int64
        expecting = ""
      of "end":
        adjustEnd = parseInt(key).int64
        expecting = ""
      of "output":
        outputDir = key
        expecting = ""
      of "top":
        topN = parseInt(key)
        expecting = ""
      of "concurrent":
        concurrent = parseInt(key)
        expecting = ""
      of "preview-mode":
        case key
        of "thumbnails": previewMode = PreviewThumbnails
        of "snippets": previewMode = PreviewSnippets
        else: error &"Unknown preview mode: {key}"
        expecting = ""

  # Check for incomplete argument
  if expecting != "":
    error &"Missing value for {expecting}"

  # Handle boundary adjustment mode (check first, takes precedence)
  if adjustClip > 0:
    if projectPath == "":
      error "Boundary adjustment requires --project PATH"
    if adjustStart < 0 or adjustEnd < 0:
      error "Boundary adjustment requires --start and --end"

    echo &"Adjusting clip #{adjustClip}: {adjustStart}ms - {adjustEnd}ms"

    if dryRun:
      echo "[Dry run] Would adjust clip boundaries and save with version history"
      quit(0)

    let (success, errors, version) = adjustClipBoundaryAndSave(
      projectPath, adjustClip, adjustStart, adjustEnd
    )

    if not success:
      echo "Adjustment failed:"
      for err in errors:
        echo &"  - {err}"
      quit(1)

    echo &"Saved as version {version}"
    echo &"Previous version: {projectPath}.v{version - 1}"
    quit(0)

  # Validate input
  if inputPath == "" and projectPath == "":
    error "Provide input video or --project PATH"

  if projectPath != "" and not fileExists(projectPath):
    error &"Project file not found: {projectPath}"

  if inputPath != "" and not fileExists(inputPath):
    error &"Input file not found: {inputPath}"

  # Default to all aspects if none specified
  if aspects.len == 0:
    aspects = @[Landscape, Portrait, Square]

  # Apply platform preset if specified
  if presetName != "":
    let preset = getPreset(presetName)
    if preset.isNone:
      echo "Available presets: " & listPresets().join(", ")
      error &"Unknown preset: {presetName}"
    # Override aspect from preset
    aspects = @[preset.get.aspect]

  # Load clips from project file
  var clips: seq[EDLClip]
  var sourcePath: string

  if projectPath != "":
    # Load from existing project
    (clips, sourcePath) = loadClipsFromJson(projectPath)
    echo &"Loaded {clips.len} clips from {projectPath}"

    if inputPath == "":
      inputPath = sourcePath

  if clips.len == 0:
    error "No clips found. Run 'honeyclip clips' first to detect clips, then use --project to load them."

  # Analysis-only mode (EXPRT-05)
  if analyzeOnly:
    echo "Analysis-only mode: exporting project files..."

    let effectiveOutputDir = if outputDir != "":
      outputDir
    else:
      let (dir, name, _) = splitFile(inputPath)
      dir / name & "_export"

    if not dirExists(effectiveOutputDir):
      createDir(effectiveOutputDir)

    if dryRun:
      echo "[Dry run] Would create:"
      echo &"  - {effectiveOutputDir}/project.json"
      echo &"  - {effectiveOutputDir}/clips.json"
      echo &"  - {effectiveOutputDir}/clips.edl"
      echo &"  - {effectiveOutputDir}/clips.fcpxml"
      quit(0)

    # Convert EDLClip to ProjectClip for project file
    var projectClips: seq[ProjectClip] = @[]
    for clip in clips:
      projectClips.add(ProjectClip(
        startMs: clip.startMs,
        endMs: clip.endMs,
        engagementScore: clip.engagementScore,
        adjustedScore: clip.engagementScore,
        text: clip.text,
        rank: clip.rank
      ))

    # Create HoneyclipProject and save it
    var proj = HoneyclipProject(
      version: 1,
      source: inputPath,
      sourceMtime: getSourceMtime(inputPath),
      sourceHash: "",
      created: now().format("yyyy-MM-dd'T'HH:mm:ss"),
      modified: now().format("yyyy-MM-dd'T'HH:mm:ss"),
      clips: projectClips,
      reframe: ReframeSettings(
        aspect: Landscape,
        easing: "medium",
        fallbackMode: "center"
      ),
      watermark: WatermarkSettings(
        enabled: false,
        watermarkType: "",
        value: "",
        x: 0,
        y: 0
      )
    )
    saveProject(proj, effectiveOutputDir / "project.json")
    echo &"Created: {effectiveOutputDir}/project.json"

    exportClipsJSON(clips, effectiveOutputDir / "clips.json", inputPath)
    echo &"Created: {effectiveOutputDir}/clips.json"

    exportCMX3600EDL(clips, effectiveOutputDir / "clips.edl", extractFilename(inputPath))
    echo &"Created: {effectiveOutputDir}/clips.edl"

    # Export FCPXML - use writeCaptionOnlyFCPXML as base structure
    # For clips export, we generate minimal structure
    let fcpxmlPath = effectiveOutputDir / "clips.fcpxml"
    # Create EDL-style content in FCPXML format manually
    var fcpxmlContent = """<?xml version='1.0' encoding='utf-8'?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormatRateUndefined" frameDuration="1/30s" width="1920" height="1080"/>
  </resources>
  <library>
    <event name="Clips Export">
"""
    for clip in clips:
      let startSec = clip.startMs.float / 1000.0
      let durationSec = (clip.endMs - clip.startMs).float / 1000.0
      fcpxmlContent.add(&"""      <clip name="Clip {clip.rank}" duration="{durationSec}s" start="{startSec}s">
        <note>Score: {clip.engagementScore:.1f} | {clip.text[0..min(50, clip.text.len-1)]}</note>
      </clip>
""")
    fcpxmlContent.add("""    </event>
  </library>
</fcpxml>
""")
    writeFile(fcpxmlPath, fcpxmlContent)
    echo &"Created: {effectiveOutputDir}/clips.fcpxml"

    quit(0)

  # Preview mode (EXPRT-03)
  if generatePreviewsFlag:
    echo &"Generating previews ({previewMode})..."

    let previewDir = if outputDir != "":
      outputDir / "previews"
    else:
      let (dir, name, _) = splitFile(inputPath)
      dir / name & "_previews"

    if dryRun:
      echo "[Dry run] Would generate previews in: " & previewDir
      quit(0)

    # Convert EDLClip to tuple format for previews
    var clipTuples: seq[tuple[startMs, endMs: int64, rank: int]] = @[]
    for clip in clips:
      clipTuples.add((clip.startMs, clip.endMs, clip.rank))

    let result = generatePreviews(inputPath, clipTuples, previewMode)

    if result.success:
      if result.contactSheetPath != "":
        echo &"Contact sheet: {result.contactSheetPath}"
      echo &"Thumbnails: {result.thumbnailPaths.len} files"
      if result.snippetPaths.len > 0:
        echo &"Snippets: {result.snippetPaths.len} files"
    else:
      echo &"Preview generation failed: {result.error}"
      quit(1)

    quit(0)

  # Full multi-aspect export (EXPRT-01)
  echo &"Exporting {clips.len} clips in {aspects.len} aspect ratio(s)..."

  let effectiveOutputDir = if outputDir != "":
    outputDir
  else:
    let (dir, name, _) = splitFile(inputPath)
    dir / name & "_clips"

  if dryRun:
    echo "[Dry run] Would export to:"
    for aspect in aspects:
      echo &"  - {effectiveOutputDir}/{aspectToString(aspect)}/"
    quit(0)

  # Get video dimensions
  var container = av.open(inputPath)
  defer: container.close()

  if container.video.len == 0:
    error "No video stream found"

  let videoStream = container.video[0]
  let sourceWidth = videoStream.codecpar.width
  let sourceHeight = videoStream.codecpar.height

  # Build export params
  var baseParams = defaultClipExportParams()
  baseParams.outputDir = effectiveOutputDir
  baseParams.maxConcurrent = concurrent

  var multiParams = MultiAspectExportParams(
    baseParams: baseParams,
    aspects: aspects,
    sourceAspect: sourceWidth.float / sourceHeight.float,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    preset: presetName
  )

  # Convert EDLClip to Clip for export
  var exportClips: seq[Clip] = @[]
  for clip in clips:
    exportClips.add(Clip(
      startMs: clip.startMs,
      endMs: clip.endMs,
      engagementScore: clip.engagementScore,
      adjustedScore: clip.engagementScore,
      text: clip.text,
      rank: clip.rank
    ))

  let results = batchExportMultiAspect(inputPath, exportClips, multiParams,
    proc(completed, total: int) =
      conwrite(&"Exporting: {completed}/{total}")
  )

  conwrite("")
  echo ""
  echo "Export Results:"
  var successCount = 0
  for r in results:
    let status = if r.success:
      successCount += 1
      "OK"
    else:
      &"FAILED: {r.error}"
    echo &"  {extractFilename(r.outputPath)} - {status}"

  echo ""
  echo &"Exported {successCount}/{results.len} files to: {effectiveOutputDir}"
