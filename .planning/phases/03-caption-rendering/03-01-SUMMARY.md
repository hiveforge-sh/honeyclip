---
phase: 03-caption-rendering
plan: 01
title: "Caption Style Foundation"
subsystem: rendering
completed: 2026-02-02
duration: 4min

requires:
  - 02-02-transcript-grouping

provides:
  - caption-styling-types
  - ass-file-generation
  - speaker-color-palette

affects:
  - 03-02-subtitle-burning

tech-stack:
  added: []
  patterns:
    - "ASS subtitle format with karaoke tags for word-level timing"
    - "Platform-specific default font paths"
    - "Color conversion: hex (#RRGGBB) to ASS BGR format (&HAABBGGRR)"

key-files:
  created:
    - src/render/captions.nim
  modified:
    - tests/unit.nim

decisions:
  - id: ass-subtitle-format
    choice: ASS format for subtitle generation
    rationale: "Supports advanced styling (outline, shadow, background box) and karaoke tags for word-level timing, more flexible than SRT/VTT"
    date: 2026-02-02

  - id: speaker-color-palette
    choice: 5-color palette (cyan, red/pink, green, yellow, purple)
    rationale: "Visually distinct colors for speaker differentiation, standard palette size covers most use cases"
    date: 2026-02-02

  - id: preset-styles
    choice: Traditional and Modern/TikTok presets
    rationale: "Traditional (outline, bottom-center) for standard videos, Modern (background box, center) for social media content"
    date: 2026-02-02

tags:
  - captions
  - subtitles
  - ass-format
  - styling
  - rendering
---

# Phase 3 Plan 1: Caption Style Foundation Summary

**One-liner:** ASS subtitle generation with configurable styling, speaker colors, and word-level karaoke timing

## What Was Built

Created caption styling system and ASS subtitle file generator for Phase 3 caption rendering. Establishes foundation for burning captions into video with customizable appearance.

### Components

**Caption Styling Types** (src/render/captions.nim):
- CaptionPosition enum: bottom-center, top-center, center
- CaptionStyle object with font, color, outline, shadow, and background box options
- Speaker color palette with 5 distinct colors
- Platform-specific default font paths (Windows, Linux, macOS)

**Style Presets**:
- Traditional: White text, black outline, bottom-center, 60px font
- Modern/TikTok: Black text, yellow background box, center position, 72px font

**ASS Format Utilities**:
- formatASSTime: Convert milliseconds to H:MM:SS.cc format
- escapeASSText: Escape special ASS characters
- colorToASS: Convert hex #RRGGBB to ASS &HAABBGGRR format (BGR order)
- getASSAlignment: Map position to ASS alignment values

**ASS Generation**:
- generateASSHeader: Create [Script Info] and [V4+ Styles] sections
- generateASSDialogue: Create dialogue lines with karaoke tags and speaker colors
- generateASS: Combine header and events into complete ASS file
- writeASSFile: Write ASS content to disk

**Testing**:
- Unit tests for time formatting, color conversion, speaker colors
- Unit tests for style presets
- Unit tests for ASS text escaping
- Unit tests for dialogue generation (simple and karaoke modes)

### Key Features

1. **Configurable Styling**: Font, color, position, outline, shadow, background box all customizable
2. **Speaker Colors**: Automatic color assignment for speaker differentiation
3. **Word Highlighting**: Karaoke tags (\k) for word-by-word reveal effect
4. **ASS Format**: Full ASS subtitle format support with advanced styling
5. **Presets**: Ready-to-use styles for common use cases

## Technical Decisions

**ASS Subtitle Format**:
- Chose ASS over SRT/VTT for caption rendering
- Supports advanced styling (outline, shadow, background box)
- Karaoke tags (\k) enable word-level timing for highlight effect
- Standard format supported by FFmpeg subtitle filter

**Color Format Conversion**:
- ASS uses BGR order with alpha prefix (&HAABBGGRR)
- Implementation converts standard hex colors (#RRGGBB) to ASS format
- Alpha channel: 00=opaque, FF=transparent (inverted from typical)

**Speaker Color Palette**:
- 5 colors chosen for visual distinctiveness
- Palette size covers typical use cases (most videos have 2-3 speakers)
- Out-of-range speakers fall back to white (default)

**Platform-Specific Fonts**:
- Default to system fonts (Arial Bold on Windows/macOS, DejaVu Sans Bold on Linux)
- Ensures captions work out-of-box without font installation
- Users can override with custom font paths

## Implementation Notes

**ASS Time Format**:
- ASS uses centiseconds (hundredths of second), not milliseconds
- Format: H:MM:SS.cc (single digit hour, unlike SRT/VTT HH:MM:SS)
- Example: 1234ms → "0:00:01.23"

**Background Box Handling**:
- BorderStyle=3 for opaque box, BorderStyle=1 for outline
- Box color specified with alpha in color@alpha format
- Named colors (yellow, black, white) converted to hex

**Karaoke Tags**:
- Format: {\kDuration}word where Duration is in centiseconds
- Applied per-word when highlightEnabled=true
- Timing extracted from Word.startMs and Word.endMs

**Speaker Color Override**:
- Two levels: style.speakerColors (custom) and SpeakerColorPalette (default)
- Custom colors take precedence
- Applied via {\c&HBBGGRR&} tag at dialogue start

## Testing Results

All unit tests compile successfully. Runtime testing requires FFmpeg build (documented blocker in STATE.md).

Tests verify:
- Time conversion accuracy (0ms, 1234ms, 3661234ms)
- Color conversion correctness (hex to BGR order)
- Speaker color palette coverage (0-4 plus invalid)
- Preset configuration values
- ASS text escaping (backslash, braces, newlines)
- Dialogue generation structure

## Files

**Created**:
- `src/render/captions.nim` (305 lines)
  - CaptionStyle type and presets
  - ASS format utilities
  - ASS generation procs
  - Speaker color palette

**Modified**:
- `tests/unit.nim` (+102 lines)
  - Caption styling tests
  - ASS format tests

## Commits

1. `c192a78` - feat(03-01): create caption styling types and presets
2. `fc50a19` - feat(03-01): implement ASS subtitle file generation
3. `0480b05` - test(03-01): add unit tests for caption styling and ASS generation

## Deviations from Plan

None - plan executed exactly as written.

## Known Limitations

1. **Limited Speaker Colors**: Only 5 colors defined, speakers beyond index 4 use white
2. **Font Availability**: Default font paths may not exist on all systems
3. **Named Colors**: Only yellow, black, white supported for background box color parsing
4. **Runtime Testing**: Unit tests require FFmpeg build to execute (compile-time verification only)

## Next Phase Readiness

**Ready for Plan 03-02** (Subtitle Burning):
- ASS file generation complete
- Caption styles configurable
- Speaker colors implemented
- Word-level timing via karaoke tags

**Blockers**: None

**Follow-up Work**:
- Add font validation (check if fontPath exists before using)
- Expand named color support for box backgrounds
- Add more speaker colors for large multi-speaker videos
- Runtime unit tests once FFmpeg is built

## Metrics

- Lines added: 407
- Lines modified: 102
- Files created: 1
- Files modified: 1
- Tests added: 11
- Duration: 4 minutes
