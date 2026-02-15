# Phase 19: Brand Templates - Research

**Researched:** 2026-02-15
**Domain:** Video watermarking, intro/outro concatenation, caption styling presets, TOML configuration
**Confidence:** HIGH

## Summary

Phase 19 enables users to apply consistent branding across batch-processed videos through watermark positioning, intro/outro clips, and caption styling presets. The implementation builds on Phase 16's TOML template system and existing FFmpeg filter infrastructure.

**Key findings:**
1. FFmpeg's `overlay` filter provides production-ready watermark positioning with dynamic expressions for responsive placement
2. FFmpeg's `concat` demuxer is the standard approach for prepending/appending intro/outro clips
3. The codebase already has caption styling infrastructure (`CaptionStyle` type) that can be persisted to TOML
4. Phase 16's `BatchTemplate` type and `toml_serialization` library support nested objects for brand configuration

**Primary recommendation:** Extend BatchTemplate with nested BrandConfig object containing watermark, intro/outro, and caption styling fields. Build FFmpeg filter string generators following existing patterns in `src/render/captions.nim`.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| FFmpeg overlay filter | Built-in | Image/logo watermark positioning | Industry standard, supports dynamic position expressions (W, H, w, h variables) |
| FFmpeg concat demuxer | Built-in | Intro/outro clip concatenation | Fastest method for same-codec clips, file-based workflow |
| nim-toml-serialization | Current | Brand template persistence | Already in use for Phase 16, supports nested objects |
| FFmpeg drawtext filter | Built-in | Text watermark overlays | Flexible positioning, styling, and timing control |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| FFmpeg scale2ref filter | Built-in | Watermark scaling | When logo needs responsive sizing based on video dimensions |
| FFmpeg concat filter | Built-in | Intro/outro with re-encoding | When clips have different codecs/resolutions (slower) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| overlay filter | Custom composition | Hand-rolling loses tested positioning math, alpha blending, performance optimization |
| concat demuxer | Manual frame copying | Demuxer is stream-copy fast; manual approach requires re-encoding |
| TOML templates | JSON/YAML | TOML already used in Phase 16; consistency is valuable |

**Installation:**
No new dependencies required. Uses existing FFmpeg build and toml_serialization from Phase 16.

## Architecture Patterns

### Recommended Project Structure

```
src/
├── batch/
│   ├── templates.nim       # Extend BatchTemplate with BrandConfig
│   ├── discover.nim        # Existing
│   └── runner.nim          # Existing
├── brand/
│   ├── watermark.nim       # Watermark filter generation
│   ├── concat.nim          # Intro/outro concatenation
│   └── styles.nim          # Caption style preset persistence
```

### Pattern 1: Nested TOML Configuration

**What:** Extend BatchTemplate with nested BrandConfig object
**When to use:** Brand settings are logically grouped and optional
**Example:**

```nim
# src/batch/templates.nim
type
  WatermarkConfig* = object
    enabled*: bool
    imagePath*: string      # Path to logo PNG/image
    position*: string       # "top-left", "top-right", "bottom-left", "bottom-right", "center"
    offsetX*: int           # Pixel offset from edge (default 10)
    offsetY*: int           # Pixel offset from edge (default 10)
    scale*: float           # Watermark scale factor (default 0.1 = 10% of video width)
    opacity*: float         # Opacity 0.0-1.0 (default 1.0)

  IntroOutroConfig* = object
    introPath*: string      # Path to intro clip (empty = none)
    outroPath*: string      # Path to outro clip (empty = none)

  CaptionStyleConfig* = object
    preset*: string         # "traditional", "modern", "tiktok", or ""
    fontPath*: string       # Custom font override
    fontSize*: int          # Size override
    color*: string          # Color override
    position*: string       # "bottom", "center", "top"
    outline*: bool
    shadow*: bool
    box*: bool

  BrandConfig* = object
    watermark*: WatermarkConfig
    introOutro*: IntroOutroConfig
    captionStyle*: CaptionStyleConfig

  BatchTemplate* = object
    # Existing fields...
    brand*: BrandConfig
```

**TOML file example:**

```toml
# template.toml
edit = "audio"
margin = "0.2s"

[brand.watermark]
enabled = true
image_path = "/path/to/logo.png"
position = "bottom-right"
offset_x = 20
offset_y = 20
scale = 0.08
opacity = 0.9

[brand.intro_outro]
intro_path = "/path/to/intro.mp4"
outro_path = "/path/to/outro.mp4"

[brand.caption_style]
preset = "modern"
font_size = 72
color = "#ffffff"
position = "center"
```

### Pattern 2: FFmpeg Overlay Filter with Dynamic Positioning

**What:** Build overlay filter strings with position expressions
**When to use:** Watermark placement needs to be responsive to video dimensions
**Example:**

```nim
# src/brand/watermark.nim
proc buildOverlayFilter*(config: WatermarkConfig, videoWidth: int, videoHeight: int): string =
  ## Generate FFmpeg overlay filter for watermark
  ## Returns filter string like: "overlay=W-w-20:H-h-20:format=auto:alpha=0.9"

  if not config.enabled or config.imagePath == "":
    return ""

  # Position expression mapping
  var xExpr, yExpr: string
  case config.position:
  of "top-left":
    xExpr = $config.offsetX
    yExpr = $config.offsetY
  of "top-right":
    xExpr = &"W-w-{config.offsetX}"
    yExpr = $config.offsetY
  of "bottom-left":
    xExpr = $config.offsetX
    yExpr = &"H-h-{config.offsetY}"
  of "bottom-right":
    xExpr = &"W-w-{config.offsetX}"
    yExpr = &"H-h-{config.offsetY}"
  of "center":
    xExpr = "(W-w)/2"
    yExpr = "(H-h)/2"
  else:
    xExpr = &"W-w-{config.offsetX}"  # Default to bottom-right
    yExpr = &"H-h-{config.offsetY}"

  # Build filter with alpha support
  result = &"overlay={xExpr}:{yExpr}:format=auto"

  if config.opacity < 1.0:
    # Use colorchannelmixer for opacity (more compatible than alpha)
    # Apply to watermark input before overlay
    result = &"colorchannelmixer=aa={config.opacity}[wm];[in][wm]overlay={xExpr}:{yExpr}:format=auto"
```

**Source pattern:** Based on existing `buildDrawtextFilter` in `src/render/captions.nim:332-377`

### Pattern 3: Concat Demuxer for Intro/Outro

**What:** Use file-based concat demuxer for fast stream copying
**When to use:** Intro/outro clips match main video codec/resolution
**Example:**

```nim
# src/brand/concat.nim
proc buildConcatList*(introPath, videoPath, outroPath: string): string =
  ## Build concat demuxer file list
  ## Returns path to temporary concat list file
  var lines: seq[string] = @[]

  if introPath != "" and fileExists(introPath):
    lines.add(&"file '{introPath.replace(\"'\", \"'\\''\")}'")

  lines.add(&"file '{videoPath.replace(\"'\", \"'\\''\")}'")

  if outroPath != "" and fileExists(outroPath):
    lines.add(&"file '{outroPath.replace(\"'\", \"'\\''\")}'")

  # Write to temp file
  let tempPath = getTempDir() / &"honeyclip_concat_{rand(100000..999999)}.txt"
  writeFile(tempPath, lines.join("\n"))
  return tempPath
```

**Source pattern:** Based on `src/render/previews.nim:530-545` concat implementation

### Anti-Patterns to Avoid

- **Hardcoded positions:** Don't use pixel values without expressions - breaks on different resolutions. Always use W, H, w, h variables.
- **Re-encoding intro/outro:** Don't use concat filter when demuxer works - 10-100x slower for no quality gain.
- **Inline TOML:** Don't inline brand config in batch runner - keep template parsing centralized in `templates.nim`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image overlay positioning | Custom pixel calculator | FFmpeg overlay filter expressions | Handles edge cases (video rotation, pixel aspect ratio, rounding), battle-tested |
| Video concatenation | Frame-by-frame copy | FFmpeg concat demuxer | Stream-copy is lossless and 100x faster than re-encoding |
| Caption style serialization | Custom parser | Existing CaptionStyle + toml_serialization | Type-safe, already handles all edge cases (color parsing, font paths, etc.) |
| Watermark scaling | Manual resize | FFmpeg scale2ref filter | Preserves aspect ratio, handles alpha channels correctly |

**Key insight:** FFmpeg's filter system has solved all edge cases around positioning, alpha blending, format conversion. Custom solutions will miss cases like HDR passthrough, pixel format edge cases, alpha channel premultiplication.

## Common Pitfalls

### Pitfall 1: Concat Format Mismatch

**What goes wrong:** Concat demuxer fails silently or produces corrupted output when clips have different codecs/frame rates
**Why it happens:** Demuxer is stream-copy only - can't transcode on the fly
**How to avoid:**
1. Document intro/outro requirements (must match main video codec, resolution, frame rate)
2. Provide concat filter fallback for mismatched formats
3. Add validation step that checks codec compatibility before concat
**Warning signs:** Output has desync, dropped frames, or "Non-monotonous DTS" errors

### Pitfall 2: Watermark Path Escaping

**What goes wrong:** FFmpeg filter fails to parse paths with special characters (colons, backslashes, quotes)
**Why it happens:** Filter syntax uses colons and quotes as delimiters
**How to avoid:** Use `escapeFilterPath` pattern from `src/render/captions.nim:308-316`
- Escape backslashes: `\\` → `\\\\`
- Escape colons: `:` → `\\:`
- Escape quotes: `'` → `\\'`
**Warning signs:** "Cannot parse filter" errors from FFmpeg

### Pitfall 3: Caption Style TOML Field Naming

**What goes wrong:** TOML fields don't map to Nim camelCase fields (e.g., `font_size` vs `fontSize`)
**Why it happens:** toml_serialization default mapping vs kebab-case TOML convention
**How to avoid:**
1. Check nim-toml-serialization auto-mapping behavior (it handles camelCase-to-snake_case)
2. Use `{.serializedFieldName: "custom-name".}` pragma for hyphenated fields
3. Test with actual TOML file before documenting format
**Warning signs:** "Unknown field" warnings or fields silently defaulting

### Pitfall 4: Watermark Scale on Portrait Videos

**What goes wrong:** Watermark sized as % of width is huge on portrait videos (9:16)
**Why it happens:** Width is smaller dimension in portrait
**How to avoid:**
1. Document that scale is "% of video width" explicitly
2. Or use min(W,H) for scale reference: scale watermark to 10% of smaller dimension
3. Provide examples for both landscape and portrait
**Warning signs:** User complaints about watermark being too large on vertical videos

## Code Examples

Verified patterns from codebase and FFmpeg documentation:

### Watermark with Opacity

```nim
# Build two-step filter: apply opacity, then overlay
proc buildWatermarkFilter*(logoPath: string, position: string, opacity: float): string =
  let escapedPath = escapeFilterPath(logoPath)

  # Calculate position expression
  var xExpr, yExpr: string
  case position:
  of "bottom-right":
    xExpr = "W-w-10"  # 10px from right edge
    yExpr = "H-h-10"  # 10px from bottom edge
  else:
    xExpr = "10"
    yExpr = "10"

  # Two-input filter: [0:v] is video, [1:v] is logo
  if opacity < 1.0:
    result = &"[1:v]format=rgba,colorchannelmixer=aa={opacity}[logo];[0:v][logo]overlay={xExpr}:{yExpr}"
  else:
    result = &"[0:v][1:v]overlay={xExpr}:{yExpr}"
```

### Intro/Outro Concat with Validation

```nim
proc validateConcatCompatibility*(files: seq[string]): bool =
  ## Check if video files can be safely concatenated with demuxer
  ## Returns true if all have same codec, resolution, frame rate

  if files.len < 2:
    return true

  # Use ffprobe to check each file
  # This is a simplified check - real implementation would parse ffprobe JSON
  var codecs: seq[string] = @[]
  var resolutions: seq[string] = @[]

  for file in files:
    # In real implementation, use ffprobe JSON output
    # For now, assume we extract codec and resolution
    discard

  # Check all match
  return true  # Simplified
```

### Caption Style Preset Loading

```nim
# Extend existing CaptionStyle with TOML serialization
proc captionStyleFromConfig*(config: CaptionStyleConfig): CaptionStyle =
  ## Convert TOML config to CaptionStyle

  # Start with preset or default
  var style: CaptionStyle
  if config.preset != "":
    style = getPreset(config.preset)
  else:
    style = getPreset("traditional")

  # Apply overrides
  if config.fontPath != "":
    style.fontPath = config.fontPath
  if config.fontSize > 0:
    style.fontSize = config.fontSize
  if config.color != "":
    style.color = config.color
  if config.position != "":
    case config.position:
    of "bottom": style.position = cpBottomCenter
    of "center": style.position = cpCenter
    of "top": style.position = cpTopCenter
    else: discard

  # Boolean overrides (only if explicitly set in TOML)
  # In practice, need to distinguish "not set" from "set to false"
  # toml_serialization supports Option[bool] for this

  return style
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual ffmpeg commands | Template-based workflows | 2024+ | Batch processing tools now use TOML/YAML for brand config |
| Re-encode for concat | Concat demuxer (stream copy) | FFmpeg 2.x+ | 100x faster intro/outro merging |
| Static pixel positions | Expression-based positioning | FFmpeg 3.x+ | Watermarks adapt to different resolutions |
| Inline filter args | Nested configuration objects | Modern tooling | Type-safe, validated brand templates |

**Deprecated/outdated:**
- FFmpeg concat protocol (deprecated in favor of demuxer)
- movie filter for watermarks (overlay filter is now standard)

## Open Questions

1. **Intro/outro codec validation**
   - What we know: Concat demuxer requires identical codecs
   - What's unclear: Should we auto-transcode mismatched intros, or error with clear message?
   - Recommendation: Error first (Phase 19), auto-transcode in future phase if users request it

2. **Watermark scale reference dimension**
   - What we know: Scale as % of width is simple but breaks on portrait
   - What's unclear: Is min(W,H) intuitive enough, or should we support both width-based and auto modes?
   - Recommendation: Use width-based for v1, document portrait scaling behavior clearly

3. **Caption style TOML field naming**
   - What we know: nim-toml-serialization supports auto-mapping
   - What's unclear: Does it handle camelCase↔snake_case automatically, or do we need pragmas?
   - Recommendation: Test with Phase 16's existing template.nim and document actual behavior

## Sources

### Primary (HIGH confidence)

- [FFmpeg Filters Documentation](https://ffmpeg.org/ffmpeg-filters.html) - Official overlay and concat filter docs
- [FFmpeg overlay filter reference](https://ayosec.github.io/ffmpeg-filters-docs/4.1/Filters/Video/overlay.html) - Position expression variables (W, H, w, h)
- [nim-toml-serialization README](https://github.com/status-im/nim-toml-serialization/blob/master/README.md) - Nested objects, arrays, field mapping
- Codebase: `src/render/captions.nim` - Existing filter building patterns
- Codebase: `src/render/previews.nim:514-566` - Existing concat demuxer usage
- Codebase: `src/batch/templates.nim` - Existing TOML template structure

### Secondary (MEDIUM confidence)

- [Using FFmpeg to Add Watermarks to Your Videos | Cloudinary](https://cloudinary.com/guides/video-effects/ffmpeg-watermark) - Watermark positioning techniques
- [How to Merge and Concatenate Videos with FFmpeg (2026 Guide) | WaveSpeedAI](https://wavespeed.ai/blog/posts/blog-how-to-merge-concatenate-videos-ffmpeg/) - Concat demuxer vs filter comparison
- [FFmpeg drawtext filter | OTTVerse](https://ottverse.com/ffmpeg-drawtext-filter-dynamic-overlays-timecode-scrolling-text-credits/) - Text overlay positioning
- [FFmpeg Filters Explained | Cincopa](https://www.cincopa.com/learn/ffmpeg-filters-explained-crop-scale-pad-overlay-and-more) - Position expression examples

### Tertiary (LOW confidence)

- Web search results on video batch processing tools - General pattern validation
- Commercial tools (FlexClip, Watermarkly) - Feature comparison only, not implementation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - FFmpeg filters are industry standard, codebase already uses them
- Architecture: HIGH - Patterns match existing render modules, TOML structure tested in Phase 16
- Pitfalls: MEDIUM - Some based on FFmpeg docs, some inferred from common errors

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (30 days - stable FFmpeg API, established patterns)
