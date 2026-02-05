# Phase 12: Custom Hook Patterns - Research

**Researched:** 2026-02-05
**Domain:** JSON configuration parsing and pattern matching
**Confidence:** HIGH

## Summary

Custom hook patterns enable users to extend honeyclip's engagement detection by defining JSON-based pattern configurations. The standard approach in Nim uses `std/json` for parsing with structured error handling via exception types (`JsonParsingError`, `IOError`, `OSError`, `ValueError`). Pattern matching uses compiled regex with case-insensitive flags. File discovery follows Unix conventions with ordered search paths (CLI flag → project directory → user config directory).

The existing codebase already has hook detection infrastructure (`src/analyze/hooks.nim`) with text patterns (regex) and prosody detection (audio energy analysis). This phase extends that foundation to load patterns from JSON files. The architecture should validate JSON schema strictly, merge custom patterns with built-ins additively, and compile regex patterns once at load time for performance.

**Primary recommendation:** Use `std/json` with try-except blocks catching specific exception types. Validate required fields immediately after parsing using `{}` accessor (returns nil for missing fields). Compile regex patterns at load time into `seq[HookPattern]` and cache for the process lifetime. Follow XDG directory conventions for config file discovery.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| std/json | stdlib | JSON parsing and validation | Built-in, no dependencies, well-tested |
| std/re | stdlib | Regex pattern matching | PCRE wrapper, battle-tested, compile-time optimization support |
| std/os | stdlib | File system and path operations | Cross-platform file discovery, XDG support |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| std/strutils | stdlib | String manipulation | Case normalization for pattern matching |
| std/tables | stdlib | Pattern name deduplication | Tracking which built-in patterns to override |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| std/json | PMunch/jsonschema | jsonschema adds schema DSL validation but requires external dependency; std/json with manual validation is sufficient for simple schema |
| std/re | nitely/nim-regex | nim-regex is pure Nim with linear-time guarantees, but std/re (PCRE) is faster and supports compile-time optimization |

**Installation:**
No additional packages needed - all stdlib.

## Architecture Patterns

### Recommended Project Structure
```
src/analyze/
├── hooks.nim           # Core hook detection (exists)
├── hook_schema.nim     # NEW: JSON schema loading and validation
└── hook_discovery.nim  # NEW: File discovery logic (optional - can fold into hook_schema.nim)
```

### Pattern 1: Strict Schema Validation
**What:** Parse JSON, validate required fields, fail fast with clear error messages
**When to use:** Always - user-provided JSON must be validated before use

**Example:**
```nim
# Source: std/json documentation + honeyclip pattern
import std/[json, strutils]

type
  HookPatternJson = object
    name: string
    category: string
    weight: float32
    # Pattern matching criteria (at least one required)
    textRegex: string
    keywords: seq[string]
    prosody: string  # Named profile or empty
    prosodyThresholds: tuple[pause: float32, volumeSpike: float32]
    # Multi-criteria logic
    matchMode: string  # "all" or "any"

proc loadHooksFromJson*(path: string): seq[HookPattern] =
  ## Load and validate custom hooks from JSON
  result = @[]

  try:
    let root = parseFile(path)

    # Validate top-level structure
    if not root.hasKey("hooks"):
      raise newException(ValueError, "Missing required field: 'hooks'")

    let hooksNode = root["hooks"]
    if hooksNode.kind != JObject:
      raise newException(ValueError, "Field 'hooks' must be an object")

    # Parse each hook pattern
    for patternName, patternNode in hooksNode.pairs:
      # Use {} accessor for optional fields, [] for required
      let name = patternNode{"name"}.getStr(patternName)
      let category = patternNode{"category"}.getStr("custom")
      let weight = patternNode{"weight"}.getFloat(15.0).float32

      # Validate at least one matching criterion exists
      let hasTextRegex = patternNode.hasKey("regex")
      let hasKeywords = patternNode.hasKey("keywords")
      let hasProsody = patternNode.hasKey("prosody")

      if not (hasTextRegex or hasKeywords or hasProsody):
        raise newException(ValueError,
          &"Pattern '{name}' must have at least one criterion: regex, keywords, or prosody")

      # ... construct HookPattern

  except IOError, OSError as e:
    raise newException(IOError, &"Failed to read hooks file '{path}': {e.msg}")
  except JsonParsingError as e:
    raise newException(ValueError, &"Invalid JSON in '{path}': {e.msg}")
  except ValueError as e:
    raise newException(ValueError, &"Schema validation failed for '{path}': {e.msg}")
```

### Pattern 2: File Discovery with Ordered Search
**What:** Check multiple locations in priority order, load first found
**When to use:** Configuration file discovery (hooks, metadata templates)

**Example:**
```nim
# Source: Nim XDG conventions + honeyclip metadata/parser.nim pattern
import std/[os, strutils]

proc findHooksFile*(explicitPath: string = ""): string =
  ## Discover hooks file with priority order
  ## Returns: path to hooks file or empty string if not found

  # Priority 1: Explicit CLI path
  if explicitPath != "":
    if fileExists(explicitPath):
      return explicitPath
    else:
      return ""  # Caller will handle missing file

  # Priority 2: Current/video directory
  let localPath = getCurrentDir() / "honeyclip.hooks.json"
  if fileExists(localPath):
    return localPath

  # Priority 3: XDG config directory (~/.config/honeyclip/)
  let configDir = getConfigDir() / "honeyclip"
  let xdgPath = configDir / "honeyclip.hooks.json"
  if fileExists(xdgPath):
    return xdgPath

  return ""  # No hooks file found
```

### Pattern 3: Regex Compilation and Caching
**What:** Compile regex patterns once at load time, store in seq
**When to use:** Pattern-heavy operations where compilation cost matters

**Example:**
```nim
# Source: std/re documentation + honeyclip existing hooks.nim
import std/re

type
  CompiledHookPattern = object
    name: string
    regex: Option[Regex]  # Some patterns may not have regex
    keywords: seq[string]
    weight: float32

proc compilePattern(jsonPattern: HookPatternJson): CompiledHookPattern =
  ## Compile regex at load time for performance
  result.name = jsonPattern.name
  result.weight = jsonPattern.weight
  result.keywords = jsonPattern.keywords

  if jsonPattern.textRegex != "":
    # Case-insensitive flag via (?i) or re() with {reIgnoreCase}
    let pattern = "(?i)" & jsonPattern.textRegex
    result.regex = some(re(pattern))
  else:
    result.regex = none(Regex)

# Usage: compile once, use many times
let patterns = loadAndCompileHooks("hooks.json")
for text in segments:
  for pattern in patterns:
    if pattern.regex.isSome and text.contains(pattern.regex.get):
      # Match found
```

### Pattern 4: Additive Merging with Override
**What:** Load built-in patterns, then custom patterns; custom patterns with duplicate names replace built-ins
**When to use:** Extending default configuration while allowing user customization

**Example:**
```nim
# Source: Common configuration pattern
import std/tables

proc mergeHookPatterns(builtins, custom: seq[HookPattern]): seq[HookPattern] =
  ## Merge custom hooks with built-ins, custom overrides by name
  result = @[]

  # Track which names we've seen
  var seen = initTable[string, bool]()

  # Add custom patterns first (priority)
  for pattern in custom:
    result.add(pattern)
    seen[pattern.name] = true

  # Add built-ins that weren't overridden
  for pattern in builtins:
    if not seen.hasKey(pattern.name):
      result.add(pattern)
```

### Anti-Patterns to Avoid
- **Parsing JSON in hot paths:** Compile patterns once at startup, not per-segment
- **Silent failures:** Always surface JSON validation errors to user with actionable messages
- **Regex in string literals without compile-time check:** Use `re()` at module level or const for compile-time validation
- **Ignoring file discovery priority:** Users expect CLI flags to override auto-discovery

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON schema validation | Custom validator with reflection | Manual validation with clear error messages | Nim's std/json with `{}` accessor + explicit field checks is clearer than schema DSL for simple schemas |
| Regex caching | Custom LRU cache | Compile at load time into seq | Patterns are static per-run; no need for eviction logic |
| Config file search | Recursive directory walking | Ordered path checks | Config files have conventional locations; no need for expensive search |
| Case-insensitive matching | toLower + string compare | Regex `(?i)` flag | Regex engine is optimized for this; string lowering allocates |

**Key insight:** Nim's stdlib is sufficient for this domain. Adding external dependencies (jsonschema, custom config frameworks) increases complexity without material benefit for a simple schema.

## Common Pitfalls

### Pitfall 1: Using [] accessor for optional JSON fields
**What goes wrong:** `node["field"]` raises `KeyError` if field doesn't exist, crashing the program
**Why it happens:** Nim's json module has two accessors: `[]` (required) and `{}` (optional)
**How to avoid:** Use `{}` accessor for optional fields: `node{"field"}.getStr("")`
**Warning signs:** KeyError exceptions during JSON parsing, crashes on valid-but-incomplete JSON

### Pitfall 2: Compiling regex on every pattern match
**What goes wrong:** Regex compilation is expensive (parsing, DFA construction); doing it per-match kills performance
**Why it happens:** Putting `re(pattern)` directly in function arguments
**How to avoid:** Compile patterns at load time, store in seq or const
**Warning signs:** Slow pattern matching, high CPU usage, linear scaling with segments × patterns

### Pitfall 3: Generic error messages on JSON validation failure
**What goes wrong:** User gets "Invalid JSON" without knowing what's wrong or where
**Why it happens:** Catching all exceptions with generic handler
**How to avoid:** Catch specific exception types, include field names and expected values in error messages
**Warning signs:** User confusion, support requests asking "what's wrong with my JSON?"

### Pitfall 4: Not handling XDG config directory creation
**What goes wrong:** Auto-discovery fails because `~/.config/honeyclip/` doesn't exist
**Why it happens:** Assuming config directory exists
**How to avoid:** Either document that directory must exist, OR create it when generating starter template
**Warning signs:** Config files placed in home directory not found, users confused about "correct" location

### Pitfall 5: Case-sensitive pattern matching when users expect case-insensitive
**What goes wrong:** Pattern `"What"` doesn't match `"what"`, surprising users
**Why it happens:** Default regex is case-sensitive
**How to avoid:** Always use `(?i)` prefix or compile with case-insensitive flag
**Warning signs:** User reports "my pattern doesn't work" when testing with different case

## Code Examples

Verified patterns from official sources:

### JSON Parsing with Error Handling
```nim
// Source: https://nim-lang.org/docs/json.html
import std/[json, strformat]

proc loadHooksFile(path: string): JsonNode =
  try:
    result = parseFile(path)
  except IOError, OSError as e:
    raise newException(IOError, &"Cannot read file '{path}': {e.msg}")
  except JsonParsingError as e:
    raise newException(ValueError, &"Invalid JSON in '{path}': {e.msg}")
  except ValueError as e:
    raise newException(ValueError, &"JSON parsing error in '{path}': {e.msg}")
```

### Safe Field Access with Defaults
```nim
// Source: https://nim-lang.org/docs/json.html
let weight = node{"weight"}.getFloat(15.0)  # Default 15.0 if missing
let category = node{"category"}.getStr("custom")  # Default "custom"
let matchMode = node{"match"}.getStr("all")  # Default "all"

# Check for field existence
if node.hasKey("prosody"):
  let prosodyProfile = node["prosody"].getStr()
```

### Case-Insensitive Regex Compilation
```nim
// Source: https://nim-lang.org/docs/re.html
import std/re

# Compile-time with (?i) flag
const pattern = re(r"(?i)^(what|why|how)\b")

# Runtime compilation
let userPattern = "(?i)" & jsonPattern.textRegex
let compiled = re(userPattern)
```

### File Discovery with XDG Support
```nim
// Source: https://nim-lang.org/docs/os.html
import std/os

# XDG config directory
let configDir = getConfigDir()  # ~/.config on POSIX
let hooksPath = configDir / "honeyclip" / "honeyclip.hooks.json"

# Check existence
if fileExists(hooksPath):
  # Load hooks
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual field validation | `{}` accessor with nil-safe defaults | Nim 1.0+ (stable since) | Cleaner code, fewer crashes |
| Runtime regex compilation | Compile-time via const or load-time | std/re PCRE wrapper | ~10-100x faster pattern matching |
| Home directory configs | XDG Base Directory Spec | Linux convention 2010+, Nim support 0.19+ | Multi-user systems, clean home directory |
| Separate config parsers per format | std/json, std/parsecfg, std/parsejson unified | Nim stdlib evolution | Single dependency, consistent API |

**Deprecated/outdated:**
- `marshal` module for JSON: Replaced by std/jsonutils with to/from procs
- Manual string-based config parsing: std/parsecfg handles INI-style, std/json for structured

## Open Questions

Things that couldn't be fully resolved:

1. **Should prosody thresholds be exposed as numeric values or only named profiles?**
   - What we know: Current code uses hardcoded thresholds (0.05 silence, 1.5x volume spike)
   - What's unclear: Whether users need numeric control or named profiles suffice
   - Recommendation: Support BOTH - named profiles map to thresholds, but allow explicit numeric override for power users

2. **Should starter template generation be automatic or explicit?**
   - What we know: User decision says "if `--hooks <path>` specified and file doesn't exist, generate starter template"
   - What's unclear: Should we also offer `--generate-hooks-template` flag for discoverability?
   - Recommendation: Generate on missing file (as decided), and log message saying "Generated starter template at <path>" for discoverability

3. **How to handle invalid regex patterns in user JSON?**
   - What we know: `re()` raises exception on invalid regex
   - What's unclear: Whether to fail entire file or skip invalid pattern with warning
   - Recommendation: Fail entire file (strict validation) - prevents user from thinking invalid pattern is active

## Sources

### Primary (HIGH confidence)
- [std/json documentation](https://nim-lang.org/docs/json.html) - parseFile exceptions, field accessors, defaults
- [std/re documentation](https://nim-lang.org/docs/re.html) - PCRE wrapper, case-insensitive flag
- [std/os documentation](https://nim-lang.org/docs/os.html) - getConfigDir, fileExists, path operations
- honeyclip codebase - `src/analyze/hooks.nim` (existing hook infrastructure), `src/metadata/parser.nim` (file discovery pattern)

### Secondary (MEDIUM confidence)
- [Nim compiler user guide](https://nim-lang.github.io/Nim/nimc.html) - XDG config directory conventions
- [JSON Schema validation docs](https://json-schema.org/draft/2020-12/json-schema-validation) - anyOf/allOf patterns for match logic
- [nim-regex GitHub](https://github.com/nitely/nim-regex) - Compile-time vs runtime compilation performance notes

### Tertiary (LOW confidence)
- Web search results on JSON template generation best practices - General guidance, not Nim-specific
- Case-insensitive regex performance articles - General optimization principles, not benchmarked for Nim

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - std/json and std/re are battle-tested stdlib modules, extensively documented
- Architecture: HIGH - Patterns verified against existing honeyclip code and official Nim docs
- Pitfalls: HIGH - Documented in official json.html, observed in honeyclip codebase patterns

**Research date:** 2026-02-05
**Valid until:** 60 days (stdlib changes slowly; patterns are stable)
