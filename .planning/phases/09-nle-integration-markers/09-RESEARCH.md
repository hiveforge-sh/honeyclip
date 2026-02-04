# Phase 9: NLE Integration & Markers - Research

**Researched:** 2026-02-03
**Domain:** NLE export formats, timeline markers, score visualization
**Confidence:** MEDIUM

## Summary

NLE integration for engagement data requires extending existing FCP7 XML, FCPXML, and EDL export formats with marker support, plus implementing full AAF export with markers. The standard approach uses XML-based marker elements for FCP7/FCPXML, comment lines for EDL, and COM-based API for AAF.

The codebase already has strong foundations: FCP7 XML export (`fcp7.nim`), FCPXML export (`fcp11.nim`), and EDL export (`edl.nim`) all exist and handle timeline structure correctly. These need marker element extensions. AAF is the only format requiring full implementation.

For score visualization, two proven approaches exist: text generator clips (already implemented for captions in `fcp7.nim` and `fcp11.nim`) and FFmpeg drawgraph filter for line graphs. Speaker tracking infrastructure exists via `diarization.nim` using pyannote.audio.

**Primary recommendation:** Extend existing XML exporters with marker elements, use pyaaf2 (Python) for AAF generation via external process, implement FFmpeg-based line graph rendering for score visualization.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| xmltree (Nim stdlib) | - | XML manipulation | Already used in `fcp7.nim`, `fcp11.nim` |
| pyaaf2 | 1.7.1 | AAF file creation | Pure Python, most active AAF library |
| FFmpeg drawgraph | - | Line graph rendering | Native, no deps beyond existing FFmpeg |
| FFmpeg drawtext | - | Text overlay rendering | Native, already in use for captions |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pyannote.audio | 3.1 | Speaker diarization | Already implemented in `diarization.nim` |
| nimpy | - | Python interop | For pyaaf2 invocation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| pyaaf2 (Python) | AAF SDK (C++) | C++ SDK is complex COM API, build overhead, same functionality |
| FFmpeg drawgraph | Pre-render PNG + overlay | More control but slower, requires image library |
| External AAF call | Native AAF via C++ | Simpler but adds 200KB+ AAF SDK dependency |

**Installation:**
```bash
# Already have: Nim xmltree, FFmpeg
# Need for AAF:
pip install pyaaf2
```

## Architecture Patterns

### Recommended Project Structure
```
src/exports/
├── fcp7.nim           # Extend with addMarkersFCP7()
├── fcp11.nim          # Extend with addMarkersFCPXML()
├── edl.nim            # Extend with addMarkersEDL()
├── aaf.nim            # NEW: AAF export via pyaaf2
└── markers.nim        # NEW: Marker data structures

src/render/
└── scoreviz.nim       # NEW: Score visualization rendering
```

### Pattern 1: Marker Element Extension
**What:** Add marker elements to existing XML structures without breaking current exports
**When to use:** FCP7 XML and FCPXML formats
**Example:**
```nim
# FCP7 XML marker format (verified from Apple docs)
proc addMarkerFCP7*(parent: XmlNode, name: string, comment: string,
                    inFrame, outFrame: int64, color: tuple[r,g,b: int]) =
  let marker = newElement("marker")
  marker.add elem("name", name)
  marker.add elem("in", $inFrame)
  marker.add elem("out", $outFrame)
  marker.add elem("comment", comment)

  let colorNode = newElement("color")
  colorNode.add elem("red", $color.r)
  colorNode.add elem("green", $color.g)
  colorNode.add elem("blue", $color.b)
  colorNode.add elem("alpha", "255")
  marker.add colorNode

  parent.add marker

# FCPXML marker format (simpler, self-closing)
proc addMarkerFCPXML*(spine: XmlNode, name: string, startSec: float,
                      durationSec: float = 1.0) =
  let marker = newElement("marker")
  marker.attrs = {
    "start": $startSec & "s",
    "duration": $durationSec & "s",
    "value": name
  }.toXmlAttributes
  spine.add marker
```

### Pattern 2: EDL Comment Line Markers
**What:** Use comment lines (asterisk prefix) to embed marker metadata in EDL
**When to use:** CMX3600 EDL format (limited marker support)
**Example:**
```nim
# EDL markers via comment lines (CMX3600 doesn't have LOCATOR in standard)
proc addMarkerCommentsEDL*(lines: var seq[string], timeMs: int64,
                          markerType: string, text: string, fps: float = 30.0) =
  let tc = formatTimecode(timeMs, fps)
  lines.add(&"* MARKER {tc} TYPE: {markerType}")
  lines.add(&"* MARKER_TEXT: {text}")
```

### Pattern 3: External AAF Generation
**What:** Call Python script via nimpy to generate AAF files with pyaaf2
**When to use:** AAF format export (too complex for native Nim)
**Example:**
```nim
import nimpy

proc exportAAF*(videoPath: string, markers: seq[Marker], outputPath: string) =
  # Marshal marker data to JSON
  let markerJson = %* {
    "video": videoPath,
    "markers": markers.mapIt(%* {
      "name": it.name,
      "start_ms": it.startMs,
      "end_ms": it.endMs,
      "comment": it.comment,
      "color": it.color
    })
  }

  # Call Python helper script
  let py = pyBuiltinsModule()
  let json = pyImport("json")
  let subprocess = pyImport("subprocess")

  subprocess.run(@[
    "python", "scripts/export_aaf.py",
    "--input", $markerJson,
    "--output", outputPath
  ], check=true)
```

### Pattern 4: FFmpeg Drawgraph Score Visualization
**What:** Use FFmpeg's drawgraph filter to render engagement scores as line graph overlay
**When to use:** Generating score visualization video track
**Example:**
```bash
# Generate score timeline as text file (one value per frame)
echo "0.5 0.6 0.7 0.85 0.9 0.75..." > scores.txt

# Render as line graph overlay
ffmpeg -i video.mp4 -filter_complex "
  [0:v]split[v][vtmp];
  color=c=black@0.7:s=1920x200[bg];
  [vtmp]crop=1920:200:0:0[crop];
  [bg][crop]overlay[withbg];
  [withbg]drawgraph=
    s=1920x200:
    mode=line:
    slide=scroll:
    fg1=0x00FF00:
    max=1.0:
    min=0.0:
    r=30:
    file=scores.txt[graph];
  [v][graph]overlay=0:H-200[out]
" -map "[out]" output.mp4
```

### Anti-Patterns to Avoid
- **Inline AAF SDK in Nim:** AAF SDK is COM-based C++, requires extensive wrapper code, use pyaaf2 instead
- **Hardcoded frame rates:** Always calculate from timebase, NLEs support NTSC (29.97, 23.976) and drop-frame
- **Marker name truncation without warning:** FCP7 has no strict limits, but DaVinci may truncate, document this
- **RGB as 0-255 for all formats:** FCP7 uses 0-255, FCPXML uses 0.0-1.0 normalized, check per format

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AAF file writing | Native C++ AAF SDK bindings | pyaaf2 via Python subprocess | AAF SDK is 200KB+ COM API with complex object model, pyaaf2 is battle-tested |
| SMPTE timecode math | Manual HH:MM:SS:FF parsing | Existing `parseSMPTE` in `fcp11.nim` | Handles drop-frame, NTSC rates, already tested |
| Line graph rendering | Cairo/Canvas drawing | FFmpeg drawgraph filter | FFmpeg already required, drawgraph is hardware-accelerated, no extra deps |
| Speaker name mapping | Custom JSON schema | Existing `loadSpeakerMap` in `diarization.nim` | Already handles speaker ID -> name mapping |

**Key insight:** NLE formats have subtle compatibility issues (NTSC rates, drop-frame timecode, color space differences). Use existing code that's already been tested with real NLEs.

## Common Pitfalls

### Pitfall 1: Marker Color Format Confusion
**What goes wrong:** Markers appear wrong color or not at all in NLE
**Why it happens:** FCP7 uses 0-255 RGB, FCPXML uses 0.0-1.0 normalized RGB, EDL has no color
**How to avoid:**
- Create helper functions: `hexToFCP7Color()` (already exists in `fcp7.nim`), add `hexToFCPXMLColor()`
- Document color format in marker data structure
- Test imports in actual NLE applications
**Warning signs:** Green markers show as red, or markers don't appear in timeline

### Pitfall 2: Frame vs. Time Representation
**What goes wrong:** Markers appear at wrong positions in timeline
**Why it happens:** FCP7 uses frame numbers, FCPXML uses rational seconds, EDL uses SMPTE timecode
**How to avoid:**
- Always convert from milliseconds to target format using timebase
- Use `msToIndex()` helper for frame conversion (exists in `engagement.nim`)
- Verify with drop-frame NTSC content (29.97fps)
**Warning signs:** Markers drift further from correct position as timeline progresses

### Pitfall 3: AAF Marker Timing Precision
**What goes wrong:** AAF markers show at slightly wrong times in Media Composer
**Why it happens:** AAF uses edit rate (samples per second), not milliseconds
**How to avoid:**
- Use pyaaf2's `.slots['Position']` with integer edit units, not float seconds
- Calculate: `edit_units = (time_ms * edit_rate) / 1000`
- Default to 48000 edit rate (matches audio sample rate for precision)
**Warning signs:** Markers are off by a few frames in Media Composer but correct in XML import

### Pitfall 4: EDL 999 Event Limit
**What goes wrong:** EDL export silently truncates markers beyond event 999
**Why it happens:** CMX3600 format has hard limit of 999 events (clips + markers treated as events in some implementations)
**How to avoid:**
- Count total events (clips + markers) before export
- Warn user if limit exceeded, suggest FCP7 XML or AAF instead
- Prioritize marker types (engagement peaks > scene boundaries > speaker changes)
**Warning signs:** Not all markers appear in DaVinci after EDL import

### Pitfall 5: Text Generator Track Opacity
**What goes wrong:** Text overlay track blocks video content
**Why it happens:** Text generators default to opaque background in some NLEs
**How to avoid:**
- Use `opacity` parameter (FCP7) or `blend` mode (FCPXML) to ensure transparency
- For FCP7: Set background alpha to 0 in text generator params
- Test in target NLE that text appears over video, not blocking it
**Warning signs:** Video blacks out when text track is visible

## Code Examples

Verified patterns from official sources:

### FCP7 XML Marker Structure
```xml
<!-- Source: Apple FCP7 XML Interchange Format documentation -->
<marker>
  <name>Engagement Peak #1</name>
  <comment>Score: 85/100 - High engagement</comment>
  <in>3000</in>
  <out>3001</out>
  <color>
    <red>0</red>
    <green>255</green>
    <blue>0</blue>
    <alpha>255</alpha>
  </color>
</marker>
```

### FCPXML Marker Structure
```xml
<!-- Source: Demystifying Final Cut Pro XMLs guide -->
<marker start="4000s" duration="1s" value="Speaker Change: John" />
```

### EDL Marker Comments
```edl
# Source: CMX3600 format examples
001  REELA    V     C        00:00:10:00 00:00:15:00 01:00:00:00 01:00:05:00
* ENGAGEMENT_PEAK: Score 92/100 (#1)
* SCENE_BOUNDARY: Transition at 00:00:10:00
```

### FFmpeg Score Overlay (Text Mode)
```bash
# Source: FFmpeg drawtext documentation
# Text clips showing score every 5 seconds
ffmpeg -i input.mp4 -vf "drawtext=
  fontfile=/path/to/font.ttf:
  text='Score\: %{eif\:min(100,max(0,t*10))\:d}/100':
  x=(w-text_w)/2:
  y=50:
  fontsize=36:
  fontcolor=white:
  box=1:
  boxcolor=black@0.5:
  enable='between(mod(t,5),0,1)'
" output.mp4
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AAF SDK (C++) | pyaaf2 (Python) | ~2018 | Pure Python implementation much easier to integrate |
| FCP7 XML only | FCP7 + FCPXML support | FCP X release (2011) | Must support both for Adobe + Apple NLEs |
| EDL with LOCATOR events | EDL with comment lines | Varies by NLE | LOCATOR not universally supported, comments safer |
| whisper without diarization | whisper + pyannote.audio | 2023 | OpenAI Whisper doesn't do speaker tracking natively |

**Deprecated/outdated:**
- **FCP7 XML for Final Cut Pro X:** FCPX uses FCPXML (different format), FCP7 XML only works for Premiere/Resolve
- **EDL LOCATOR syntax:** Some NLEs don't support it, comment lines more universal
- **Single-speaker transcripts:** Modern engagement needs speaker tracking, use diarization

## Open Questions

Things that couldn't be fully resolved:

1. **AAF CompositionMob vs. MasterMob for markers**
   - What we know: pyaaf2 supports both, examples show markers on CompositionMob timeline
   - What's unclear: Best practice for engagement markers (timeline markers vs. source markers)
   - Recommendation: Use CompositionMob markers (timeline markers) since engagement is per-edit, not per-source

2. **FCPXML chapter marker vs. standard marker for engagement**
   - What we know: FCPXML has both `<marker>` and `<chapter-marker>` elements
   - What's unclear: Whether engagement peaks should be chapters (orange) or standard markers (blue)
   - Recommendation: Use standard `<marker>` for all types, distinguish by color and name prefix

3. **Line graph rendering performance at 4K**
   - What we know: FFmpeg drawgraph works at HD (1920x1080), example videos at HD
   - What's unclear: Performance impact at 4K (3840x2160) for 200px tall graph
   - Recommendation: Test at 4K, may need to reduce graph height or use `scale` filter

## Sources

### Primary (HIGH confidence)
- [Apple FCP7 XML Interchange Format](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/Elements/Elements.html) - Marker element specification
- [FFmpeg drawtext filter documentation](https://ottverse.com/ffmpeg-drawtext-filter-dynamic-overlays-timecode-scrolling-text-credits/) - Text overlay with timeline control
- Existing codebase: `fcp7.nim`, `fcp11.nim`, `edl.nim`, `diarization.nim` - Working implementations

### Secondary (MEDIUM confidence)
- [Demystifying Final Cut Pro XMLs](https://fcp.cafe/developer-case-studies/fcpxml/) - FCPXML marker examples
- [pyaaf2 GitHub repository](https://github.com/markreidvfx/pyaaf2) - AAF marker implementation examples
- [CMX3600 EDL format](https://xmil.biz/EDL-X/CMX3600.pdf) - Official specification (SMPTE 258M-1993)
- [FFmpeg waveform visualization guide](https://shotstack.io/learn/ffmpeg-create-waveform/) - Line graph rendering techniques

### Tertiary (LOW confidence)
- [whisper.cpp speaker diarization discussion](https://github.com/ggml-org/whisper.cpp/discussions/2430) - Speaker tracking integration (marked for validation)
- Community discussions on EDL LOCATOR support - Varies by NLE, needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - pyaaf2 via Python is pragmatic but untested in this codebase, XML extensions are solid
- Architecture: HIGH - Extending existing exporters follows established patterns, FFmpeg approach proven
- Pitfalls: HIGH - Based on existing code comments and Apple documentation, frame rate issues well-documented

**Research date:** 2026-02-03
**Valid until:** 30 days (stable domain, NLE formats change slowly, pyaaf2 updated quarterly)
