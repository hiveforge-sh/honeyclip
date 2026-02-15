---
phase: 19-brand-templates
plan: 01
subsystem: batch-processing
tags: [brand-config, watermark, intro-outro, caption-styles, toml]
dependency_graph:
  requires:
    - "16-01: BatchTemplate TOML parser"
    - "src/render/captions: CaptionStyle and preset system"
  provides:
    - "BrandConfig type system with TOML deserialization"
    - "Watermark FFmpeg filter generation (5 positions, opacity)"
    - "Concat demuxer file list builder for intro/outro"
    - "Caption style override system with preset loading"
  affects:
    - "19-02: CLI flag processing will use these brand modules"
    - "19-03: Integration tests will validate brand config flow"
tech_stack:
  added:
    - "src/brand/watermark.nim: FFmpeg overlay filter strings"
    - "src/brand/concat.nim: concat demuxer list generation"
    - "src/brand/styles.nim: CaptionStyle override conversion"
  patterns:
    - "Nested TOML configuration with [brand.*] sections"
    - "Pure logic modules (no CLI coupling)"
    - "FFmpeg filter string generation"
key_files:
  created:
    - path: "src/brand/watermark.nim"
      exports: ["WatermarkPosition", "parseWatermarkPosition", "buildWatermarkFilter", "buildWatermarkScaleFilter"]
      lines: 91
    - path: "src/brand/concat.nim"
      exports: ["validateConcatFiles", "buildConcatList", "cleanupConcatList"]
      lines: 51
    - path: "src/brand/styles.nim"
      exports: ["CaptionOverrides", "parseCaptionPosition", "toCaptionStyle"]
      lines: 54
  modified:
    - path: "src/batch/templates.nim"
      changes: "Added WatermarkConfig, IntroOutroConfig, CaptionStyleConfig, BrandConfig types; extended BatchTemplate; updated toArgs() and validateTemplate()"
      lines_added: 95
decisions: []
metrics:
  duration_seconds: 122
  tasks_completed: 2
  files_created: 3
  files_modified: 1
  commits: 2
  tests_added: 0
  completed_date: 2026-02-15
---

# Phase 19 Plan 01: Brand Template Core Types Summary

BrandConfig type system with nested watermark, intro/outro, and caption style configuration. Pure-logic brand modules for FFmpeg filter generation.

## What Was Built

Created the foundational type system and core brand modules for Phase 19's brand template feature:

1. **BrandConfig Type Hierarchy** - Extended `BatchTemplate` with nested brand configuration:
   - `WatermarkConfig`: Logo overlay with position, scale, opacity, offset
   - `IntroOutroConfig`: Intro/outro clip paths
   - `CaptionStyleConfig`: Caption style preset and override fields
   - `BrandConfig`: Top-level container for all brand settings

2. **Three Brand Modules** (pure logic, no CLI coupling):
   - **watermark.nim**: FFmpeg overlay filter generation
     - 5 position presets (top-left, top-right, bottom-left, bottom-right, center)
     - Opacity support via colorchannelmixer filter
     - scale2ref filter for aspect-preserving watermark scaling
   - **concat.nim**: FFmpeg concat demuxer file list builder
     - Validates intro/outro file existence
     - Generates concat list with escaped paths
     - Temp file management with cleanup
   - **styles.nim**: CaptionStyle override converter
     - Loads preset (traditional/modern/tiktok)
     - Applies field-level overrides
     - Maps position strings to CaptionPosition enum

3. **BatchTemplate Integration**:
   - `toArgs()` emits watermark/intro/outro/caption CLI flags when brand fields set
   - `validateTemplate()` warns on missing watermark image or intro/outro files
   - TOML deserialization handles nested `[brand.watermark]`, `[brand.intro_outro]`, `[brand.caption_style]` sections

## Key Decisions

None - plan executed as written. All design decisions were made during Phase 19 research.

## Deviations from Plan

None - plan executed exactly as written.

## Technical Implementation

### BrandConfig Type System

```nim
type
  WatermarkConfig* = object
    enabled*: bool
    imagePath*: string
    position*: string  # "top-left", "top-right", "bottom-left", "bottom-right", "center"
    offsetX*: int
    offsetY*: int
    scale*: float
    opacity*: float

  IntroOutroConfig* = object
    introPath*: string
    outroPath*: string

  CaptionStyleConfig* = object
    preset*: string
    fontPath*: string
    fontSize*: int
    color*: string
    position*: string
    outline*: bool
    shadow*: bool
    backgroundBox*: bool

  BrandConfig* = object
    watermark*: WatermarkConfig
    introOutro*: IntroOutroConfig
    captionStyle*: CaptionStyleConfig
```

### Watermark Filter Generation

Supports all 5 positions with FFmpeg overlay variables:

```nim
# Bottom-right: x=W-w-10, y=H-h-10
# Top-left: x=10, y=10
# Center: x=(W-w)/2, y=(H-h)/2
```

Opacity via colorchannelmixer when < 1.0:
```
[1:v]format=rgba,colorchannelmixer=aa=0.7[wm];[0:v][wm]overlay={x}:{y}:format=auto
```

### Concat List Format

FFmpeg concat demuxer format with escaped paths:
```
file 'intro.mp4'
file 'video.mp4'
file 'outro.mp4'
```

Single quotes in paths escaped as `'\''`.

### Caption Style Overrides

Preset-first approach:
1. Load base preset (traditional/modern/tiktok)
2. Apply non-default overrides (fontPath, fontSize, color, position)
3. Return merged CaptionStyle

## Files Created/Modified

**Created:**
- `src/brand/watermark.nim` (91 lines)
- `src/brand/concat.nim` (51 lines)
- `src/brand/styles.nim` (54 lines)

**Modified:**
- `src/batch/templates.nim` (+95 lines)

## Testing

All verification steps passed:
- `nim check src/batch/templates.nim` - PASS
- `nim check src/brand/watermark.nim` - PASS
- `nim check src/brand/concat.nim` - PASS
- `nim check src/brand/styles.nim` - PASS
- `nimble test` - PASS (no regressions)

No unit tests added (plan 19-03 will add comprehensive brand template tests).

## Integration Points

**Dependencies (requires):**
- Phase 16-01: `BatchTemplate` TOML parser with toml_serialization
- `src/render/captions`: `CaptionStyle`, `CaptionPosition`, `getPreset`, `escapeFilterPath`

**Provides for future plans:**
- 19-02: Brand modules ready for CLI flag processing
- 19-03: Complete brand config type system ready for integration tests

**External surface:**
- TOML template authors can now use `[brand.*]` sections
- All brand modules export public APIs for CLI integration

## Performance Notes

- Filter generation is pure string building (no I/O)
- Concat list uses temp file with random suffix (same pattern as captions.nim)
- No performance impact on existing batch processing

## Commits

| Commit | Message |
|--------|---------|
| c9feb83 | feat(19-01): extend BatchTemplate with BrandConfig types |
| c4d7a1c | feat(19-01): create brand modules for watermark, concat, and caption styles |

## Self-Check: PASSED

All files created:
- FOUND: src/brand/watermark.nim
- FOUND: src/brand/concat.nim
- FOUND: src/brand/styles.nim

All commits exist:
- FOUND: c9feb83
- FOUND: c4d7a1c

All verification commands passed:
- nim check (all modules): PASS
- nimble test: PASS
