# Phase 6: Engagement Clip Detection - Context

**Gathered:** 2026-02-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Automatically detect optimal clip boundaries and rank clips by engagement score for batch export. Users can detect scene boundaries that define natural segmentation, see clips ranked highest to lowest, and batch export multiple clips from a single video. Speaker reframing and multi-aspect export are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Clip Boundary Logic
- Use both scene changes AND engagement transitions to determine boundaries
- Prefer scene changes as primary markers, but also split on major engagement drops
- Prioritize speech alignment: avoid cutting mid-sentence; extend or trim slightly to complete thoughts
- Target clip duration: 15-60 seconds (short-form social media style)
- Merge adjacent high-engagement segments into single clips to avoid too many tiny clips

### Ranking & Selection
- Default to top 5 clips by engagement score
- No minimum score threshold; rank all segments, let user decide which to use
- When clips overlap in time, prefer the longer clip
- Promote variety: reduce score of clips that overlap significantly with higher-ranked ones
- Slight boost for "hook" segments (attention-grabbing openings)
- Face priority is configurable via flag (user can toggle whether face presence boosts ranking)
- Configurable intro skip duration (flag to skip first N seconds)
- Configurable outro skip duration (flag to skip last N seconds)

### Batch Export Workflow
- Two-step workflow: Detect → Preview → Export
- First show clips list, user confirms which to export
- Output directory: subfolder next to source video (e.g., `video_clips/`)
- File naming: include timestamp (`video_00m30s-01m15s.mp4`)
- Render clips in parallel for speed (multiple FFmpeg processes)

### Output Format
- Both rendered video clips AND metadata files
- Metadata formats: JSON + EDL (both produced)
- JSON includes full breakdown: overall score + audio/motion/speech sub-scores + hooks found
- Video codec: always H.264 for maximum compatibility

### Claude's Discretion
- Exact engagement drop threshold that triggers a clip split
- Parallel render concurrency level (balance CPU/RAM)
- EDL format variant (CMX3600 vs other)
- How to handle edge cases where no clips meet any reasonable criteria

</decisions>

<specifics>
## Specific Ideas

- Clips should feel like natural "moments" that could be posted as-is to TikTok/Reels/Shorts
- The preview step is important: user should see what they're getting before committing to render time
- Timestamp-based naming makes it easy to find the original segment in the source video

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-engagement-clip-detection*
*Context gathered: 2026-02-02*
