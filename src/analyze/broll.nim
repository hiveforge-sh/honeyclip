## B-Roll insertion-point detection for honeyclip
##
## Detects narrative-meaningful gaps in a transcript where B-roll clips can be
## inserted. Uses a three-signal topic-shift heuristic:
##   - Pause length between adjacent segments
##   - Speaker/sentence boundary strength
##   - Engagement-score delta across the gap
##
## Selection follows the same greedy spacing algorithm as Phase 18 chapters.
## No I/O — pure compute over Transcript + EngagementTimeline.

import std/[algorithm, math, strutils]
import ../transcript/types as transcriptTypes
import engagement_types

type
  BrollInsertion* = object
    startMs*: int64        ## start of the pause (end of previous segment)
    endMs*: int64          ## end of the B-roll window (clamped to maxPauseMs)
    pauseMs*: int64        ## raw pause duration
    contextText*: string   ## transcript text around insertion for Flash rewrite
    score*: float32        ## topic-shift score 0..100
    sourceTag*: string     ## dominant signal: "long-pause", "boundary", "engagement-delta"

  BrollParams* = object
    minSpacingMs*: int64           ## min ms between selected insertions (default 30_000)
    targetDensityPerMin*: float32  ## insertions per minute for auto-cap (default 1.0)
    maxInsertions*: int            ## -1 = derive from duration + density
    minPauseMs*: int64             ## shortest pause to consider (default 800)
    maxPauseMs*: int64             ## clip length cap in ms (default 6000)
    contextWindowSec*: int         ## seconds of transcript context for Flash (default 8)
    minScore*: float32             ## score threshold; below this skip (default 50.0)
    pauseWeight*: float32          ## weight for pause-length component (default 0.4)
    boundaryWeight*: float32       ## weight for speaker/sentence boundary (default 0.3)
    engagementDeltaWeight*: float32  ## weight for engagement delta (default 0.3)

proc defaultBrollParams*(): BrollParams =
  result.minSpacingMs = 30_000
  result.targetDensityPerMin = 1.0'f32
  result.maxInsertions = -1
  result.minPauseMs = 800
  result.maxPauseMs = 6000
  result.contextWindowSec = 8
  result.minScore = 50.0'f32
  result.pauseWeight = 0.4'f32
  result.boundaryWeight = 0.3'f32
  result.engagementDeltaWeight = 0.3'f32

proc engagementScoreAt(engagement: EngagementTimeline, ms: int64,
                        side: string): float32 =
  ## Return engagement score on the 'before' or 'after' side of a timestamp.
  ## 'before': last segment whose midpoint is <= ms
  ## 'after':  first segment whose midpoint is >= ms
  result = 50.0'f32  # neutral default when no segment found
  if side == "before":
    for seg in engagement.segments:
      let mid = (seg.startMs + seg.endMs) div 2
      if mid <= ms:
        result = seg.score
      elif mid > ms:
        break
  else:  # after
    for seg in engagement.segments:
      let mid = (seg.startMs + seg.endMs) div 2
      if mid >= ms:
        return seg.score

proc buildContextText(transcript: Transcript, startMs: int64, endMs: int64,
                      windowMs: int64): string =
  ## Collect words from transcript whose startMs falls in [startMs-window, endMs+window].
  var parts: seq[string]
  for seg in transcript.segments:
    for w in seg.words:
      if w.startMs >= (startMs - windowMs) and w.startMs <= (endMs + windowMs):
        parts.add(w.text)
  result = parts.join(" ")

proc detectBrollInsertions*(transcript: Transcript,
                             engagement: EngagementTimeline,
                             params: BrollParams): seq[BrollInsertion] =
  ## Walk adjacent segment pairs in the transcript. For each pause >= minPauseMs,
  ## score the insertion candidate and return ALL candidates (no filtering or selection).
  ## Caller should pair with selectInsertions() to apply score threshold + spacing.
  let segs = transcript.segments
  if segs.len < 2:
    return @[]

  let contextWindowMs = int64(params.contextWindowSec) * 1000

  for i in 0 ..< segs.len - 1:
    let curr = segs[i]
    let next = segs[i + 1]
    let pauseMs = next.startMs - curr.endMs

    if pauseMs < params.minPauseMs:
      continue  # too short

    # --- Pause-length component (0..100) ---
    let pauseComp = min(100.0'f32,
                        pauseMs.float32 / params.maxPauseMs.float32 * 100.0'f32)

    # --- Boundary component (0..100) ---
    # speaker is int in TranscriptSegment; -1 = unassigned, 0+ = speaker index
    let boundaryComp: float32 =
      if curr.speaker != next.speaker and curr.speaker >= 0 and next.speaker >= 0:
        100.0'f32
      elif curr.text.endsWith('.') or curr.text.endsWith('!') or
           curr.text.endsWith('?'):
        # Sentence boundary
        if next.text.len > 0 and next.text[0].isUpperAscii:
          75.0'f32
        else:
          50.0'f32
      else:
        50.0'f32  # any segment boundary is a soft boundary

    # --- Engagement-delta component (0..100) ---
    let scoreBefore = engagementScoreAt(engagement, curr.endMs, "before")
    let scoreAfter  = engagementScoreAt(engagement, next.startMs, "after")
    let delta = abs(scoreAfter - scoreBefore)
    let engagementDeltaComp = min(100.0'f32, delta / 30.0'f32 * 100.0'f32)

    # --- Weighted score ---
    let score = pauseComp * params.pauseWeight +
                boundaryComp * params.boundaryWeight +
                engagementDeltaComp * params.engagementDeltaWeight

    # --- Source tag: component with highest weighted contribution ---
    let pauseContrib = pauseComp * params.pauseWeight
    let boundaryContrib = boundaryComp * params.boundaryWeight
    let deltaContrib = engagementDeltaComp * params.engagementDeltaWeight
    let sourceTag =
      if pauseContrib >= boundaryContrib and pauseContrib >= deltaContrib:
        "long-pause"
      elif boundaryContrib >= deltaContrib:
        "boundary"
      else:
        "engagement-delta"

    # --- endMs clamped to startMs + min(pauseMs, maxPauseMs) ---
    let startMs = curr.endMs
    let endMs   = startMs + min(pauseMs, params.maxPauseMs)

    # --- Context text ---
    let contextText = buildContextText(transcript, startMs, endMs, contextWindowMs)

    result.add BrollInsertion(
      startMs: startMs,
      endMs: endMs,
      pauseMs: pauseMs,
      contextText: contextText,
      score: score,
      sourceTag: sourceTag
    )

proc selectInsertions*(candidates: seq[BrollInsertion],
                       params: BrollParams,
                       durationMs: int64): seq[BrollInsertion] =
  ## Filter by minScore, sort by score descending, greedy-pick respecting
  ## minSpacingMs, cap at resolved maxInsertions, return chronologically sorted.
  ##
  ## maxInsertions resolution:
  ##   if params.maxInsertions < 0: max(1, ceil(durationMs / 60_000 * targetDensityPerMin))
  ##   else: params.maxInsertions

  # Resolve max count
  let maxCount: int =
    if params.maxInsertions < 0:
      max(1, int(ceil(durationMs.float64 / 60_000.0 * params.targetDensityPerMin.float64)))
    else:
      params.maxInsertions

  # Filter by minimum score
  var filtered: seq[BrollInsertion]
  for c in candidates:
    if c.score >= params.minScore:
      filtered.add(c)

  # Sort by score descending (mirror chapters.nim detectEngagementPeaks)
  filtered.sort(proc(a, b: BrollInsertion): int = cmp(b.score, a.score))

  # Greedy selection with minimum spacing
  var selected: seq[BrollInsertion]
  for candidate in filtered:
    var tooClose = false
    for existing in selected:
      if abs(candidate.startMs - existing.startMs) < params.minSpacingMs:
        tooClose = true
        break
    if not tooClose:
      selected.add(candidate)
    if selected.len >= maxCount:
      break

  # Sort selected chronologically
  selected.sort(proc(a, b: BrollInsertion): int = cmp(a.startMs, b.startMs))
  result = selected
