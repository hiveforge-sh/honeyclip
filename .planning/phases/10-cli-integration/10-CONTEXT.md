# Phase 10: CLI Integration - Context

**Gathered:** 2026-02-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Integrate all engagement analysis features into a unified CLI workflow. This phase creates the `analyze` convenience command, adds engagement signals to edit expressions, and implements real-time progress reporting. No new analysis capabilities — only CLI/UX integration of existing features from Phases 5-9.

</domain>

<decisions>
## Implementation Decisions

### Command structure
- `engage` command (existing) outputs full analysis as JSON report
- New `analyze` command combines engage + clips as convenience shortcut
- `analyze` default behavior: save engagement.json, save .honeyclip-project.json, print top clips, prompt for next action (export clips, NLE, done)
- TTY-aware prompting: interactive prompt when terminal, silent when piped/scripted
- Both `--engage` flag AND score expressions available on main command
- Skip flags available: `--no-faces`, `--no-transcript` to bypass expensive steps
- Cache behavior: `--fresh` forces re-run, default uses cache
- `--dry-run` flag shows what steps would run without executing

### Progress reporting
- Per-step progress bars (separate bar for transcript, faces, scoring)
- Detailed verbosity by default: bars + timing + counts (e.g., "Found 23 faces, 450 words")
- Auto-detect TTY: quiet when piped, progress when terminal
- Explicit flags: `--quiet` and `--verbose` available for override

### Edit workflow integration
- `--engage` flag enables engagement filtering with default threshold 50
- Threshold configurable via flag value: `--engage=70`
- AND logic when combining: `--engage=60 --edit "motion() > 0.5"` = both must be true
- Full expression access: score(), audio(), motion(), speech(), face_count(), peak(), hook(), speaker_change(), is_hook(), faces_visible(), speaking_rate()
- Always cache engagement data when using `--engage` in edit workflow
- Partial signal fallback: if transcript fails, use available signals (audio/motion)
- Named presets available:
  - Content type: `viral`, `podcast`, `tutorial`, `interview`
  - Platform: `tiktok`, `youtube`, `instagram`
- Both numeric thresholds and named presets work: `--engage=70` or `--engage=viral`

### Output behavior
- Output files in same directory as source video
- Prefix naming convention: `engagement_video.json`, `clips_video.json`
- Overwrite prompt in TTY, fail in scripts if file exists
- `--force` or `-f` flag overwrites without asking

### Claude's Discretion
- Exact pipeline ordering for `analyze` command
- How preset values map to scoring weights
- Progress bar library/implementation
- Error message formatting

</decisions>

<specifics>
## Specific Ideas

- TTY-aware behavior throughout: prompts in terminal, machine-friendly output when piped
- Presets cover both content types (viral, podcast) AND platforms (tiktok, youtube)
- Partial signal fallback ensures tool degrades gracefully instead of failing

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-cli-integration*
*Context gathered: 2026-02-03*
