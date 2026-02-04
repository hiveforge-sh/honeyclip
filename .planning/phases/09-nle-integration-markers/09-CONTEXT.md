# Phase 9: NLE Integration & Markers - Context

**Gathered:** 2026-02-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Export engagement data and speaker information to professional video editing applications (Premiere, After Effects, Resolve, Final Cut Pro). Delivers timeline markers for engagement peaks, scene boundaries, and speaker changes. Includes engagement score visualization options.

</domain>

<decisions>
## Implementation Decisions

### Marker Semantics
- Three marker types: engagement peaks, scene boundaries, and speaker changes
- Color-coded by type: Green=engagement peak, Blue=scene boundary, Yellow=speaker change
- Engagement markers show score + rank + descriptive label (e.g., "85/100 (#2) - High engagement")
- Speaker change markers include speaker name/ID ("Speaker: John" or "Speaker 1" if unnamed)

### Format Coverage
- Full support for all four formats: FCP7 XML, FCPXML, AAF, and EDL
- EDL: Use LOCATOR events where supported, fall back to comment lines
- AAF: Full project support with markers + media references + clip structure
- After Effects: User chooses between FCP7 XML or AAF export

### Score Visualization
- Three visualization modes available, user can choose one or all:
  1. Graphic layer (line graph waveform showing score over time)
  2. Text overlay track (text clips showing score every 5 seconds)
  3. Markers only (scores embedded in marker comments)
- Graphic/text tracks on separate video track above source (easily toggled off)

### Export Workflow
- Extend existing `export` command with `--nle` flag
- Accept both NLE names (`--nle premiere`) and format names (`--nle fcp7xml`)
- Either mode: Use project file if available, else run inline analysis
- All visualization modes included by default (markers + graphic + text), can be disabled with flags

### Claude's Discretion
- Exact color hex values for marker types
- Line graph rendering implementation
- Text overlay styling and positioning
- LOCATOR event syntax for EDL variants

</decisions>

<specifics>
## Specific Ideas

- Engagement markers combine quantitative (score/rank) with qualitative (descriptive label)
- Full AAF support including embedded media references
- Score visualization is opt-out rather than opt-in

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-nle-integration-markers*
*Context gathered: 2026-02-03*
