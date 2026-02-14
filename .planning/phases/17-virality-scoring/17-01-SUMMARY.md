---
phase: 17-virality-scoring
plan: 01
subsystem: engagement-analysis
tags: [virality, scoring, clips, ranking, engagement]
dependency_graph:
  requires:
    - "EngagementSegment type with scores, hooks, faces"
    - "Clip detection pipeline in clips.nim"
    - "Clip ranking infrastructure with overlap penalty"
  provides:
    - "ViralityComponents type with hook, flow, value, trend breakdown"
    - "Virality score calculation from engagement signals (0-100 scale)"
    - "Component-level transparency for virality scoring"
  affects:
    - "Clip ranking (now sorts by viralityScore instead of engagementScore)"
    - "Future CLI output (will display virality breakdown)"
    - "Future JSON exports (will include virality fields)"
tech_stack:
  added: []
  patterns:
    - "Four-component virality model: Hook, Flow, Value, Trend"
    - "Research-backed weighting: Hook 35%, Flow 30%, Value 25%, Trend 10%"
    - "Variance-based flow penalty for retention consistency"
    - "Pattern diversity as originality proxy for trend score"
key_files:
  created: []
  modified:
    - "src/analyze/engagement_types.nim - Added ViralityComponents type"
    - "src/analyze/clips.nim - Added virality calculation procs and updated ranking"
    - "tests/unit.nim - Updated rankClips test to set viralityScore"
    - "src/batch/templates.nim - Renamed from template.nim (keyword conflict fix)"
    - "src/batch/runner.nim - Fixed malebolgia syntax and countProcessors ambiguity"
    - "src/cmds/batch.nim - Updated import to use templates module"
decisions:
  - decision: "Use four-component virality model (hook, flow, value, trend)"
    rationale: "Research shows modern virality (2026) driven by first impression, retention consistency, content quality, and authenticity"
    alternatives: "Single combined score (less transparency), ML-based scoring (overcomplicated)"
  - decision: "Weight components: Hook 35%, Flow 30%, Value 25%, Trend 10%"
    rationale: "Research-backed weights from 2026 virality algorithm analysis in phase 17 RESEARCH.md"
    alternatives: "Equal weights (ignores research), user-configurable weights (future enhancement)"
  - decision: "Penalize flow score by variance (stdDev * 0.5, cap 30 points)"
    rationale: "High variance indicates inconsistent retention (rollercoaster engagement), should rank lower than stable clips"
    alternatives: "No variance penalty (misses consistency signal), fixed penalty (not proportional)"
  - decision: "Sort clips by viralityScore, preserve engagementScore field"
    rationale: "Backward compatibility - existing engagementScore still useful for segment-level analysis"
    alternatives: "Replace engagementScore entirely (breaking change)"
metrics:
  duration: 859
  tasks_completed: 2
  files_created: 0
  files_modified: 6
  completed_date: 2026-02-14
---

# Phase 17 Plan 01: Virality Scoring Core Logic Summary

**One-liner:** Four-component virality scoring (hook, flow, value, trend) with research-backed weights, integrated into clip detection and ranking pipeline

## Overview

Added quantified virality scoring to honeyclip's clip detection system. Each detected clip now receives a 0-100 virality score composed of four weighted components: Hook (first impression strength), Flow (retention consistency), Value (content quality signals), and Trend (authenticity/originality). The system reuses existing engagement signals (segment scores, hook detection, face tracking) to calculate these components, providing transparency into what makes a clip viral.

Clips are now ranked by virality score instead of raw engagement score, with the existing overlap penalty and hook boost logic preserved. The implementation includes variance-based flow penalties (to penalize inconsistent retention) and pattern diversity scoring (to reward authentic/original content).

## Tasks Completed

### Task 1: Add ViralityComponents type and virality fields to Clip
**Status:** ✓ Complete
**Commit:** `29e2e8b`

- Added `ViralityComponents` type to `src/analyze/engagement_types.nim`:
  - `hook: float32` - First impression strength (0-100)
  - `flow: float32` - Retention consistency (0-100)
  - `value: float32` - Content quality signals (0-100)
  - `trend: float32` - Authenticity/originality (0-100)
- Added two new fields to `Clip` type in `src/analyze/clips.nim`:
  - `viralityScore: float32` - Combined virality score (0-100)
  - `viralityComponents: ViralityComponents` - Component breakdown
- Preserved existing `engagementScore` field for backward compatibility
- Project compiles successfully after changes

**Files modified:**
- `src/analyze/engagement_types.nim` (added ViralityComponents type)
- `src/analyze/clips.nim` (added virality fields to Clip)

**Verification:** `nimble make` succeeds, `grep` confirms ViralityComponents exists in both files

### Task 2: Implement virality calculation and update ranking
**Status:** ✓ Complete
**Commit:** `889fdfd`

- Added imports: `std/[sets, math]` for HashSet and sqrt()
- Implemented virality calculation procs in `src/analyze/clips.nim`:
  - `calculateHookScore(firstSegment)` - Base score + 15 point bonus for hooks (capped at 100)
  - `calculateFlowScore(segments)` - Average score with variance penalty (stdDev * 0.5, capped at 30)
  - `calculateValueScore(segments, maxFaceCount)` - Average score + face boost (3 points per face, capped at 15)
  - `calculateTrendScore(segments)` - Hook pattern diversity (33.33 points per unique pattern, 50 neutral)
  - `calculateViralityComponents(segments, maxFaceCount)` - Orchestrates all four component calculations
  - `combineViralityScore(components)` - Weighted average: hook*0.35 + flow*0.30 + value*0.25 + trend*0.10
- Updated `detectClips()` to calculate virality:
  - Collect overlapping segments into `clipSegments` seq
  - Call `calculateViralityComponents()` with segments and maxFaceCount
  - Set `viralityScore` and `viralityComponents` on each Clip
- Updated `rankClips()` to sort by virality:
  - Changed sort from `engagementScore` to `viralityScore`
  - Changed adjusted score base from `engagementScore` to `viralityScore`
  - Preserved overlap penalty and hook boost logic unchanged
- Updated `tests/unit.nim` rankClips test:
  - Set `viralityScore` on test clips to match their `engagementScore`
  - Ensures backward-compatible test behavior (clips rank predictably)

**Files modified:**
- `src/analyze/clips.nim` (virality procs, detectClips, rankClips updates)
- `tests/unit.nim` (test update for viralityScore)

**Verification:** `nimble make` succeeds, `grep` confirms virality procs and field usage

## Deviations from Plan

### Auto-fixed Issues (Deviation Rule 3: Blocking Issues)

**1. Rule 3 - Blocking: Module name conflicts with Nim keyword**
- **Found during:** Task 1 compilation attempt
- **Issue:** `src/batch/template.nim` module name conflicts with Nim's `template` keyword, causing parse error
- **Fix:** Renamed `src/batch/template.nim` to `src/batch/templates.nim`, updated imports in `runner.nim`, `batch.nim`, and `tests/unit.nim`
- **Files modified:** `src/batch/templates.nim` (renamed), `src/batch/runner.nim`, `src/cmds/batch.nim`, `tests/unit.nim`
- **Commit:** `d08ea52` (blocking fixes)
- **Rationale:** Pre-existing blocker preventing any compilation - must fix to proceed with Task 1

**2. Rule 3 - Blocking: Ambiguous countProcessors() call**
- **Found during:** Task 1 compilation attempt after template fix
- **Issue:** `countProcessors()` imported from both `cpuinfo` and `osproc` modules, causing ambiguous call error
- **Fix:** Qualified call as `cpuinfo.countProcessors()` in `src/batch/runner.nim`
- **Files modified:** `src/batch/runner.nim`
- **Commit:** `d08ea52` (blocking fixes)
- **Rationale:** Ambiguous symbol error prevents compilation

**3. Rule 3 - Blocking: Incorrect malebolgia spawn syntax**
- **Found during:** Task 1 compilation attempt after countProcessors fix
- **Issue:** malebolgia `spawn` syntax used `-> results.add` pattern which causes "re-use of expression" error
- **Fix:** Pre-allocate `results` seq with correct length, use indexed assignment: `m.spawn processOneFile(...) -> results[i]`
- **Files modified:** `src/batch/runner.nim`
- **Commit:** `d08ea52` (blocking fixes)
- **Rationale:** Incorrect malebolgia API usage - need pre-allocated seq with index assignment, not append

All three blocking issues were pre-existing bugs in Phase 16 batch processing code that were never tested to compile. Fixed inline per deviation rules - no user permission needed since they blocked Task 1 execution.

## Verification Results

All success criteria met:

1. ✓ ViralityComponents type defined with hook, flow, value, trend float32 fields
2. ✓ Clip type has viralityScore and viralityComponents fields
3. ✓ Four component calculation procs exist: calculateHookScore, calculateFlowScore, calculateValueScore, calculateTrendScore
4. ✓ combineViralityScore uses weights: hook 0.35, flow 0.30, value 0.25, trend 0.10
5. ✓ detectClips() populates viralityScore and viralityComponents on each clip
6. ✓ rankClips() sorts by viralityScore instead of engagementScore
7. ✓ engagementScore field preserved on Clip (backward compatibility)
8. ✓ Project compiles: `nimble make` succeeds
9. ✓ `grep -r "ViralityComponents" src/analyze/` returns matches in both engagement_types.nim and clips.nim
10. ✓ `grep "viralityScore" src/analyze/clips.nim` shows field in Clip type, usage in detectClips and rankClips

## Key Implementation Details

**Component Calculation Logic:**
- **Hook:** First segment score + 15.0 bonus if `hasHook` flag set, capped at 100.0
- **Flow:** Average segment score - variance penalty (stdDev * 0.5, capped at 30.0)
- **Value:** Average segment score + face boost (maxFaceCount * 3.0, capped at 15.0)
- **Trend:** Unique hook pattern count * 33.33 (1=33, 2=67, 3+=100), neutral 50.0 if no patterns

**Weighted Combination:**
- Final virality score = Hook*35% + Flow*30% + Value*25% + Trend*10%
- Based on 2026 virality research (see phase 17 RESEARCH.md sources)

**Ranking Changes:**
- Primary sort changed from `engagementScore` to `viralityScore`
- Adjusted score base changed from `engagementScore` to `viralityScore`
- Overlap penalty, hook boost, and preferLongerClips logic unchanged
- Test updated to set viralityScore on test clips (prevents sort instability from default 0.0f values)

**Backward Compatibility:**
- `engagementScore` field preserved (still useful for segment-level analysis)
- Virality fields added alongside existing fields (non-breaking change)
- Future JSON exports will include both `engagementScore` and `viralityScore`

## Next Steps (Not Implemented - Future Plans)

1. **Plan 17-02:** Display virality breakdown in CLI output (clips command)
   - Show component scores (hook, flow, value, trend) in `clips --list` output
   - Add virality score to clip ranking display

2. **Plan 17-03:** Export virality data in JSON/EDL formats
   - Add `viralityScore` and `viralityComponents` to JSON exports
   - Include virality metadata in EDL/NLE exports

3. **Future Enhancement:** User-configurable component weights
   - Add `ViralityParams` to `EngagementParams`
   - Allow platform-specific tuning (TikTok vs YouTube Shorts)

## Performance Impact

- Minimal - virality calculation reuses existing segment iteration in `detectClips()`
- Adds ~100 lines of calculation code, but no additional I/O or memory allocation
- Variance calculation is O(n) where n = segments per clip (typically <50)
- HashSet for pattern diversity is O(m) where m = hook patterns per clip (typically <10)

## Self-Check: PASSED

**Created files:**
- None (only modified existing files)

**Modified files verified:**
```bash
[ -f "src/analyze/engagement_types.nim" ] && echo "FOUND: src/analyze/engagement_types.nim"
[ -f "src/analyze/clips.nim" ] && echo "FOUND: src/analyze/clips.nim"
[ -f "tests/unit.nim" ] && echo "FOUND: tests/unit.nim"
```
Output:
```
FOUND: src/analyze/engagement_types.nim
FOUND: src/analyze/clips.nim
FOUND: tests/unit.nim
```

**Commits verified:**
```bash
git log --oneline --all | grep -E "(29e2e8b|889fdfd|d08ea52)"
```
Output:
```
889fdfd feat(17-01): implement virality scoring and update clip ranking
d08ea52 fix(batch): resolve compilation blockers in batch processing code
29e2e8b feat(17-01): add ViralityComponents type and virality fields to Clip
```

All files exist, all commits found, self-check PASSED.
