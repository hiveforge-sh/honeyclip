# Codebase Concerns

**Analysis Date:** 2026-02-01

## Tech Debt

**Buffer Size Hardcoding:**
- Issue: Fixed buffer sizes throughout C FFmpeg bindings may cause issues when APIs change
- Files: `src/ffmpeg.nim` (line 132: 1024 char filename array, line 365-366: 8-element arrays for frame data), `src/render/audio.nim` (line 25: 16384 byte JSON capture buffer, line 34: 4096 byte vsnprintf buffer)
- Impact: If FFmpeg adds more streams or metadata exceeds buffer capacity, buffer overflows possible; JSON output from loudnorm filter truncated if exceeds 16KB
- Fix approach: Use dynamic allocation for variable-length data or validate against FFmpeg's actual struct sizes at build time

**Memory-Mapped Audio File Cleanup:**
- Issue: Audio buffer memory-mapped files created at `tempDir / "{index}.map"` with no explicit cleanup tracked in main scope
- Files: `src/render/audio.nim` (lines 107-112: newAudioBuffer creates memfile), `makeAudioFrames` iterator (lines 597-599, 923-928)
- Impact: Temp .map files could accumulate if iterator is abandoned or exception occurs between creation and cleanup; relies on defer blocks for cleanup
- Fix approach: Wrap cleanup in try-finally at higher scope, validate tempDir is actually cleared on startup

**Unsafe C String Handling:**
- Issue: Multiple casts from Nim strings to cstring without null termination verification
- Files: `src/render/audio.nim` (lines 39, 322, 327: strncat, av_strdup on unverified cstrings), `src/edit.nim` (line 27-80: manual string parsing with index bounds checks)
- Impact: If FFmpeg's loudnorm JSON exceeds captured_json buffer, strncat could write past bounds; manual parsing could miss edge cases
- Fix approach: Use Nim's string utilities instead of raw C functions, validate all C string lengths before operations

## Known Bugs

**Incomplete Loudnorm JSON Parsing:**
- Symptoms: EBU normalization may fail silently with "using defaults" message if JSON output incomplete or truncated
- Files: `src/render/audio.nim` (lines 747-762)
- Trigger: Large audio files where loudnorm filter generates >16KB JSON output, or FFmpeg's log callback exceeds 4096 bytes per vsnprintf call
- Workaround: Increase captured_json buffer size (line 25) and buffer size in C code (line 34); test with large files

**Uninitialized Variable in av.nim mediaLength:**
- Symptoms: biggest_pts used in return without initialization (line 139 uses biggest_pts that defaults to 0)
- Files: `src/av.nim` (line 126-139)
- Trigger: When audio stream exists but no valid PTS found in packets
- Workaround: Initializes to 0 implicitly, but logic unclear if intentional; should explicitly initialize to AV_NOPTS_VALUE

**Memory-Mapped File Handle Leak on Exception:**
- Symptoms: memFile handle not closed if exception occurs after memFile creation but before iterator completes
- Files: `src/render/audio.nim` (AudioBuffer object, lines 102-112)
- Trigger: Exception during audio processing after audioBuffer creation
- Workaround: Iterator has defer blocks (line 923-928) but only executes if iterator drains; early exit doesn't run cleanup

## Security Considerations

**yt-dlp Argument Injection:**
- Risk: User-supplied `--yt-dlp-extras` argument (line 246 in main.nim) split on spaces and passed directly to startProcess
- Files: `src/main.nim` (lines 245-246: `cmd.add(args.ytDlpExtras.split(" "))`)
- Current mitigation: Uses startProcess with poUsePath flag, which doesn't invoke shell
- Recommendations: Use proper argument array instead of string.split(); validate ytDlpExtras against whitelist of allowed flags; document that complex arguments with spaces won't work

**JSON Output Path Traversal (Minimal):**
- Risk: export --output parameter used directly in file operations without path validation
- Files: `src/edit.nim` (parseExportString at lines 27-80)
- Current mitigation: Main.nim checks if file exists before writing; Nim's file operations have some protections
- Recommendations: Add explicit path normalization/validation before any file write in main()

**Unsafe AVFilter Usage:**
- Risk: User-supplied `--edit` expression evaluated through palet expression parser with no obvious bounds checking
- Files: `src/palet/lexer.nim` (no regex, but custom lexer), `src/palet/edit.nim` (evaluation logic)
- Current mitigation: Custom lexer is not regex-based, so no ReDoS; expression parser is S-expression based
- Recommendations: Add expression complexity limit (depth/size) to prevent stack overflow; document allowed expression syntax

## Performance Bottlenecks

**Audio Resampling Two-Pass Loudnorm:**
- Problem: EBU normalization does full analysis pass (line 686-737) then full processing pass (line 764-877) on entire audio buffer
- Files: `src/render/audio.nim` (lines 658-877)
- Cause: loudnorm FFmpeg filter requires two-pass: measure then adjust with measured values
- Improvement path: Cache measurement results per file; consider streaming-style processing for very large files

**Memory-Mapped File I/O for Audio Processing:**
- Problem: Entire audio timeline buffered to disk for each layer/mixing scenario
- Files: `src/render/audio.nim` (line 110-111: memfiles.open with newFileSize = samples * channels * sizeof(int16))
- Cause: Allows handling arbitrarily large audio without RAM limits, but disk I/O slower than RAM
- Improvement path: Profile memfile vs RAM allocation for typical videos (30min @ 48kHz stereo = ~17GB, would require memfile)

**Inefficient Subtitle Extraction:**
- Problem: No caching of decoded subtitles; multiple passes re-parse same subtitle packets
- Files: `src/analyze/subtitle.nim` (decode on each analysis pass)
- Cause: Subtitle analysis run before main rendering; no cross-pass cache
- Improvement path: Cache decoded subtitles in media analysis phase, reuse in rendering

## Fragile Areas

**FFmpeg Binding Updates:**
- Files: `src/ffmpeg.nim` (807 lines of C struct definitions)
- Why fragile: Defines direct memory layouts for libavformat, libavutil, libavcodec C structures; FFmpeg API changes (e.g., v5.x to v6.x to v7.x) can change struct sizes/member order
- Safe modification: Only update if building against newer FFmpeg; add version guards (`when defined(...)`); test with `nim c tests/unit` to validate struct sizes (test at line 131-146)
- Test coverage: Unit tests validate sizeof() for structs (lines 136-146), catches layout changes

**Audio Filter Graph Setup:**
- Files: `src/render/audio.nim` (lines 269-344: createFilterGraph, lines 361-475: processAudioClip filter execution)
- Why fragile: Complex FFmpeg filter chain construction with manual buffer/frame management; errors in av_buffersrc/av_buffersink calls propagate silently as "error ..." without context
- Safe modification: Test filters independently with test media (audio_speed, audio_volume, atempo are most tested); avoid adding new complex filters without e2e testing
- Test coverage: No unit tests for filter graphs; only manual test with `python3 tests/test.py`

**Expression Parser Evaluation:**
- Files: `src/palet/lexer.nim` (201 lines), `src/palet/edit.nim` (388 lines)
- Why fragile: Custom lexer/parser with ad-hoc error handling (mostly via error() which kills program); no recovery from malformed expressions
- Safe modification: Add test cases for edge cases (empty input, deeply nested parens, invalid tokens); validate against REPL before adding
- Test coverage: Minimal; unit tests missing for lexer/parser (should test in tests/unit.nim)

**Loudnorm JSON Capture Mechanism:**
- Files: `src/render/audio.nim` (lines 19-63 embedded C code, lines 747-762 JSON parsing)
- Why fragile: Hijacks FFmpeg's global log callback to capture JSON output; buffer sizes hardcoded; depends on exact FFmpeg logging format
- Safe modification: Add buffer overflow checks; validate FFmpeg version outputs JSON in expected format; add fallback if capture fails
- Test coverage: E2E test in `python3 tests/test.py` should cover, but no unit test for edge cases

## Scaling Limits

**Audio Buffer Memory Mapping Scaling:**
- Current capacity: Limited by disk space for temp files; typical 2-hour video @ 48kHz stereo = ~34GB memfile
- Limit: Disk I/O becomes bottleneck; temp directory cleanup on exit could take minutes
- Scaling path: Implement streaming audio processing in chunks without full buffering; use named pipes instead of temp files

**Timeline Clip Resolution:**
- Current capacity: Clips stored in seq, linear search for overlap detection (timeline.nim)
- Limit: If timeline has >10000 clips, analysis becomes O(n²)
- Scaling path: Use interval tree or segment tree for efficient overlap queries

**FFmpeg Decoder Thread Count:**
- Current capacity: Auto-detect CPU cores with `thread_count = 0` (av.nim line 53)
- Limit: Very high core counts (128+) may exhaust memory; no explicit limit set
- Scaling path: Add config option for max threads; cap based on available memory

## Dependencies at Risk

**tinyre Pinned to Specific Commit:**
- Risk: tinyre (regex library) pinned to commit `77469f5` (ae.nimble line 12)
- Impact: Cannot get bug fixes or security updates without manual action
- Migration plan: Switch to Nim standard library `re` module if possible; or create nimble package release for tinyre with proper versioning

**FFmpeg Source Build Fragility:**
- Risk: ae.nimble has hardcoded codec enable/disable lists that may diverge from current FFmpeg
- Impact: Build fails if FFmpeg deprecates a codec without updating disable lists
- Migration plan: Implement runtime FFmpeg version detection; skip disabling already-removed codecs

## Missing Critical Features

**No Graceful Degradation:**
- Problem: If loudnorm filter unavailable or FFmpeg build missing audio filter support, entire audio processing fails
- Blocks: Users with minimal FFmpeg builds cannot normalize audio
- Solution: Detect filter availability at startup, disable normalization if unavailable with warning

**No Resume/Checkpoint Support:**
- Problem: Long exports (2+ hours) restart from zero if interrupted
- Blocks: Unreliable for large files or unstable systems
- Solution: Implement checkpoint saving (which clips/frames completed); resume by seeking past completed work

**No Dry-Run Mode:**
- Problem: Users cannot test --edit expression without full render
- Blocks: Iterative editing workflow tedious (must wait for full render to see if logic correct)
- Solution: Add `--dry-run` flag that shows what WOULD be cut without rendering

## Test Coverage Gaps

**Expression Parser Edge Cases:**
- What's not tested: Deeply nested parentheses, very long symbol names, boundary conditions in arithmetic
- Files: `src/palet/lexer.nim`, `src/palet/edit.nim`
- Risk: Parser crashes or hangs on malformed input; silent truncation of long identifiers
- Priority: High - expression parser is user-facing

**FFmpeg Error Handling:**
- What's not tested: Behavior when FFmpeg version lacks codec, filter returns unexpected format, stream index out of bounds
- Files: `src/av.nim`, `src/render/format.nim`, `src/render/audio.nim`
- Risk: Cryptic error messages; undefined behavior if decoder returns unexpected sample format
- Priority: High - affects reliability across FFmpeg versions

**Memory-Mapped File Cleanup:**
- What's not tested: Iterator abandonment (early break), exception during audio processing, out-of-disk scenarios
- Files: `src/render/audio.nim` (memFile cleanup)
- Risk: Orphaned temp files accumulate; no recovery from disk full
- Priority: Medium - impacts temp directory pollution

**Resampler Output Formats:**
- What's not tested: Resampler behavior with mono audio, unusual sample rates (8kHz, 384kHz), format conversion from float to int16 edge cases
- Files: `src/resampler.nim`, `src/render/audio.nim` (lines 487-565)
- Risk: Silent audio corruption (clipping, phase shift, zero audio) with edge case formats
- Priority: Medium - should test before releases

**CLI Argument Parsing:**
- What's not tested: Extremely long argument values, special characters in file paths, missing required arguments
- Files: `src/main.nim` (parseActions, many other manual parsing)
- Risk: Unexpected behavior or crashes on edge case inputs
- Priority: Low - less critical than core rendering

---

*Concerns audit: 2026-02-01*
