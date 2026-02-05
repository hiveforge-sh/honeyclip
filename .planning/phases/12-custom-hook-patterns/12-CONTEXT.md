# Phase 12: Custom Hook Patterns - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Enable users to define custom hook detection patterns via JSON file. Supports regex, keywords, and prosody thresholds. Built-in patterns remain available as defaults. Custom patterns loaded via CLI flag or auto-discovery.

</domain>

<decisions>
## Implementation Decisions

### Schema design
- Top-level structure: named object `{"hooks": {...}, "settings": {...}}` — room for global settings
- Each pattern has a numeric weight field (e.g., 15.0 points) — user controls boost impact
- Patterns have `name` and `category` fields for identification and grouping
- Strict schema validation — invalid JSON or missing required fields = fail with clear error message

### Pattern matching
- Pattern criteria: best UX approach — allow optional fields, use whatever's specified
- Multi-criteria combination: configurable via `"match": "all"` or `"match": "any"` per pattern
- Prosody thresholds: support both named profiles (`"prosody": "excited"`) AND explicit numeric thresholds
- Text matching: always case-insensitive — covers most use cases, simpler for users

### File discovery
- Default filename: `honeyclip.hooks.json` — explicit branding, clear purpose
- Discovery priority: CLI `--hooks` flag > video directory > home directory (`~/.config/honeyclip/`)
- Show which hooks file loaded: only with `--verbose` flag
- Missing file behavior: if `--hooks <path>` specified and file doesn't exist, generate starter template at that path

### Default integration
- Custom hooks merge with built-ins (additive) — both sets active simultaneously
- Override mechanism: custom pattern with same name as built-in replaces that built-in
- Debugging: verbose output shows all loaded hooks (built-in + custom) before processing
- Output visibility: JSON engagement output includes `"hooks": ["pattern-name", ...]` per segment; console shows matches with `--verbose`

### Claude's Discretion
- Exact JSON schema field names and nesting
- Starter template content
- Named prosody profile definitions (excited, emphatic, etc.)
- Internal pattern compilation and caching

</decisions>

<specifics>
## Specific Ideas

- Pattern names should be useful for debugging — show in verbose output and JSON
- Categories enable grouping related hooks (e.g., "questions", "callouts", "brand-specific")
- Template generation helps users get started quickly when they specify a non-existent path

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-custom-hook-patterns*
*Context gathered: 2026-02-05*
