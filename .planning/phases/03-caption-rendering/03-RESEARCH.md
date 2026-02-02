# Phase 3: Caption Rendering - Research

**Researched:** 2026-02-02
**Domain:** Video caption rendering with FFmpeg filters and NLE export
**Confidence:** HIGH

## Summary

This research investigates how to burn captions into video with customizable styling and export to NLE formats (SRT/VTT/FCP7/FCPXML). The phase builds on Phase 2's transcript foundation, using the existing caption grouping logic to render styled text overlays via FFmpeg's drawtext and subtitle filters, and extends the existing NLE export modules to include caption tracks.

**Key findings:**
- FFmpeg's drawtext filter provides comprehensive text styling (font, size, color, position, outline, shadow, background box)
- ASS subtitle format with karaoke timing (\k tags) enables word-level highlighting effects
- The subtitles/ass filters burn ASS files into video with full style preservation
- Existing FCP7/FCPXML exporters can be extended to include caption tracks as title clips
- Font selection requires full paths on Windows (C:/Windows/Fonts/) and Linux (/usr/share/fonts/)
- Industry standard: 42 character limit, 48-60px font size, white text with black outline, bottom-center positioning
- Modern "TikTok style": centered position, yellow/white highlight, bold sans-serif fonts (Poppins/Futura)

**Primary recommendation:** Use FFmpeg drawtext for simple caption burning (no word highlighting), generate ASS files with \k karaoke tags for word highlighting, extend existing FCP7/FCPXML exporters to include caption tracks as title clips, provide preset styles (traditional/modern).

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg drawtext filter | FFmpeg 6.1+ | Text overlay rendering | Built-in, full styling control, production-proven |
| FFmpeg subtitles/ass filter | FFmpeg 6.1+ | Burn ASS subtitle files | Requires libass, preserves all ASS styling |
| ASS subtitle format | Advanced SubStation Alpha | Word-level timing with karaoke | Industry standard for styled subs, supports \k tags |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| libfreetype | 2.x | Font rendering | Already linked in FFmpeg for drawtext |
| libfontconfig | 2.x (optional) | System font discovery | Optional, allows font="Arial" instead of fontfile path |
| FCP7 XML | 5.0+ | NLE export format | Already implemented in src/exports/fcp7.nim |
| FCPXML | 11.0+ | Final Cut Pro X format | Already implemented in src/exports/fcp11.nim |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| FFmpeg drawtext | ImageMagick + composite | More complex pipeline, no timing sync |
| ASS format | Custom overlay rendering | Reinvents wheel, no NLE compatibility |
| Hardcoded fonts | System font API | Platform-specific code, deployment issues |

**Installation:**
```bash
# Already available (FFmpeg built with libfreetype)
nimble makeff

# Verify drawtext filter available
build/bin/ffmpeg -filters | grep drawtext

# No additional dependencies needed
```

## Architecture Patterns

### Recommended Project Structure
```
src/
├── cmds/
│   ├── transcript.nim          # Existing - add caption rendering
│   └── captions.nim            # New - dedicated caption command
├── transcript/
│   ├── formats.nim             # Existing - SRT/VTT export
│   ├── grouping.nim            # Existing - caption grouping logic
│   └── types.nim               # Existing - Caption/Word types
├── render/
│   ├── captions.nim            # New - burn captions with FFmpeg filters
│   └── subtitle.nim            # Existing - remux subtitle streams
├── exports/
│   ├── fcp7.nim                # Existing - extend with caption tracks
│   ├── fcp11.nim               # Existing - extend with caption tracks
│   └── json.nim                # Existing - timeline export
```

### Pattern 1: Two-Stage Caption Rendering
**What:** Generate styled caption file (ASS/SRT), then burn into video with FFmpeg filter
**When to use:** Default for all caption burning operations
**Example:**
```nim
# Stage 1: Generate caption file from transcript
let captions = groupIntoCaptions(transcript, maxChars=42)
let assPath = generateASSFile(captions, styling, wordHighlight=true)

# Stage 2: Burn into video with FFmpeg ass filter
let filterGraph = buildFilterGraph(inputVideo)
filterGraph.addFilter("ass", &"filename={assPath}")
renderVideo(filterGraph, outputPath)
```

### Pattern 2: FFmpeg Drawtext Filter Chain
**What:** Use drawtext filter with dynamic text expressions for simple captions
**When to use:** When word highlighting not needed, for basic overlay text
**Example:**
```nim
proc buildDrawtextFilter(caption: Caption, style: CaptionStyle): string =
  # Build FFmpeg drawtext filter string
  var filter = "drawtext="

  # Font and size
  filter &= &"fontfile={style.fontPath}:"
  filter &= &"fontsize={style.fontSize}:"
  filter &= &"fontcolor={style.color}:"

  # Position (bottom center default)
  filter &= "x=(w-text_w)/2:"  # Center horizontally
  filter &= &"y=h-{style.marginBottom}:"

  # Outline for contrast
  if style.outline:
    filter &= &"borderw={style.outlineWidth}:"
    filter &= &"bordercolor={style.outlineColor}:"

  # Drop shadow
  if style.shadow:
    filter &= &"shadowx={style.shadowX}:"
    filter &= &"shadowy={style.shadowY}:"
    filter &= &"shadowcolor={style.shadowColor}:"

  # Background box
  if style.backgroundBox:
    filter &= "box=1:"
    filter &= &"boxcolor={style.boxColor}:"
    filter &= &"boxborderw={style.boxPadding}:"

  # Text with timing
  filter &= &"text='{caption.text}':"
  filter &= &"enable='between(t,{caption.startMs/1000},{caption.endMs/1000})'"

  return filter
```

### Pattern 3: ASS Karaoke Timing for Word Highlighting
**What:** Generate ASS subtitle file with \k karaoke tags for word-by-word reveal
**When to use:** When --highlight flag enabled, for TikTok-style word emphasis
**Example:**
```nim
proc generateASSWithKaraoke(caption: Caption, style: CaptionStyle): string =
  # ASS format with karaoke timing
  var assText = ""

  for i, word in caption.words:
    # Calculate duration in centiseconds
    let durationCs = (word.endMs - word.startMs) div 10

    # Add karaoke tag (\k for instant highlight)
    assText &= &"{{\\k{durationCs}}}{word.text}"

    if i < caption.words.len - 1:
      assText &= " "

  # Build ASS dialogue line with styling
  return &"Dialogue: 0,{formatASSTime(caption.startMs)},{formatASSTime(caption.endMs)},Default,,0,0,0,,{assText}"
```
**Source:** [ASS Override Tags - Aegisub](https://aegisub.org/docs/latest/ass_tags/)

### Pattern 4: Speaker Color Palette
**What:** Fixed color assignments for consistent speaker identification
**When to use:** When transcript has speaker diarization enabled
**Example:**
```nim
const SpeakerColors = [
  "#00d4ff",  # Speaker 0: Cyan/Blue
  "#ff6b6b",  # Speaker 1: Red/Pink
  "#4ecb71",  # Speaker 2: Green
  "#ffe66d",  # Speaker 3: Yellow
  "#a29bfe",  # Speaker 4: Purple
]

proc getSpeakerColor(speaker: int): string =
  if speaker < 0 or speaker >= SpeakerColors.len:
    return "#ffffff"  # Default white
  return SpeakerColors[speaker]
```

### Pattern 5: NLE Caption Track Export
**What:** Extend FCP7/FCPXML exporters to include caption clips as title tracks
**When to use:** When exporting to NLE with --export=final-cut-pro or premiere
**Example:**
```nim
proc addCaptionTrack(xml: XmlNode, captions: seq[Caption], styling: CaptionStyle) =
  # Add video track for captions
  let captionTrack = newElement("track")

  for caption in captions:
    # Create title clip for each caption
    let clipItem = newElement("clipitem")
    clipItem.add elem("name", "Caption: " & caption.text[0..min(20, caption.text.len-1)])
    clipItem.add elem("start", $caption.startMs)
    clipItem.add elem("end", $caption.endMs)

    # Add text filter effect with styling preserved
    let textEffect = newElement("effect")
    textEffect.add elem("name", "Text")
    textEffect.add param("str", "Text", caption.text)
    textEffect.add param("fontname", "Font", styling.fontName)
    textEffect.add param("fontsize", "Size", $styling.fontSize)
    textEffect.add param("fontcolor", "Color", styling.color)

    clipItem.add textEffect
    captionTrack.add clipItem

  xml.add captionTrack
```

### Anti-Patterns to Avoid
- **Don't use drawtext for word highlighting:** Drawtext doesn't support per-word timing, use ASS karaoke instead
- **Don't hardcode font names without fallback:** "font=Arial" requires libfontconfig, use full paths for reliability
- **Don't forget to escape colons in Windows paths:** "fontfile=C:/Windows/Fonts/arial.ttf" requires "C\\:/Windows/Fonts/arial.ttf"
- **Don't use long captions without line breaks:** Enforce 42-char limit from Phase 2 grouping logic
- **Don't position captions at exact screen edge:** Leave margin for platform UI elements (100-150px from edges)

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Text rendering engine | Custom rasterizer | FFmpeg drawtext (libfreetype) | Handles font hinting, kerning, Unicode, anti-aliasing |
| Subtitle format parser | Regex-based SRT parser | Generate ASS directly | ASS has precise timing syntax, style inheritance, metadata |
| Word timing animation | Frame-by-frame overlay | ASS karaoke \k tags | Native subtitle format, NLE-compatible, zero code |
| Font discovery | Directory scanning | libfontconfig (optional) | Resolves font aliases, finds system fonts cross-platform |
| Color contrast calculation | Manual RGB math | Use proven palettes | WCAG 4.5:1 contrast tested, platform-tested visibility |

**Key insight:** FFmpeg's text rendering filters represent decades of production use in broadcast and streaming. The drawtext filter alone has 100+ parameters covering every conceivable text styling need. ASS subtitle format has been refined since the early 2000s for anime fansubs requiring precise styling and effects.

## Common Pitfalls

### Pitfall 1: Font Path Escaping on Windows
**What goes wrong:** FFmpeg drawtext fails with "Cannot find font" when using Windows paths like C:/Windows/Fonts/arial.ttf
**Why it happens:** Colons in filter arguments are parameter separators; Windows drive letters collide
**How to avoid:** Escape colons with backslash: `fontfile=C\\:/Windows/Fonts/arial.ttf`
**Warning signs:** Error message "Cannot find font file" or "Invalid argument" from drawtext filter
**Source:** [drawtext examples](https://hhsprings.bitbucket.io/docs/programming/examples/ffmpeg/drawing_texts/drawtext.html)

### Pitfall 2: ASS Format Requires UTF-8 Without BOM
**What goes wrong:** Special characters display as boxes, first word has garbage prefix
**Why it happens:** Same as Phase 2 - ASS parsers expect UTF-8 without BOM marker
**How to avoid:** Use Nim's default `writeFile()` which writes UTF-8 without BOM
**Warning signs:** Unicode characters broken, first subtitle has weird prefix
**Source:** Phase 2 research, SRT/VTT best practices apply to ASS

### Pitfall 3: Drawtext Text Parameter Requires Proper Escaping
**What goes wrong:** Filter fails when caption text contains single quotes, colons, or backslashes
**Why it happens:** FFmpeg filter syntax uses these as special characters
**How to avoid:** Escape: `'` → `\'`, `:` → `\:`, `\` → `\\`, newline → `\n`
**Warning signs:** "Error parsing options" or captions with corrupted text
**Example:** `text='Speaker 1\: Hello!'` not `text='Speaker 1: Hello!'`

### Pitfall 4: Word Highlighting Requires Precise Timing Alignment
**What goes wrong:** Highlighted words appear before/after spoken, desync accumulates
**Why it happens:** ASS karaoke timing uses centisecond precision, must match whisper timestamps exactly
**How to avoid:** Convert ms timestamps to centiseconds: `durationCs = (endMs - startMs) div 10`
**Warning signs:** User reports "words light up too early/late" or "gradually gets out of sync"

### Pitfall 5: Caption Position Overlaps Platform UI Elements
**What goes wrong:** Captions hidden behind TikTok/Instagram buttons, cut off on mobile screens
**Why it happens:** Platform UI elements at screen edges (100-150px zones)
**How to avoid:**
- Bottom position: `y=h-150` (not `y=h-50`)
- Center position: `y=(h-text_h)/2` (safe zone)
- Top position: `y=150` (not `y=50`)
**Warning signs:** User complaints about "can't see captions" or "text behind buttons"
**Source:** [Social Media Safe Zones 2026](https://postplanify.com/blog/social-media-safe-zones-2026-complete-guide)

### Pitfall 6: Font Size Too Small on Mobile Devices
**What goes wrong:** Captions readable on desktop but illegible on phones
**Why it happens:** Font size absolute (pixels), not relative to video resolution
**How to avoid:** Minimum 48-60px for 1080p video, scale proportionally for other resolutions
**Formula:** `fontSize = max(48, videoHeight / 18)`
**Warning signs:** Mobile users report "can't read text" while desktop users have no issues
**Source:** [Video Caption Design Best Practices - OpusClip](https://www.opus.pro/blog/video-caption-design-placement)

### Pitfall 7: Insufficient Text Contrast on Variable Backgrounds
**What goes wrong:** Captions disappear against bright/dark backgrounds depending on video scene
**Why it happens:** Single color without outline/shadow loses contrast on some backgrounds
**How to avoid:**
- Always use black outline (borderw=4) with white text
- Or use background box with semi-transparent black
- Or use both outline AND shadow for maximum contrast
**Minimum:** 4.5:1 contrast ratio per WCAG accessibility guidelines
**Warning signs:** Some captions invisible in certain video scenes
**Source:** [Closed Caption Styling Best Practices - 3PlayMedia](https://www.3playmedia.com/blog/closed-caption-styling-formatting-best-practices-you-need-to-know/)

## Code Examples

Verified patterns from official sources:

### FFmpeg Drawtext Filter - Traditional Subtitle Style
```bash
# Bottom center, white text with black outline, 60px font
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
fontsize=60:\
fontcolor=white:\
borderw=4:\
bordercolor=black:\
x=(w-text_w)/2:\
y=h-150:\
text='This is a caption':\
enable='between(t,0.5,3.2)'
```
**Source:** [FFmpeg drawtext filter examples - OTTVerse](https://ottverse.com/ffmpeg-drawtext-filter-dynamic-overlays-timecode-scrolling-text-credits/)

### FFmpeg Drawtext Filter - Modern TikTok Style
```bash
# Center position, yellow highlight background, bold sans-serif
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
fontsize=72:\
fontcolor=black:\
x=(w-text_w)/2:\
y=(h-text_h)/2:\
box=1:\
boxcolor=yellow@0.8:\
boxborderw=20:\
text='THIS IS HIGHLIGHTED':\
enable='between(t,1.0,4.5)'
```

### ASS File Structure with Karaoke Timing
```ass
[Script Info]
Title: Generated Captions
ScriptType: v4.00+
WrapStyle: 0
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,60,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,4,2,2,10,10,150,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.50,0:00:03.20,Default,,0,0,0,,{\k50}This {\k80}is {\k120}a {\k90}caption
Dialogue: 0,0:00:03.50,0:00:06.00,Default,,0,0,0,,{\k60}Word {\k90}by {\k100}word
```
**Explanation:**
- `\k50` = 0.5 second duration before next word highlights
- PrimaryColour = highlighted word color (white)
- SecondaryColour = pre-highlight color (transparent for pop-in effect)
- OutlineColour = black outline for contrast
**Source:** [ASS File Format Specification](http://www.tcax.org/docs/ass-specs.htm)

### Nim Caption Style Configuration
```nim
type
  CaptionPosition* = enum
    cpBottomCenter  # Traditional subtitle position
    cpTopCenter     # Avoid bottom UI elements
    cpCenter        # TikTok/Reels style

  CaptionStyle* = object
    # Font
    fontPath*: string       # Full path to TTF/OTF file
    fontName*: string       # Name for NLE export
    fontSize*: int          # Pixels (48-72 typical)

    # Colors (hex format #RRGGBB)
    color*: string          # Text color
    speakerColors*: seq[string]  # Override color per speaker

    # Contrast options
    outline*: bool
    outlineWidth*: int      # 3-5 typical
    outlineColor*: string   # Usually black

    shadow*: bool
    shadowX*: int           # Offset in pixels
    shadowY*: int
    shadowColor*: string    # Usually black with alpha

    backgroundBox*: bool
    boxColor*: string       # Color with alpha, e.g., "black@0.6"
    boxPadding*: int        # Padding around text

    # Position
    position*: CaptionPosition
    marginBottom*: int      # Distance from bottom (when bottom-aligned)
    marginTop*: int         # Distance from top (when top-aligned)

    # Word highlighting
    highlightStyle*: string  # "karaoke" or "none"

proc getPreset*(name: string): CaptionStyle =
  case name:
  of "traditional":
    result = CaptionStyle(
      fontSize: 60,
      color: "#ffffff",
      outline: true,
      outlineWidth: 4,
      outlineColor: "#000000",
      shadow: false,
      backgroundBox: false,
      position: cpBottomCenter,
      marginBottom: 150,
      highlightStyle: "none"
    )
  of "modern", "tiktok":
    result = CaptionStyle(
      fontSize: 72,
      color: "#000000",
      outline: false,
      shadow: false,
      backgroundBox: true,
      boxColor: "#ffff00@0.8",
      boxPadding: 20,
      position: cpCenter,
      highlightStyle: "karaoke"
    )
```

### Extending FCP7 Exporter with Caption Track
```nim
# In src/exports/fcp7.nim, add after video/audio tracks:

proc addCaptionTrack(sequence: XmlNode, captions: seq[Caption],
                     styling: CaptionStyle, tb: int64, ntsc: string) =
  let track = newElement("track")

  for i, caption in captions:
    let clipitem = <>clipitem(id = &"caption-{i}")

    # Timing in FCP7 format (frames)
    clipitem.add elem("start", $caption.startMs)
    clipitem.add elem("end", $caption.endMs)
    clipitem.add elem("in", "0")
    clipitem.add elem("out", $(caption.endMs - caption.startMs))

    # Add text filter
    let filter = newElement("filter")
    let effect = newElement("effect")
    effect.add elem("name", "Text")
    effect.add elem("effectid", "text")
    effect.add elem("effectcategory", "text")
    effect.add elem("effecttype", "generator")

    # Text parameters
    effect.add param("str", "Text", caption.text)
    effect.add param("fontname", "Font", styling.fontName)
    effect.add param("fontsize", "Size", $styling.fontSize)
    effect.add param("fontcolor", "Fill Color", styling.color)

    # Position
    let (x, y) = case styling.position:
      of cpBottomCenter: (0, -200)  # Relative to center
      of cpCenter: (0, 0)
      of cpTopCenter: (0, 200)
    effect.add param("xcenter", "X", $x)
    effect.add param("ycenter", "Y", $y)

    filter.add effect
    clipitem.add filter
    track.add clipitem

  sequence.add track
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded font paths | libfontconfig font resolution | FFmpeg 4.0+ (2018) | Allows font="Arial" instead of full paths |
| SRT-only export | ASS with karaoke timing | ASS spec v4+ (2005, refined) | Enables word highlighting, advanced styling |
| Fixed caption position | Safe zone positioning | 2020+ (mobile-first) | Captions visible on TikTok/Instagram/YouTube |
| Single style output | Multiple preset styles | Current trend (2024+) | Traditional vs TikTok/Reels styles |
| Manual NLE import | Caption tracks in FCPXML | FCPXML 1.11 (2023) | Captions as editable title clips |

**Deprecated/outdated:**
- **SRT without styling:** Use ASS for burned captions (more control)
- **Fixed 40px font size:** Modern standard is 48-60px minimum for mobile readability
- **Bottom edge positioning (y=h-50):** Now 150px margin to avoid UI overlap
- **Text without outline/shadow:** Insufficient contrast, fails accessibility standards

## Open Questions

Things that couldn't be fully resolved:

1. **Exact FFmpeg build configuration for drawtext filter**
   - What we know: Requires `--enable-libfreetype` in FFmpeg build, honeyclip already has this
   - What's unclear: Does current build support `--enable-libfontconfig` for font name resolution?
   - Recommendation: Test `drawtext=font=Arial` vs `fontfile=/path/to/arial.ttf`, document which works

2. **Optimal default font for cross-platform compatibility**
   - What we know: Need TTF/OTF file that exists on Windows, Linux, macOS
   - What's unclear: Best bundled font or system font that's universally available
   - Recommendation:
     - Windows default: `C:/Windows/Fonts/arialbd.ttf` (Arial Bold)
     - Linux default: `/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf`
     - macOS default: `/Library/Fonts/Arial Bold.ttf`
     - Fall back to first found if default missing

3. **Word highlighting style for maximum readability**
   - What we know: Options include color change, scale animation, background highlight
   - What's unclear: Which is most readable and least distracting
   - Recommendation: Use ASS karaoke \k tag with color change (PrimaryColour → yellow, instant transition)

4. **Caption timing gap between groups**
   - What we know: Phase 2 uses 100-200ms gaps between caption groups
   - What's unclear: Should gaps exist in burned captions or display continuously?
   - Recommendation: Honor 100ms minimum gap for visual clarity (prevents overwhelming screen)

5. **NLE caption track layer structure**
   - What we know: Can export as single track with multiple clips or multiple tracks per speaker
   - What's unclear: What's most useful for video editors?
   - Recommendation: Single track with all captions, speaker differentiation via clip color/name

6. **Minimum display time for readability**
   - What we know: Industry uses ~1.5-2 seconds minimum for short captions
   - What's unclear: Exact formula for character count vs minimum time
   - Recommendation: `minDisplayMs = max(1500, caption.text.len * 50)` (50ms per character)

## Sources

### Primary (HIGH confidence)
- [FFmpeg drawtext filter documentation - OTTVerse](https://ottverse.com/ffmpeg-drawtext-filter-dynamic-overlays-timecode-scrolling-text-credits/) - Comprehensive examples with styling
- [FFmpeg Filters Documentation - Official](https://ffmpeg.org/ffmpeg-filters.html) - drawtext, subtitles, ass filters
- [ASS Format Specification](http://www.tcax.org/docs/ass-specs.htm) - Complete ASS file format and karaoke timing
- [ASS Override Tags - Aegisub](https://aegisub.org/docs/latest/ass_tags/) - \k karaoke tag documentation
- [Video Caption Design Best Practices - OpusClip](https://www.opus.pro/blog/video-caption-design-placement) - 2026 best practices, font sizes, positioning

### Secondary (MEDIUM confidence)
- [How to Add Subtitles with FFmpeg - Bannerbear](https://www.bannerbear.com/blog/how-to-add-subtitles-to-a-video-file-using-ffmpeg/) - subtitles vs ass filter differences
- [Closed Caption Styling Best Practices - 3PlayMedia](https://www.3playmedia.com/blog/closed-caption-styling-formatting-best-practices-you-need-to-know/) - Contrast ratios, accessibility
- [TikTok Caption Best Practices - OpusClip](https://www.opus.pro/blog/tiktok-caption-subtitle-best-practices) - Modern centered style, yellow highlights
- [Social Media Safe Zones 2026 - PostPlanify](https://postplanify.com/blog/social-media-safe-zones-2026-complete-guide) - Platform UI margins
- [FFmpeg drawtext examples - BitBucket](https://hhsprings.bitbucket.io/docs/programming/examples/ffmpeg/drawing_texts/drawtext.html) - Font path escaping, parameter examples

### Tertiary (LOW confidence - requires validation)
- WebSearch findings on TikTok/Reels caption trends (yellow highlight popularity)
- Various video editing blogs discussing font size recommendations
- Community discussions on ASS karaoke implementation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - FFmpeg drawtext/ass filters are production-proven, well-documented
- ASS karaoke timing: HIGH - Specification stable since 2005, widely used in fansubbing community
- Font selection: MEDIUM - Cross-platform font paths need validation per system
- Styling presets: HIGH - Based on 2026 industry best practices from OpusClip research
- NLE export: MEDIUM - FCP7/FCPXML exporters exist, caption track extension is straightforward
- Word highlighting: MEDIUM - ASS karaoke well-documented, but optimal style requires testing

**Research date:** 2026-02-02
**Valid until:** 60 days (stable domain, FFmpeg filter APIs rarely change)
**Next validation:** Check FFmpeg 7.x for new drawtext parameters, verify font paths on Windows/Linux test systems
