# Phase 5: Engagement Scoring Foundation - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Analyze video segments using multi-modal signals (audio energy, motion, speech features) to produce a combined engagement score (0-100). This phase delivers the scoring algorithm and data structures. Clip detection and export belong to Phase 6.

</domain>

<decisions>
## Implementation Decisions

### Signal Weighting
- Equal weights for all three signal types (audio, motion, speech) — each contributes ~33%
- Simple averaging when signals conflict — conflicting signals produce mid-range scores
- Face presence boosts engagement score (faces = human interest indicator)
- Compute both relative (normalized to video) AND absolute (fixed thresholds) scores — let downstream tools choose

### Score Granularity
- Primary scoring unit: sentence-aligned from transcript
- Merge adjacent sentences within ~10 points into larger segments
- Minimum segment duration: 2 seconds
- Non-speech segments scored using audio+motion only (no null/undefined scores)

### Output Format
- Both standalone JSON timeline AND embedded scores in transcript JSON
- Include raw signal values (audio_energy, motion_level, speech_score) alongside combined score
- CLI writes files by default, --summary flag prints human-readable overview to stdout

### Hook Detection
- Multiple hook patterns: opening statements, questions, emphasis patterns, unusual pauses
- Combined detection: text patterns (keywords/regex) AND audio prosody (pitch, volume, pauses)
- Hooks flagged in output ("hook": true) AND boost engagement score
- Max 3 hooks per minute to avoid over-flagging
- No automatic bonus for video openings — must earn hook status through detected patterns
- Custom hook phrases via JSON config file (structured format with phrases and optional weights)

### Claude's Discretion
- Hook score boost amount (tuned based on testing)
- Engagement data caching strategy (based on computation cost analysis)
- Built-in hook phrase list
- Exact prosody thresholds for audio-based hook detection

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for signal analysis and scoring algorithms.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-engagement-scoring-foundation*
*Context gathered: 2026-02-02*
