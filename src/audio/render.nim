## Final delivery of enhanced audio: mux into the source video (video stream
## copied) or write the cleaned WAV on its own.
import std/[osproc, os, strutils]
import ../analyze/audio_enhance

proc buildMuxCmd*(videoPath, enhancedAudioPath, outputPath: string): string =
  ## Pure command construction (testable). The enhanced WAV is re-encoded to
  ## AAC for MP4-family containers; other containers take FFmpeg's default.
  let ext = outputPath.splitFile.ext.toLowerAscii
  let audioCodec = if ext in [".mp4", ".m4v", ".mov", ".m4a"]: " -c:a aac -b:a 192k"
                   else: ""
  quoteShell(ffmpegBin()) & " -hide_banner -loglevel error -y -i " &
    quoteShell(videoPath) & " -i " & quoteShell(enhancedAudioPath) &
    " -c:v copy" & audioCodec & " -map 0:v -map 1:a " & quoteShell(outputPath)

proc muxEnhancedAudio*(videoPath, enhancedAudioPath, outputPath: string): bool =
  let (_, code) = execCmdEx(buildMuxCmd(videoPath, enhancedAudioPath, outputPath))
  code == 0 and fileExists(outputPath)

proc writeAudioOnly*(enhancedAudioPath, outputPath: string): bool =
  try:
    copyFile(enhancedAudioPath, outputPath)
    result = true
  except CatchableError:
    result = false
