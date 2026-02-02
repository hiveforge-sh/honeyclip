# Phase 4: Face Detection Infrastructure - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect faces in video frames with adaptive sampling and persistent caching. This is infrastructure — detected faces feed into Phase 5 (Engagement Scoring) and Phase 7 (Speaker Tracking & Reframing). No direct user interaction with detection output.

</domain>

<decisions>
## Implementation Decisions

### Detection defaults
- Favor recall over precision — catch all faces even with some false positives (better for downstream speaker tracking)
- Filter small faces below ~5% of frame height to remove background noise (crowds, photos on walls)
- Track all faces in multi-face frames — let speaker tracking (Phase 7) decide who's active
- Include facial landmarks (eyes, nose, mouth positions) in detection output — useful for gaze direction in future phases

### Adaptive sampling
- Trigger increased sampling on BOTH scene changes AND face state changes (appears/disappears)
- Favor speed: 1-2 fps baseline, spike on changes — fast processing, acceptable for typical content
- Keep minimum rate (1fps) even when no faces detected — faces may appear later
- Full CLI control: expose all parameters (min/max fps, thresholds, window size) for power users

### Caching rules
- Cache invalidation: input file hash + detection parameters (changing confidence/sampling invalidates)
- Storage location: `.honeyclip/` folder alongside video file (portable, easy to find)
- Binary format for fast loading (not human-readable)
- Add CLI commands: `honeyclip cache --clear-faces`, `honeyclip cache --info` for cache management

### Claude's Discretion
- Exact confidence threshold value (guided by "favor recall" decision)
- Scene change detection algorithm
- Multi-frame consensus window size and agreement threshold
- Binary cache format structure
- CLI parameter naming and defaults

</decisions>

<specifics>
## Specific Ideas

- Metropolitan Police finding cited in blockers: 85% false positive rate in production — multi-frame consensus critical
- Success criteria requires <15% false positive rate on real-world video
- libfacedetection already built in Phase 1 — use its CNN-based detection

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-face-detection-infrastructure*
*Context gathered: 2026-02-02*
