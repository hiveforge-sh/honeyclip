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
import ../src/cmds/transcript as transcriptCmd
import ../src/render/captions

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
  info.main(@["resources/testsrc.mp4"])

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

# Transcript command helper tests

test "transcript-countSpeakers":
  var transcript = newTranscript()

  # Test with speakers [0, 0, 1, 1, 2]
  var word1 = newWord("Hello", 0, 100, 0.9)
  word1.speaker = 0
  transcript.addWord(word1)

  var word2 = newWord("world", 100, 200, 0.9)
  word2.speaker = 0
  transcript.addWord(word2)

  var word3 = newWord("How", 200, 300, 0.9)
  word3.speaker = 1
  transcript.addWord(word3)

  var word4 = newWord("are", 300, 400, 0.9)
  word4.speaker = 1
  transcript.addWord(word4)

  var word5 = newWord("you", 400, 500, 0.9)
  word5.speaker = 2
  transcript.addWord(word5)

  check transcriptCmd.countSpeakers(transcript) == 3

test "transcript-countSpeakers-unassigned":
  var transcript = newTranscript()

  # Test with all -1 (unassigned)
  transcript.addWord(newWord("Hello", 0, 100, 0.9))
  transcript.addWord(newWord("world", 100, 200, 0.9))

  check transcriptCmd.countSpeakers(transcript) == 0

test "transcript-createBackup":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)

  let testFile = tempDir / "test.srt"
  let bakFile = testFile & ".bak"

  # Create initial file
  writeFile(testFile, "original content")
  check fileExists(testFile)
  check not fileExists(bakFile)

  # Create backup
  transcriptCmd.createBackup(testFile)
  check fileExists(bakFile)
  check not fileExists(testFile)
  check readFile(bakFile) == "original content"

  # Create new file
  writeFile(testFile, "new content")
  check fileExists(testFile)

  # Create backup again (should overwrite existing .bak)
  transcriptCmd.createBackup(testFile)
  check fileExists(bakFile)
  check readFile(bakFile) == "new content"

test "transcript-createBackup-nonexistent":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)

  let testFile = tempDir / "nonexistent.srt"

  # Should not throw when file doesn't exist
  transcriptCmd.createBackup(testFile)
  check not fileExists(testFile)
  check not fileExists(testFile & ".bak")

test "transcript-generateOutputPath":
  # Test with default output dir (same as input)
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "", ".srt") == "/path/to/video.srt"
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "", ".vtt") == "/path/to/video.vtt"
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "", ".json") == "/path/to/video.json"

  # Test with custom output dir
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "/other", ".srt") == "/other/video.srt"
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "/custom/dir", ".json") == "/custom/dir/video.json"

  # Test with different input formats
  check transcriptCmd.generateOutputPath("/videos/clip.mkv", "", ".srt") == "/videos/clip.srt"
  check transcriptCmd.generateOutputPath("/home/user/test.avi", "/out", ".vtt") == "/out/test.vtt"

# Caption Styling Tests

test "caption-formatASSTime":
  check formatASSTime(0) == "0:00:00.00"
  check formatASSTime(1234) == "0:00:01.23"
  check formatASSTime(3661234) == "1:01:01.23"
  check formatASSTime(500) == "0:00:00.50"
  check formatASSTime(12345) == "0:00:12.34"

test "caption-colorToASS":
  # White
  check colorToASS("#ffffff") == "&H00FFFFFF"
  # Red (note BGR order)
  check colorToASS("#ff0000") == "&H000000FF"
  # Green
  check colorToASS("#00ff00") == "&H0000FF00"
  # Blue
  check colorToASS("#0000ff") == "&H00FF0000"
  # Black
  check colorToASS("#000000") == "&H00000000"

test "caption-getSpeakerColor":
  # Valid speaker indices
  check getSpeakerColor(0) == "#00d4ff"  # Cyan
  check getSpeakerColor(1) == "#ff6b6b"  # Red/Pink
  check getSpeakerColor(2) == "#4ecb71"  # Green
  check getSpeakerColor(3) == "#ffe66d"  # Yellow
  check getSpeakerColor(4) == "#a29bfe"  # Purple

  # Invalid/unassigned speakers
  check getSpeakerColor(-1) == "#ffffff"  # Default white
  check getSpeakerColor(10) == "#ffffff"  # Out of range

test "caption-getPreset-traditional":
  let style = getPreset("traditional")
  check style.outline == true
  check style.outlineWidth == 4
  check style.fontSize == 60
  check style.position == cpBottomCenter
  check style.marginBottom == 150
  check style.color == "#ffffff"
  check style.backgroundBox == false

test "caption-getPreset-modern":
  let style = getPreset("modern")
  check style.backgroundBox == true
  check style.position == cpCenter
  check style.fontSize == 72
  check style.color == "#000000"
  check style.boxColor == "yellow@0.8"
  check style.boxPadding == 20
  check style.outline == false

test "caption-getPreset-tiktok":
  # "tiktok" is an alias for "modern"
  let style1 = getPreset("modern")
  let style2 = getPreset("tiktok")
  check style1.backgroundBox == style2.backgroundBox
  check style1.position == style2.position

test "caption-escapeASSText":
  check escapeASSText("hello world") == "hello world"
  check escapeASSText("hello {world}") == "hello \\{world\\}"
  check escapeASSText("line1\nline2") == "line1\\nline2"
  check escapeASSText("back\\slash") == "back\\\\slash"
  check escapeASSText("{test}\\n") == "\\{test\\}\\\\n"

test "caption-generateASSDialogue-simple":
  var transcript = newTranscript()
  transcript.addWord(newWord("Hello", 0, 500, 0.9))
  transcript.addWord(newWord("world", 500, 1000, 0.9))
  let captions = groupIntoCaptions(transcript)

  let style = getPreset("traditional")
  let dialogue = generateASSDialogue(captions[0], style)

  # Check that dialogue contains timing
  check dialogue.contains("0:00:00.00")
  check dialogue.contains("0:00:01.00")
  # Check text content
  check dialogue.contains("Hello world")

test "caption-generateASSDialogue-karaoke":
  var transcript = newTranscript()
  var word1 = newWord("Hello", 0, 500, 0.9)
  var word2 = newWord("world", 500, 1000, 0.9)
  transcript.addWord(word1)
  transcript.addWord(word2)

  let captions = groupIntoCaptions(transcript)

  var style = getPreset("traditional")
  style.highlightEnabled = true
  let dialogue = generateASSDialogue(captions[0], style)

  # Check for karaoke tags (\k)
  check dialogue.contains("\\k")
  # Check it contains both words
  check dialogue.contains("Hello")
  check dialogue.contains("world")

# Caption Filter Builder Tests

test "caption-escapeFilterPath":
  # Windows path with colon
  when defined(windows):
    check escapeFilterPath("C:/path/file.ass").contains("C\\:")
  # Unix path unchanged for slashes
  check escapeFilterPath("/usr/local/file.ass") == "/usr/local/file.ass"
  # Quotes escaped
  check escapeFilterPath("path with 'quotes'").contains("\\'")
  # Backslashes escaped
  check escapeFilterPath("path\\file").contains("\\\\")

test "caption-buildASSFilter":
  let filter = buildASSFilter("C:/temp/captions.ass")
  # Should start with ass=filename=
  check filter.startsWith("ass=filename='")
  # Should contain escaped path
  check filter.contains("\\:")

test "caption-escapeDrawtextText":
  check escapeDrawtextText("hello") == "hello"
  check escapeDrawtextText("it's") == "it\\'s"
  check escapeDrawtextText("a:b") == "a\\:b"
  check escapeDrawtextText("back\\slash") == "back\\\\slash"
  check escapeDrawtextText("multi\nline") == "multi\\nline"

test "caption-buildDrawtextFilter":
  var style = getPreset("traditional")
  style.fontPath = "/path/to/font.ttf"
  let filter = buildDrawtextFilter("Hello world", style, 0, 1000)

  # Should start with drawtext=
  check filter.startsWith("drawtext=")
  # Should contain font settings
  check filter.contains("fontfile=")
  check filter.contains("fontsize=60")
  check filter.contains("fontcolor=#ffffff")
  # Should contain timing
  check filter.contains("enable=")
  check filter.contains("between(t,")
  # Position varies by enum
  check filter.contains("y=h-150")  # cpBottomCenter with marginBottom=150

test "caption-buildDrawtextFilter-center":
  var style = getPreset("modern")
  style.fontPath = "/path/to/font.ttf"
  let filter = buildDrawtextFilter("Test", style, 500, 1500)

  # Center position
  check filter.contains("y=(h-text_h)/2")
  # Should have box settings
  check filter.contains("box=1")
  check filter.contains("boxcolor=")

test "caption-prepareCaptionFilter":
  var transcript = newTranscript()
  transcript.addWord(newWord("Hello", 0, 500, 0.9))
  transcript.addWord(newWord("world", 500, 1000, 0.9))
  let captions = groupIntoCaptions(transcript)

  var config = CaptionBurnConfig(
    style: getPreset("traditional"),
    width: 1920,
    height: 1080,
    useHighlight: false,
    tempDir: ""
  )

  let (filter, tempFile) = prepareCaptionFilter(captions, config)

  # Filter should be non-empty
  check filter.len > 0
  check filter.startsWith("ass=filename=")

  # Temp file should exist and end with .ass
  check tempFile.endsWith(".ass")
  check fileExists(tempFile)

  # Read and verify ASS content
  let content = readFile(tempFile)
  check content.contains("[Script Info]")
  check content.contains("[Events]")
  check content.contains("Hello world")

  # Cleanup
  cleanupCaptionTemp(tempFile)
  check not fileExists(tempFile)

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
