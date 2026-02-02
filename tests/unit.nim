import unittest
import std/[os, tempfiles, strutils]

import ../src/[av, edit, ffmpeg, timeline]
import ../src/util/[color, fun, lang]
import ../src/cmds/info
import ../src/media
import ../src/wavutil
import ../src/exports/[kdenlive, fcp11]
import ../src/transcript/types
import ../src/transcript/grouping
import ../src/transcript/formats

func `$`*(layout: AVChannelLayout): string =
  const bufSize: csize_t = 256
  var buffer = newString(bufSize)
  let ret = av_channel_layout_describe(layout.unsafeAddr, buffer.cstring, bufSize)

  if ret > 0:
    let actualLen = buffer.find('\0')
    if actualLen >= 0:
      result = buffer[0..<actualLen]
    else:
      result = buffer
  else:
    result = "unknown"

test "avrational":
  let a = AVRational(num: 3, den: 4)
  let b = AVRational(num: 3, den: 4)
  check a + b == AVRational(num: 3, den: 2)
  check a + a == a * 2

  let intThree: int64 = 3
  check intThree / AVRational(3) == AVRational(1)
  check intThree * AVRational(3) == AVRational(9)

  check AVRational(num: 9, den: 3).int64 == intThree
  check AVRational(num: 10, den: 3).int64 == intThree
  check AVRational(num: 11, den: 3).int64 == intThree
  check AVRational(num: 10, den: 5) != AVRational(num: 2, den: 1) # use compare

  check AVRational("42") == AVRational(42)
  check AVRational("-2/3") == AVRational(num: -2, den: 3)
  check AVRational("6/8") == AVRational(num: 3, den: 4)
  check AVRational("1.5") == AVRational(num: 3, den: 2)

test "color":
  check RGBColor(red: 0, green: 0, blue: 0).toString == "#000000"
  check RGBColor(red: 255, green: 255, blue: 255).toString == "#ffffff"

  check parseColor("#000") == RGBColor(red: 0, green: 0, blue: 0)
  check parseColor("#000000") == RGBColor(red: 0, green: 0, blue: 0)
  check parseColor("#FFF") == RGBColor(red: 255, green: 255, blue: 255)
  check parseColor("#fff") == RGBColor(red: 255, green: 255, blue: 255)
  check parseColor("#FFFFFF") == RGBColor(red: 255, green: 255, blue: 255)

  check parseColor("black") == RGBColor(red: 0, green: 0, blue: 0)
  check parseColor("darkgreen") == RGBColor(red: 0, green: 100, blue: 0)

test "dialogue":
  check "0,0,Default,,0,0,0,,oop".dialogue == "oop"
  check "0,0,Default,,0,0,0,,boop".dialogue == "boop"

test "encoder":
  let (_, encoderCtx) = initEncoder("pcm_s16le")
  check encoderCtx.codec_type == AVMEDIA_TYPE_AUDIO
  check encoderCtx.bit_rate != 0

  let (_, encoderCtx2) = initEncoder(AV_CODEC_ID_PCM_S16LE)
  check encoderCtx2.codec_type == AVMEDIA_TYPE_AUDIO
  check encoderCtx2.bit_rate != 0

test "exports":
  check(parseExportString("premiere:name=a,version=3") == ("premiere", "a", "3"))
  check(parseExportString("premiere:name=a") == ("premiere", "a", "11"))
  check(parseExportString("premiere:name=\"Hello \\\" World") == ("premiere",
      "Hello \" World", "11"))
  check(parseExportString("premiere:name=\"Hello \\\\ World") == ("premiere",
      "Hello \\ World", "11"))

test "info":
  main(@["resources/testsrc.mp4"])

test "margin":
  var levels: seq[bool]
  levels = @[false, false, true, false, false]
  mutMargin(levels, 0, 1)
  check(levels == @[false, false, true, true, false])

  levels = @[false, false, true, false, false]
  mutMargin(levels, 1, 0)
  check(levels == @[false, true, true, false, false])

  levels = @[false, false, true, false, false]
  mutMargin(levels, 1, 1)
  check(levels == @[false, true, true, true, false])

  levels = @[false, false, true, false, false]
  mutMargin(levels, 2, 2)
  check(levels == @[true, true, true, true, true])

  levels = @[false, true, true, true, false]
  mutMargin(levels, -1, -1)
  check(levels == @[false, false, true, false, false])

  levels = @[false, true, true, true, true, true, true, true, false]
  mutMargin(levels, 3, -4)
  check(levels == @[true, true, true, true, false, false, false, false, false])

test "mp3towav":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out2.wav"
  transcodeAudio("resources/mono.mp3", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check container.audio.len == 1
  check $container.audio[0].name == "pcm_s16le"
  check $container.audio[0].codecpar.ch_layout in ["mono", "1 channels"]

test "mp4towav":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out.wav"
  transcodeAudio("resources/testsrc.mp4", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check container.audio.len == 1
  check $container.audio[0].name == "pcm_s16le"

test "size-of-objects":
  check sizeof(seq) == 16
  check sizeof(ref seq) == 8
  check sizeof(string) == 16
  check sizeof(ref string) == 8
  check sizeof(AVCodecID) == 4
  check sizeof(AVPixelFormat) == 4
  check sizeof(AVRational) == 8
  check sizeof(VideoStream) == 96
  check sizeof(AudioStream) == 48
  check sizeof(SubtitleStream) == 16
  check sizeof(MediaInfo) == 96
  check sizeof(Clip) == 40

  check sizeof(RGBColor) == 3
  check sizeof(v3) == 144

test "lang-to-string":
  check sizeof(Lang) == 4
  var a: Lang = ['a', 's', 'd', 'f']
  check $a == "asdf"
  a  = ['e', 'n', 'g', '\0']
  check $a == "eng"

test "smpte":
  check parseSMPTE("13:44:05:21", AVRational(num: 24000, den: 1001)) == 1186701

test "uuid":
  # Test that genUuid generates valid RFC 4122 version 4 UUIDs
  for i in 1..3:
    let uuid = genUuid()

    # Check format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    check(uuid.len == 36)
    check(uuid[8] == '-')
    check(uuid[13] == '-')
    check(uuid[18] == '-')
    check(uuid[23] == '-')

    # Check version (should be 4)
    check(uuid[14] == '4')

    # Check variant bits (should be 8, 9, a, or b)
    check(uuid[19] in ['8', '9', 'a', 'b'])

    # Check all other characters are valid hex
    for j, c in uuid:
      if j notin [8, 13, 18, 23]: # Skip dashes
        check(c in "0123456789abcdef")

test "transcript-formatTimestamp":
  check formatTimestamp(0) == "00:00:00,000"
  check formatTimestamp(1234) == "00:00:01,234"
  check formatTimestamp(3661234) == "01:01:01,234"
  check formatTimestamp(1234, usePeriod=true) == "00:00:01.234"

test "transcript-isLowConfidence":
  let word1 = newWord("hello", 0, 1000, 0.3)
  let word2 = newWord("world", 1000, 2000, 0.7)
  let word3 = newWord("test", 2000, 3000, 0.4)

  # Test with default threshold (0.5)
  check isLowConfidence(word1) == true
  check isLowConfidence(word2) == false

  # Test with custom threshold (0.3)
  check isLowConfidence(word3, 0.3) == false
  check isLowConfidence(word1, 0.3) == false
  check isLowConfidence(word1, 0.4) == true

test "transcript-Word-construction":
  let word = newWord("hello", 100, 500, 0.95)
  check word.text == "hello"
  check word.startMs == 100
  check word.endMs == 500
  check word.confidence == 0.95
  check word.speaker == -1  # defaults to unassigned
  check word.isNonSpeech == false
  check word.label == ""

test "transcript-SRT-format":
  # Test SRT timestamp format uses comma
  let srtTimestamp = formatTimestamp(1234, usePeriod=false)
  check srtTimestamp == "00:00:01,234"
  check srtTimestamp.contains(",")
  check not srtTimestamp.contains(".")

  # Test SRT arrow format
  let startTime = formatTimestamp(0, usePeriod=false)
  let endTime = formatTimestamp(2500, usePeriod=false)
  check startTime == "00:00:00,000"
  check endTime == "00:00:02,500"

test "transcript-VTT-format":
  # Test VTT timestamp format uses period
  let vttTimestamp = formatTimestamp(1234, usePeriod=true)
  check vttTimestamp == "00:00:01.234"
  check vttTimestamp.contains(".")
  check not vttTimestamp.contains(",")

  # Test VTT header presence
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let vttFile = tempDir / "test.vtt"

  # Create minimal test data
  var transcript = newTranscript()
  transcript.addWord(newWord("Hello", 0, 500, 0.9))
  let captions = groupIntoCaptions(transcript)
  exportVTT(captions, vttFile)

  # Verify file starts with WEBVTT
  let content = readFile(vttFile)
  check content.startsWith("WEBVTT\n")

test "transcript-Caption-grouping":
  var transcript = newTranscript()

  # Create words that should split into multiple captions
  # "Hello world. How are you?" - should split at sentence boundary
  transcript.addWord(newWord("Hello", 0, 300, 0.9))
  transcript.addWord(newWord("world.", 300, 800, 0.9))
  transcript.addWord(newWord("How", 800, 1000, 0.9))
  transcript.addWord(newWord("are", 1000, 1200, 0.9))
  transcript.addWord(newWord("you?", 1200, 1500, 0.9))

  # Group with tight char limit to force split
  let captions = groupIntoCaptions(transcript, maxChars=15)

  # Should create at least 2 captions (split at sentence boundary)
  check captions.len >= 2

  # First caption should be sentence
  check captions[0].text.contains("Hello world.")
  check captions[0].words.len == 2

test "transcript-Caption-speaker-change":
  var transcript = newTranscript()

  # Create words with different speakers
  var word1 = newWord("Hello", 0, 500, 0.9)
  word1.speaker = 0
  transcript.addWord(word1)

  var word2 = newWord("world", 500, 1000, 0.9)
  word2.speaker = 0
  transcript.addWord(word2)

  var word3 = newWord("Goodbye", 1000, 1500, 0.9)
  word3.speaker = 1  # Speaker change
  transcript.addWord(word3)

  let captions = groupIntoCaptions(transcript)

  # Should create at least 2 captions due to speaker change
  check captions.len >= 2

  # Second caption should have speakerChanged = true
  check captions[1].speakerChanged == true
  check captions[1].speaker == 1

test "transcript-speaker-label-placement":
  var transcript = newTranscript()

  # Create caption with speaker 0
  var word1 = newWord("Hello", 0, 500, 0.9)
  word1.speaker = 0
  transcript.addWord(word1)

  var word2 = newWord("world", 500, 1000, 0.9)
  word2.speaker = 1  # Speaker change
  transcript.addWord(word2)

  let captions = groupIntoCaptions(transcript)
  check captions.len == 2

  # Test SRT format
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let srtFile = tempDir / "test.srt"
  exportSRT(captions, srtFile)

  let srtContent = readFile(srtFile)

  # First caption with speaker 0 should NOT have label (no previous speaker)
  # Second caption with speaker 1 should have label (speaker changed)
  check srtContent.contains("- Speaker 1:")

  # Test VTT format
  let vttFile = tempDir / "test.vtt"
  exportVTT(captions, vttFile)

  let vttContent = readFile(vttFile)
  check vttContent.contains("<v Speaker1>")

# ML FFI Wrapper Tests
# These tests verify FFI wrappers compile correctly
# Runtime tests require actual ML libraries

when defined(enable_ml):
  import ../src/ml/facedetect
  import ../src/ml/onnx
  import ../src/ml/opencv

  suite "ML FFI Wrappers":
    test "facedetect types exist":
      var rect: FaceRect
      check rect.x == 0
      check rect.y == 0
      check rect.width == 0
      check rect.height == 0
      check rect.confidence == 0.0

    test "onnx types exist":
      # Type existence check (not runtime test)
      type TestOrtEnv = OrtEnv
      type TestOrtSession = OrtSession
      type TestOrtValue = OrtValue
      check true

    test "opencv types exist":
      type TestMat = Mat
      type TestSize = Size
      check COLOR_BGR2RGB.int == 4
      check COLOR_RGB2GRAY.int == 7
