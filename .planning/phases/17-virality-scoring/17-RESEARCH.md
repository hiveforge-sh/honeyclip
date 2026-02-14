# Phase 17: Virality Scoring - Research

**Researched:** 2026-02-14
**Domain:** Video engagement scoring, virality prediction, social media metrics
**Confidence:** HIGH

## Summary

Phase 17 extends honeyclip's existing engagement analysis system to provide quantified virality scores (0-100) for detected clips. The system already has the foundational components in place: engagement segments with scores, hook detection, face tracking, audio/motion signals, and clip detection. This phase focuses on composing these existing signals into a multi-component virality score with breakdown visibility.

The research reveals that modern virality scoring (2026) is driven by four key components:
1. **Hook** - First 3-second retention, measured by intro attention capture
2. **Flow** - Sustained retention through the clip, measured by watch time percentage
3. **Value** - Content quality signals like engagement actions and face presence
4. **Trend** - Authenticity and originality signals

honeyclip's current architecture already captures the raw signals needed for these components. The implementation will involve calculating component scores from existing data, combining them with proper weights, and exposing the breakdown in both CLI output and JSON exports.

**Primary recommendation:** Extend `EngagementSegment` and `Clip` types to include virality component scores (hook, flow, value, trend). Calculate these from existing signals (hook detection, segment scores, face counts, score variance). Sort clips by virality score in `rankClips()`. Display breakdown in `clips` command output.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Nim stdlib | 2.2.2+ | Math operations, sorting | Built-in, no dependencies |
| existing engagement.nim | current | Segment scoring, signal analysis | Already implemented and tested |
| existing clips.nim | current | Clip detection, ranking | Already implements scoring framework |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| existing hooks.nim | current | Hook pattern detection | Already integrated in engagement analysis |
| existing engagement_types.nim | current | Data structures for scores | Extend for virality components |

### Alternatives Considered

None needed. This phase extends existing architecture rather than introducing new libraries.

**Installation:**
No additional dependencies required. All functionality uses existing Nim stdlib and honeyclip modules.

## Architecture Patterns

### Recommended Project Structure

```
src/analyze/
├── engagement.nim         # Extend with virality component calculation
├── engagement_types.nim   # Add ViralityScore type with component breakdown
├── clips.nim              # Update rankClips() to sort by virality score
└── hooks.nim              # Already provides hook detection signals
```

### Pattern 1: Component Score Calculation

**What:** Calculate each virality component (hook, flow, value, trend) from existing engagement signals
**When to use:** After clip boundaries are detected, before ranking

**Example:**
```nim
type
  ViralityComponents* = object
    hook*: float32      # 0-100: Hook strength (first segment score + hasHook boost)
    flow*: float32      # 0-100: Retention consistency (score variance penalty)
    value*: float32     # 0-100: Content quality (average score + face boost)
    trend*: float32     # 0-100: Authenticity signals (hook pattern diversity)

proc calculateViralityScore*(clip: Clip, segments: seq[EngagementSegment]): ViralityComponents =
  # Hook: First segment score + hook detection bonus
  let firstSeg = segments[0]  # Assume segments sorted by startMs
  result.hook = firstSeg.score
  if firstSeg.hasHook:
    result.hook = min(100.0f, result.hook + 15.0f)  # Hook boost

  # Flow: Penalize high variance (inconsistent retention)
  var avgScore = 0.0f
  for seg in segments:
    avgScore += seg.score
  avgScore /= segments.len.float32

  var variance = 0.0f
  for seg in segments:
    variance += (seg.score - avgScore) * (seg.score - avgScore)
  variance /= segments.len.float32

  let flowPenalty = min(variance / 100.0f, 30.0f)  # Cap penalty at 30 points
  result.flow = max(0.0f, avgScore - flowPenalty)

  # Value: Average engagement + quality signals
  result.value = avgScore
  if clip.faceCount > 0:
    result.value = min(100.0f, result.value + clip.faceCount.float32 * 3.0f)

  # Trend: Hook pattern diversity (more unique patterns = more authentic)
  var uniquePatterns: HashSet[string]
  for seg in segments:
    for pattern in seg.hookMatches:
      uniquePatterns.incl(pattern)

  # More diverse patterns = higher trend score (max 3 patterns = 100)
  result.trend = min(100.0f, uniquePatterns.len.float32 * 33.33f)
  if uniquePatterns.len == 0:
    result.trend = 50.0f  # Neutral for no hooks

proc combineViralityScore*(components: ViralityComponents): float32 =
  ## Combine components with 2026 algorithm weights
  ## Based on research: Hook 35%, Flow 30%, Value 25%, Trend 10%
  result = (components.hook * 0.35f +
            components.flow * 0.30f +
            components.value * 0.25f +
            components.trend * 0.10f)
```

### Pattern 2: Score Breakdown Display

**What:** Show virality component breakdown in CLI output for transparency
**When to use:** In `clips --list` output and JSON exports

**Example:**
```nim
proc printClipWithVirality*(clip: Clip, components: ViralityComponents) =
  let startTime = formatTimestamp(clip.startMs)
  let endTime = formatTimestamp(clip.endMs)

  echo &"  #{clip.rank}: {startTime}-{endTime} Virality: {clip.viralityScore:.0f}"
  echo &"      Hook: {components.hook:.0f}  Flow: {components.flow:.0f}  Value: {components.value:.0f}  Trend: {components.trend:.0f}"

  # Existing text display
  if clip.text.len > 0:
    echo &"      \"{clip.text[0..min(70, clip.text.len-1)]}...\""
```

### Pattern 3: Sorting by Virality

**What:** Replace engagement score sorting with virality score sorting in rankClips()
**When to use:** During clip ranking phase

**Example:**
```nim
proc rankClips*(clips: seq[Clip], params: ClipRankingParams): seq[Clip] =
  var ranked: seq[Clip] = @[]
  var candidates = clips

  # Sort by virality score instead of engagementScore
  candidates.sort(proc(a, b: Clip): int = cmp(b.viralityScore, a.viralityScore))

  # Rest of ranking logic (overlap penalty, etc.) unchanged
  # ...
```

### Anti-Patterns to Avoid

- **Black box scoring:** Don't hide component calculations. Users need to see hook/flow/value/trend breakdown to understand why a clip scored high.
- **Fixed weights:** Don't hard-code component weights without allowing future configuration via `EngagementParams`.
- **Ignoring existing signals:** Don't recalculate audio/motion/speech from scratch. Reuse existing segment scores.
- **Breaking existing APIs:** Don't remove `engagementScore` field. Add `viralityScore` alongside it for backward compatibility.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Score normalization | Custom min-max normalization | Existing `normalizePercentile()` in engagement_types.nim | Already handles outliers with percentile bounds |
| Segment variance | Custom variance calculation | Nim's `math.variance()` or simple loop | Variance calculation is straightforward, no library needed |
| Component weighting | Complex ML models | Simple weighted average | Research shows fixed weights (Hook 35%, Flow 30%, Value 25%, Trend 10%) work well |
| Score display | Custom formatting | Existing `formatTimestamp()` and string interpolation | Already implemented in clips.nim |

**Key insight:** Don't overcomplicate virality scoring with machine learning or complex algorithms. Research shows that simple weighted combinations of well-chosen components (hook, flow, value, trend) correlate strongly with actual viral performance. The value is in component selection and transparency, not algorithmic sophistication.

## Common Pitfalls

### Pitfall 1: Overweighting Hook at Expense of Flow

**What goes wrong:** Setting hook weight too high (>50%) causes clips with strong openings but poor retention to rank higher than consistently engaging clips.

**Why it happens:** Hook detection is more explicit (hasHook flag) and feels more "measurable" than flow metrics.

**How to avoid:** Use research-backed weights: Hook 35%, Flow 30%, Value 25%, Trend 10%. Hook is important but not dominant.

**Warning signs:** Clips with single hook pattern in first segment but low average scores ranking #1.

### Pitfall 2: Ignoring Score Variance in Flow Calculation

**What goes wrong:** Using average score alone for flow doesn't distinguish between consistently engaging clips (stable high scores) and rollercoaster clips (alternating high/low scores).

**Why it happens:** Average is simpler to calculate and understand than variance.

**How to avoid:** Calculate variance of segment scores and penalize high variance. A clip that maintains 75-80 score throughout should rank higher than one that jumps between 50 and 100.

**Warning signs:** Clips with wildly varying segment scores (50, 95, 45, 90) scoring as high as stable clips (75, 78, 77, 76).

### Pitfall 3: Conflating Virality Score with Engagement Score

**What goes wrong:** Replacing `engagementScore` field instead of adding `viralityScore` alongside breaks existing CLI output and JSON exports.

**Why it happens:** Seems simpler to have one "score" field.

**How to avoid:** Add virality score as separate field. Existing `engagementScore` is still useful for segment-level analysis. Virality score is clip-level and combines different components.

**Warning signs:** Tests failing, JSON schema changes breaking downstream consumers.

### Pitfall 4: No Score Breakdown Visibility

**What goes wrong:** Showing only final virality score (65) without component breakdown (Hook: 85, Flow: 60, Value: 70, Trend: 40) prevents users from understanding what makes a clip viral.

**Why it happens:** Component breakdown requires more output lines, feels verbose.

**How to avoid:** Always display component breakdown. This is a feature, not noise. Users want to know "why did this clip score 65?" The answer is the breakdown.

**Warning signs:** User confusion about why low-engagement clips rank high (answer: strong hook), or why high-engagement clips rank low (answer: poor flow/variance).

## Code Examples

Verified patterns from honeyclip codebase:

### Extending Existing Types

```nim
# In src/analyze/engagement_types.nim
type
  ViralityComponents* = object
    ## Breakdown of virality score components
    hook*: float32      # 0-100: First impression strength
    flow*: float32      # 0-100: Retention consistency
    value*: float32     # 0-100: Content quality signals
    trend*: float32     # 0-100: Authenticity/originality

  EngagementSegment* = object
    # Existing fields...
    startMs*: int64
    endMs*: int64
    score*: float32
    hasHook*: bool
    hookMatches*: seq[string]
    faceCount*: int
    # New field for virality analysis (optional, computed on-demand)
    # Not stored in segment, computed at clip level

  Clip* = object
    # Existing fields...
    startMs*: int64
    endMs*: int64
    engagementScore*: float32
    hasHook*: bool
    # New fields for virality
    viralityScore*: float32          # Combined 0-100 score
    viralityComponents*: ViralityComponents  # Component breakdown
```

### Calculating Components from Existing Signals

```nim
# In src/analyze/clips.nim or new src/analyze/virality.nim
import std/[sets, math]
import engagement_types

proc calculateHookScore*(firstSegment: EngagementSegment): float32 =
  ## Hook score: First segment engagement + hook detection bonus
  result = firstSegment.score
  if firstSegment.hasHook:
    result = min(100.0f, result + 15.0f)

proc calculateFlowScore*(segments: seq[EngagementSegment]): float32 =
  ## Flow score: Average engagement with variance penalty
  if segments.len == 0:
    return 0.0f

  # Calculate average
  var avgScore = 0.0f
  for seg in segments:
    avgScore += seg.score
  avgScore /= segments.len.float32

  # Calculate variance
  var variance = 0.0f
  for seg in segments:
    let diff = seg.score - avgScore
    variance += diff * diff
  variance /= segments.len.float32

  # Penalize high variance (inconsistent retention)
  # Standard deviation penalty capped at 30 points
  let stdDev = sqrt(variance)
  let flowPenalty = min(stdDev * 0.5f, 30.0f)

  result = max(0.0f, avgScore - flowPenalty)

proc calculateValueScore*(segments: seq[EngagementSegment],
                          maxFaceCount: int): float32 =
  ## Value score: Average engagement + face presence boost
  if segments.len == 0:
    return 0.0f

  var avgScore = 0.0f
  for seg in segments:
    avgScore += seg.score
  avgScore /= segments.len.float32

  result = avgScore

  # Face boost (human presence = higher value)
  if maxFaceCount > 0:
    let faceBoost = min(maxFaceCount.float32 * 3.0f, 15.0f)
    result = min(100.0f, result + faceBoost)

proc calculateTrendScore*(segments: seq[EngagementSegment]): float32 =
  ## Trend score: Hook pattern diversity (originality proxy)
  var uniquePatterns: HashSet[string]

  for seg in segments:
    for pattern in seg.hookMatches:
      uniquePatterns.incl(pattern)

  if uniquePatterns.len == 0:
    return 50.0f  # Neutral for no hooks

  # More diverse patterns = higher originality
  # 1 pattern = 33, 2 patterns = 67, 3+ patterns = 100
  result = min(100.0f, uniquePatterns.len.float32 * 33.33f)

proc calculateViralityComponents*(clip: Clip,
                                   segments: seq[EngagementSegment]): ViralityComponents =
  ## Calculate all virality components from clip segments
  if segments.len == 0:
    return ViralityComponents(hook: 0.0f, flow: 0.0f, value: 0.0f, trend: 0.0f)

  result.hook = calculateHookScore(segments[0])
  result.flow = calculateFlowScore(segments)
  result.value = calculateValueScore(segments, clip.faceCount)
  result.trend = calculateTrendScore(segments)

proc combineViralityScore*(components: ViralityComponents): float32 =
  ## Combine components with research-backed weights
  ## Hook 35%, Flow 30%, Value 25%, Trend 10%
  result = (components.hook * 0.35f +
            components.flow * 0.30f +
            components.value * 0.25f +
            components.trend * 0.10f)
```

### Sorting Clips by Virality Score

```nim
# In src/analyze/clips.nim, modify rankClips()
proc rankClips*(clips: seq[Clip], params: ClipRankingParams): seq[Clip] =
  if clips.len == 0:
    return @[]

  var ranked: seq[Clip] = @[]
  var candidates = clips

  # Sort by virality score descending (instead of engagementScore)
  candidates.sort(proc(a, b: Clip): int = cmp(b.viralityScore, a.viralityScore))

  # Rest of ranking logic (overlap penalty) unchanged
  for candidate in candidates:
    if ranked.len >= params.topN:
      break

    var adjustedScore = candidate.viralityScore  # Use virality instead of engagement

    # Overlap penalty logic unchanged
    for selected in ranked:
      let iou = calculateIoU(candidate, selected)
      if iou > params.overlapThreshold:
        adjustedScore -= params.overlapPenalty * iou

    if adjustedScore > 0.0f or ranked.len == 0:
      var rankedClip = candidate
      rankedClip.adjustedScore = adjustedScore
      rankedClip.rank = ranked.len + 1
      ranked.add(rankedClip)

  # Re-sort by adjusted score
  ranked.sort(proc(a, b: Clip): int = cmp(b.adjustedScore, a.adjustedScore))
  for i in 0 ..< ranked.len:
    ranked[i].rank = i + 1

  return ranked
```

### CLI Output with Component Breakdown

```nim
# In src/cmds/clips.nim, modify printClipList()
proc printClipList*(clips: seq[Clip], inputPath: string) =
  echo ""
  echo &"Detected Clips ({clips.len} total, sorted by virality)"
  echo "=========================================="
  echo ""

  for clip in clips:
    let startTime = formatTimestamp(clip.startMs)
    let endTime = formatTimestamp(clip.endMs)
    let duration = (clip.endMs - clip.startMs) div 1000

    # Main line: rank, time range, duration, virality score
    echo &"  #{clip.rank}: {startTime}-{endTime} ({duration}s) Virality: {clip.viralityScore:.0f}"

    # Component breakdown line
    let c = clip.viralityComponents
    echo &"      Hook: {c.hook:.0f}  Flow: {c.flow:.0f}  Value: {c.value:.0f}  Trend: {c.trend:.0f}"

    # Text preview (existing)
    if clip.text.len > 0:
      var text = clip.text.replace("\n", " ").strip()
      if text.len > 70:
        text = text[0..67] & "..."
      echo &"      \"{text}\""
    echo ""
```

### JSON Export with Components

```nim
# In src/exports/edl.nim or clips.nim JSON export
proc clipToJson*(clip: Clip): JsonNode =
  result = %* {
    "start_ms": clip.startMs,
    "end_ms": clip.endMs,
    "rank": clip.rank,
    "engagement_score": clip.engagementScore,  # Keep for backward compatibility
    "virality_score": clip.viralityScore,       # New field
    "virality_components": {                    # New breakdown
      "hook": clip.viralityComponents.hook,
      "flow": clip.viralityComponents.flow,
      "value": clip.viralityComponents.value,
      "trend": clip.viralityComponents.trend
    },
    "text": clip.text,
    "has_hook": clip.hasHook,
    "face_count": clip.faceCount
  }
```

## State of the Art

| Old Approach | Current Approach (2026) | When Changed | Impact |
|--------------|-------------------------|--------------|--------|
| View count as virality | Retention-first metrics | 2024-2025 algorithm updates | Platforms prioritize watch time over raw views |
| Single engagement score | Multi-component breakdown | 2025 creator tools evolution | Transparency into why content performs |
| Polished production | Raw authenticity | September 2025 TikTok algorithm | Authentic content gets 60% better engagement |
| Trending audio focus | Originality bonus | Late 2025 platform changes | Recycled trends lost 40-60% reach overnight |
| Likes as primary metric | Shares/saves weighted higher | 2024-2026 gradual shift | Share = new user acquisition, highly valued |

**Deprecated/outdated:**
- **View count metrics:** Platforms deprecated view count as primary virality indicator. Modern algorithms prioritize retention percentage over raw views.
- **Single score systems:** Early engagement tools showed one "score" field. 2026 best practice is component breakdown (hook, flow, value, trend) for actionable insights.
- **Fixed 3-second hooks:** While 3 seconds remains important, modern analysis distinguishes between retention at 3s, 10s, 30s, and end. Flow captures this progression.

## Open Questions

1. **Component weight tuning**
   - What we know: Research suggests Hook 35%, Flow 30%, Value 25%, Trend 10%
   - What's unclear: Whether these weights should vary by platform (TikTok vs YouTube Shorts) or content type (education vs entertainment)
   - Recommendation: Start with fixed weights, add optional `ViralityParams` in future phase if users request platform-specific tuning

2. **Trend component measurement**
   - What we know: Hook pattern diversity provides originality proxy
   - What's unclear: Whether adding speech rate variance or other prosody signals would improve trend detection
   - Recommendation: Use hook pattern diversity for v1, collect user feedback on trend score accuracy

3. **Flow variance penalty scaling**
   - What we know: High variance (inconsistent scores) should penalize flow
   - What's unclear: Optimal penalty scaling (currently stdDev * 0.5, capped at 30 points)
   - Recommendation: Start with conservative penalty, monitor clip rankings, adjust if stable clips rank too low

4. **Backward compatibility for JSON consumers**
   - What we know: Adding `viralityScore` and `viralityComponents` fields to JSON
   - What's unclear: Whether any external tools consume honeyclip JSON and would break
   - Recommendation: Keep existing `engagementScore` field, add virality fields as new. Version JSON schema if needed in future.

## Sources

### Primary (HIGH confidence)

- [Short-Form Video Dominance: Mastering Reels, TikTok, and YouTube Shorts in 2026](https://almcorp.com/blog/short-form-video-mastery-tiktok-reels-youtube-shorts-2026/) - Hook, flow, retention metrics
- [10 Viral Hook Templates for 1M+ Views (2026 Guide)](https://virvid.ai/blog/ai-shorts-script-hook-ultimate-guide-2026) - Hook patterns and intro retention (70%+ benchmark)
- [How the TikTok Algorithm Works 2026: What Makes Videos Go Viral | Joyspace](https://joyspace.ai/cracking-tiktok-algorithm-virality-calculation) - Watch time prioritization, engagement weighting
- [Short-Form Content Performance & Virality Metrics 2026](https://influenceflow.io/resources/short-form-content-performance-and-virality-metrics-the-complete-2026-guide/) - Engagement thresholds (5% strong, 10% viral potential)

### Secondary (MEDIUM confidence)

- [The Weighted Scoring Model: Guide, Template, and Calculator](https://www.savio.io/product-roadmap/weighted-scoring-model/) - Weighted scoring formula patterns
- [Score Normalization - ScienceDirect Topics](https://www.sciencedirect.com/topics/computer-science/score-normalization) - Normalization techniques for multi-component scores
- [Silent, Vertical & 3-Second Hooks Win Video Production Trends 2026](https://asensebranding.com/blogs/video-production-trends-in-2026-how-algorithms-favor-silent-vertical-instant-videos) - Hook timing benchmarks
- [What Content Creators Need to Know About TikTok's New Algorithm in 2026 - OpusClip Blog](https://www.opus.pro/blog/tiktoks-new-algorithm-2026) - Originality bonus, authenticity signals

### Tertiary (LOW confidence)

- [How to Go Viral on YouTube in 2026 (10 Strategies)](https://posteverywhere.ai/blog/how-to-go-viral-on-youtube) - General viral strategies (needs verification with platform data)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Extends existing honeyclip architecture, no new dependencies
- Architecture: HIGH - Patterns follow existing engagement.nim and clips.nim design
- Pitfalls: MEDIUM - Based on general scoring system experience, needs validation with actual clip data

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (30 days - viral scoring metrics stable, but platform algorithm changes can shift weights)
