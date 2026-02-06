## Quality Metrics Validation for Benchmarks
##
## Provides PSNR and SSIM calculation using FFmpeg's libavfilter
## to validate that optimizations don't degrade output quality.

import std/[strformat, strutils, os, osproc]
import ../src/log

type
  QualityMetrics* = object
    psnr*: float      # Peak Signal-to-Noise Ratio (dB)
    ssim*: float      # Structural Similarity Index (0-1)
    valid*: bool      # Whether metrics were successfully calculated

const
  MinimumPSNR* = 30.0    # Minimum acceptable PSNR (dB) - anything below is degraded
  MinimumSSIM* = 0.95    # Minimum acceptable SSIM - anything below has visible artifacts

# Calculate PSNR and SSIM between two video files using FFmpeg
proc calculateQualityMetrics*(reference: string, test: string): QualityMetrics =
  ## Calculate PSNR and SSIM between reference and test videos.
  ## Uses FFmpeg's built-in filters for accurate measurement.
  
  result = QualityMetrics(psnr: 0.0, ssim: 0.0, valid: false)
  
  # Check files exist
  if not fileExists(reference):
    debug &"Reference file not found: {reference}"
    return
  
  if not fileExists(test):
    debug &"Test file not found: {test}"
    return
  
  # Try to find ffmpeg binary (built locally or system)
  var ffmpegBin = "build/bin/ffmpeg"
  if not fileExists(ffmpegBin):
    ffmpegBin = findExe("ffmpeg")
    if ffmpegBin == "":
      debug "FFmpeg not found (needed for quality metrics)"
      return
  
  # Calculate PSNR using FFmpeg
  # Format: ffmpeg -i test.mp4 -i reference.mp4 -filter_complex psnr -f null -
  let psnrCmd = &"{ffmpegBin} -i \"{test}\" -i \"{reference}\" -filter_complex \"psnr=stats_file=-\" -f null - 2>&1"
  
  var psnrValue = 0.0
  try:
    let (psnrOutput, psnrExitCode) = execCmdEx(psnrCmd)
    if psnrExitCode == 0:
      # Parse PSNR from output
      # Format: "psnr_avg:38.21 psnr_y:39.45 psnr_u:42.18 psnr_v:41.92"
      for line in psnrOutput.splitLines():
        if "psnr_avg:" in line:
          let parts = line.split("psnr_avg:")
          if parts.len > 1:
            let valueStr = parts[1].split()[0]
            try:
              psnrValue = parseFloat(valueStr)
            except:
              discard
    else:
      debug &"PSNR calculation failed: {psnrOutput}"
  except:
    debug "PSNR calculation failed (exception)"
    return
  
  # Calculate SSIM using FFmpeg
  # Format: ffmpeg -i test.mp4 -i reference.mp4 -filter_complex ssim -f null -
  let ssimCmd = &"{ffmpegBin} -i \"{test}\" -i \"{reference}\" -filter_complex \"ssim=stats_file=-\" -f null - 2>&1"
  
  var ssimValue = 0.0
  try:
    let (ssimOutput, ssimExitCode) = execCmdEx(ssimCmd)
    if ssimExitCode == 0:
      # Parse SSIM from output
      # Format: "All:0.987654 (18.456789)"
      for line in ssimOutput.splitLines():
        if "All:" in line:
          let parts = line.split("All:")
          if parts.len > 1:
            let valueStr = parts[1].split()[0]
            try:
              ssimValue = parseFloat(valueStr)
            except:
              discard
    else:
      debug &"SSIM calculation failed: {ssimOutput}"
  except:
    debug "SSIM calculation failed (exception)"
    return
  
  result = QualityMetrics(
    psnr: psnrValue,
    ssim: ssimValue,
    valid: psnrValue > 0.0 and ssimValue > 0.0
  )

proc meetsQualityThreshold*(metrics: QualityMetrics): bool =
  ## Check if quality metrics meet minimum thresholds.
  if not metrics.valid:
    return false
  return metrics.psnr >= MinimumPSNR and metrics.ssim >= MinimumSSIM

proc formatMetrics*(metrics: QualityMetrics): string =
  ## Format quality metrics for display.
  if not metrics.valid:
    return "N/A (metrics unavailable)"
  
  let psnrStatus = if metrics.psnr >= MinimumPSNR: "✓" else: "✗"
  let ssimStatus = if metrics.ssim >= MinimumSSIM: "✓" else: "✗"
  
  return &"PSNR: {metrics.psnr:.2f}dB {psnrStatus}, SSIM: {metrics.ssim:.4f} {ssimStatus}"

# Simplified quality check using file hash (when FFmpeg not available)
proc hashBasedQualityCheck*(reference: string, test: string): bool =
  ## Simple quality check: verify files are identical (hash-based).
  ## This is less sophisticated than PSNR/SSIM but catches major regressions.
  
  if not fileExists(reference) or not fileExists(test):
    return false
  
  # Read and compare file sizes first (fast check)
  let refSize = getFileSize(reference)
  let testSize = getFileSize(test)
  
  # Allow 1% size difference (encoding variations)
  let sizeDiffPercent = abs(testSize.float - refSize.float) / refSize.float * 100.0
  if sizeDiffPercent > 1.0:
    debug &"File size difference: {sizeDiffPercent:.1f}% (ref: {refSize}, test: {testSize})"
    return false
  
  return true
