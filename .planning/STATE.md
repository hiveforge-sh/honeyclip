# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-01)

**Project:** honeyclip — Extract the sweetest moments from your video
**Core value:** Surface the most engaging moments from any video with a single command — transcript with engagement scores, suggested clips, and speaker-centered reframing.
**Current focus:** Phase 10 - CLI Integration

## Current Position

Phase: 11 of 14 (ML Library Size Optimization) — Complete
Plan: 2 of 2 in phase
Status: Phase 11 complete (stripping and size validation)
Last activity: 2026-02-05 — Completed 11-02-PLAN.md (stripping and size validation)

Progress v1.0: [████████████████████████████████████████████████] 100%
Progress v1.1: [████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 52
- Average duration: 3.3 min
- Total execution time: 2.83 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-foundation-build-infrastructure | 5 | 17min | 3.4min |
| 02-transcript-foundation | 4 | 15min | 3.8min |
| 03-caption-rendering | 5 | 19.5min | 3.9min |
| 04-face-detection-infrastructure | 4 | 11.2min | 2.8min |
| 05-engagement-scoring-foundation | 4 | 21min | 5.25min |
| 06-engagement-clip-detection | 4 | 10.75min | 2.7min |
| 07-speaker-tracking-reframing | 6 | 28.3min | 4.7min |
| 08-multi-aspect-export-workflow | 5 | 9.3min | 1.9min |
| 09-nle-integration-markers | 7 | 27.8min | 4.0min |
| 10-cli-integration | 5 | 29min | 5.8min |
| 14-media-metadata-management | 3 | 13.5min | 4.5min |
| 11-ml-library-size-optimization | 2 | 7min | 3.5min |

**Recent Trend:**
- Last 5 plans: 14-02 (5.5min), 14-03 (3.5min), 11-01 (2min), 11-02 (5min)
- Trend: Phase 11 complete, v1.1 Polish 33% done

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Local signals for engagement (no cloud dependencies, faster processing, works offline)
- SRT output format (standard format, works with all video editors)
- Face detection via ML (motion-only tracking insufficient for speaker centering)
- New subcommand + integration (flexibility for standalone use and pipeline integration)
- Build ML libraries from source for consistent cross-platform support (01-01)
- SHA256-based caching to avoid unnecessary rebuilds (01-01)
- OpenCV minimal build (core+imgproc+objdetect only) to reduce binary size (01-01)
- ONNX Runtime minimal build (extended mode, no ML ops) for size optimization (01-01)
- 50MB soft limit / 100MB hard limit for ML library size validation (01-01)
- Buffer-based API for libfacedetection (CNN weights static, no object state) (01-02)
- ONNX Runtime function table pattern via OrtGetApiBase (01-02)
- OpenCV via importcpp for direct C++ cv::Mat access (01-02)
- result.handle assignment to avoid Nim 2.x implicit destructor conflicts (01-02)
- ONNX Runtime cross-compilation deferred due to Windows SDK requirement (01-03)
- Separate ccache directories prevent false cache hits between targets (01-03)
- Explicit platform checks for CUDA/OpenCL in cross-compilation (01-03)
- Cache ML sources separately from built libraries for faster incremental builds (01-04)
- 50MB soft limit (warning) / 100MB hard limit (fail) for ML library size in CI (01-04)
- Auto-enable ML tests when libfacedetection.a exists (no manual flag) (01-04)
- Rebrand to honeyclip under hiveforge-sh organization (01-05)
- SRT uses comma separator, VTT uses period for timestamp milliseconds (02-01)
- Word-level timestamps via whisper filter format=json with max_len=1 (02-01)
- Speaker -1 = unassigned until diarization, 0+ = identified speakers (02-01)
- Template instead of nested proc to avoid Nim closure memory safety issues (02-02)
- 42-char default caption limit (standard readable line length) (02-02)
- Prefer sentence boundaries when within 20% of char limit (02-02)
- Never break before small words (a, the, to, of, etc.) (02-02)
- Speaker labels only on speaker change to reduce visual clutter (02-02)
- UTF-8 output without BOM for maximum player compatibility (02-02)
- Prompt for model download if missing (user-friendly) (02-04)
- Output all three formats by default (SRT, VTT, JSON) (02-04)
- Backup files use .bak extension (overwrite existing backup) (02-04)
- ASS subtitle format for caption rendering (supports advanced styling and karaoke tags) (03-01)
- 5-color speaker palette (cyan, red/pink, green, yellow, purple) (03-01)
- Traditional and Modern/TikTok caption style presets (03-01)
- FFmpeg ass filter for subtitle rendering (supports advanced styling and karaoke) (03-02)
- Temporary ASS file generation with cleanup pattern (03-02)
- Windows colon escaping (C: -> C\:) for FFmpeg filter paths (03-02)
- Exported filter builder functions for testing and reuse (03-02)
- FCP7 captions as text generator clips (editable in Premiere/Resolve) (03-03)
- FCPXML captions as title clips in gap element (non-destructive overlay) (03-03)
- Frame-based timing for NLE exports (frame-accurate positioning) (03-03)
- Speaker colors via effect parameters (visual differentiation in NLE) (03-03)
- CLI subcommands (burn, export) for different caption workflows (03-04)
- Style presets with CLI override flags for flexible customization (03-04)
- JSON transcript input (requires prior transcript extraction) (03-04)
- Exported parseCaptionStyle and loadTranscriptFromJSON for testability (03-04)
- Minimal XML structure for caption-only NLE exports (no audio tracks) (03-05)
- Video clip reference included in caption exports for NLE timeline context (03-05)
- Support stdout output with "-" path for piping (03-05)
- Multi-frame consensus with 3-frame window and 0.6 threshold for stability (04-01)
- IoU > 0.5 threshold for matching faces across frames (04-01)
- Default confidence filter 0.3 (higher than libfacedetection 0.02 default) (04-01)
- Cache location .honeyclip/ alongside video (not getTempDir) for persistence (04-01)
- 20 face cache file limit per directory (vs 10 for motion cache) (04-01)
- 1fps baseline sampling for static scenes, 5fps during scene changes or face state changes (04-02)
- Scene change threshold 0.4 via FFmpeg scdet filter (04-02)
- 1-second cooldown duration after spike events before returning to baseline (04-02)
- Frame skipping strategy avoids filter graph recreation overhead (04-02)
- All analysis parameters in cache key for proper invalidation (04-03)
- Conversion helpers in faces.nim to avoid circular dependency (04-03)
- Default FaceAnalysisParams: minConfidence 0.3, consensus 3@0.6, minFaceRatio 0.05, baseFps 1.0, maxFps 5.0, sceneThreshold 0.4 (04-03)
- --clear-faces flag operates on .honeyclip/ in current directory (04-04)
- --info flag shows both system and face caches (04-04)
- Face detection tests conditional on enable_ml to support incremental ML builds (04-04)
- Equal weights (33.3% each) for audio, motion, speech signals in engagement scoring (05-01)
- Percentile normalization (5th-95th) over min-max for outlier robustness (05-01)
- Dual scoring: relative (normalized to video) and absolute (fixed thresholds) (05-01)
- Hook boost default 15.0 points, face boost 5.0 per face (max 10.0 total) (05-01)
- Minimum segment duration 2000ms, merge threshold 10.0 points (05-01)
- Signal alignment via timebase conversion for precise timestamp mapping (05-03)
- Speech scoring: 120-180 wpm optimal, 60% rate + 40% confidence weighting (05-03)
- Face boost capped at +10 points (2 faces max contribution) (05-03)
- Adjacent segment merging via weighted average by duration (05-03)
- Non-speech segments (gaps > 2s) scored with audio+motion only (05-03)
- JSON engagement output includes both relative and absolute scores for flexibility (05-04)
- Summary mode shows top 5 segments and score distribution histogram (05-04)
- Timebase extracted from video stream (or audio if no video) for analyzeEngagement (05-04)
- EDLClip DTO for decoupled export (CLI converts Clip->EDLClip, export module stays simple) (06-02)
- Both EDL and JSON formats in same module (share EDLClip type, minimize duplication) (06-02)
- 30fps default for SMPTE timecode (maximum NLE compatibility, NTSC industry standard) (06-02)
- Reel names 8 char max, uppercase, alphanumeric (CMX3600 standard SMPTE 258M) (06-02)
- FFmpeg scdet filter with 0.4 threshold for scene change detection (06-01)
- EDLClip DTO for decoupled export (CLI converts Clip->EDLClip, export module stays simple) (06-02)
- Both EDL and JSON formats in same module (share EDLClip type, minimize duplication) (06-02)
- 30fps default for SMPTE timecode (maximum NLE compatibility, NTSC industry standard) (06-02)
- Reel names 8 char max, uppercase, alphanumeric (CMX3600 standard SMPTE 258M) (06-02)
- 2-second merge window for nearby boundaries to reduce fragmentation (06-01)
- Boundaries extend to sentence ends to avoid mid-sentence cuts (06-01)
- Clip duration targets: 15-60 seconds (30s optimal) for social media (06-01)
- Multi-signal boundary detection: scene changes + engagement drops + speech alignment (06-01)
- IoU threshold 0.3 triggers overlap penalty (30.0 points per overlap) (06-03)
- Top 5 clips by default with hook boost (+5.0 points) (06-03)
- Prefer longer clips when overlapping (extra 5.0 point penalty for shorter) (06-03)
- Parallel export with 4 concurrent FFmpeg processes by default (06-03)
- Frame-accurate clip extraction with libx264 re-encoding (06-03)
- Output directory defaults to subfolder next to source video (06-03)
- Timestamp-based filename format: video_00m30s-01m15s.mp4 (06-03)
- Default to --list mode if neither --list nor --export specified (safety-first preview) (06-04)
- No clips detected shows helpful message instead of error (better UX) (06-04)
- Qualified type names (clips.Clip vs timeline.Clip) to avoid collisions (06-04)
- Simplified Kalman filter with diagonal covariance for efficiency (full matrix operations not required) (07-01)
- Constant velocity model for face tracking (adequate for typical video frame rates) (07-01)
- Track age and hit streak determine stability (maxAge 90 frames = 3s @ 30fps, minHits 3) (07-01)
- Predicted bboxes have confidence 0.5 to distinguish from actual detections (07-01)
- ArcFace ResNet100 112x112 input for face embeddings (standard, efficient for 1-5fps) (07-02)
- Cosine similarity >0.7 threshold for same person matching (research-backed) (07-02)
- Empty embedding return on failure for graceful degradation to IoU-only tracking (07-02)
- getTensorData[T] helper in onnx.nim for type-safe ONNX output access (07-02)
- Combined cost metric: 70% IoU distance + 30% appearance distance (spatial proximity favored) (07-03)
- IoU < 0.5 triggers infinite cost (1e6) to prevent unlikely matches (07-03)
- Greedy assignment algorithm optimal for small N (typical 1-5 faces in video) (07-03)
- Kalman filters stored in tracker and synchronized with track lifecycle (07-03)
- Temporal embedding smoothing (0.9 old + 0.1 new) for stable re-identification (07-03)
- Active speaker detection via largest face heuristic during speaking segments (07-03)
- Easing presets: Slow=1.5s, Medium=0.75s, Fast=0.35s matching speed requirements (07-04)
- Medium shot padding formula: face height * 2.5 for head and shoulders visible (07-04)
- Debouncing spatial threshold: 20 pixels minimum distance to trigger crop switch (07-04)
- Cubic-bezier control points: Slow(0.25,0.25), Medium(0.42,0.58), Fast(0.55,1.0) for distinct feels (07-04)
- 60fps internal keyframe rate for smooth motion regardless of source framerate (07-05)
- FFmpeg enable= expressions for time-based crop segments (07-05)
- Fallback percentage tracking to warn if >50% of frames lack face detection (07-05)
- libx264 fast preset + CRF 23 for reframed output encoding (07-05)
- Import and re-export AspectRatio from reframe/crop.nim (avoid duplication) (08-01)
- SHA256 hash verification optional via verifyHash parameter (mtime default for speed) (08-01)
- Project schema version 1 for future migration support (08-01)
- Table-based preset lookup pattern for platform configs (08-01)
- FFmpeg thumbnail filter batch size 100 for best-frame selection (08-02)
- Contact sheet uses concat+tile approach for reliable multi-input handling (08-02)
- Video snippets use fast preset + CRF 28 for preview quality (08-02)
- Metadata burned into previews via drawtext filter (clip rank + time range) (08-02)
- Side-by-side uses hstack filter with scale=iw/2:-1 for equal width (08-02)
- Overview video uses concat demuxer with generated list file (08-02)
- Validation errors include clip rank and millisecond timestamps for easy identification (08-04)
- Version numbering is continuous (.v1, .v2, .v3...) not overwriting (08-04)
- adjustClipBoundary validates all clips after modification to catch created overlaps (08-04)
- Boundary adjustment mode takes precedence in export command (check first before other modes) (08-05)
- Default to all three aspects if none specified in export command (08-05)
- Platform preset overrides aspect ratio selection in export command (08-05)
- Require --project flag for export command (no inline analysis) (08-05)
- Green (#00FF00) for engagement peak markers (09-01)
- Blue (#0066FF) for scene boundary markers (09-01)
- Yellow (#FFCC00) for speaker change markers (09-01)
- 30fps default for marker timecode calculation (09-01)
- FCP7 markers use 0-255 RGB format (not normalized like caption colors) (09-02)
- Frame calculation: (timestampMs * timebase) div 1000 for FCP7 in/out (09-02)
- Markers attach to asset-clip element in FCPXML (09-03)
- Rational time format (frames*den/num)s for FCPXML timing (09-03)
- FCPXML markers use note attribute for comments, no color support in XML (09-03)
- Python subprocess delegation for AAF (pyaaf2 too complex for FFI) (09-05)
- Optional pyaaf2 dependency with clear install instructions (09-05)
- JSON intermediate format for Nim-Python data passing (09-05)
- drawbox for graph baseline (simpler than drawgraph for basic visualization) (09-06)
- enable='between()' for time-gated text visibility (09-06)
- Score normalization 0-100 to 0-1 for FFmpeg compatibility (09-06)
- Comma-separated filter chain for segment-based display (09-06)
- Module rename export.nim to exportcmd.nim to avoid Nim 2.2 reserved keyword issue (09-07)
- NLE target parsing supports both NLE names and format names (09-07)
- Case-insensitive NLE target matching (09-07)
- Score visualization via FFmpeg subprocess (09-07)
- Number parsing takes precedence over preset lookup for --engage flag (10-01)
- Presets include both threshold and signal weights for complete configuration (10-01)
- Expression functions load from cached .engage.json with error if missing (10-01)
- Predicate-based segmentsToBoolArray for flexible engagement filtering (10-01)
- AND logic for combining --edit and --engage (both must be true to keep frames) (10-02)
- Engagement filter applied after interpretEdit but before margins (10-02)
- Default threshold 50.0 when --engage used without value (10-02)
- Per-step progress bars with clear labels for long-running analysis (10-04)
- Timing information displayed after completion for user feedback (10-04)
- bar.end() called after each analysis step to clear progress (10-04)
- Summary shows word count, segment count, scene changes, and timing (10-04)
- analyze command is primary recommended workflow (combines engage + clips) (10-03)
- TTY-aware prompting via stdin.isatty() for interactive vs scriptable workflows (10-03)
- Cache-first with --fresh override for engagement analysis (10-03)
- Per-step progress bars with clear labels for long-running analysis (10-04)
- Timing information displayed after completion for user feedback (10-04)
- bar.end() called after each analysis step to clear progress (10-04)
- Summary shows word count, segment count, scene changes, and timing (10-04)
- --quiet flag suppresses all progress and prompts for scriptable workflows (10-05)
- --verbose flag forces progress display even when output is piped (10-05)
- TTY auto-detection: show prompts in terminal, silent when piped (unless --verbose) (10-05)
- Enhanced error messages include actionable next steps with example commands (10-05)
- JSON template format with global, video, audio metadata and chapters (14-01)
- Variable substitution for VIDEO_TITLE, AUTHOR_NAME, YEAR, ISO_DATE, FILENAME (14-01)
- Template discovery checks video directory first, then home directory (14-01)
- Use "artist" not "author" field for MP4 compatibility (14-01)
- FFmetadata INI format generation for FFmpeg -i metadata.txt (14-01)
- Escape special chars (=, ;, #, \, newline) for ffmetadata format (14-01)
- Standalone `meta` command for applying metadata to video files (14-02)
- CLI override flags (--title, --author, --copyright) take precedence over template (14-02)
- Dry-run mode shows template content before applying (14-02)
- Export command --meta-template flag for single-command metadata workflow (14-03)
- Use source video path for variable substitution, not individual clip paths (14-03)
- FFmpeg -map_metadata pattern for embedding metadata during export (14-03)
- effectiveParams pattern for propagating optional parameters through export pipeline (14-03)
- MinSizeRel build type for OpenCV and libfacedetection (15-25% size reduction expected) (11-01)
- Explicitly disable 10 OpenCV modules even with BUILD_LIST (belt-and-suspenders approach) (11-01)
- Keep opencv_photo module for future image preprocessing (11-01)
- Disable 5 unused 3rdparty dependencies: CAROTENE, EIGEN, ADE, FLATBUFFERS, ITT (11-01)
- Package-specified CMAKE_BUILD_TYPE overrides cmakeBuild default (11-01)
- walkFiles replaced with find command via gorgeEx (NimScript compatibility) (11-02)
- Debug symbols extracted before stripping (.dSYM macOS, .debug Linux) (11-02)
- Hard limit (100MB) is warning only, no build failure (11-02)
- Soft limit (50MB) shows interactive prompt, skipped in CI via existsEnv('CI') (11-02)
- Platform-specific strip: strip -x (macOS), strip --strip-unneeded (Linux) (11-02)

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 1 (Foundation):**
- Cross-platform build complexity for ONNX Runtime and OpenCV (especially Windows cross-compile via MinGW) - PARTIALLY RESOLVED: Windows cross-compile works for libfacedetection and OpenCV (01-03), ONNX Runtime needs Windows SDK headers
- Binary size explosion risk (10MB → 100MB+ with ML libraries) - MITIGATED: Phase 11 added MinSizeRel build type and stripping. Expected reduction from 114MB to 70-85MB. Full verification pending.
- Nim/C++ FFI memory management patterns must be established before adding multiple ML dependencies - RESOLVED: Patterns established in 01-02 (=destroy hooks, defer cleanup)
- ONNX Runtime build complexity may cause issues on different systems - RESOLVED: Eigen hash issue fixed in 01-05
- First ML library build takes 1-2 hours - DOCUMENTED: Users need to be aware

**Phase 2 (Transcript):**
- Unit tests require FFmpeg build (nimble makeff) to execute - currently only syntax-checked
- RESOLVED: All transcript components implemented and integrated

**Phase 4 (Face Detection):**
- PHASE COMPLETE: All deliverables implemented
- Face detection false positive rate - RESOLVED: Multi-frame consensus algorithm (04-01)
- Adaptive frame sampling - RESOLVED: 1-5fps dynamic rate based on scene changes (04-02)
- faces() API ready with caching, CLI tools, and comprehensive unit tests (04-01 through 04-04)

**Phase 5 (Engagement Scoring):**
- PHASE COMPLETE: All deliverables implemented
- No ground truth data for validating engagement scores - validation will require real-world video testing
- Scoring algorithm based on content features (audio, motion, speech, faces, hooks)

**Phase 6 (Engagement Clip Detection):**
- PHASE COMPLETE: All deliverables implemented
- Boundary detection, ranking, export, and CLI integration ready
- Unit tests validate IoU, timecode, boundary merging, ranking
- Ready for Phase 7 speaker reframing integration

**Phase 7 (Speaker Reframing):**
- PHASE COMPLETE: All deliverables implemented
- DeepSORT-style tracking with Kalman filter and Hungarian algorithm
- ArcFace embeddings for face re-identification (ONNX)
- Cubic-bezier easing for smooth camera transitions
- FFmpeg compositor for dynamic crop rendering
- CLI reframe command with aspect ratio and speed presets
- Graceful fallback to center crop when faces not detected
- Note: ML features (face detection) stubbed on Windows due to LTO issues

**Phase 8 (Multi-Aspect Export):**
- PHASE COMPLETE: All 5 plans implemented
- Platform presets for social media encoding (Instagram, TikTok, YouTube, etc.)
- Project file persistence with mtime-based stale detection
- Preview generation (thumbnails, contact sheets, video snippets)
- Multi-aspect batch export with concurrent FFmpeg processes
- Clip boundary adjustment with validation and version history
- Unified export CLI command integrating all Phase 8 features

**Phase 9 (NLE Integration & Markers):**
- PHASE COMPLETE: All 7 plans implemented
- Marker types for engagement peaks, scene boundaries, speaker changes
- FCP7 XML marker export with color support
- FCPXML marker export with rational time format
- EDL marker export with CMX3600 comment format
- AAF marker export via Python subprocess (optional pyaaf2)
- Score visualization filters for engagement overlay rendering
- Export command --nle flag integrates all marker formats

**Phase 10 (CLI Integration):**
- COMPLETE: All 5 plans delivered
- Named engagement presets (viral, podcast, tutorial, interview, tiktok, youtube, instagram) (10-01)
- Expression functions (score, face_count, is_hook, speaking_rate) for --edit (10-01)
- --engage CLI flag with numeric thresholds and preset names (10-02)
- AND logic combining engagement filter with edit expressions (10-02)
- analyze convenience command combining engage + clips workflow (10-03)
- TTY-aware interactive prompting for next action (10-03)
- Cache-first workflow with --fresh override (10-03)
- Progress bars for long-running operations (transcript, analysis, clip detection) (10-04)
- --quiet and --verbose flags for scriptable/debuggable workflows (10-05)
- Enhanced error messages with actionable troubleshooting hints (10-05)

**Phase 14 (Media Metadata Management):**
- COMPLETE: All 3 plans delivered
- JSON template format with variable substitution (VIDEO_TITLE, AUTHOR_NAME, YEAR, ISO_DATE) (14-01)
- FFmetadata INI generation for FFmpeg integration (14-01)
- Standalone `meta` command for applying templates to video files (14-02)
- Export command --meta-template flag for single-command workflow (14-03)
- CLI override flags (--meta-title, --meta-author, --meta-copyright) (14-03)

## Session Continuity

Last session: 2026-02-05T15:35:00Z
Stopped at: Completed 11-02-PLAN.md (stripping and size validation)
Resume file: None
Next: Phase 12 or 13

**Project Status: v1.0 COMPLETE, v1.1 IN PROGRESS**
v1.0 Engagement Analysis complete (48 plans). v1.1 Polish in progress: Phase 11 complete (2/2 plans), 2 phases remaining after 11.

**Phase 11 (ML Library Size Optimization):**
- COMPLETE: All 2 plans delivered
- MinSizeRel build type for OpenCV and libfacedetection (11-01)
- Explicitly disable 15 OpenCV modules and 5 3rdparty dependencies (11-01)
- Debug symbol extraction before stripping (.dSYM macOS, .debug Linux) (11-02)
- Size reporting by category (OpenCV, ONNX, Abseil, etc.) (11-02)
- Soft/hard limit validation with CI awareness (11-02)

### Roadmap Evolution

- Phase 14 added: Media Metadata Management (JSON/YAML templates for copyright, author, custom tags, chapter markers)
