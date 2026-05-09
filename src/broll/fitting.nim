## Variable-duration clip fitting for honeyclip
##
## Adapts a generated B-roll clip to the requested pause length using one of
## four strategies: truncate, freeze-pad, speed-ramp, or request-extra.
## All FFmpeg commands are built as strings (pure builders) and executed via
## execCmdEx (mirror Phase 19-02 pattern). T-21-06: paths passed through quoteShell.

import std/[osproc, strformat, strutils]

type
  FittingStrategy* = enum
    fsNone           ## actual within tolerance of requested (no action needed)
    fsTruncate       ## actual > requested: trim to requested length
    fsPadFreeze      ## requested > actual by <=500ms: freeze last frame
    fsPadSpeedRamp   ## requested > actual by <=2000ms: slow down via setpts
    fsRequestExtra   ## gap too large for safe fitting; caller decides

const fittingToleranceMs* = 200
const padFreezeMaxGapMs* = 500
const padSpeedMaxGapMs* = 2000

proc selectFittingStrategy*(actualMs, requestedMs: int64): FittingStrategy =
  ## Select the appropriate fitting strategy based on actual vs. requested duration.
  ## Returns fsNone if the difference is within tolerance (200ms).
  let diff = actualMs - requestedMs
  if abs(diff) <= fittingToleranceMs:
    return fsNone
  if diff > 0:
    return fsTruncate
  let gap = -diff  # how much we need to add
  if gap <= padFreezeMaxGapMs:
    return fsPadFreeze
  if gap <= padSpeedMaxGapMs:
    return fsPadSpeedRamp
  return fsRequestExtra

proc buildFittingCmd*(clipPath: string, requestedMs, actualMs: int64,
                      strategy: FittingStrategy, outPath: string): string =
  ## Build the FFmpeg command string for the given fitting strategy.
  ## Returns empty string for fsNone / fsRequestExtra (no command needed).
  ## Paths are shell-quoted (T-21-06 compliance).
  case strategy
  of fsNone, fsRequestExtra:
    result = ""
  of fsTruncate:
    let durSec = requestedMs.float / 1000.0
    result = &"ffmpeg -y -i {clipPath.quoteShell} -t {durSec:.3f} -c copy {outPath.quoteShell}"
  of fsPadFreeze:
    let padSec = (requestedMs - actualMs).float / 1000.0
    result = &"ffmpeg -y -i {clipPath.quoteShell} -vf tpad=stop_mode=clone:stop_duration={padSec:.3f} {outPath.quoteShell}"
  of fsPadSpeedRamp:
    let speedRatio = actualMs.float / requestedMs.float
    result = &"ffmpeg -y -i {clipPath.quoteShell} -vf setpts={1.0 / speedRatio:.4f}*PTS {outPath.quoteShell}"

proc fitClipDuration*(clipPath: string, requestedMs, actualMs: int64,
                      strategy: FittingStrategy, outPath: string): bool =
  ## Execute the fitting command. Returns false if strategy is fsNone/fsRequestExtra
  ## or if the FFmpeg process exits non-zero.
  let cmd = buildFittingCmd(clipPath, requestedMs, actualMs, strategy, outPath)
  if cmd == "":
    return false
  let (output, exitCode) = execCmdEx(cmd)
  discard output
  return exitCode == 0
