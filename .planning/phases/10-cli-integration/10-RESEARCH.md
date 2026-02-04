# Phase 10: CLI Integration - Research

**Researched:** 2026-02-03
**Domain:** CLI command structure, argument parsing, progress reporting, TTY detection
**Confidence:** HIGH

## Summary

CLI integration for engagement analysis requires three main components: (1) a new `analyze` command combining engagement analysis + clip detection into a convenience workflow, (2) integration of engagement signals into the main edit expression system via `--engage` flag and score() expressions, and (3) per-step progress bars with TTY-aware output.

The codebase already has strong foundations: subcommand pattern in `main.nim` with command dispatch table, existing `engage` and `clips` commands that perform the core analysis, expression parser in `palet/edit.nim` for `--edit` evaluation, and threaded progress bar system in `util/bar.nim` with TTY detection via `stdin.isatty()` from Nim's `std/terminal`.

User decisions from CONTEXT.md lock in key patterns: `analyze` command as convenience wrapper, `--engage` flag enables threshold filtering, named presets for content types and platforms, TTY-aware prompting for interactive vs scripted use, and per-step progress bars (transcript → faces → scoring).

**Primary recommendation:** Extend existing command pattern with `analyze.nim`, add engagement functions to `palet/edit.nim` expression evaluator, use existing Bar infrastructure with multiple `start()`/`end()` calls for per-step progress, leverage `stdin.isatty()` for TTY detection.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| std/terminal | Nim stdlib | TTY detection via isatty() | Native, already used in main.nim |
| util/bar.nim | Internal | Threaded progress bars | Already implemented, modern/classic/ascii modes |
| palet/edit.nim | Internal | Expression parser/evaluator | Powers --edit flag, extensible for new functions |
| std/parseopt | Nim stdlib | Argument parsing | Not used yet, but standard library option |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| cligen | Latest | Advanced CLI generation | Only if replacing manual parsing (overkill for this phase) |
| log.nim | Internal | conwrite(), debug(), error() helpers | Already used throughout codebase |
| json (std) | Nim stdlib | Project file I/O | Already used in exports/project.nim |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual arg parsing | cligen library | Current pattern works fine, cligen adds dependency |
| Multiple Bar instances | Single bar with state | Current Bar design supports multiple start/end cycles |
| Custom TTY detection | std/terminal isatty() | Standard library is cross-platform, well-tested |

**Installation:**
```bash
# No new dependencies required
# All components exist in codebase or Nim stdlib
```

## Architecture Patterns

### Recommended Project Structure
```
src/cmds/
├── analyze.nim        # NEW: Convenience command (engage + clips + prompts)
├── engagement.nim     # EXISTS: Extend with --fresh, --no-transcript, --no-faces
├── clips.nim          # EXISTS: No changes needed
└── exportcmd.nim      # EXISTS: No changes needed

src/palet/
└── edit.nim           # EXTEND: Add engagement expression functions
                       # score(), face_count(), peak(), hook(), speaker_change()
                       # is_hook(), faces_visible(), speaking_rate()

src/
└── main.nim           # EXTEND: Add analyze to cmdHandlers table
                       # Add --engage flag parsing to main arg loop
```

### Pattern 1: Subcommand Registration
**What:** Add new command to dispatch table in main.nim
**When to use:** Any new honeyclip subcommand
**Example:**
```nim
# In main.nim
const cmdHandlers: seq[Command] = @[
  ("cache", cache.main),
  ("analyze", analyze.main),  # NEW
  ("engage", engagement.main),
  # ... rest
]

# In cli.nim
const commands*: seq[tuple[name: string, help: string]] = @[
  ("analyze", "Analyze video and extract clips (convenience workflow)"),
  ("engage", "Analyze video engagement (audio, motion, speech, faces)"),
  # ... rest
]
```

### Pattern 2: TTY-Aware Output
**What:** Use `stdin.isatty()` to detect terminal vs pipe/redirect
**When to use:** Interactive prompts, progress bars, colorized output
**Example:**
```nim
import std/terminal

# Check if running in terminal
if stdin.isatty():
  # Interactive mode: show prompts
  echo "Continue? (y/n): "
  let response = stdin.readLine()
else:
  # Scripted mode: no prompts, machine-readable output
  echo "COMPLETED"

# Progress bar auto-detects in Bar.hide field (log.nim quiet flag)
# Override with explicit --quiet or --verbose flags
```
Source: [Nim std/terminal documentation](https://nim-lang.org/docs/terminal.html)

### Pattern 3: Per-Step Progress Bars
**What:** Multiple sequential progress bars for multi-phase analysis
**When to use:** Long-running operations with distinct phases
**Example:**
```nim
var bar = initBar(BarType.modern)

# Phase 1: Transcript extraction
bar.start(100.0, "Extracting transcript")
for i in 0..100:
  bar.tick(float(i))
  sleep(10)
bar.`end`()

# Phase 2: Face detection
bar.start(500.0, "Detecting faces")
for i in 0..500:
  bar.tick(float(i))
  sleep(10)
bar.`end`()

# Phase 3: Engagement scoring
bar.start(200.0, "Scoring engagement")
for i in 0..200:
  bar.tick(float(i))
  sleep(10)
bar.`end`()

# Cleanup thread
bar.destroy()
```

### Pattern 4: Expression Function Extension
**What:** Add new evaluator functions to palet/edit.nim
**When to use:** New signals for --edit expressions
**Example:**
```nim
# In palet/edit.nim editEval() function
case text[node[0].`from` ..< node[0].to]:
of "audio":
  # ... existing audio() implementation
of "motion":
  # ... existing motion() implementation
of "score":
  # NEW: Engagement score signal
  let threshold = 50.0  # Default threshold
  # Load cached engagement data
  let engagementPath = generateOutputPath(args.input, "", ".engage.json")
  if not fileExists(engagementPath):
    error "Engagement data not found. Run 'honeyclip engage' first or use --engage flag"
  let timeline = loadEngagementTimeline(engagementPath)
  # Convert segments to boolean array at timebase resolution
  return segmentsToLevels(timeline.segments, tb, threshold)
of "face_count":
  # NEW: Number of faces visible
  # Similar pattern: load cached face data, threshold on count
  # ...
```

### Pattern 5: Named Presets
**What:** Table-based preset lookup for engagement thresholds and weights
**When to use:** Platform/content-type presets like `--engage=viral`
**Example:**
```nim
# In engagement module
type PresetConfig = object
  threshold: float32
  audioWeight: float32
  motionWeight: float32
  speechWeight: float32

const Presets = {
  "viral": PresetConfig(
    threshold: 75.0,
    audioWeight: 0.3,
    motionWeight: 0.4,
    speechWeight: 0.3
  ),
  "podcast": PresetConfig(
    threshold: 50.0,
    audioWeight: 0.1,
    motionWeight: 0.1,
    speechWeight: 0.8
  ),
  # ... etc
}.toTable

proc parseEngageFlag(value: string): PresetConfig =
  # Try parsing as number first
  try:
    let threshold = parseFloat(value)
    return PresetConfig(threshold: threshold, ...)
  except ValueError:
    # Try looking up preset
    if value in Presets:
      return Presets[value]
    else:
      error &"Unknown preset: {value}"
```

### Anti-Patterns to Avoid
- **Don't create separate Bar instances per step** - Reuse single Bar with start/end cycles
- **Don't parse --engage in palet/edit.nim** - Handle in main.nim arg loop, pass config to interpretEdit()
- **Don't prompt when !stdin.isatty()** - Always check TTY before interactive input
- **Don't block on engagement analysis in edit workflow** - Cache data, fail fast if missing

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TTY detection | Custom platform checks | std/terminal.isatty() | Cross-platform, handles edge cases (redirects, pipes, ptys) |
| Progress bars | Custom \r overwrites | util/bar.nim | Threaded, handles terminal width, multiple styles |
| Expression parsing | String split/regex | Existing palet/edit.nim | Lisp-style parser with proper precedence |
| Argument parsing | Manual state machine | Current pattern in main.nim | Works, matches codebase style |
| Project file I/O | Custom serialization | exports/project.nim | Already has save/load with stale detection |

**Key insight:** Nim's std/terminal provides robust TTY detection that handles not just `isatty()` but also terminal width, cursor control, and ANSI codes. The existing util/bar.nim is a production-ready progress bar with threading and auto-width detection. Don't rebuild these.

## Common Pitfalls

### Pitfall 1: Forgetting to Check TTY Before Prompting
**What goes wrong:** Script hangs waiting for stdin when piped
**Why it happens:** Prompts like `readLine()` block if stdin is not a TTY
**How to avoid:** Always wrap prompts in `if stdin.isatty()` check
**Warning signs:** CI/automation hanging on "Press Enter to continue..."

### Pitfall 2: Progress Bar Thread Not Cleaned Up
**What goes wrong:** Process doesn't exit cleanly, thread leaks
**Why it happens:** Bar.destroy() not called after multiple start/end cycles
**How to avoid:** Defer bar.destroy() at command entry, call after all progress phases
**Warning signs:** Process takes 1-2 seconds to exit after completion

### Pitfall 3: Expression Functions Without Cache Check
**What goes wrong:** score() expression re-runs expensive analysis every frame
**Why it happens:** No cache file check before computing engagement
**How to avoid:** Load cached engagement data, error if missing, hint to run `honeyclip engage` first
**Warning signs:** Edit workflow 100x slower than expected

### Pitfall 4: AND Logic Misunderstanding
**What goes wrong:** `--engage=60 --edit "motion() > 0.5"` keeps only motion frames, ignoring engagement
**Why it happens:** User expects engagement filtering + additional motion constraint
**How to avoid:** Document AND logic clearly: both conditions must be true. Provide OR syntax if needed.
**Warning signs:** User complaints about "engagement flag not working"

### Pitfall 5: Named Preset Name Collisions
**What goes wrong:** `--engage=50` parsed as preset "50" instead of threshold 50.0
**Why it happens:** Preset lookup before number parsing
**How to avoid:** Try number parsing first, fall back to preset lookup
**Warning signs:** Error "Unknown preset: 50" when user expects numeric threshold

## Code Examples

Verified patterns from existing codebase:

### Command Entry Point Pattern
```nim
# From cmds/engagement.nim
proc main*(cArgs: seq[string]) =
  var inputPath: string = ""
  var model: string = ""
  var outputPath: string = ""
  var showSummary: bool = false
  var noFaces: bool = false

  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--help", "-h":
      echo """usage: honeyclip engage file model [options]
      ...
      """
      quit(0)
    of "--summary":
      showSummary = true
    of "--no-faces":
      noFaces = true
    # ... etc
```

### TTY Detection for Progress
```nim
# From main.nim (already uses isatty check)
if paramCount() < 1:
  if stdin.isatty():
    echo """
██╗  ██╗ ██████╗ ███╗   ██╗███████╗██╗   ██╗ ██████╗██╗     ██╗██████╗
...
"""
    quit(0)

# From log.nim (quiet mode auto-disables progress)
proc conwrite*(msg: string) {.raises:[].} =
  if not quiet:
    try:
      let columns = terminalWidth()
      let buffer: string = " ".repeat(columns - msg.len - 3)
      stdout.write("  " & msg & buffer & "\r")
      stdout.flushFile()
```

### Multiple Progress Phases
```nim
# From cmds/clips.nim (shows multi-phase pattern)
conwrite(&"Extracting transcript from {inputPath}...")
var transcript: Transcript = extractTranscript(inputPath, model, "", "")

conwrite("Analyzing engagement...")
var timeline: EngagementTimeline = analyzeEngagement(...)

conwrite("Detecting scene changes...")
let sceneChanges = extractSceneChanges(inputPath)

conwrite("Detecting clips...")
let boundaries = detectBoundaries(...)
var detectedClips = detectClips(...)

conwrite("")  # Clear progress line
echo "Results:"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-phase progress | Multi-phase with separate bars | Phase 2-9 | Better UX for long operations |
| Global quiet flag only | TTY auto-detection + explicit flags | Phase 1 | Works in pipes and scripts |
| Manual arg parsing | State machine with expecting | Phase 1 | Handles --key val and --key=val |
| String edit expressions | Lisp-style parser | Phase 1 (inherited) | Composable with and/or/not |

**Deprecated/outdated:**
- Single progress bar for entire workflow - Modern CLIs show per-step progress
- Prompting without TTY check - Breaks automation and CI

## Open Questions

Things that couldn't be fully resolved:

1. **Preset Weight Values**
   - What we know: User wants presets for "viral", "podcast", "tutorial", "interview", "tiktok", "youtube", "instagram"
   - What's unclear: Exact weight mappings for each preset
   - Recommendation: Start with reasonable defaults, tune based on real video testing. Document that presets are starting points.

2. **Expression Function Caching Strategy**
   - What we know: score() needs cached engagement data
   - What's unclear: Should expressions auto-run analysis if cache missing, or error?
   - Recommendation: Error with helpful message pointing to `honeyclip engage` or `--engage` flag. Explicit is better than surprising analysis runs.

3. **Progress Bar Title Colors**
   - What we know: Bar supports ANSI escape sequences in title
   - What's unclear: Should different phases use different colors?
   - Recommendation: Use consistent color (existing icon color), rely on text to differentiate phases. Simpler and less "noisy".

## Sources

### Primary (HIGH confidence)
- [Nim std/terminal documentation](https://nim-lang.org/docs/terminal.html) - isatty() and terminal functions
- Existing codebase: `src/main.nim`, `src/cmds/engagement.nim`, `src/cmds/clips.nim`, `src/util/bar.nim`, `src/palet/edit.nim`, `src/log.nim`
- [Nim Terminal Detection Guide](https://scripter.co/nim-check-if-stdin-stdout-are-associated-with-terminal-or-pipe/) - TTY detection patterns

### Secondary (MEDIUM confidence)
- [cligen documentation](https://c-blake.github.io/cligen/cligen.html) - Alternative CLI parsing (not needed for this phase)
- [Jake Zimmerman: Improving CLIs with isatty](https://blog.jez.io/cli-tty/) - General best practices (language-agnostic)

### Tertiary (LOW confidence)
- None - all findings verified with authoritative sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components exist in codebase or Nim stdlib
- Architecture: HIGH - Patterns verified in existing commands (engage, clips, cache)
- Pitfalls: HIGH - Identified from existing codebase patterns and common CLI antipatterns

**Research date:** 2026-02-03
**Valid until:** 2026-03-03 (30 days - stable domain, Nim stdlib doesn't change frequently)
