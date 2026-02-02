import std/[json, strutils, os]
import ../ffmpeg
import ../av
import ./types

proc extractTranscript*(inputPath: string, model: string, language: string = "", vadModel: string = ""): Transcript =
  ## Extract word-level transcript from audio using whisper.cpp
  ## Returns a Transcript object with word-level timestamps and confidence scores
  result = newTranscript()

  # Create temporary file for JSON output
  let tempDir = getTempDir()
  let outputFile = tempDir / "whisper_output_" & $getCurrentProcessId() & ".json"
  defer:
    if fileExists(outputFile):
      removeFile(outputFile)

  # Open input media
  let input = av.open(inputPath)
  defer: input.close()

  if input.audio.len == 0:
    raise newException(IOError, "No audio stream found")

  let audioStreamIndex = input.audio[0].index

  # Create filter graph for whisper processing
  let filterGraph = avfilter_graph_alloc()
  defer: avfilter_graph_free(addr filterGraph)

  # Create buffer source for audio input
  let abuffer = avfilter_get_by_name("abuffer")
  var bufferCtx: ptr AVFilterContext

  let audioStream = input.streams[audioStreamIndex]
  let sampleRate = audioStream.codecpar.sample_rate
  let channelLayout = audioStream.codecpar.ch_layout.u.mask
  let sampleFormat = cast[AVSampleFormat](audioStream.codecpar.format)

  # Get sample format name
  let sampleFmtName = av_get_sample_fmt_name(cint(sampleFormat))
  let bufferArgs = "sample_rate=" & $sampleRate & ":sample_fmt=" & $sampleFmtName & ":channel_layout=" & $channelLayout

  var ret = avfilter_graph_create_filter(addr bufferCtx, abuffer, "in", bufferArgs.cstring, nil, filterGraph)
  if ret < 0:
    raise newException(IOError, "Failed to create buffer source")

  # Create whisper filter
  let whisperFilter = avfilter_get_by_name("whisper")
  var whisperCtx: ptr AVFilterContext

  # Escape paths for filter arguments
  let escapedModel = model.replace("\\", "\\\\").replace(":", "\\:")
  let escapedOutput = outputFile.replace("\\", "\\\\").replace(":", "\\:")

  # Build whisper filter arguments
  var whisperArgs = "model=" & escapedModel & ":format=json:max_len=1:destination=" & escapedOutput

  if language != "":
    whisperArgs &= ":language=" & language

  if vadModel != "":
    let escapedVad = vadModel.replace("\\", "\\\\").replace(":", "\\:")
    whisperArgs &= ":vad_model=" & escapedVad

  ret = avfilter_graph_create_filter(addr whisperCtx, whisperFilter, "whisper", whisperArgs.cstring, nil, filterGraph)
  if ret < 0:
    raise newException(IOError, "Failed to create whisper filter")

  # Create buffer sink
  let abuffersink = avfilter_get_by_name("abuffersink")
  var sinkCtx: ptr AVFilterContext

  if avfilter_graph_create_filter(addr sinkCtx, abuffersink, "out", nil, nil, filterGraph) < 0:
    raise newException(IOError, "Failed to create buffer sink")

  # Link filters: buffer -> whisper -> sink
  if avfilter_link(bufferCtx, 0, whisperCtx, 0) < 0:
    raise newException(IOError, "Failed to link buffer to whisper")
  if avfilter_link(whisperCtx, 0, sinkCtx, 0) < 0:
    raise newException(IOError, "Failed to link whisper to sink")

  if avfilter_graph_config(filterGraph, nil) < 0:
    raise newException(IOError, "Failed to configure filter graph")

  # Set up decoder for the audio stream
  let decoderCtx = initDecoder(audioStream.codecpar)
  defer: avcodec_free_context(addr decoderCtx)

  let frame = av_frame_alloc()
  defer: av_frame_free(addr frame)

  let outputFrame = av_frame_alloc()
  defer: av_frame_free(addr outputFrame)

  # Process audio through filter graph
  for decodedFrame in input.decode(cint(audioStreamIndex), decoderCtx, frame):
    if av_buffersrc_write_frame(bufferCtx, decodedFrame) < 0:
      continue

    # Try to get output from whisper filter
    while av_buffersink_get_frame_flags(sinkCtx, outputFrame, 0) >= 0:
      av_frame_unref(outputFrame)

  # Flush the filter
  if av_buffersrc_write_frame(bufferCtx, nil) >= 0:
    while av_buffersink_get_frame_flags(sinkCtx, outputFrame, 0) >= 0:
      av_frame_unref(outputFrame)

  # Parse JSON output
  if not fileExists(outputFile):
    raise newException(IOError, "Whisper did not generate output file")

  let jsonContent = readFile(outputFile)
  let jsonData = parseJson(jsonContent)

  # Parse transcription from JSON
  if jsonData.hasKey("transcription"):
    let transcription = jsonData["transcription"]
    if transcription.kind == JArray:
      for segment in transcription:
        if not segment.hasKey("text") or not segment.hasKey("offsets"):
          continue

        let text = segment["text"].getStr().strip()
        if text.len == 0:
          continue

        let startMs = segment["offsets"]["from"].getInt()
        let endMs = segment["offsets"]["to"].getInt()

        # Get confidence from tokens if available
        var confidence = 0.5  # Default confidence
        if segment.hasKey("tokens") and segment["tokens"].kind == JArray and segment["tokens"].len > 0:
          let firstToken = segment["tokens"][0]
          if firstToken.hasKey("p"):
            confidence = firstToken["p"].getFloat()

        # Check if this is non-speech
        var word = newWord(text, startMs, endMs, confidence)

        # Detect non-speech markers
        if text.startsWith("[") and text.endsWith("]"):
          word.isNonSpeech = true
          let label = text[1 ..< text.len - 1].toLowerAscii()
          word.label = label

        result.addWord(word)

  # Set language if detected
  if jsonData.hasKey("language"):
    result.language = jsonData["language"].getStr()
