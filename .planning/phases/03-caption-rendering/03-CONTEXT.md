# Phase 3: Caption Rendering - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Generate and render captions from transcripts with customizable styling, optional word highlighting, and export to multiple NLE formats. Includes burning captions into video and exporting editable caption tracks for post-production.

</domain>

<decisions>
## Implementation Decisions

### Caption Styling
- User-specified font via CLI flag (any system font)
- Position user-configurable: default bottom center, allow top/center/bottom + left/center/right
- Contrast options all configurable: outline, drop shadow, and background box as options
- Default preset: traditional subtitle style (bottom center, white with black outline, medium size)

### Word Highlighting
- Off by default, enable with --highlight flag
- Words appear as spoken (pop in instantly, not pre-displayed)
- Highlighting style: Claude's discretion (pick most readable approach)

### Caption Timing
- Use transcript grouping logic from Phase 2 (sentence/phrase boundaries)
- Small gap (100-200ms) between caption groups for visual clarity
- Transitions: cut (instant) between caption groups
- Minimum display time: Claude's discretion based on readability

### Speaker Differentiation
- Speakers identified by color, not text labels
- Fixed color palette: Speaker 0 = color A, Speaker 1 = color B, etc. (consistent across videos)

### NLE Export
- Support all formats: SRT/VTT, FCP7 XML, and FCPXML
- Word-level highlighting/reveal timing exports as keyframes for NLE
- Media file paths: relative by default, --absolute-paths flag for override
- Styling preservation and layer structure: Claude's discretion based on format capabilities

### Claude's Discretion
- Specific highlight style (color change vs bold vs background)
- Minimum caption display time
- CLI command structure (separate vs combined commands)
- Which styling attributes preserve in which NLE formats
- One layer per caption vs single layer (per format)
- Default font choice and sizes
- Color palette for speaker differentiation

</decisions>

<specifics>
## Specific Ideas

- Word-by-word reveal should feel punchy (instant pop-in, not animated)
- Traditional subtitle as default — the TikTok/Reels centered style should be available but not default
- Speaker colors should be consistent so viewers can learn "blue = host, yellow = guest" across clips

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-caption-rendering*
*Context gathered: 2026-02-02*
