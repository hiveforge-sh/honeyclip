import std/[strformat, streams, json]
import types, grouping

proc writeSafe(s: Stream, text: string) =
  ## Write text to stream (stdout or file)
  s.write(text)

proc openOutput(path: string): Stream =
  ## Open output stream (stdout or file)
  if path == "-":
    result = newFileStream(stdout)
  else:
    result = newFileStream(path, fmWrite)
    if result.isNil:
      raise newException(IOError, "Failed to open output file: " & path)

proc exportSRT*(captions: seq[Caption], outputPath: string, markLowConfidence: bool = true, confidenceThreshold: float = 0.5) =
  ## Export captions as SRT subtitle format
  ##
  ## Args:
  ##   captions: Sequence of caption objects to export
  ##   outputPath: Output file path (or "-" for stdout)
  ##   markLowConfidence: Mark low-confidence words with [?]
  ##   confidenceThreshold: Threshold for low confidence (default 0.5)

  let stream = openOutput(outputPath)
  defer: stream.close()

  for i, caption in captions:
    # Write index (1-based)
    stream.writeSafe(&"{i + 1}\n")

    # Write timestamp line (SRT uses comma)
    let startTime = formatTimestamp(caption.startMs, usePeriod = false)
    let endTime = formatTimestamp(caption.endMs, usePeriod = false)
    stream.writeSafe(&"{startTime} --> {endTime}\n")

    # Build text with optional speaker label and confidence markers
    var text = ""

    # Add speaker label if speaker changed
    if caption.speakerChanged and caption.speaker >= 0:
      text &= &"- Speaker {caption.speaker}: "

    # Build caption text with optional low-confidence markers
    for j, word in caption.words:
      if j > 0:
        text &= " "

      text &= word.text

      # Mark low confidence words
      if markLowConfidence and word.isLowConfidence(confidenceThreshold):
        text &= "[?]"

    stream.writeSafe(text & "\n")

    # Blank line separator
    stream.writeSafe("\n")

proc exportVTT*(captions: seq[Caption], outputPath: string, speakerColors: bool = false, markLowConfidence: bool = true, confidenceThreshold: float = 0.5) =
  ## Export captions as WebVTT subtitle format
  ##
  ## Args:
  ##   captions: Sequence of caption objects to export
  ##   outputPath: Output file path (or "-" for stdout)
  ##   speakerColors: Add color styling for speakers
  ##   markLowConfidence: Mark low-confidence words with [?]
  ##   confidenceThreshold: Threshold for low confidence (default 0.5)

  let stream = openOutput(outputPath)
  defer: stream.close()

  # Write WEBVTT header
  stream.writeSafe("WEBVTT\n")

  # Optional styling for speaker colors
  if speakerColors:
    stream.writeSafe("\n")
    stream.writeSafe("STYLE\n")
    stream.writeSafe("::cue(v[voice=\"Speaker0\"]) { color: #00d4ff; }\n")
    stream.writeSafe("::cue(v[voice=\"Speaker1\"]) { color: #ff6b6b; }\n")
    stream.writeSafe("::cue(v[voice=\"Speaker2\"]) { color: #4ecb71; }\n")
    stream.writeSafe("::cue(v[voice=\"Speaker3\"]) { color: #ffe66d; }\n")
    stream.writeSafe("::cue(v[voice=\"Speaker4\"]) { color: #a29bfe; }\n")

  stream.writeSafe("\n")

  for caption in captions:
    # Write timestamp line (VTT uses period)
    let startTime = formatTimestamp(caption.startMs, usePeriod = true)
    let endTime = formatTimestamp(caption.endMs, usePeriod = true)
    stream.writeSafe(&"{startTime} --> {endTime}\n")

    # Build text with optional speaker voice tag and confidence markers
    var text = ""

    # Add speaker voice tag if speaker changed
    if caption.speakerChanged and caption.speaker >= 0:
      text &= &"<v Speaker{caption.speaker}>"

    # Build caption text with optional low-confidence markers
    for j, word in caption.words:
      if j > 0:
        text &= " "

      text &= word.text

      # Mark low confidence words
      if markLowConfidence and word.isLowConfidence(confidenceThreshold):
        text &= "[?]"

    stream.writeSafe(text & "\n")

    # Blank line separator
    stream.writeSafe("\n")

proc exportJSON*(transcript: Transcript, captions: seq[Caption], outputPath: string, compact: bool = false) =
  ## Export transcript and captions as JSON
  ##
  ## Args:
  ##   transcript: Full transcript with word-level data
  ##   captions: Grouped captions
  ##   outputPath: Output file path (or "-" for stdout)
  ##   compact: Use compact JSON format (default false)

  # Build JSON structure
  var root = newJObject()
  root["language"] = %transcript.language
  root["duration_ms"] = %transcript.duration

  # Add words array
  var wordsArray = newJArray()
  for word in transcript.words:
    var wordObj = newJObject()
    wordObj["text"] = %word.text
    wordObj["start_ms"] = %word.startMs
    wordObj["end_ms"] = %word.endMs
    wordObj["confidence"] = %word.confidence
    wordObj["speaker"] = %word.speaker
    if word.isNonSpeech:
      wordObj["is_non_speech"] = %true
      wordObj["label"] = %word.label
    wordsArray.add(wordObj)
  root["words"] = wordsArray

  # Add captions array
  var captionsArray = newJArray()
  for caption in captions:
    var captionObj = newJObject()
    captionObj["text"] = %caption.text
    captionObj["start_ms"] = %caption.startMs
    captionObj["end_ms"] = %caption.endMs
    captionObj["speaker"] = %caption.speaker
    captionObj["speaker_changed"] = %caption.speakerChanged
    captionsArray.add(captionObj)
  root["captions"] = captionsArray

  # Write JSON output
  let stream = openOutput(outputPath)
  defer: stream.close()

  if compact:
    stream.writeSafe($root)
  else:
    stream.writeSafe(root.pretty())
  stream.writeSafe("\n")
