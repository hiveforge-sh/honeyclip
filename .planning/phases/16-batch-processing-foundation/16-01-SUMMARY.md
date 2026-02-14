---
phase: 16-batch-processing-foundation
plan: 01
subsystem: batch-processing
tags: [batch, toml, template, file-discovery, cli]
dependency_graph:
  requires: []
  provides:
    - "TOML template parsing (BatchTemplate type)"
    - "Video file discovery with recursive scanning"
    - "Batch subcommand CLI entry point"
  affects:
    - "CLI command registration (cli.nim, main.nim)"
    - "Project dependencies (toml_serialization)"
tech_stack:
  added:
    - "toml_serialization - TOML parsing library"
  patterns:
    - "Template-based configuration with type-safe field mapping"
    - "Recursive file discovery with extension filtering"
    - "CLI argument parsing following honeyclip command pattern"
key_files:
  created:
    - "src/batch/template.nim - TOML template parser"
    - "src/batch/discover.nim - Video file discovery"
    - "src/cmds/batch.nim - Batch subcommand entry point"
  modified:
    - "honeyclip.nimble - Added toml_serialization dependency"
    - "src/cli.nim - Registered batch command with help text"
    - "src/main.nim - Added batch handler to command table"
decisions:
  - decision: "Use toml_serialization for TOML parsing"
    rationale: "Type-safe serialization library with good Nim integration"
    alternatives: "parsetoml (manual parsing), json (different format)"
  - decision: "Store template fields as strings, convert to CLI args at runtime"
    rationale: "Defers validation to existing CLI parsing logic, avoids duplication"
    alternatives: "Parse template fields into typed structures upfront"
  - decision: "Defer batch runner implementation to Plan 16-02"
    rationale: "Establishes foundation first, parallel execution requires more design"
    alternatives: "Implement serial runner in this plan"
metrics:
  duration: 123
  tasks_completed: 2
  files_created: 3
  files_modified: 3
  completed_date: 2026-02-14
---

# Phase 16 Plan 01: Template Parser and Discovery Foundation Summary

**One-liner:** TOML template parsing with BatchTemplate type, recursive video file discovery, and batch CLI entry point

## Overview

Created the foundational infrastructure for batch processing: a TOML template parser that maps user-defined settings to CLI arguments, a video file discovery module with recursive scanning and structure-preserving output paths, and the batch subcommand skeleton with argument parsing.

Users can now define processing settings in TOML templates and run `honeyclip batch <path> --template <file.toml>` to discover video files. The batch runner (parallel execution) is deferred to Plan 16-02.

## Tasks Completed

### Task 1: Create TOML template parser and file discovery modules
**Status:** ✓ Complete
**Commit:** `eedf946`

- Added `toml_serialization` dependency to `honeyclip.nimble`
- Created `src/batch/template.nim` with:
  - `BatchTemplate` type with fields for edit, margin, whenSilent, whenNormal, outputFormat, outputSuffix, outputDir, engage, noFaces, noTranscript
  - `loadTemplate()` proc for parsing TOML files with error handling
  - `toArgs()` proc to convert template to CLI argument sequence
  - `validateTemplate()` proc to check for conflicting options
- Created `src/batch/discover.nim` with:
  - `VideoExtensions` constant with common video file extensions
  - `findVideoFiles()` proc for recursive directory scanning with alphabetical sorting
  - `generateOutputPath()` proc to preserve directory structure in output paths

**Files created:**
- `src/batch/template.nim` (66 lines)
- `src/batch/discover.nim` (42 lines)

**Files modified:**
- `honeyclip.nimble` (added dependency)

**Verification:** `nim check` passed for both modules, types exported correctly

### Task 2: Create batch subcommand with argument parsing and CLI registration
**Status:** ✓ Complete
**Commit:** `3877aee`

- Created `src/cmds/batch.nim` following existing command pattern
- Implemented argument parsing for:
  - `--template/-t` (required) - TOML template path
  - `--output/-o` (optional) - Output directory
  - `--jobs/-j` (optional) - Parallel worker count
  - `--resume` (flag) - Resume from checkpoint
  - `--dry-run` (flag) - Show files without processing
- Added template loading, validation with warnings, file discovery
- Implemented dry-run mode to list discovered files
- Registered command in `src/cli.nim` with help text
- Added handler to `src/main.nim` command table in alphabetical order
- Placeholder message for batch runner (deferred to Plan 16-02)

**Files created:**
- `src/cmds/batch.nim` (76 lines)

**Files modified:**
- `src/cli.nim` (added command registration)
- `src/main.nim` (added import and handler)

**Verification:** `nim check` passed, `nimble test` passed (no regressions)

## Deviations from Plan

None - plan executed exactly as written. No bugs found, no missing functionality, no architectural changes needed.

## Verification Results

All success criteria met:

1. ✓ `nim check src/batch/template.nim` passes
2. ✓ `nim check src/batch/discover.nim` passes
3. ✓ `nim check src/cmds/batch.nim` passes
4. ✓ `nimble test` passes (no regressions)
5. ✓ BatchTemplate type has edit, margin, whenSilent, whenNormal, outputFormat, outputSuffix fields
6. ✓ loadTemplate parses TOML file into BatchTemplate
7. ✓ toArgs converts template to CLI argument sequence
8. ✓ findVideoFiles recursively discovers video files
9. ✓ generateOutputPath preserves directory structure
10. ✓ Batch command registered in cli.nim and main.nim

## Key Implementation Details

**TOML Template Structure:**
```toml
# Example template (user-facing)
edit = "audio"
margin = "0.2s"
when-silent = "cut()"
output-format = "mp4"
output-suffix = "_edited"
engage = "50"
no-faces = false
```

**Template to CLI Args Conversion:**
- Only non-empty/non-default fields are added to argument list
- Boolean flags (noFaces, noTranscript) only added if true
- Enables reuse of existing CLI parsing and validation logic

**File Discovery:**
- Supports single file input (returns as-is) or directory (recursive scan)
- Case-insensitive extension matching
- Alphabetical sorting for deterministic processing order
- Raises IOError if path doesn't exist

**Output Path Generation:**
- Preserves relative directory structure from input root
- Appends suffix before extension (e.g., `video.mp4` → `video_edited.mp4`)
- Supports custom output directory with structure preservation
- Falls back to input directory if outputDir not specified

## Dependencies Added

- `toml_serialization` - TOML parsing with type-safe field mapping

## Next Steps

**Plan 16-02:** Batch runner with parallel execution, progress tracking, error handling, and checkpoint/resume support.

**Integration:** Template parser and file discovery are ready for runner to consume.

## Self-Check: PASSED

**Files exist:**
```
FOUND: src/batch/template.nim
FOUND: src/batch/discover.nim
FOUND: src/cmds/batch.nim
```

**Commits exist:**
```
FOUND: eedf946 (Task 1 - template parser and file discovery)
FOUND: 3877aee (Task 2 - batch subcommand and registration)
```

**Module compilation:**
```
PASSED: nim check src/batch/template.nim
PASSED: nim check src/batch/discover.nim
PASSED: nim check src/cmds/batch.nim
```

**Test suite:**
```
PASSED: nimble test (no regressions)
```

All artifacts verified. Plan 16-01 execution complete.
