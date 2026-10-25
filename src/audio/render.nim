## Final delivery of enhanced audio: mux into the source video (video stream
## copied) or write the cleaned WAV on its own.
import std/[osproc, os, strutils, strformat]
import ../analyze/audio_enhance
import ../log

proc buildMuxCmd*(videoPath, enhancedAudioPath, outputPath: string;
                  audioTrack: int = 0; trackCount: int = 1;
                  keepExtra: bool = true): string =
  ## Pure command construction (testable). The enhanced WAV is re-encoded to
  ## AAC for MP4-family containers; other containers take FFmpeg's default.
  ## With several source audio tracks, the enhanced audio replaces track
  ## `audioTrack` (0-based) in place and the rest are stream-copied.
  ## Video is optional (`0:v?`) so audio-only containers mux too. With
  ## keepExtra, subtitle and attachment streams and chapters are copied
  ## through as well (WR-03).
  let ext = outputPath.splitFile.ext.toLowerAscii
  let mp4Family = ext in [".mp4", ".m4v", ".mov", ".m4a"]
  let head = quoteShell(ffmpegBin()) & " -hide_banner -loglevel error -y -i " &
    quoteShell(videoPath) & " -i " & quoteShell(enhancedAudioPath) & " -c:v copy"
  let extra = if keepExtra: " -map 0:s? -map 0:t? -c:s copy -c:t copy -map_chapters 0"
              else: " -map_chapters 0"
  if trackCount <= 1:
    let audioCodec = if mp4Family: " -c:a aac -b:a 192k" else: ""
    return head & audioCodec & " -map 0:v? -map 1:a" & extra & " " &
      quoteShell(outputPath)
  let t = audioTrack
  let encoder = if ext == ".webm": &"libopus -b:a:{t} 160k" else: &"aac -b:a:{t} 192k"
  var maps = " -map 0:v?"
  for i in 0 ..< trackCount:
    maps.add (if i == t: " -map 1:a:0" else: &" -map 0:a:{i}")
  head & maps & extra & &" -c:a copy -c:a:{t} {encoder} -map_metadata:s:a:{t} 0:s:a:{t} " &
    quoteShell(outputPath)

proc muxEnhancedAudio*(videoPath, enhancedAudioPath, outputPath: string;
                       audioTrack: int = 0; trackCount: int = 1): bool =
  ## Copies subtitles/attachments/chapters when the output container accepts
  ## them; if it does not (e.g. ASS subtitles into .mp4), retries without
  ## them and says so instead of dropping them silently.
  let (_, code) = execCmdEx(buildMuxCmd(videoPath, enhancedAudioPath, outputPath,
                                        audioTrack, trackCount))
  if code == 0 and fileExists(outputPath): return true
  let (_, code2) = execCmdEx(buildMuxCmd(videoPath, enhancedAudioPath, outputPath,
                                         audioTrack, trackCount, keepExtra = false))
  result = code2 == 0 and fileExists(outputPath)
  if result:
    warning "Subtitle/attachment streams of " & videoPath &
      " could not be copied into " & outputPath.splitFile.ext &
      " output; they were left out"

proc buildAudioOnlyCmd*(enhancedAudioPath, outputPath: string): string =
  ## Transcode the enhanced WAV into whatever format outputPath's extension
  ## names (FFmpeg picks the muxer and default encoder from it).
  quoteShell(ffmpegBin()) & " -hide_banner -loglevel error -y -i " &
    quoteShell(enhancedAudioPath) & " -vn " & quoteShell(outputPath)

proc writeAudioOnly*(enhancedAudioPath, outputPath: string): bool =
  ## A .wav output is a plain copy; anything else (.mp3, .m4a, .flac, ...)
  ## is transcoded so the bytes match the extension (WR-04). An extension
  ## FFmpeg cannot write fails instead of producing a mislabelled WAV.
  if outputPath.splitFile.ext.toLowerAscii == ".wav":
    try:
      copyFile(enhancedAudioPath, outputPath)
      return true
    except CatchableError:
      return false
  let (_, code) = execCmdEx(buildAudioOnlyCmd(enhancedAudioPath, outputPath))
  code == 0 and fileExists(outputPath)
