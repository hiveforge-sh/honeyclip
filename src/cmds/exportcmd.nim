## Export command - Unified CLI for multi-aspect export, previews, and boundary adjustment
##
## This command ties together all Phase 8 export workflow features:
##   - EXPRT-01: Multi-aspect export via --aspect flag
##   - EXPRT-03: Preview generation via --preview flag
##   - EXPRT-04: Boundary adjustment via --adjust flag
##   - EXPRT-05: Analysis-only mode via --analyze-only flag
##
## Platform presets provide quick encoding configurations for social media.

import std/[strformat, strutils, os, json, tables, algorithm, times, options, osproc]
import ../log
import ../util/fun
import ../util/bar
import ../av
import ../analyze/clips
import ../analyze/engagement_types
import ../exports/[edl, presets, project, fcp7, fcp11, markers, aaf]
import ../render/[previews, scoreviz]
import ../reframe/crop
import ../metadata/[types, parser, apply]

type
  NLEFormat* = enum
    nleNone        ## Not NLE export mode
    nleFCP7XML     ## Adobe Premiere, DaVinci Resolve
    nleFCPXML      ## Final Cut Pro X
    nleEDL         ## DaVinci Resolve, generic
    nleAAF         ## After Effects, Media Composer

proc parseNLETarget*(target: string): NLEFormat =
  ## Parse NLE name or format string to NLEFormat
  case target.toLowerAscii()
  of "premiere", "fcp7xml", "fcp7", "resolve-xml":
    return nleFCP7XML
  of "fcpx", "finalcut", "fcpxml", "fcp11":
    return nleFCPXML
  of "resolve", "edl", "resolve-edl":
    return nleEDL
  of "aftereffects", "ae", "aaf", "mediacomposer", "avid":
    return nleAAF
  else:
    return nleNone

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

  # NLE export options
  var nleTarget: string = ""
  var nleFormat: NLEFormat = nleNone
  var includeScoreViz: bool = true
  var scoreVizMode: ScoreVizMode = svmBoth
  var noMarkers: bool = false

  # Metadata options
  var metaTemplatePath: string = ""
  var metaTitleOverride: string = ""
  var metaAuthorOverride: string = ""
  var metaCopyrightOverride: string = ""

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

NLE Export:
  --nle TARGET          Export for NLE: premiere, fcpx, resolve, aftereffects
                        Or format: fcp7xml, fcpxml, edl, aaf
  --no-markers          Skip timeline markers (engagement/scene/speaker)
  --no-graph            Skip score graph overlay track
  --no-text             Skip score text overlay track

Metadata:
  --meta-template PATH  Apply metadata template during export
  --meta-title TEXT     Override title in template
  --meta-author TEXT    Override author in template
  --meta-copyright TEXT Override copyright in template

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
  honeyclip export video.mp4 --project clips.json --nle premiere
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
    of "--nle":
      expecting = "nle"
    of "--no-markers":
      noMarkers = true
    of "--no-graph":
      if scoreVizMode == svmBoth:
        scoreVizMode = svmText
      elif scoreVizMode == svmGraph:
        includeScoreViz = false
    of "--no-text":
      if scoreVizMode == svmBoth:
        scoreVizMode = svmGraph
      elif scoreVizMode == svmText:
        includeScoreViz = false
    of "--meta-template", "--meta":
      expecting = "meta-template"
    of "--meta-title":
      expecting = "meta-title"
    of "--meta-author":
      expecting = "meta-author"
    of "--meta-copyright":
      expecting = "meta-copyright"
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
      of "nle":
        nleTarget = key
        nleFormat = parseNLETarget(key)
        if nleFormat == nleNone:
          error &"Unknown NLE target: {key}. Use: premiere, fcpx, resolve, aftereffects, or format names (fcp7xml, fcpxml, edl, aaf)"
        expecting = ""
      of "meta-template":
        metaTemplatePath = key
        expecting = ""
      of "meta-title":
        metaTitleOverride = key
        expecting = ""
      of "meta-author":
        metaAuthorOverride = key
        expecting = ""
      of "meta-copyright":
        metaCopyrightOverride = key
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

  # Load and process metadata template
  var metadataFilePath: string = ""

  if metaTemplatePath != "":
    if not fileExists(metaTemplatePath):
      error &"Metadata template not found: {metaTemplatePath}"

    var metadataTemplate = loadTemplate(metaTemplatePath)

    # Use inputPath (source video) for consistent variable substitution
    # This ensures all clips from the same video share the same base metadata
    metadataTemplate = substituteVariables(metadataTemplate, inputPath, metaAuthorOverride)

    # Apply CLI overrides
    var overrides = initTable[string, string]()
    if metaTitleOverride != "":
      overrides["title"] = metaTitleOverride
    if metaAuthorOverride != "":
      overrides["artist"] = metaAuthorOverride
    if metaCopyrightOverride != "":
      overrides["copyright"] = metaCopyrightOverride

    if overrides.len > 0:
      metadataTemplate = merge(metadataTemplate, overrides)

    # Write ffmetadata file for FFmpeg
    metadataFilePath = writeFFMetadataFile(metadataTemplate)
    echo &"Loaded metadata template: {metaTemplatePath}"

  # NLE export mode
  if nleFormat != nleNone:
    echo &"Exporting to {nleTarget} format..."

    let effectiveOutputDir = if outputDir != "":
      outputDir
    else:
      let (dir, name, _) = splitFile(inputPath)
      dir / name & "_nle"

    if not dirExists(effectiveOutputDir):
      createDir(effectiveOutputDir)

    # Generate markers from engagement data and clip boundaries
    var nleMarkers: seq[Marker] = @[]

    if not noMarkers:
      # 1. Engagement markers: from top clips by virality score
      var rankedClips = clips.sortedByIt(-it.viralityScore)
      for rank, clip in rankedClips[0 ..< min(10, rankedClips.len)]:
        nleMarkers.add(createEngagementMarker(
          clip.startMs,
          int(clip.engagementScore),  # Score is already 0-100
          rank + 1  # 1-indexed rank
        ))

      # 2. Scene boundary markers: from clip start points (transitions between clips)
      for i, clip in clips:
        if i > 0:  # Skip first clip (no boundary before it)
          nleMarkers.add(createSceneMarker(clip.startMs))

    let outputExt = case nleFormat
      of nleFCP7XML: ".xml"
      of nleFCPXML: ".fcpxml"
      of nleEDL: ".edl"
      of nleAAF: ".aaf"
      else: ".xml"

    let outputFile = effectiveOutputDir / &"markers{outputExt}"

    if dryRun:
      echo &"[Dry run] Would create: {outputFile}"
      if includeScoreViz:
        echo &"[Dry run] Would create: {effectiveOutputDir}/score_overlay.mp4"
      quit(0)

    case nleFormat
    of nleFCP7XML:
      writeMarkersFCP7(inputPath, nleMarkers, outputFile)
    of nleFCPXML:
      writeMarkersFCPXML(inputPath, nleMarkers, outputFile)
    of nleEDL:
      exportMarkersEDL(nleMarkers, outputFile, extractFilename(inputPath))
    of nleAAF:
      try:
        exportAAF(inputPath, nleMarkers, outputFile)
      except AAFExportError as e:
        echo &"AAF export failed: {e.msg}"
        echo "Falling back to FCP7 XML..."
        writeMarkersFCP7(inputPath, nleMarkers, outputFile.replace(".aaf", ".xml"))
    else:
      discard

    echo &"Created: {outputFile}"

    # Generate score visualization if requested
    if includeScoreViz and clips.len > 0:
      # Convert clips to engagement segments for visualization
      var segments: seq[EngagementSegment] = @[]
      for clip in clips:
        var seg = newEngagementSegment(clip.startMs, clip.endMs)
        seg.score = clip.engagementScore  # Score is already 0-100
        segments.add(seg)

      # Setup visualization parameters
      var vizParams = defaultScoreVizParams()
      vizParams.mode = scoreVizMode

      # Get video dimensions for filter generation
      var container = av.open(inputPath)
      defer: container.close()

      if container.video.len > 0:
        let videoStream = container.video[0]
        let width = videoStream.codecpar.width
        let height = videoStream.codecpar.height

        # Generate filter command
        let filter = generateScoreOverlayFilter(vizParams, segments, width, height)

        if filter.len > 0:
          let vizOutputPath = effectiveOutputDir / "score_overlay.mp4"
          # Use FFmpeg to render visualization overlay
          let (output, exitCode) = execCmdEx(&"ffmpeg -y -i \"{inputPath}\" -vf \"{filter}\" -c:v libx264 -preset fast -crf 23 -c:a copy \"{vizOutputPath}\"")
          if exitCode == 0:
            echo &"Created: {vizOutputPath}"
          else:
            echo &"Score visualization failed: {output}"

    quit(0)

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
        rank: clip.rank,
        viralityScore: clip.viralityScore
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
      rank: clip.rank,
      viralityScore: clip.viralityScore,
      viralityComponents: ViralityComponents(
        hook: clip.viralityHook,
        flow: clip.viralityFlow,
        value: clip.viralityValue,
        trend: clip.viralityTrend
      )
    ))

  let results = batchExportMultiAspect(inputPath, exportClips, multiParams,
    metadataPath = metadataFilePath,
    onProgress = proc(completed, total: int) =
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

  # Cleanup temp metadata file
  if metadataFilePath != "" and fileExists(metadataFilePath):
    removeFile(metadataFilePath)
