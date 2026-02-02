import unittest
import std/[os, tempfiles, strutils, xmltree, json]

import ../src/[av, edit, ffmpeg, timeline]
import ../src/util/[color, fun, lang]
import ../src/cmds/info
import ../src/media
import ../src/wavutil
import ../src/exports/[kdenlive, fcp11, fcp7]
import ../src/transcript/types
import ../src/transcript/grouping
import ../src/transcript/formats
import ../src/cmds/transcript as transcriptCmd
import ../src/cmds/caption as captionCmd
import ../src/cmds/engagement as engagementCmd
import ../src/render/captions
import ../src/analyze/engagement_types
import ../src/analyze/hooks
import ../src/analyze/clips
import ../src/exports/edl
import ../src/reframe/compositor
import ../src/reframe/crop
import ../src/tracking/types as trackingTypes

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
  check sizeof(timeline.Clip) == 40

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
  # Use transcript version explicitly (engagement also has formatTimestamp)
  check types.formatTimestamp(0) == "00:00:00,000"
  check types.formatTimestamp(1234) == "00:00:01,234"
  check types.formatTimestamp(3661234) == "01:01:01,234"
  check types.formatTimestamp(1234, usePeriod=true) == "00:00:01.234"

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

# NLE Caption Export Tests

test "nle-hexToFCP7Color":
  check hexToFCP7Color("#ffffff") == "1.0 1.0 1.0"
  check hexToFCP7Color("#ff0000") == "1.0 0.0 0.0"
  check hexToFCP7Color("#000000") == "0.0 0.0 0.0"
  check hexToFCP7Color("#00ff00") == "0.0 1.0 0.0"
  check hexToFCP7Color("#0000ff") == "0.0 0.0 1.0"

test "nle-hexToFCPXMLColor":
  check hexToFCPXMLColor("#ffffff") == "1 1 1 1"
  check hexToFCPXMLColor("#ff0000") == "1 0 0 1"
  check hexToFCPXMLColor("#000000") == "0 0 0 1"
  check hexToFCPXMLColor("#00ff00") == "0 1 0 1"

test "nle-addCaptionTrackFCP7":
  # Create sample captions
  var transcript = newTranscript()
  transcript.addWord(newWord("Hello", 0, 500, 0.9))
  transcript.addWord(newWord("world", 500, 1000, 0.9))
  let captions = groupIntoCaptions(transcript)

  # Create minimal XmlNode video element
  let video = newElement("video")

  # Add caption track
  let style = getPreset("traditional")
  addCaptionTrackFCP7(video, captions, style, 30, "FALSE")

  # Verify track element added
  check video.len > 0
  let track = video[0]
  check track.tag == "track"

  # Verify clipitem count matches caption count
  check track.len == captions.len

  # Verify each clipitem has Text effect
  for i in 0..<track.len:
    let clipitem = track[i]
    check clipitem.tag == "clipitem"
    # Look for effect element
    var hasEffect = false
    for child in clipitem:
      if child.tag == "effect":
        hasEffect = true
        # Check for Text effect name
        for effectChild in child:
          if effectChild.tag == "name" and effectChild.innerText == "Text":
            check true
    check hasEffect

test "nle-addCaptionTrackFCPXML":
  # Create sample captions
  var transcript = newTranscript()
  transcript.addWord(newWord("Test", 0, 500, 0.9))
  transcript.addWord(newWord("caption", 500, 1000, 0.9))
  let captions = groupIntoCaptions(transcript)

  # Create minimal XmlNode spine element
  let spine = newElement("spine")

  # Add caption track
  let style = getPreset("traditional")
  let tb = AVRational(num: 30000, den: 1001)
  addCaptionTrackFCPXML(spine, captions, style, tb)

  # Verify gap element added
  check spine.len > 0
  let gap = spine[0]
  check gap.tag == "gap"

  # Verify title elements added
  check gap.len == captions.len

  # Verify title count matches caption count
  for i in 0..<gap.len:
    let title = gap[i]
    check title.tag == "title"

test "nle-speaker-color-in-exports":
  # Create captions with different speakers
  var transcript = newTranscript()

  var word1 = newWord("Speaker", 0, 500, 0.9)
  word1.speaker = 0
  transcript.addWord(word1)

  var word2 = newWord("one", 500, 1000, 0.9)
  word2.speaker = 0
  transcript.addWord(word2)

  var word3 = newWord("Speaker", 1000, 1500, 0.9)
  word3.speaker = 1
  transcript.addWord(word3)

  var word4 = newWord("two", 1500, 2000, 0.9)
  word4.speaker = 1
  transcript.addWord(word4)

  let captions = groupIntoCaptions(transcript)

  # Verify we have at least 2 captions due to speaker change
  check captions.len >= 2
  check captions[0].speaker == 0
  check captions[1].speaker == 1

  # Test FCP7 export - verify color parameters vary by speaker
  let video = newElement("video")
  let style = getPreset("traditional")
  addCaptionTrackFCP7(video, captions, style, 30, "FALSE")

  check video.len > 0
  let track = video[0]
  check track.len >= 2

  # Extract color values from first two clips
  var color1 = ""
  var color2 = ""
  for child in track[0]:
    if child.tag == "effect":
      for param in child:
        if param.tag == "parameter":
          for paramChild in param:
            if paramChild.tag == "name" and paramChild.innerText == "Fill Color":
              # Find value sibling
              for valueChild in param:
                if valueChild.tag == "value":
                  color1 = valueChild.innerText

  for child in track[1]:
    if child.tag == "effect":
      for param in child:
        if param.tag == "parameter":
          for paramChild in param:
            if paramChild.tag == "name" and paramChild.innerText == "Fill Color":
              for valueChild in param:
                if valueChild.tag == "value":
                  color2 = valueChild.innerText

  # Colors should be different for different speakers
  check color1.len > 0
  check color2.len > 0
  check color1 != color2

# Caption Command Tests

test "caption-cmd-parseCaptionStyle-defaults":
  # Test default style (traditional preset)
  let style = captionCmd.parseCaptionStyle(@[])
  check style.fontSize == 60
  check style.color == "#ffffff"
  check style.position == cpBottomCenter
  check style.outline == true
  check style.highlightEnabled == false

test "caption-cmd-parseCaptionStyle-modern":
  # Test modern preset
  let style = captionCmd.parseCaptionStyle(@["--style", "modern"])
  check style.fontSize == 72
  check style.backgroundBox == true
  check style.position == cpCenter

test "caption-cmd-parseCaptionStyle-overrides":
  # Test CLI overrides
  let style = captionCmd.parseCaptionStyle(@[
    "--style", "traditional",
    "--fontsize", "80",
    "--color", "#ff0000",
    "--position", "center",
    "--highlight"
  ])
  check style.fontSize == 80
  check style.color == "#ff0000"
  check style.position == cpCenter
  check style.highlightEnabled == true

test "caption-cmd-parseCaptionStyle-outline":
  # Test outline flags
  let styleWithOutline = captionCmd.parseCaptionStyle(@["--outline"])
  check styleWithOutline.outline == true

  let styleNoOutline = captionCmd.parseCaptionStyle(@["--no-outline"])
  check styleNoOutline.outline == false

test "caption-cmd-parseCaptionStyle-position":
  # Test position variants
  let bottom = captionCmd.parseCaptionStyle(@["--position", "bottom"])
  check bottom.position == cpBottomCenter

  let center = captionCmd.parseCaptionStyle(@["--position", "center"])
  check center.position == cpCenter

  let top = captionCmd.parseCaptionStyle(@["--position", "top"])
  check top.position == cpTopCenter

test "caption-cmd-loadTranscriptFromJSON":
  # Create temp JSON transcript
  let tempFile = getTempDir() / "test_transcript.json"
  let jsonContent = """{
    "language": "en",
    "duration_ms": 5000,
    "words": [
      {
        "text": "Hello",
        "start_ms": 0,
        "end_ms": 500,
        "confidence": 0.9,
        "speaker": 0
      },
      {
        "text": "world",
        "start_ms": 500,
        "end_ms": 1000,
        "confidence": 0.95,
        "speaker": 0
      }
    ]
  }"""
  writeFile(tempFile, jsonContent)

  try:
    let transcript = captionCmd.loadTranscriptFromJSON(tempFile)
    check transcript.language == "en"
    check transcript.duration == 5000
    check transcript.words.len == 2
    check transcript.words[0].text == "Hello"
    check transcript.words[1].text == "world"
  finally:
    if fileExists(tempFile):
      removeFile(tempFile)

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

# Face Detection Tests
# These tests validate face detection consensus and filtering algorithms
# Import is conditional to avoid build failures when ML libs not available

when defined(enable_ml):
  import ../src/analyze/faces

  suite "Face Detection":
    test "IoU identical rectangles":
      let a = FaceDetection(x: 100, y: 100, width: 50, height: 50)
      let b = FaceDetection(x: 100, y: 100, width: 50, height: 50)
      check iou(a, b) == 1.0

    test "IoU no overlap":
      let a = FaceDetection(x: 0, y: 0, width: 50, height: 50)
      let b = FaceDetection(x: 100, y: 100, width: 50, height: 50)
      check iou(a, b) == 0.0

    test "IoU partial overlap":
      let a = FaceDetection(x: 0, y: 0, width: 100, height: 100)
      let b = FaceDetection(x: 50, y: 50, width: 100, height: 100)
      # Overlap is 50x50 = 2500
      # Union is 100*100 + 100*100 - 2500 = 17500
      # IoU = 2500/17500 = 0.1428...
      check abs(iou(a, b) - (2500.0 / 17500.0)) < 0.001

    test "FaceConsensus filters unstable faces":
      var consensus = newFaceConsensus(windowSize = 3, threshold = 0.6)

      # Add face appearing in 2/3 frames (66.7% >= 60% threshold, should be stable)
      consensus.addFrame(@[FaceDetection(x: 100, y: 100, width: 50, height: 50, frameIndex: 0)])
      consensus.addFrame(@[])  # No face in frame 2
      consensus.addFrame(@[FaceDetection(x: 100, y: 100, width: 50, height: 50, frameIndex: 2)])

      let stable = consensus.getStableFaces()
      # 2/3 = 0.667 >= 0.6, so face should be marked stable
      check stable.len == 1
      check stable[0].stable == true

    test "FaceConsensus keeps stable faces":
      var consensus = newFaceConsensus(windowSize = 3, threshold = 0.6)

      # Add face appearing in 3/3 frames (100% > threshold)
      let face = FaceDetection(x: 100, y: 100, width: 50, height: 50)
      consensus.addFrame(@[face])
      consensus.addFrame(@[face])
      consensus.addFrame(@[face])

      let stable = consensus.getStableFaces()
      check stable.len == 1
      check stable[0].stable == true

    test "FaceConsensus rejects truly unstable faces":
      var consensus = newFaceConsensus(windowSize = 3, threshold = 0.6)

      # Add face appearing in only 1/3 frames (33% < 60% threshold)
      consensus.addFrame(@[FaceDetection(x: 100, y: 100, width: 50, height: 50, frameIndex: 0)])
      consensus.addFrame(@[])  # No face in frame 2
      consensus.addFrame(@[])  # No face in frame 3

      let stable = consensus.getStableFaces()
      # 1/3 = 0.33 < 0.6, so face should be marked unstable
      check stable.len == 1
      check stable[0].stable == false

    test "filterBySize removes small faces":
      let faces = @[
        FaceDetection(x: 0, y: 0, width: 10, height: 10),  # Too small (10/480 = 2%)
        FaceDetection(x: 0, y: 0, width: 50, height: 50),  # OK (50/480 = 10%)
      ]
      let filtered = filterBySize(faces, frameHeight = 480, minRatio = 0.05)
      check filtered.len == 1
      check filtered[0].height == 50

    test "filterBySize keeps faces at exact threshold":
      let faces = @[
        FaceDetection(x: 0, y: 0, width: 24, height: 24),  # Exactly 5% of 480
      ]
      let filtered = filterBySize(faces, frameHeight = 480, minRatio = 0.05)
      check filtered.len == 1

    test "AdaptiveSampler spikes on scene change":
      var sampler = newAdaptiveSampler(baseFps = 1.0, maxFps = 5.0, sceneThreshold = 0.4)
      let fps = sampler.updateSamplingRate(sceneScore = 0.5, faceCount = 0, currentTime = 0.0)
      check fps == 5.0  # Spiked due to scene change

    test "AdaptiveSampler spikes on face state change":
      var sampler = newAdaptiveSampler(baseFps = 1.0, maxFps = 5.0, sceneThreshold = 0.4)
      # First update establishes baseline
      discard sampler.updateSamplingRate(sceneScore = 0.1, faceCount = 0, currentTime = 0.0)
      # Face count changes (0 -> 1), should spike
      let fps = sampler.updateSamplingRate(sceneScore = 0.1, faceCount = 1, currentTime = 0.5)
      check fps == 5.0

    test "AdaptiveSampler returns to baseline after cooldown":
      var sampler = newAdaptiveSampler(baseFps = 1.0, maxFps = 5.0, cooldown = 1.0)
      discard sampler.updateSamplingRate(sceneScore = 0.5, faceCount = 0, currentTime = 0.0)  # Spike
      let fps = sampler.updateSamplingRate(sceneScore = 0.1, faceCount = 0, currentTime = 2.0)  # After cooldown
      check fps == 1.0  # Back to baseline

    test "AdaptiveSampler maintains high rate during cooldown":
      var sampler = newAdaptiveSampler(baseFps = 1.0, maxFps = 5.0, cooldown = 1.0)
      discard sampler.updateSamplingRate(sceneScore = 0.5, faceCount = 0, currentTime = 0.0)  # Spike at t=0
      # Check rate during cooldown (t=0.5, before 1.0s cooldown expires)
      let fps = sampler.updateSamplingRate(sceneScore = 0.1, faceCount = 0, currentTime = 0.5)
      check fps == 5.0  # Still at high rate

# Face Embedding Tests
# These tests validate face embedding extraction and cosine similarity

when defined(enable_ml):
  import ../src/tracking/embeddings

  suite "Face Embeddings":
    test "cosineSimilarity identical vectors":
      let a = @[1.0f, 0.0f, 0.0f]
      let b = @[1.0f, 0.0f, 0.0f]
      check cosineSimilarity(a, b) == 1.0

    test "cosineSimilarity orthogonal vectors":
      let a = @[1.0f, 0.0f, 0.0f]
      let b = @[0.0f, 1.0f, 0.0f]
      check abs(cosineSimilarity(a, b) - 0.0) < 0.001

    test "cosineSimilarity opposite vectors":
      let a = @[1.0f, 0.0f, 0.0f]
      let b = @[-1.0f, 0.0f, 0.0f]
      check abs(cosineSimilarity(a, b) - (-1.0)) < 0.001

    test "cosineSimilarity range check":
      # Partially aligned vectors
      let a = @[1.0f, 1.0f, 0.0f]
      let b = @[1.0f, 0.0f, 0.0f]
      let sim = cosineSimilarity(a, b)
      # Should be in valid range [-1, 1]
      check sim >= -1.0 and sim <= 1.0
      # Should be positive (same general direction)
      check sim > 0.0

    test "cosineSimilarity empty vectors":
      let a: seq[float32] = @[]
      let b: seq[float32] = @[]
      check cosineSimilarity(a, b) == 0.0

    test "cosineSimilarity mismatched lengths":
      let a = @[1.0f, 0.0f]
      let b = @[1.0f, 0.0f, 0.0f]
      check cosineSimilarity(a, b) == 0.0

    test "preprocessFace output dimensions":
      # Create dummy image data (112x112 RGB)
      let imgSize = 112
      var imageData = newSeq[uint8](imgSize * imgSize * 3)
      # Initialize with test pattern
      for i in 0..<imageData.len:
        imageData[i] = uint8(i mod 256)

      # Preprocess entire image as face region
      let processed = preprocessFace(
        cast[ptr uint8](unsafeAddr imageData[0]),
        x = 0, y = 0, w = imgSize, h = imgSize,
        stride = imgSize * 3,
        imgW = imgSize, imgH = imgSize
      )

      # Output should be [1, 3, 112, 112] = 37632 floats
      check processed.len == 1 * 3 * 112 * 112
      check processed.len == 37632

    test "preprocessFace normalization range":
      # Create image with known values
      let imgSize = 112
      var imageData = newSeq[uint8](imgSize * imgSize * 3)
      # Fill with mid-gray (127) to test normalization
      for i in 0..<imageData.len:
        imageData[i] = 127

      let processed = preprocessFace(
        cast[ptr uint8](unsafeAddr imageData[0]),
        x = 0, y = 0, w = imgSize, h = imgSize,
        stride = imgSize * 3,
        imgW = imgSize, imgH = imgSize
      )

      # With value 127, normalization is (127 - 127.5) / 128.0 ≈ -0.004
      # All values should be approximately 0 (within floating point precision)
      var allNearZero = true
      for val in processed:
        if abs(val) > 0.01:
          allNearZero = false
          break
      check allNearZero

    test "preprocessFace invalid crop":
      # Test with invalid bounding box (outside image)
      let imgSize = 112
      var imageData = newSeq[uint8](imgSize * imgSize * 3)

      let processed = preprocessFace(
        cast[ptr uint8](unsafeAddr imageData[0]),
        x = 200, y = 200, w = 50, h = 50,  # Outside image bounds
        stride = imgSize * 3,
        imgW = imgSize, imgH = imgSize
      )

      # Should return zeros for invalid crop
      check processed.len == 37632
      var allZero = true
      for val in processed:
        if val != 0.0f:
          allZero = false
          break
      check allZero

# Engagement Types Tests

suite "Engagement Types":
  test "default params has equal weights":
    let params = defaultEngagementParams()
    check abs(params.audioWeight - 0.333f) < 0.01
    check abs(params.motionWeight - 0.333f) < 0.01
    check abs(params.speechWeight - 0.333f) < 0.01
    check params.hookBoost == 15.0f
    check params.minSegmentDurationMs == 2000

  test "percentile normalization basic":
    let signal = @[0.0f, 25.0f, 50.0f, 75.0f, 100.0f]
    let normalized = normalizePercentile(signal, 0.0, 1.0)
    # With 0% and 100% percentiles, should map 0->0, 100->100
    check normalized[0] == 0.0f
    check normalized[4] == 100.0f

  test "percentile normalization outliers":
    let signal = @[0.0f, 10.0f, 10.0f, 10.0f, 10.0f, 10.0f, 10.0f, 10.0f, 10.0f, 100.0f]
    # 5th percentile ~ 10, 95th percentile ~ 10
    let normalized = normalizePercentile(signal)
    # Outliers (0 and 100) should be clamped
    check normalized[0] >= 0.0f
    check normalized[9] <= 100.0f

  test "percentile normalization empty":
    let signal: seq[float32] = @[]
    let normalized = normalizePercentile(signal)
    check normalized.len == 0

  test "percentile normalization single value":
    let signal = @[42.0f]
    let normalized = normalizePercentile(signal)
    check normalized.len == 1
    check normalized[0] == 50.0f

  test "percentile normalization all same":
    let signal = @[5.0f, 5.0f, 5.0f, 5.0f]
    let normalized = normalizePercentile(signal)
    check normalized.len == 4
    # All same values should map to 50.0
    for val in normalized:
      check val == 50.0f

  test "segment duration calculation":
    var seg = newEngagementSegment(1000, 3500)
    check seg.durationMs == 2500

  test "segment isEmpty":
    var seg = newEngagementSegment(0, 1000)
    check seg.isEmpty() == true
    seg.text = "Hello"
    check seg.isEmpty() == false

  test "computePercentileBounds basic":
    let signal = @[0.0f, 10.0f, 20.0f, 30.0f, 40.0f, 50.0f, 60.0f, 70.0f, 80.0f, 90.0f, 100.0f]
    let bounds = computePercentileBounds(signal, 0.1, 0.9)
    # 10th percentile (index 1) = 10.0, 90th percentile (index 9) = 90.0
    check abs(bounds.low - 10.0f) < 1.0f
    check abs(bounds.high - 90.0f) < 1.0f

  test "normalizeValue clamps correctly":
    # Value below range should clamp to 0
    check normalizeValue(5.0f, 10.0f, 20.0f) == 0.0f
    # Value above range should clamp to 100
    check normalizeValue(25.0f, 10.0f, 20.0f) == 100.0f
    # Value in middle should be 50
    check normalizeValue(15.0f, 10.0f, 20.0f) == 50.0f

# Hook Detection Tests

suite "Hook Detection":
  test "question opening detected":
    let patterns = loadBuiltinPatterns()
    let matches = matchTextPatterns("What makes this special?", patterns)
    check matches.len > 0
    check "question_opening" in matches

  test "mid-sentence what not detected as question":
    let patterns = loadBuiltinPatterns()
    let matches = matchTextPatterns("I know what you mean", patterns)
    # "what" in middle of sentence should not match ^what pattern
    check not ("question_opening" in matches)

  test "emphasis word detected":
    let patterns = loadBuiltinPatterns()
    let matches = matchTextPatterns("You must see this", patterns)
    check matches.len > 0
    check "emphasis_words" in matches

  test "combined detection requires prosody":
    let patterns = loadBuiltinPatterns()
    # Text pattern matches but no prosody
    var flatAudio = newSeq[float32](10)
    for i in 0..<10: flatAudio[i] = 0.3f
    let result = detectHook("What is this?", flatAudio, 0.3f, patterns)
    check result.textMatches.len > 0
    check not result.hasProsodyIndicator
    check not result.isHook  # Requires BOTH

  test "combined detection with volume spike":
    let patterns = loadBuiltinPatterns()
    # Text pattern matches AND volume spike
    let audioWithSpike = @[0.1f, 0.2f, 0.8f, 0.3f, 0.1f]  # spike > 1.5x avg
    let result = detectHook("What is this?", audioWithSpike, 0.3f, patterns)
    check result.textMatches.len > 0
    check result.hasProsodyIndicator
    check result.isHook  # Has BOTH

  test "combined detection with pause":
    let patterns = loadBuiltinPatterns()
    # Text pattern matches AND pause at start
    let audioWithPause = @[0.01f, 0.01f, 0.01f, 0.3f, 0.3f]  # silence then normal
    let result = detectHook("What is this?", audioWithPause, 0.3f, patterns)
    check result.textMatches.len > 0
    check result.hasProsodyIndicator
    check result.isHook  # Has BOTH

  test "rate limiting keeps max 3 per minute":
    var hooks: seq[tuple[timestampMs: int64, result: HookResult]] = @[]
    for i in 0..<5:
      hooks.add((int64(i * 10000), HookResult(isHook: true, confidence: 0.8f)))
    let limited = rateLimitHooks(hooks, maxPerMinute = 3)
    check limited.len == 3

  test "rate limiting across multiple minutes":
    var hooks: seq[tuple[timestampMs: int64, result: HookResult]] = @[]
    # Add 5 hooks in first minute
    for i in 0..<5:
      hooks.add((int64(i * 10000), HookResult(isHook: true, confidence: 0.5f)))
    # Add 5 hooks in second minute
    for i in 0..<5:
      hooks.add((int64(60000 + i * 10000), HookResult(isHook: true, confidence: 0.6f)))
    let limited = rateLimitHooks(hooks, maxPerMinute = 3)
    # Should get 3 from first minute + 3 from second = 6
    check limited.len == 6

  test "rate limiting preserves highest confidence":
    var hooks: seq[tuple[timestampMs: int64, result: HookResult]] = @[]
    # Add hooks with varying confidence
    hooks.add((int64(0), HookResult(isHook: true, confidence: 0.5f)))
    hooks.add((int64(10000), HookResult(isHook: true, confidence: 0.9f)))  # Highest
    hooks.add((int64(20000), HookResult(isHook: true, confidence: 0.7f)))
    hooks.add((int64(30000), HookResult(isHook: true, confidence: 0.6f)))
    let limited = rateLimitHooks(hooks, maxPerMinute = 2)
    check limited.len == 2
    # Should include timestamp 10000 (highest confidence)
    check int64(10000) in limited

# Engagement CLI Tests

suite "Engagement CLI":
  test "timelineToJson produces valid JSON":
    var timeline = EngagementTimeline(
      segments: @[],
      duration: 5000,
      avgScore: 50.0f,
      hookCount: 0,
      params: defaultEngagementParams()
    )
    let jsonStr = engagementCmd.timelineToJson(timeline)
    let parsed = parseJson(jsonStr)
    check parsed["duration_ms"].getInt() == 5000
    check parsed["avg_score"].getFloat() > 0.0

  test "timelineToJson includes segment fields":
    var seg = newEngagementSegment(0, 2500)
    seg.text = "Test segment"
    seg.score = 75.5f
    seg.scoreRelative = 80.0f
    seg.scoreAbsolute = 72.0f
    seg.audioScore = 65.0f
    seg.motionScore = 45.0f
    seg.speechScore = 82.0f
    seg.hasHook = true
    seg.faceCount = 1
    seg.speaker = 0

    var timeline = EngagementTimeline(
      segments: @[seg],
      duration: 5000,
      avgScore: 75.5f,
      hookCount: 1,
      params: defaultEngagementParams()
    )
    let jsonStr = engagementCmd.timelineToJson(timeline)
    let parsed = parseJson(jsonStr)

    check parsed["segments"].len == 1
    let segJson = parsed["segments"][0]
    check segJson["start_ms"].getInt() == 0
    check segJson["end_ms"].getInt() == 2500
    check segJson["text"].getStr() == "Test segment"
    check segJson["score"].getFloat() > 75.0
    check segJson["has_hook"].getBool() == true
    check segJson["face_count"].getInt() == 1
    check segJson["speaker"].getInt() == 0

  test "timelineToJson compact mode":
    var timeline = EngagementTimeline(
      segments: @[],
      duration: 1000,
      avgScore: 50.0f,
      hookCount: 0,
      params: defaultEngagementParams()
    )
    let compactJson = engagementCmd.timelineToJson(timeline, compact = true)
    let prettyJson = engagementCmd.timelineToJson(timeline, compact = false)

    # Compact should have no newlines
    check not compactJson.contains("\n")
    # Pretty should have newlines
    check prettyJson.contains("\n")

  test "engagement types export correctly":
    # Verify we can construct and use engagement types
    var seg = newEngagementSegment(0, 2500)
    seg.score = 75.5f
    seg.hasHook = true
    check seg.score > 0
    check seg.hasHook == true
    check seg.durationMs() == 2500

  test "generateOutputPath for engagement":
    check engagementCmd.generateOutputPath("/path/to/video.mp4", "", ".engage.json") == "/path/to/video.engage.json"
    check engagementCmd.generateOutputPath("/path/to/video.mp4", "/out", ".engage.json") == "/out/video.engage.json"

suite "clips module":
  test "calculateIoU no overlap":
    var clipA = clips.Clip(startMs: 0, endMs: 10000)
    var clipB = clips.Clip(startMs: 20000, endMs: 30000)
    check calculateIoU(clipA, clipB) == 0.0f

  test "calculateIoU full overlap":
    var clipA = clips.Clip(startMs: 0, endMs: 10000)
    var clipB = clips.Clip(startMs: 0, endMs: 10000)
    check calculateIoU(clipA, clipB) == 1.0f

  test "calculateIoU partial overlap":
    var clipA = clips.Clip(startMs: 0, endMs: 10000)
    var clipB = clips.Clip(startMs: 5000, endMs: 15000)
    # Intersection: 5000-10000 = 5000ms
    # Union: 0-15000 = 15000ms
    # IoU = 5000/15000 = 0.333...
    let iou = calculateIoU(clipA, clipB)
    check iou > 0.33f and iou < 0.34f

  test "formatTimecode zero":
    check formatTimecode(0) == "00:00:00:00"

  test "formatTimecode one minute":
    check formatTimecode(60000) == "00:01:00:00"

  test "formatTimecode complex":
    # 1 hour, 23 minutes, 45 seconds, 15 frames at 30fps
    # = 3600 + 23*60 + 45 seconds = 5025 seconds
    # 5025 seconds * 1000 + 500ms (15 frames at 30fps)
    let ms = int64(5025 * 1000 + 500)
    let tc = formatTimecode(ms, 30.0)
    check tc == "01:23:45:15"

  test "parseTimecode roundtrip":
    let original: int64 = 12345678  # ~3.4 hours
    let tc = formatTimecode(original)
    let parsed = parseTimecode(tc)
    # Allow 1 frame tolerance (33ms at 30fps)
    check abs(parsed - original) < 34

  test "mergeNearbyBoundaries":
    var boundaries = @[
      ClipBoundary(timestampMs: 1000, reason: SceneChange),
      ClipBoundary(timestampMs: 1500, reason: EngagementDrop),  # Within 2000ms window
      ClipBoundary(timestampMs: 5000, reason: SpeechBoundary)
    ]
    let merged = mergeNearbyBoundaries(boundaries, 2000)
    check merged.len == 2
    check merged[0].reason == SceneChange  # SceneChange preferred
    check merged[1].timestampMs == 5000

  test "rankClips overlap penalty":
    var testClips = @[
      clips.Clip(startMs: 0, endMs: 30000, engagementScore: 90.0f),
      clips.Clip(startMs: 10000, endMs: 40000, engagementScore: 85.0f),  # Overlaps with first
      clips.Clip(startMs: 50000, endMs: 80000, engagementScore: 80.0f)   # No overlap
    ]
    var params = defaultClipRankingParams()
    params.topN = 3
    let ranked = rankClips(testClips, params)

    # First clip should be rank 1 (highest score)
    check ranked[0].rank == 1
    check ranked[0].engagementScore == 90.0f

    # Third clip (no overlap) should rank higher than second (overlapping)
    # due to overlap penalty
    check ranked[1].engagementScore == 80.0f or ranked[2].engagementScore == 80.0f

# Reframe Compositor Tests

suite "Reframe Compositor":
  test "newCompositor defaults":
    let comp = newCompositor()
    check comp.easing == Slow
    check comp.targetAspect == Portrait
    check comp.keyframes.len == 0
    check comp.fallbackFrameCount == 0
    check comp.totalFrameCount == 0

  test "addKeyframe tracks fallback":
    var comp = newCompositor()
    let crop1 = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)
    let crop2 = CropRegion(x: 200, y: 100, width: 607, height: 1080, timestamp: 1.0)

    comp.addKeyframe(0.0, crop1, trackId = 0)  # Tracked frame
    comp.addKeyframe(1.0, crop2, trackId = -1)  # Fallback frame

    check comp.totalFrameCount == 2
    check comp.fallbackFrameCount == 1
    check comp.keyframes.len == 2

  test "getFallbackPercentage calculation":
    var comp = newCompositor()
    let crop = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)

    # Add 7 tracked frames and 3 fallback frames
    for i in 0..<7:
      comp.addKeyframe(i.float, crop, trackId = 0)
    for i in 7..<10:
      comp.addKeyframe(i.float, crop, trackId = -1)

    let percentage = comp.getFallbackPercentage()
    # 3/10 = 30%
    check abs(percentage - 30.0) < 0.1

  test "getFallbackPercentage empty":
    let comp = newCompositor()
    check comp.getFallbackPercentage() == 0.0

  test "getCropAtTime single keyframe":
    var comp = newCompositor()
    let crop = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)
    comp.addKeyframe(0.0, crop, trackId = 0)

    # Query at any time should return same crop
    let result1 = comp.getCropAtTime(0.5)
    let result2 = comp.getCropAtTime(2.0)
    check result1.x == 100
    check result2.x == 100

  test "getCropAtTime interpolation":
    var comp = newCompositor()
    let crop1 = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)
    let crop2 = CropRegion(x: 200, y: 200, width: 607, height: 1080, timestamp: 2.0)

    comp.addKeyframe(0.0, crop1, trackId = 0)
    comp.addKeyframe(2.0, crop2, trackId = 0)

    # Query at midpoint (t=1.0)
    let result = comp.getCropAtTime(1.0)

    # With easing, interpolation is not linear
    # But should be between start and end values
    check result.x >= 100 and result.x <= 200
    check result.y >= 100 and result.y <= 200
    # Should NOT be exact midpoint due to easing
    check result.x != 150

  test "getCropAtTime before first keyframe":
    var comp = newCompositor()
    let crop = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 1.0)
    comp.addKeyframe(1.0, crop, trackId = 0)

    # Query before first keyframe returns first keyframe
    let result = comp.getCropAtTime(0.0)
    check result.x == 100

  test "getCropAtTime after last keyframe":
    var comp = newCompositor()
    let crop = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 1.0)
    comp.addKeyframe(1.0, crop, trackId = 0)

    # Query after last keyframe returns last keyframe
    let result = comp.getCropAtTime(5.0)
    check result.x == 100

  test "generateCropFilter single keyframe":
    var comp = newCompositor()
    let crop = CropRegion(x: 100, y: 50, width: 607, height: 1080, timestamp: 0.0)
    comp.addKeyframe(0.0, crop, trackId = 0)

    let filter = comp.generateCropFilter()
    # Should be static crop without enable expression
    check filter.contains("crop=w=607")
    check filter.contains("h=1080")
    check filter.contains("x=100")
    check filter.contains("y=50")
    check not filter.contains("enable=")

  test "generateCropFilter multiple keyframes":
    var comp = newCompositor()
    let crop1 = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)
    let crop2 = CropRegion(x: 200, y: 200, width: 607, height: 1080, timestamp: 1.0)

    comp.addKeyframe(0.0, crop1, trackId = 0)
    comp.addKeyframe(1.0, crop2, trackId = 0)

    let filter = comp.generateCropFilter()

    # Should contain multiple crop expressions with enable
    check filter.contains("crop=")
    check filter.contains("enable='between(t,")
    # Should have multiple segments (comma-separated)
    check filter.count("crop=") > 1

  test "generateCropFilter time ranges":
    var comp = newCompositor()
    let crop1 = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)
    let crop2 = CropRegion(x: 200, y: 200, width: 607, height: 1080, timestamp: 2.0)

    comp.addKeyframe(0.0, crop1, trackId = 0)
    comp.addKeyframe(2.0, crop2, trackId = 0)

    let filter = comp.generateCropFilter()

    # Should contain time range starting at 0.0
    check filter.contains("between(t,0.000,")
    # Filter string should reference the duration
    check filter.len > 0

  test "generateCropFilter empty":
    let comp = newCompositor()
    let filter = comp.generateCropFilter()
    # No keyframes should produce empty filter
    check filter.len == 0

  test "renderReframe generates valid filter":
    var comp = newCompositor()
    let crop1 = CropRegion(x: 100, y: 100, width: 607, height: 1080, timestamp: 0.0)
    let crop2 = CropRegion(x: 200, y: 200, width: 607, height: 1080, timestamp: 1.0)

    comp.addKeyframe(0.0, crop1, trackId = 0)
    comp.addKeyframe(1.0, crop2, trackId = 0)

    # Test that renderReframe succeeds with valid compositor
    let success = renderReframe("input.mp4", "output.mp4", comp, 607, 1080)
    check success == true

  test "renderReframe fails with no keyframes":
    let comp = newCompositor()
    let success = renderReframe("input.mp4", "output.mp4", comp, 607, 1080)
    check success == false
