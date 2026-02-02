# Phase 7: Speaker Tracking & Reframing - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Track speakers across video frames with persistent identity and auto-reframe video to center the active speaker for vertical (9:16) output. Graceful degradation to smart crop when no faces detected.

</domain>

<decisions>
## Implementation Decisions

### Speaker Identity
- Use face embedding ML model to recognize speakers when they return to frame
- Hold last known position for up to 3 seconds during temporary occlusion (hand in front of face, head turn)
- Add `--debug-speakers` flag to show colored boxes around tracked faces for debugging/review

### Reframe Behavior
- Configurable speed presets: slow (cinematic), medium (balanced), fast (social)
- Default to slow/cinematic preset (1-2 second transitions)
- Medium shot framing: head and shoulders visible (interview/podcast style)
- Camera follow uses smooth easing, not instant snaps

### Multi-Speaker Handling
- Configurable strategy via flag: active-speaker (default) or largest-face
- Active speaker tracking correlates audio with detected faces (requires transcript)
- Hold on last speaker during silence until someone else speaks
- 0.5 second minimum hold (debounce) before switching to prevent flicker in rapid dialogue
- Subtle fade/soft cut when switching between speakers (helps viewer follow)
- Use speaker diarization labels from Phase 2 transcript to improve tracking accuracy
- Fall back to largest-face strategy when audio-face correlation fails

### Fallback Modes
- Configurable fallback: center-crop or smart-crop-motion (default)
- Default smart crop follows area with most motion activity
- Transitions from fallback to face-tracking use same speed as regular tracking
- Warn at end if >50% of video used fallback crop ("consider different source")

### Claude's Discretion
- Face composition offset (center vs rule of thirds) for vertical format
- Exact easing curves for camera follow motion
- Face embedding model selection (ONNX-compatible)
- Motion detection sensitivity for smart crop fallback
- Subtle cut implementation (cross-dissolve duration, etc.)

</decisions>

<specifics>
## Specific Ideas

- Speed presets should feel distinct: slow=professional/documentary, medium=conversational, fast=TikTok/Reels energy
- Medium shot framing means viewer can see gestures and body language, not just talking head
- Debounce prevents "tennis match" feel in podcast back-and-forth
- Fallback warning helps user understand when source video isn't ideal for reframing

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-speaker-tracking-reframing*
*Context gathered: 2026-02-02*
