# Phase 16: Batch Processing Foundation - Research

**Researched:** 2026-02-14
**Domain:** Batch Processing, Parallel Execution, Job Persistence
**Confidence:** HIGH

## Summary

Batch processing in CLI tools requires four core components: (1) configuration templates, (2) parallel file processing, (3) progress tracking with ETA, and (4) resume/checkpoint mechanisms. For honeyclip, we'll implement this using TOML for templates, Nim's malebolgia for parallel processing, a simple file-based checkpoint system, and enhance the existing custom progress bar.

The research reveals that Nim's standard `threadpool` is deprecated in favor of modern alternatives: `malebolgia` (structured concurrency, 300 LOC) and `taskpools` (lightweight task parallelism). For file-based checkpoint systems, the simplest pattern is tracking completed files in a state file (JSON or simple text list) that gets updated after each successful completion. TOML 1.0 support is available via `nim-toml-serialization` with direct type mapping.

**Primary recommendation:** Use malebolgia for parallel processing (simpler API, structured concurrency), nim-toml-serialization for TOML templates, enhance existing util/bar.nim for multi-file progress, and implement a simple JSON-based checkpoint file to track completion state.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| nim-toml-serialization | latest | TOML parsing/serialization | TOML 1.0 spec compliance, direct-to-type parsing without tokens, maintained by Status-im |
| malebolgia | latest | Parallel processing | Recommended replacement for deprecated threadpool, structured concurrency, minimal footprint (~300 LOC) |
| std/os | stdlib | File system operations | Built-in support for walkDirRec, file globbing patterns |
| std/json | stdlib | Checkpoint persistence | Simple, human-readable state tracking |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| taskpools | latest | Alternative parallel lib | If you need explicit thread pool control or blockchain security requirements |
| db_sqlite | stdlib | SQLite persistence | Only if checkpoint data becomes complex (multi-user, queries, complex state) |
| tiny_sqlite | latest | Type-safe SQLite wrapper | If using SQLite and want type safety over db_sqlite's string-based API |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| malebolgia | taskpools | taskpools is more explicit (spawn returns FlowVar[T]), malebolgia has cleaner barrier API |
| malebolgia | weave | weave is higher performance but heavier weight (optimized for compute), overkill for file I/O |
| JSON checkpoint | SQLite | SQLite adds dependency weight, only needed for complex queries or concurrent access |
| nim-toml-serialization | parsetoml | parsetoml only supports TOML 0.5.0 vs 1.0.0, lacks serialization features |

**Installation:**
```bash
nimble install toml_serialization
nimble install malebolgia
# stdlib modules need no installation
```

## Architecture Patterns

### Recommended Project Structure
```
src/
├── cmds/
│   └── batch.nim           # New batch command handler
├── batch/
│   ├── template.nim        # TOML template parsing and types
│   ├── runner.nim          # Parallel batch execution engine
│   ├── checkpoint.nim      # State persistence and resume logic
│   └── progress.nim        # Multi-file progress tracking
└── util/
    └── bar.nim             # Existing - enhance for batch mode
```

### Pattern 1: TOML Template Structure

**What:** Declarative configuration file that maps to honeyclip CLI arguments
**When to use:** User needs to apply same settings to multiple files
**Example:**
```nim
# Template type definition
type
  BatchTemplate = object
    edit: string              # --edit expression
    margin: string            # --margin duration
    whenSilent: string        # --when-silent action
    whenNormal: string        # --when-normal action
    outputFormat: string      # -ex export format
    outputSuffix: string      # appended to output filename
    # ... other honeyclip options

# Source: nim-toml-serialization README
import toml_serialization

proc loadTemplate(path: string): BatchTemplate =
  Toml.loadFile(path, BatchTemplate)
```

Template TOML file example:
```toml
# silent-removal.toml
edit = "audio"
margin = "0.2s"
when-silent = "cut()"
when-normal = "nil()"
output-format = "mp4"
output-suffix = "_edited"
```

### Pattern 2: Parallel File Processing with Malebolgia

**What:** Process multiple files concurrently using structured concurrency
**When to use:** CPU cores available, files are independent
**Example:**
```nim
# Source: https://github.com/Araq/malebolgia
import malebolgia
import std/os

type ProcessResult = object
  path: string
  success: bool
  error: string

proc processFile(path: string, template: BatchTemplate): ProcessResult =
  # Process single file with template settings
  result.path = path
  try:
    # Call honeyclip processing logic here
    result.success = true
  except:
    result.success = false
    result.error = getCurrentExceptionMsg()

proc batchProcess(files: seq[string], template: BatchTemplate) =
  var m = createMaster()
  var results = initLocker newSeq[ProcessResult]()

  m.awaitAll:
    for file in files:
      m.spawn processFile(file, template) -> results

  # Results are synchronized after awaitAll
  let finalResults = results.extract()
```

### Pattern 3: File-Based Checkpoint System

**What:** Track completed files to enable resume after failure
**When to use:** Long-running batches that may be interrupted
**Example:**
```nim
# Source: Research on GNU Parallel --joblog pattern
import std/json

type CheckpointState = object
  batchId: string
  templatePath: string
  totalFiles: int
  completed: seq[string]      # Paths of successfully processed files
  failed: seq[string]         # Paths of failed files with errors
  lastUpdated: float64

proc saveCheckpoint(state: CheckpointState, checkpointPath: string) =
  writeFile(checkpointPath, $(%state))  # Convert to JSON

proc loadCheckpoint(checkpointPath: string): CheckpointState =
  let data = parseFile(checkpointPath)
  to(data, CheckpointState)

proc markCompleted(checkpointPath: string, filePath: string) =
  var state = loadCheckpoint(checkpointPath)
  state.completed.add(filePath)
  state.lastUpdated = epochTime()
  saveCheckpoint(state, checkpointPath)
```

### Pattern 4: Multi-File Progress Tracking

**What:** Extend existing util/bar.nim to show "file X/N" progress across batch
**When to use:** User needs visibility into batch progress
**Example:**
```nim
# Enhance existing Bar type in util/bar.nim
proc startBatch*(bar: Bar, totalFiles: int, currentFile: int, filename: string) =
  let title = &"[{currentFile}/{totalFiles}] {filename}"
  bar.start(100.0, title)  # Each file gets 0-100% progress

proc tickBatch*(bar: Bar, fileProgress: float) =
  bar.tick(fileProgress)
```

Progress output format:
```
  ⏳[3/10] video.mp4 |████████░░░░░░░░░|  45.2%  ETA 12:34 PM
```

### Pattern 5: File Discovery with walkDirRec

**What:** Recursively find all video files in input directory
**When to use:** User provides folder instead of individual files
**Example:**
```nim
# Source: https://nim-lang.org/docs/os.html
import std/os

const videoExts = [".mp4", ".mov", ".avi", ".mkv", ".webm"]

proc findVideoFiles(dir: string): seq[string] =
  for path in walkDirRec(dir):
    for ext in videoExts:
      if path.endsWith(ext):
        result.add(path)
        break
```

### Anti-Patterns to Avoid

- **Hand-rolling TOML parser:** TOML 1.0 spec is complex (nested tables, inline tables, datetime types). Use nim-toml-serialization.
- **Using deprecated std/threadpool:** Marked as deprecated and unstable. Use malebolgia or taskpools instead.
- **Global mutable state in parallel workers:** Will cause race conditions. Use malebolgia's `Locker[T]` or pass immutable data.
- **Processing files serially:** Defeats the purpose of batch mode. Always use parallel processing when CPU cores available.
- **Ignoring checkpoint after each file:** Checkpoint only at end means full restart on failure. Update after each completion.
- **Complex checkpoint database:** SQLite is overkill unless you need queries. JSON file is sufficient for simple completion tracking.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TOML parsing | Custom TOML parser | nim-toml-serialization | TOML 1.0 has complex spec: dotted keys, inline tables, datetime formats, escape sequences, multi-line strings |
| Thread pool management | Manual thread creation with `createThread` | malebolgia or taskpools | Thread pool sizing, work stealing, load balancing, memory barriers, and cleanup are subtle |
| Progress bar rendering | Custom terminal drawing | Enhance existing util/bar.nim | Already handles ANSI escapes, terminal width, ETA calculation, threading |
| File globbing | Manual path pattern matching | std/os `walkDirRec` + extension filter | Cross-platform path handling, symlink following, permission errors |
| ETA calculation | Simple division | Weighted moving average | Early samples are noisy, need warmup period, should account for variance |

**Key insight:** Parallel file I/O has subtle pitfalls (file handle limits, disk contention, memory pressure from parallel decoding). Use proven libraries (malebolgia) that handle backpressure and bounded concurrency rather than spawning unlimited threads.

## Common Pitfalls

### Pitfall 1: File Handle Exhaustion from Unlimited Parallelism

**What goes wrong:** Spawning tasks for all files at once can exhaust file descriptors or memory from parallel video decoding.

**Why it happens:** Video files are large and decoding is memory-intensive. 100 files × 100MB buffers = 10GB RAM.

**How to avoid:** Limit concurrent tasks to CPU core count. Malebolgia naturally bounds this via thread pool size. For taskpools, manually control with semaphore pattern.

**Warning signs:** "Too many open files" errors, OOM killer, system slowdown from thrashing.

### Pitfall 2: Checkpoint File Corruption from Concurrent Writes

**What goes wrong:** Multiple threads writing to checkpoint file simultaneously corrupts JSON.

**Why it happens:** File I/O is not atomic. Partial writes interleave.

**How to avoid:** Single-threaded checkpoint updates. Use channel pattern: workers send completion messages to dedicated checkpoint writer thread, or use malebolgia's `Locker[CheckpointState]` to serialize writes.

**Warning signs:** JSON parse errors on resume, missing completed files from checkpoint.

### Pitfall 3: Silent Failures Lost Without Error Tracking

**What goes wrong:** File fails to process but batch continues, user doesn't notice.

**Why it happens:** Exceptions caught in worker thread don't propagate to main thread.

**How to avoid:** Track both completed and failed files in checkpoint. Collect error messages. Print failure summary at end.

**Warning signs:** Output file count doesn't match input file count, users report "some files skipped."

### Pitfall 4: Inaccurate ETA from Variable File Sizes

**What goes wrong:** ETA calculated from "files completed" doesn't account for large files taking longer.

**Why it happens:** Simple formula: `remaining_files / (completed_files / elapsed_time)` assumes uniform file size.

**How to avoid:** Track total bytes processed vs total bytes in batch. Calculate ETA from byte throughput. Or use weighted moving average of per-file completion times.

**Warning signs:** ETA jumps wildly, shows 1 minute remaining then takes 10 minutes.

### Pitfall 5: Resume After Partial File Processing

**What goes wrong:** File was partially processed when interrupted, resume starts it again, corruption or duplicate work.

**Why it happens:** Checkpoint marks file complete before output is fully written and fsynced.

**How to avoid:** Write to temporary file, fsync, rename to final path (atomic on POSIX), then mark complete in checkpoint. Or check output file existence and validity before skipping.

**Warning signs:** Corrupted output files, files re-processed on every resume attempt.

## Code Examples

Verified patterns from official sources:

### Load TOML Template File

```nim
# Source: https://github.com/status-im/nim-toml-serialization
import toml_serialization

type
  BatchTemplate = object
    edit: string
    margin: string
    whenSilent: string
    whenNormal: string
    outputFormat: string
    outputSuffix: string

proc loadTemplate(path: string): BatchTemplate =
  result = Toml.loadFile(path, BatchTemplate)
```

### Parallel File Processing with Error Collection

```nim
# Source: https://github.com/Araq/malebolgia
import malebolgia
import std/os

type ProcessResult = object
  inputPath: string
  outputPath: string
  success: bool
  error: string
  bytesProcessed: int64

proc processOneFile(input: string, template: BatchTemplate): ProcessResult =
  result.inputPath = input
  result.outputPath = generateOutputPath(input, template.outputSuffix)
  try:
    # Call main honeyclip processing
    result.bytesProcessed = getFileSize(input)
    result.success = true
  except CatchableError as e:
    result.success = false
    result.error = e.msg

proc batchProcess(files: seq[string], template: BatchTemplate): seq[ProcessResult] =
  var m = createMaster()
  var results = initLocker newSeq[ProcessResult]()

  m.awaitAll:
    for file in files:
      m.spawn processOneFile(file, template) -> results

  result = results.extract()
```

### Checkpoint with Atomic Updates

```nim
# Source: Research on file-based checkpointing patterns
import std/[json, os, times]

type CheckpointState = object
  totalFiles: int
  completed: seq[string]
  failed: seq[tuple[path: string, error: string]]
  startTime: float64
  lastUpdate: float64

proc saveCheckpoint(state: CheckpointState, path: string) =
  let tempPath = path & ".tmp"
  writeFile(tempPath, pretty(%state))
  # Atomic rename on POSIX, near-atomic on Windows
  moveFile(tempPath, path)

proc loadCheckpoint(path: string): CheckpointState =
  if fileExists(path):
    result = to(parseFile(path), CheckpointState)
  else:
    result = CheckpointState(
      startTime: epochTime(),
      lastUpdate: epochTime()
    )
```

### File Discovery with Extension Filter

```nim
# Source: https://nim-lang.org/docs/os.html
import std/os

const VideoExtensions = [".mp4", ".mov", ".avi", ".mkv", ".webm", ".flv"]

proc findVideoFiles(inputPath: string): seq[string] =
  if fileExists(inputPath):
    # Single file
    result = @[inputPath]
  elif dirExists(inputPath):
    # Recursive directory scan
    for path in walkDirRec(inputPath):
      let (_, _, ext) = splitFile(path)
      if ext.toLowerAscii() in VideoExtensions:
        result.add(path)
  else:
    raise newException(IOError, "Path not found: " & inputPath)
```

### Enhanced Progress Bar for Batch

```nim
# Enhance existing src/util/bar.nim
# Source: Existing honeyclip util/bar.nim pattern

proc formatBatchTitle(fileNum, totalFiles: int, filename: string): string =
  let basename = extractFilename(filename)
  result = &"[{fileNum}/{totalFiles}] {basename}"

# Usage in batch processing loop:
# var bar = initBar(modern, threaded = true)
# for i, file in files:
#   let title = formatBatchTitle(i + 1, files.len, file)
#   bar.start(100.0, title)
#   # ... process file, call bar.tick(progress)
#   bar.end()
```

### Resume from Checkpoint

```nim
# Skip already-completed files on resume
import std/sets

proc getFilesToProcess(allFiles: seq[string], checkpoint: CheckpointState): seq[string] =
  let completed = checkpoint.completed.toHashSet()
  for file in allFiles:
    if file notin completed:
      result.add(file)

# Usage:
# let checkpoint = loadCheckpoint(".honeyclip-batch.json")
# let filesToProcess = getFilesToProcess(allFiles, checkpoint)
# echo &"Resuming: {filesToProcess.len} files remaining"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| std/threadpool with spawn/sync | malebolgia or taskpools | Nim 1.6+ | threadpool deprecated, modern libs have better backpressure and structured concurrency |
| parsetoml (TOML 0.5.0) | nim-toml-serialization (TOML 1.0.0) | 2020+ | TOML 1.0 spec finalized 2021, adds inline tables, dotted keys, improved datetime |
| Manual thread creation | Structured concurrency (malebolgia) | 2022+ | Prevents resource leaks, automatic cleanup, easier to reason about |
| Global progress state | Thread-safe atomics in util/bar.nim | honeyclip existing | Lock-free progress updates, smooth rendering |

**Deprecated/outdated:**
- **std/threadpool**: Marked deprecated in Nim docs, replaced by nimble packages
- **parsetoml**: Still maintained but targets older TOML spec, nim-toml-serialization is more complete

## Open Questions

1. **Should batch mode support GPU-based processing (Phase 15)?**
   - What we know: Phase 15 added GPU runtime detection, buffer pooling
   - What's unclear: If multiple files processed in parallel, can they share GPU buffers safely?
   - Recommendation: Start with CPU-only batch processing, defer GPU parallelism to future phase

2. **What's the max sane parallelism for video processing?**
   - What we know: malebolgia defaults to CPU core count
   - What's unclear: Video decoding is I/O + CPU intensive, may saturate disk before CPU
   - Recommendation: Default to `countProcessors()` but add `--jobs N` flag for user override

3. **Should templates support per-file overrides?**
   - What we know: TOML supports arrays of tables `[[files]]` with per-item config
   - What's unclear: Does this add complexity users won't use?
   - Recommendation: Phase 16 MVP is folder + template. Defer per-file overrides to future if requested.

4. **How to handle nested directory structures in output?**
   - What we know: Input folder may have subdirectories
   - What's unclear: Should output preserve directory structure or flatten?
   - Recommendation: Preserve structure by default, add `--flatten` flag for optional flattening

## Sources

### Primary (HIGH confidence)
- [nim-toml-serialization GitHub](https://github.com/status-im/nim-toml-serialization) - TOML 1.0 parsing and serialization API
- [malebolgia GitHub](https://github.com/Araq/malebolgia) - Structured concurrency and parallel processing API
- [Nim std/os documentation](https://nim-lang.org/docs/os.html) - File system operations (walkDirRec, file I/O)
- [Nim std/threadpool documentation](https://nim-lang.org/docs/threadpool.html) - Deprecation notice and migration guidance
- [GNU Parallel Tutorial](https://www.gnu.org/software/parallel/parallel_tutorial.html) - joblog, --resume, --resume-failed patterns
- [Nim db_sqlite documentation](https://nim-lang.org/docs/db_sqlite.html) - SQLite API (if needed)

### Secondary (MEDIUM confidence)
- [taskpools GitHub](https://github.com/status-im/nim-taskpools) - Alternative parallel processing library
- [Nim by Example - Parallelism](https://nim-by-example.github.io/parallelism/) - Spawn/sync patterns
- [The Developer's Guide To TOML](https://www.anbowell.com/blog/the-developers-guide-to-toml/) - TOML format overview
- [Building a Durable Execution Engine With SQLite](https://www.morling.dev/blog/building-durable-execution-engine-with-sqlite/) - Checkpoint/resume patterns
- [progress.nim GitHub](https://github.com/euantorano/progress.nim) - Simple Nim progress bar (alternative to custom util/bar.nim)

### Tertiary (LOW confidence)
- [FFmpeg Batch Convert](https://shotstack.io/learn/ffmpeg-batch-convert/) - CLI batch processing UX patterns
- [ETA calculation guide](https://www.altexsoft.com/blog/estimated-time-of-arrival/) - ETA formula basics
- WebSearch results on batch processing resume patterns - General industry practices

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries verified from official repos and Nim docs
- Architecture: HIGH - Patterns based on official examples and existing honeyclip code
- Pitfalls: MEDIUM - Drawn from general parallel processing experience and GNU Parallel docs, not honeyclip-specific testing

**Research date:** 2026-02-14
**Valid until:** 2026-04-14 (60 days - stable domain, Nim ecosystem moves slowly)
