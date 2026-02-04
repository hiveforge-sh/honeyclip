# Phase 8: Multi-Aspect Export & Workflow - Context

**Gathered:** 2026-02-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Export video in multiple aspect ratios (16:9, 9:16, 1:1) with preview generation, boundary adjustment, and analysis-only mode. Users can preview before committing to full render, adjust detected clip boundaries, and export project files without rendering.

</domain>

<decisions>
## Implementation Decisions

### Preview generation
- Both thumbnail grids and video snippets supported, selectable via flag
- Previews stored in subfolder next to video (e.g., video_previews/)
- Thumbnails proportional to duration (1 frame per N seconds)
- Video snippets: 3 seconds each from start, middle, end (9s total per clip)
- Both contact sheet (single grid image) and individual frame files generated
- Side-by-side comparison: original source and reframed version
- Metadata burned into previews: clip number, time range, engagement score
- Video snippets: combined overview video plus individual clip preview files

### Boundary adjustment
- Two methods: edit JSON file and re-run, or CLI flags for quick single-clip tweaks
- Strict validation: error on out-of-range timestamps or overlapping clips
- CLI adjustments persist back to the JSON file
- Version history: clips.json.v1, .v2, etc. for each modification

### Export modes
- Analysis-only outputs: JSON, EDL, and FCPXML (all three)
- Previews configurable: metadata only by default, --with-previews adds thumbnails
- Project file auto-discovery: look in .honeyclip/project.json, --project flag overrides
- Reframe settings (aspect ratio, easing, tracking) stored in project and overridable via CLI
- Stale detection: mtime check by default, --verify flag does full SHA256 hash
- Dry-run flag: --dry-run shows planned output without writing
- Cache reuse: use existing face cache by default, --fresh forces re-analysis

### Multi-aspect output
- Parallel rendering: all ratios render concurrently
- Output structure: subfolders by ratio (video_clips/16x9/, video_clips/9x16/, video_clips/1x1/)
- Skip reframing when source matches target ratio (just clip, no crop)
- Preset ratios only: 16:9, 9:16, 1:1 (no custom ratios)
- Default: export all three ratios
- Per-ratio quality config: different CRF/codec/resolution per aspect ratio
- Platform presets: Instagram Reels, Instagram, Facebook, X, TikTok with best-practice settings
- Manual quality flags available to override presets

### Thumbnails and watermarks
- Thumbnail: auto-select best frame by default, --thumbnail-at for custom timestamp
- Watermark: text, image, or none (none by default)
- Watermark position: fully customizable with x,y offset
- Watermark settings persist in project file for consistent re-exports

### Claude's Discretion
- Ratio selection CLI syntax (flags vs comma-separated list)
- Exact platform preset settings (bitrates, codecs per platform)
- Auto-thumbnail frame selection algorithm
- Version history file naming convention

</decisions>

<specifics>
## Specific Ideas

- Platform-aware presets for social media: Instagram Reels, Instagram, Facebook, X, TikTok each with optimized settings
- Contact sheet for quick visual review of all clips at a glance
- Side-by-side preview showing original vs reframed for crop verification
- Version history on boundary edits so users can undo mistakes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-multi-aspect-export-workflow*
*Context gathered: 2026-02-03*
