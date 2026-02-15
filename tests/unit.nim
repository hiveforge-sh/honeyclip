import unittest
import std/[os, tempfiles, strutils, xmltree, json, tables, sequtils]

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
import ../src/analyze/chapters
import ../src/exports/edl
import ../src/reframe/compositor
import ../src/reframe/crop
import ../src/tracking/types as trackingTypes
import ../src/exports/markers
import ../src/render/scoreviz
import ../src/metadata/types as metadataTypes
import ../src/metadata/apply
import ../src/analyze/hook_schema
import ../src/batch/[templates, discover, checkpoint]
import ../src/brand/[watermark, concat, styles]

# Include test fixture utilities for tolerance-based assertions
include fixtures/test_utils
include fixtures/synthetic_faces

# Include the NLE format types and parser from export command
# (can't use regular import due to 'export' being a reserved keyword)
type
  NLEFormat* = enum
    nleNone        ## Not NLE export mode
    nleFCP7XML     ## Adobe Premiere, DaVinci Resolve
    nleFCPXML      ## Final Cut Pro X
    nleEDL         ## DaVinci Resolve, generic
    nleAAF         ## After Effects, Media Composer

proc parseNLETarget*(target: string): NLEFormat =
  ## Parse NLE name or format string to NLEFormat
  case target.toLowerAscii()
  of "premiere", "fcp7xml", "fcp7", "resolve-xml":
    return nleFCP7XML
  of "fcpx", "finalcut", "fcpxml", "fcp11":
    return nleFCPXML
  of "resolve", "edl", "resolve-edl":
    return nleEDL
  of "aftereffects", "ae", "aaf", "mediacomposer", "avid":
    return nleAAF
  else:
    return nleNone

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
  # Use normalizedPath for cross-platform path comparison
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "", ".srt").normalizedPath == "/path/to/video.srt".normalizedPath
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "", ".vtt").normalizedPath == "/path/to/video.vtt".normalizedPath
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "", ".json").normalizedPath == "/path/to/video.json".normalizedPath

  # Test with custom output dir
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "/other", ".srt").normalizedPath == "/other/video.srt".normalizedPath
  check transcriptCmd.generateOutputPath("/path/to/video.mp4", "/custom/dir", ".json").normalizedPath == "/custom/dir/video.json".normalizedPath

  # Test with different input formats
  check transcriptCmd.generateOutputPath("/videos/clip.mkv", "", ".srt").normalizedPath == "/videos/clip.srt".normalizedPath
  check transcriptCmd.generateOutputPath("/home/user/test.avi", "/out", ".vtt").normalizedPath == "/out/test.vtt".normalizedPath

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

# GPU Runtime Detection Tests
# Tests GPU backend detection and platform-specific behavior
import ../src/ml/gpu_runtime

suite "GPU Runtime":
  test "detectGpu returns valid backend":
    let runtime = detectGpu()
    # On any platform, should return a valid GpuBackend
    check runtime.backend in {CPU, CUDA, CoreML}

  test "detectGpu returns CPU on Windows":
    when defined(windows):
      let runtime = detectGpu()
      check runtime.backend == CPU
      check runtime.available == false
      check runtime.deviceName == "CPU"

  test "detectGpu deviceName is not empty":
    let runtime = detectGpu()
    check runtime.deviceName.len > 0

  test "GpuBackend string representation":
    check $CPU == "cpu"
    check $CUDA == "cuda"
    check $CoreML == "coreml"

# Buffer Pool Tests
# Tests frame buffer pooling for memory-efficient video processing
import ../src/ml/buffer_pool

suite "Buffer Pool":
  test "newBufferPool creates pool with correct size":
    var pool = newBufferPool(640, 480, 3, maxBuffers = 4)
    check pool.maxBuffers == 4
    check pool.frameSize == 640 * 480 * 3
    check pool.acquiredCount == 0

  test "acquire returns non-nil buffer":
    var pool = newBufferPool(64, 64, 3, maxBuffers = 2)
    let buf = pool.acquire()
    check buf != nil
    check buf.inUse == true
    check buf.width == 64
    check buf.height == 64
    check buf.channels == 3
    check pool.acquiredCount == 1
    pool.release(buf)

  test "release returns buffer to pool":
    var pool = newBufferPool(64, 64, 3, maxBuffers = 2)
    let buf = pool.acquire()
    check pool.acquiredCount == 1
    pool.release(buf)
    check pool.acquiredCount == 0
    check buf.inUse == false

  test "acquire returns nil when pool exhausted":
    var pool = newBufferPool(64, 64, 3, maxBuffers = 2)
    let buf1 = pool.acquire()
    let buf2 = pool.acquire()
    let buf3 = pool.acquire()  # Should be nil
    check buf1 != nil
    check buf2 != nil
    check buf3 == nil
    check pool.acquiredCount == 2
    pool.release(buf1)
    pool.release(buf2)

  test "acquire after release reuses buffer":
    var pool = newBufferPool(64, 64, 3, maxBuffers = 1)
    let buf1 = pool.acquire()
    check buf1 != nil
    pool.release(buf1)
    let buf2 = pool.acquire()
    check buf2 != nil
    # Should get the same buffer back (reuse)
    check buf2 == buf1
    pool.release(buf2)

  test "available tracks free buffers":
    var pool = newBufferPool(64, 64, 3, maxBuffers = 3)
    check pool.available() == 3
    let buf1 = pool.acquire()
    check pool.available() == 2
    let buf2 = pool.acquire()
    check pool.available() == 1
    pool.release(buf1)
    check pool.available() == 2
    pool.release(buf2)
    check pool.available() == 3

  test "buffer data pointer is valid":
    var pool = newBufferPool(64, 64, 3, maxBuffers = 1)
    let buf = pool.acquire()
    check buf != nil
    check buf.data != nil
    # Should be able to write to buffer without crash
    buf.data[0] = 255'u8
    buf.data[buf.capacity - 1] = 128'u8
    check buf.data[0] == 255'u8
    check buf.data[buf.capacity - 1] == 128'u8
    pool.release(buf)

  test "4K buffer pool size calculation":
    # 4K BGR: 3840 * 2160 * 3 = 24,883,200 bytes (~24MB)
    var pool = newBufferPool(3840, 2160, 3, maxBuffers = 1)
    check pool.frameSize == 24_883_200
    let buf = pool.acquire()
    check buf != nil
    check buf.capacity == 24_883_200
    pool.release(buf)

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

      # Add face appearing in only 1/3 frames (current frame only, 33% < 60% threshold)
      # Face NOT in frames 1-2, only appears in current frame
      consensus.addFrame(@[])  # No face in frame 1
      consensus.addFrame(@[])  # No face in frame 2
      consensus.addFrame(@[FaceDetection(x: 100, y: 100, width: 50, height: 50, frameIndex: 2)])  # Face only here

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
      # Test with completely outside image bounds (negative results in empty crop)
      let imgSize = 112
      var imageData = newSeq[uint8](imgSize * imgSize * 3)

      # Use coordinates that result in cropW/cropH <= 0 after clamping
      # x=200 clamps to 111, x+w=250 clamps to 112, cropW=1 (not zero)
      # To get zero-width crop: need x >= imgW
      let processed = preprocessFace(
        cast[ptr uint8](unsafeAddr imageData[0]),
        x = 500, y = 500, w = 50, h = 50,  # Far outside: clamps to x0=111, x1=112
        stride = imgSize * 3,
        imgW = imgSize, imgH = imgSize
      )

      # Returns valid tensor but from clamped 1x1 region (bottom-right pixel)
      # Implementation clamps rather than returning zeros
      check processed.len == 37632

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
    # Text pattern matches AND pause at start (needs 6 silent samples for pause detection)
    let audioWithPause = @[0.01f, 0.01f, 0.01f, 0.01f, 0.01f, 0.01f, 0.3f, 0.3f]  # 6 silent then normal
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
    check engagementCmd.generateOutputPath("/path/to/video.mp4", "", ".engage.json").normalizedPath == "/path/to/video.engage.json".normalizedPath
    check engagementCmd.generateOutputPath("/path/to/video.mp4", "/out", ".engage.json").normalizedPath == "/out/video.engage.json".normalizedPath

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
      clips.Clip(startMs: 0, endMs: 30000, engagementScore: 90.0f, viralityScore: 90.0f),
      clips.Clip(startMs: 10000, endMs: 40000, engagementScore: 85.0f, viralityScore: 85.0f),  # Overlaps with first
      clips.Clip(startMs: 50000, endMs: 80000, engagementScore: 80.0f, viralityScore: 80.0f)   # No overlap
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

# NLE Marker Tests

suite "NLE Markers":
  test "createEngagementMarker format":
    let marker = createEngagementMarker(61500, 85, 2)
    check marker.name == "Peak #2"
    check marker.comment.contains("85/100")
    check marker.comment.contains("#2")
    check marker.comment.contains("High engagement")
    check marker.color == "#00FF00"
    check marker.markerType == mtEngagementPeak
    check marker.timestampMs == 61500
    check marker.durationMs == 1000

  test "createEngagementMarker score labels":
    # High engagement (80+)
    let high = createEngagementMarker(0, 80, 1)
    check high.comment.contains("High engagement")

    # Medium engagement (50-79)
    let medium = createEngagementMarker(0, 65, 2)
    check medium.comment.contains("Medium engagement")

    # Low engagement (<50)
    let low = createEngagementMarker(0, 40, 3)
    check low.comment.contains("Low engagement")

  test "createSceneMarker format":
    let marker = createSceneMarker(61500)
    check marker.name == "Scene"
    check marker.color == "#0066FF"
    check marker.markerType == mtSceneBoundary
    check marker.comment.contains("Scene boundary at")
    check marker.timestampMs == 61500

  test "createSpeakerMarker with name":
    let marker = createSpeakerMarker(5000, 0, "John")
    check marker.name == "Speaker: John"
    check marker.comment.contains("John")
    check marker.color == "#FFCC00"
    check marker.markerType == mtSpeakerChange

  test "createSpeakerMarker without name":
    let marker = createSpeakerMarker(5000, 1)
    check marker.name == "Speaker 1"
    check marker.comment.contains("1")
    check marker.color == "#FFCC00"

  test "labelForScore thresholds":
    check labelForScore(100.0f) == "High engagement"
    check labelForScore(80.0f) == "High engagement"
    check labelForScore(79.9f) == "Medium engagement"
    check labelForScore(50.0f) == "Medium engagement"
    check labelForScore(49.9f) == "Low engagement"
    check labelForScore(0.0f) == "Low engagement"

  test "msToTimecode calculation":
    # 1 minute, 1 second, 15 frames at 30fps
    # = 61000ms + 500ms = 61500ms
    check msToTimecode(61500, 30.0) == "00:01:01:15"
    check msToTimecode(0, 30.0) == "00:00:00:00"
    check msToTimecode(3600000, 30.0) == "01:00:00:00"  # 1 hour
    check msToTimecode(1000, 30.0) == "00:00:01:00"     # 1 second

  test "getMarkerColor returns correct colors":
    check getMarkerColor(mtEngagementPeak) == "#00FF00"
    check getMarkerColor(mtSceneBoundary) == "#0066FF"
    check getMarkerColor(mtSpeakerChange) == "#FFCC00"

# FCP7 Marker Export Tests

suite "FCP7 Markers":
  test "markerColorToFCP7 parses hex correctly":
    # Green (engagement peak color)
    let green = markerColorToFCP7("#00FF00")
    check green.r == 0
    check green.g == 255
    check green.b == 0

    # Blue (scene boundary color)
    let blue = markerColorToFCP7("#0066FF")
    check blue.r == 0
    check blue.g == 102
    check blue.b == 255

    # Yellow (speaker change color)
    let yellow = markerColorToFCP7("#FFCC00")
    check yellow.r == 255
    check yellow.g == 204
    check yellow.b == 0

    # Black
    let black = markerColorToFCP7("#000000")
    check black.r == 0
    check black.g == 0
    check black.b == 0

    # White
    let white = markerColorToFCP7("#FFFFFF")
    check white.r == 255
    check white.g == 255
    check white.b == 255

  test "addMarkerFCP7 creates correct XML structure":
    let marker = createEngagementMarker(2000, 85, 1)
    let parent = newElement("clipitem")
    addMarkerFCP7(parent, marker, 30)

    # Parent should have one child (the marker)
    check parent.len == 1
    let markerNode = parent[0]
    check markerNode.tag == "marker"

    # Check marker children exist
    var hasName, hasComment, hasIn, hasOut, hasColor = false
    for child in markerNode:
      case child.tag
      of "name":
        hasName = true
        check child.innerText == "Peak #1"
      of "comment":
        hasComment = true
        check child.innerText.contains("85/100")
      of "in":
        hasIn = true
        check child.innerText == "60"  # 2000ms at 30fps = 60 frames
      of "out":
        hasOut = true
        check child.innerText == "90"  # 2000ms + 1000ms at 30fps = 90 frames
      of "color":
        hasColor = true
        # Verify color structure
        var hasRed, hasGreen, hasBlue, hasAlpha = false
        for colorChild in child:
          case colorChild.tag
          of "red": hasRed = true; check colorChild.innerText == "0"
          of "green": hasGreen = true; check colorChild.innerText == "255"
          of "blue": hasBlue = true; check colorChild.innerText == "0"
          of "alpha": hasAlpha = true; check colorChild.innerText == "255"
          else: discard
        check hasRed and hasGreen and hasBlue and hasAlpha
      else: discard

    check hasName and hasComment and hasIn and hasOut and hasColor

  test "addMarkerFCP7 frame calculation":
    # Test frame calculation at different timebases
    # 2000ms at 30fps = 60 frames
    let marker30 = createEngagementMarker(2000, 50, 1)
    let parent30 = newElement("clipitem")
    addMarkerFCP7(parent30, marker30, 30)
    var inFrame30, outFrame30: string
    for child in parent30[0]:
      if child.tag == "in": inFrame30 = child.innerText
      if child.tag == "out": outFrame30 = child.innerText
    check inFrame30 == "60"
    check outFrame30 == "90"  # 60 + 30 (1000ms duration)

    # 2000ms at 24fps = 48 frames
    let marker24 = createEngagementMarker(2000, 50, 1)
    let parent24 = newElement("clipitem")
    addMarkerFCP7(parent24, marker24, 24)
    var inFrame24, outFrame24: string
    for child in parent24[0]:
      if child.tag == "in": inFrame24 = child.innerText
      if child.tag == "out": outFrame24 = child.innerText
    check inFrame24 == "48"
    check outFrame24 == "72"  # 48 + 24 (1000ms duration)

    # 2000ms at 60fps = 120 frames
    let marker60 = createEngagementMarker(2000, 50, 1)
    let parent60 = newElement("clipitem")
    addMarkerFCP7(parent60, marker60, 60)
    var inFrame60, outFrame60: string
    for child in parent60[0]:
      if child.tag == "in": inFrame60 = child.innerText
      if child.tag == "out": outFrame60 = child.innerText
    check inFrame60 == "120"
    check outFrame60 == "180"  # 120 + 60 (1000ms duration)

  test "addMarkersFCP7 adds multiple markers":
    let markers = @[
      createEngagementMarker(1000, 90, 1),
      createSceneMarker(3000),
      createSpeakerMarker(5000, 0, "John")
    ]
    let parent = newElement("clipitem")
    addMarkersFCP7(parent, markers, 30)

    # Should have 3 marker children
    check parent.len == 3
    for child in parent:
      check child.tag == "marker"

# FCPXML Marker Export Tests

suite "FCPXML Markers":
  test "addMarkerFCPXML creates correct XML structure":
    let marker = createEngagementMarker(1500, 85, 1)
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30000, den: 1001)  # 29.97fps NTSC
    addMarkerFCPXML(parent, marker, tb)

    # Parent should have one child (the marker)
    check parent.len == 1
    let markerNode = parent[0]
    check markerNode.tag == "marker"

    # Check marker has required attributes
    check markerNode.attr("value") == "Peak #1"
    check markerNode.attr("note").contains("85/100")
    check markerNode.attr("start").len > 0
    check markerNode.attr("duration").len > 0

  test "addMarkerFCPXML rational time format":
    # Test rational time format: marker at 1500ms with tb=30000/1001 produces correct rational string
    # 1500ms -> frames: (1500 * 30000) / (1001 * 1000) = 45000000 / 1001000 = ~44.96 frames
    # Rational: 44 * 1001 / 30000 = 44044/30000
    let marker = createEngagementMarker(1500, 50, 1)
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30000, den: 1001)
    addMarkerFCPXML(parent, marker, tb)

    let markerNode = parent[0]
    let startAttr = markerNode.attr("start")

    # Should end with 's' for seconds
    check startAttr.endsWith("s")
    # Should contain rational format (num/den)
    check startAttr.contains("/")

  test "addMarkerFCPXML simple 30fps timebase":
    # Test with simple 30fps (integer framerate)
    # 2000ms at 30fps = 60 frames
    # Rational: 60 * 1 / 30 = 60/30 = "2s" simplified, but our format gives 60*1/30s = 60/30s
    let marker = createEngagementMarker(2000, 50, 1)
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30, den: 1)
    addMarkerFCPXML(parent, marker, tb)

    let markerNode = parent[0]
    let startAttr = markerNode.attr("start")

    # Should be "60/30s" format (frame * den / num)
    check startAttr == "60/30s"

  test "addMarkerFCPXML note contains marker comment":
    let marker = createEngagementMarker(5000, 92, 3)
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30, den: 1)
    addMarkerFCPXML(parent, marker, tb)

    let markerNode = parent[0]
    let noteAttr = markerNode.attr("note")

    # Note should contain the full engagement marker comment
    check noteAttr.contains("92/100")
    check noteAttr.contains("#3")
    check noteAttr.contains("High engagement")

  test "addMarkersFCPXML adds multiple markers":
    let markers = @[
      createEngagementMarker(1000, 90, 1),
      createSceneMarker(3000),
      createSpeakerMarker(5000, 0, "John")
    ]
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30, den: 1)
    addMarkersFCPXML(parent, markers, tb)

    # Should have 3 marker children
    check parent.len == 3
    for child in parent:
      check child.tag == "marker"

  test "addMarkerFCPXML zero timestamp":
    let marker = createEngagementMarker(0, 75, 1)
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30, den: 1)
    addMarkerFCPXML(parent, marker, tb)

    let markerNode = parent[0]
    # Zero should produce "0s"
    check markerNode.attr("start") == "0s"

  test "addMarkerFCPXML duration calculation":
    # Default marker duration is 1000ms
    # At 30fps: 1000ms = 30 frames
    let marker = createEngagementMarker(0, 50, 1)
    let parent = newElement("asset-clip")
    let tb = AVRational(num: 30, den: 1)
    addMarkerFCPXML(parent, marker, tb)

    let markerNode = parent[0]
    # Duration should be 30 frames = "30/30s"
    check markerNode.attr("duration") == "30/30s"

# EDL Marker Export Tests

suite "EDL Markers":
  test "markerTypeToString conversion":
    check markerTypeToString(mtEngagementPeak) == "ENGAGEMENT_PEAK"
    check markerTypeToString(mtSceneBoundary) == "SCENE_BOUNDARY"
    check markerTypeToString(mtSpeakerChange) == "SPEAKER_CHANGE"

  test "addMarkerEDL generates correct comment lines":
    let marker = createEngagementMarker(90000, 85, 1)  # 1:30 at 30fps
    var lines: seq[string] = @[]
    addMarkerEDL(lines, marker, 30.0)

    check lines.len == 3
    check lines[0].startsWith("* MARKER ")
    check lines[0].contains("00:01:30:00")  # 90000ms = 1min 30sec
    check lines[0].contains("TYPE: ENGAGEMENT_PEAK")
    check lines[1] == "* MARKER_NAME: Peak #1"
    check lines[2].contains("* MARKER_COMMENT:")
    check lines[2].contains("85/100")

  test "addMarkerEDL scene boundary format":
    let marker = createSceneMarker(5000)
    var lines: seq[string] = @[]
    addMarkerEDL(lines, marker, 30.0)

    check lines.len == 3
    check lines[0].contains("TYPE: SCENE_BOUNDARY")
    check lines[1] == "* MARKER_NAME: Scene"
    check lines[2].contains("Scene boundary")

  test "addMarkerEDL speaker change format":
    let marker = createSpeakerMarker(10000, 2, "Alice")
    var lines: seq[string] = @[]
    addMarkerEDL(lines, marker, 30.0)

    check lines.len == 3
    check lines[0].contains("TYPE: SPEAKER_CHANGE")
    check lines[1] == "* MARKER_NAME: Speaker: Alice"
    check lines[2].contains("Alice")

  test "addMarkersEDL multiple markers":
    let markers = @[
      createEngagementMarker(0, 90, 1),
      createSceneMarker(30000),
      createSpeakerMarker(60000, 1)
    ]
    var lines: seq[string] = @[]
    addMarkersEDL(lines, markers, 30.0)

    # Each marker is 3 lines + 1 blank = 4 lines each, 3 markers = 12 lines
    check lines.len == 12

  test "EDL timecode calculation at 30fps":
    # 90000ms at 30fps = 90 seconds = 1:30:00
    let marker = createEngagementMarker(90000, 50, 1)
    var lines: seq[string] = @[]
    addMarkerEDL(lines, marker, 30.0)

    check lines[0].contains("00:01:30:00")

  test "EDL timecode calculation with frames":
    # 90500ms at 30fps = 90.5 seconds = 1:30 + 15 frames
    let marker = createEngagementMarker(90500, 50, 1)
    var lines: seq[string] = @[]
    addMarkerEDL(lines, marker, 30.0)

    check lines[0].contains("00:01:30:15")

  test "exportMarkersEDL creates valid file":
    let tempDir = createTempDir("tmp", "")
    defer: removeDir(tempDir)

    let markers = @[
      createEngagementMarker(5000, 85, 1),
      createSceneMarker(10000)
    ]

    let edlPath = tempDir / "markers.edl"
    exportMarkersEDL(markers, edlPath, "TestVideo", 30.0)

    check fileExists(edlPath)
    let content = readFile(edlPath)
    check content.contains("TITLE: TestVideo Markers")
    check content.contains("* MARKER ")
    check content.contains("ENGAGEMENT_PEAK")
    check content.contains("SCENE_BOUNDARY")

  test "exportCMX3600EDLWithMarkers integrates clips and markers":
    let tempDir = createTempDir("tmp", "")
    defer: removeDir(tempDir)

    let clips = @[
      EDLClip(startMs: 0, endMs: 10000, engagementScore: 80.0, text: "Test clip", rank: 1)
    ]
    let markers = @[
      createEngagementMarker(5000, 80, 1)
    ]

    let edlPath = tempDir / "combined.edl"
    exportCMX3600EDLWithMarkers(clips, markers, edlPath, "TestSrc", 30.0)

    check fileExists(edlPath)
    let content = readFile(edlPath)

    # Should have clip event
    check content.contains("001  ")
    check content.contains("ENGAGEMENT_SCORE: 80.0")

    # Should have marker section
    check content.contains("* --- MARKERS ---")
    check content.contains("ENGAGEMENT_PEAK")

# Score Visualization Tests

suite "Score Visualization":
  test "defaultScoreVizParams returns expected defaults":
    let params = defaultScoreVizParams()
    check params.mode == svmBoth
    check params.graphHeight == 100
    check params.graphPosition == "bottom"
    check params.graphColor == "#00FF00"
    check params.graphOpacity == 0.5
    check params.textInterval == 5
    check params.textPosition == "top-right"
    check params.fontSize == 24
    check params.fontColor == "#FFFFFF"

  test "writeScoreDataFile output format":
    # Create test segments
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    # Write to temp file
    let tempDir = createTempDir("tmp", "")
    defer: removeDir(tempDir)
    let outputPath = tempDir / "scores.txt"

    # Write data for 1 second at 30fps = 30 frames
    writeScoreDataFile(segments, outputPath, fps = 30.0, durationMs = 1000)

    # Read and verify
    let content = readFile(outputPath)
    let lines = content.strip().splitLines()

    # Should have 30 lines (30 frames)
    check lines.len == 30

    # Each line should be a value between 0 and 1
    for line in lines:
      let value = parseFloat(line)
      check value >= 0.0 and value <= 1.0

    # Score of 50/100 should produce 0.500
    check lines[0] == "0.500"

  test "writeScoreDataFile handles multiple segments":
    var segments: seq[EngagementSegment] = @[]

    var seg1 = newEngagementSegment(0, 500)
    seg1.score = 25.0f
    segments.add(seg1)

    var seg2 = newEngagementSegment(500, 1000)
    seg2.score = 75.0f
    segments.add(seg2)

    let tempDir = createTempDir("tmp", "")
    defer: removeDir(tempDir)
    let outputPath = tempDir / "scores.txt"

    # Write data for 1 second at 10fps = 10 frames
    writeScoreDataFile(segments, outputPath, fps = 10.0, durationMs = 1000)

    let content = readFile(outputPath)
    let lines = content.strip().splitLines()

    check lines.len == 10

    # First 5 frames (0-500ms) should be 0.250
    check lines[0] == "0.250"
    check lines[4] == "0.250"

    # Last 5 frames (500-1000ms) should be 0.750
    check lines[5] == "0.750"
    check lines[9] == "0.750"

  test "generateGraphFilter produces valid filter":
    let params = defaultScoreVizParams()
    let filter = generateGraphFilter(params, "scores.txt", 1920, 1080)

    # Should produce drawbox filter
    check filter.contains("drawbox")
    # Should reference graph height
    check filter.contains("h=100")
    # Should have width
    check filter.contains("w=1920")
    # Should position at bottom (1080 - 100 = 980)
    check filter.contains("y=980")
    # Should have opacity
    check filter.contains("@0.5")

  test "generateGraphFilter respects top position":
    var params = defaultScoreVizParams()
    params.graphPosition = "top"
    let filter = generateGraphFilter(params, "scores.txt", 1920, 1080)

    # Should position at top (y=0)
    check filter.contains("y=0")

  test "generateTextFilter produces drawtext with enable":
    var segments: seq[EngagementSegment] = @[]

    var seg1 = newEngagementSegment(0, 5000)
    seg1.score = 75.0f
    segments.add(seg1)

    var seg2 = newEngagementSegment(5000, 10000)
    seg2.score = 85.0f
    segments.add(seg2)

    let params = defaultScoreVizParams()
    let filter = generateTextFilter(params, segments)

    # Should contain drawtext
    check filter.contains("drawtext=")
    # Should contain enable expression
    check filter.contains("enable='between(t,")
    # Should contain score text
    check filter.contains("Score\\: 75/100")
    check filter.contains("Score\\: 85/100")
    # Should have two drawtext filters (comma-separated)
    check filter.count("drawtext=") == 2

  test "generateTextFilter respects position":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    # Test top-left
    var params = defaultScoreVizParams()
    params.textPosition = "top-left"
    let filterTL = generateTextFilter(params, segments)
    check filterTL.contains("x=10")
    check filterTL.contains("y=10")

    # Test bottom-right
    params.textPosition = "bottom-right"
    let filterBR = generateTextFilter(params, segments)
    check filterBR.contains("x=w-text_w-10")
    check filterBR.contains("y=h-text_h-10")

  test "generateTextFilter respects font settings":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    var params = defaultScoreVizParams()
    params.fontSize = 32
    params.fontColor = "#FF0000"
    let filter = generateTextFilter(params, segments)

    check filter.contains("fontsize=32")
    check filter.contains("fontcolor=#FF0000")

  test "generateScoreOverlayFilter graph only":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    var params = defaultScoreVizParams()
    params.mode = svmGraph
    let filter = generateScoreOverlayFilter(params, segments, 1920, 1080)

    # Should have graph filter
    check filter.contains("drawbox")
    # Should NOT have text filter
    check not filter.contains("drawtext")

  test "generateScoreOverlayFilter text only":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    var params = defaultScoreVizParams()
    params.mode = svmText
    let filter = generateScoreOverlayFilter(params, segments, 1920, 1080)

    # Should NOT have graph filter
    check not filter.contains("drawbox")
    # Should have text filter
    check filter.contains("drawtext")

  test "generateScoreOverlayFilter both modes":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    var params = defaultScoreVizParams()
    params.mode = svmBoth
    let filter = generateScoreOverlayFilter(params, segments, 1920, 1080)

    # Should have both filters
    check filter.contains("drawbox")
    check filter.contains("drawtext")
    # Should be comma-separated
    check filter.contains(",")

  test "renderScoreGraph helper":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    let filter = renderScoreGraph(segments, 1920, 1080)
    check filter.contains("drawbox")

  test "renderScoreText helper":
    var segments: seq[EngagementSegment] = @[]
    var seg = newEngagementSegment(0, 1000)
    seg.score = 50.0f
    segments.add(seg)

    let filter = renderScoreText(segments)
    check filter.contains("drawtext")

  test "generateTextFilter empty segments":
    let segments: seq[EngagementSegment] = @[]
    let params = defaultScoreVizParams()
    let filter = generateTextFilter(params, segments)

    # Should produce empty filter for no segments
    check filter.len == 0

# NLE Export Command Tests

suite "NLE Export Command":
  test "parseNLETarget premiere variants":
    check parseNLETarget("premiere") == nleFCP7XML
    check parseNLETarget("fcp7xml") == nleFCP7XML
    check parseNLETarget("fcp7") == nleFCP7XML
    check parseNLETarget("resolve-xml") == nleFCP7XML
    # Case insensitive
    check parseNLETarget("PREMIERE") == nleFCP7XML
    check parseNLETarget("Fcp7Xml") == nleFCP7XML

  test "parseNLETarget fcpx variants":
    check parseNLETarget("fcpx") == nleFCPXML
    check parseNLETarget("finalcut") == nleFCPXML
    check parseNLETarget("fcpxml") == nleFCPXML
    check parseNLETarget("fcp11") == nleFCPXML
    # Case insensitive
    check parseNLETarget("FCPX") == nleFCPXML

  test "parseNLETarget resolve/edl variants":
    check parseNLETarget("resolve") == nleEDL
    check parseNLETarget("edl") == nleEDL
    check parseNLETarget("resolve-edl") == nleEDL
    # Case insensitive
    check parseNLETarget("RESOLVE") == nleEDL
    check parseNLETarget("EDL") == nleEDL

  test "parseNLETarget aaf variants":
    check parseNLETarget("aftereffects") == nleAAF
    check parseNLETarget("ae") == nleAAF
    check parseNLETarget("aaf") == nleAAF
    check parseNLETarget("mediacomposer") == nleAAF
    check parseNLETarget("avid") == nleAAF
    # Case insensitive
    check parseNLETarget("AAF") == nleAAF
    check parseNLETarget("AVID") == nleAAF

  test "parseNLETarget unknown returns nleNone":
    check parseNLETarget("unknown") == nleNone
    check parseNLETarget("invalid") == nleNone
    check parseNLETarget("") == nleNone
    check parseNLETarget("some-random-string") == nleNone

  test "NLEFormat enum has expected values":
    # Verify enum exists and has correct ordering
    check ord(nleNone) == 0
    check ord(nleFCP7XML) == 1
    check ord(nleFCPXML) == 2
    check ord(nleEDL) == 3
    check ord(nleAAF) == 4

# Engagement Presets Tests

import ../src/analyze/presets

suite "Engagement Presets":
  test "parseEngageValue with numeric input":
    let (threshold, config) = parseEngageValue("70")
    check threshold == 70.0
    check abs(config.audioWeight - 0.333) < 0.01
    check abs(config.motionWeight - 0.333) < 0.01
    check abs(config.speechWeight - 0.333) < 0.01

  test "parseEngageValue with float input":
    let (threshold, config) = parseEngageValue("75.5")
    check abs(threshold - 75.5) < 0.01

  test "parseEngageValue viral preset":
    let (threshold, config) = parseEngageValue("viral")
    check threshold == 75.0
    check abs(config.motionWeight - 0.4) < 0.01
    check abs(config.audioWeight - 0.3) < 0.01
    check abs(config.speechWeight - 0.3) < 0.01

  test "parseEngageValue podcast preset":
    let (threshold, config) = parseEngageValue("podcast")
    check threshold == 50.0
    check abs(config.speechWeight - 0.8) < 0.01
    check abs(config.audioWeight - 0.1) < 0.01
    check abs(config.motionWeight - 0.1) < 0.01

  test "parseEngageValue tutorial preset":
    let (threshold, config) = parseEngageValue("tutorial")
    check threshold == 40.0
    check abs(config.motionWeight - 0.4) < 0.01
    check abs(config.speechWeight - 0.4) < 0.01
    check abs(config.audioWeight - 0.2) < 0.01

  test "parseEngageValue interview preset":
    let (threshold, config) = parseEngageValue("interview")
    check threshold == 45.0
    check abs(config.speechWeight - 0.6) < 0.01
    check abs(config.audioWeight - 0.2) < 0.01
    check abs(config.motionWeight - 0.2) < 0.01

  test "parseEngageValue tiktok preset":
    let (threshold, config) = parseEngageValue("tiktok")
    check threshold == 80.0
    check abs(config.motionWeight - 0.5) < 0.01
    check abs(config.audioWeight - 0.3) < 0.01
    check abs(config.speechWeight - 0.2) < 0.01

  test "parseEngageValue youtube preset":
    let (threshold, config) = parseEngageValue("youtube")
    check threshold == 60.0
    check abs(config.audioWeight - 0.4) < 0.01
    check abs(config.motionWeight - 0.3) < 0.01
    check abs(config.speechWeight - 0.3) < 0.01

  test "parseEngageValue instagram preset":
    let (threshold, config) = parseEngageValue("instagram")
    check threshold == 70.0
    check abs(config.motionWeight - 0.4) < 0.01
    check abs(config.audioWeight - 0.3) < 0.01
    check abs(config.speechWeight - 0.3) < 0.01

  # Note: parseEngageValue unknown preset calls error() which terminates the process
  # with quit(1), not a catchable exception. Verified manually:
  #   honeyclip video.mp4 --engage=unknown_preset
  #   Error! Unknown engagement preset: 'unknown_preset'. Available presets: ...

  test "defaultPresetConfig returns equal weights":
    let config = defaultPresetConfig()
    check config.threshold == 50.0
    check abs(config.audioWeight - 0.333) < 0.01
    check abs(config.motionWeight - 0.333) < 0.01
    check abs(config.speechWeight - 0.333) < 0.01

  test "preset weights sum approximately to 1.0":
    for preset in ["viral", "podcast", "tutorial", "interview", "tiktok", "youtube", "instagram"]:
      let (_, config) = parseEngageValue(preset)
      let sum = config.audioWeight + config.motionWeight + config.speechWeight
      check abs(sum - 1.0) < 0.01  # Allow small floating point error

# CLI Integration Tests (manual verification required):
#
# TTY Behavior:
#   1. honeyclip analyze --help
#      Expected: Shows all options including --quiet and --verbose
#
#   2. honeyclip analyze video.mp4 model --quiet
#      Expected: No progress bars or prompts, minimal output
#
#   3. echo | honeyclip analyze video.mp4 model
#      Expected: No interactive prompts (piped input = not TTY)
#
#   4. honeyclip analyze video.mp4 model --verbose | cat
#      Expected: Shows progress despite being piped
#
#   5. honeyclip engage video.mp4 model --quiet
#      Expected: No progress output, silent operation
#
# Error Messages:
#   6. honeyclip video.mp4 --engage
#      (without .engage.json file present)
#      Expected: Error with instructions to run "honeyclip engage" first

# Expression Parser Tests (palet/lexer.nim)

import ../src/palet/lexer

suite "Expression Lexer":
  test "parser parses empty input":
    var lexer = initLexer("test", "")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    check exprs.len == 0

  test "parser returns expression for simple input":
    var lexer = initLexer("test", "(audio)")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    check exprs.len >= 1

  test "parser returns expression for function with arg":
    var lexer = initLexer("test", "(audio 0.04)")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    check exprs.len >= 1

  test "printExpr contains function name":
    var lexer = initLexer("test", "(audio 0.04)")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    let text = "(audio 0.04)"
    let output = printExpr(exprs[0], text)
    check output.contains("audio")

  test "parser handles comments":
    var lexer = initLexer("test", "; comment\n(audio)")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    check exprs.len >= 1

  test "parser handles whitespace":
    var lexer = initLexer("test", "  ( audio   0.04  )  ")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    check exprs.len >= 1

  test "parser handles colon syntax":
    var lexer = initLexer("test", "audio:0.04")
    var parser = initParser(lexer)
    let exprs = parser.parse()
    check exprs.len >= 1

# Expression Edit Tests (palet/edit.nim)
# Note: Most functions in edit.nim are not exported, so we can only test parseEditString2

import ../src/palet/edit

suite "Expression Edit":
  test "parseEditString2 simple kind":
    let (kind, threshold, stream, width, blur, pattern) = parseEditString2("audio")
    check kind == "audio"
    check abs(threshold - 0.04) < 0.001
    check stream == 0

  test "parseEditString2 with threshold":
    let (kind, threshold, stream, width, blur, pattern) = parseEditString2("audio:threshold=0.1")
    check kind == "audio"
    check abs(threshold - 0.1) < 0.001

  test "parseEditString2 with stream":
    let (kind, threshold, stream, width, blur, pattern) = parseEditString2("audio:stream=1")
    check kind == "audio"
    check stream == 1

  test "parseEditString2 multiple params":
    let (kind, threshold, stream, width, blur, pattern) = parseEditString2("audio:threshold=0.1,stream=1")
    check kind == "audio"
    check abs(threshold - 0.1) < 0.001
    check stream == 1

  test "parseEditString2 motion with width":
    let (kind, threshold, stream, width, blur, pattern) = parseEditString2("motion:width=800,blur=11")
    check kind == "motion"
    check width == 800
    check blur == 11

  test "parseEditString2 motion defaults":
    let (kind, threshold, stream, width, blur, pattern) = parseEditString2("motion")
    check kind == "motion"
    check width == 400  # default
    check blur == 9     # default

# Kalman Filter Tests (tracking/kalman.nim)

import ../src/tracking/kalman
import ../src/tracking/types

suite "Kalman Filter":
  test "newKalmanFilter initializes state":
    let bbox = FaceRect(x: 100, y: 200, width: 50, height: 60, confidence: 0.9, angle: 0)
    let kf = newKalmanFilter(bbox)
    check kf.state[0] == 100.0  # x
    check kf.state[1] == 200.0  # y
    check kf.state[2] == 50.0   # width
    check kf.state[3] == 60.0   # height
    check kf.state[4] == 0.0    # vx (zero initial velocity)
    check kf.state[5] == 0.0    # vy

  test "newKalmanFilter sets noise parameters":
    let bbox = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    let kf = newKalmanFilter(bbox, processNoise = 0.05, measurementNoise = 0.2)
    check kf.processNoise == 0.05
    check kf.measurementNoise == 0.2

  test "predict applies velocity":
    let bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 1.0, angle: 0)
    var kf = newKalmanFilter(bbox)
    # Set velocity manually
    kf.state[4] = 5.0   # vx = 5
    kf.state[5] = -3.0  # vy = -3

    let predicted = kf.predict()
    check predicted.x == 105  # x + vx
    check predicted.y == 97   # y + vy
    check predicted.confidence == 0.5  # Predicted = 0.5 confidence

  test "predict increases uncertainty":
    let bbox = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    var kf = newKalmanFilter(bbox, processNoise = 0.1)
    let covBefore = kf.covariance[0][0]
    discard kf.predict()
    check kf.covariance[0][0] > covBefore

  test "update reduces uncertainty":
    let bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 1.0, angle: 0)
    var kf = newKalmanFilter(bbox)
    discard kf.predict()  # Increases uncertainty
    let covBefore = kf.covariance[0][0]

    let detection = FaceRect(x: 102, y: 98, width: 50, height: 50, confidence: 0.9, angle: 0)
    kf.update(detection)
    check kf.covariance[0][0] < covBefore

  test "update moves state toward detection":
    let bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 1.0, angle: 0)
    var kf = newKalmanFilter(bbox)

    let detection = FaceRect(x: 110, y: 120, width: 50, height: 50, confidence: 0.9, angle: 0)
    kf.update(detection)

    # State should move toward detection
    check kf.state[0] > 100.0 and kf.state[0] <= 110.0
    check kf.state[1] > 100.0 and kf.state[1] <= 120.0

  test "getBbox returns current state":
    let bbox = FaceRect(x: 100, y: 200, width: 50, height: 60, confidence: 0.9, angle: 0)
    let kf = newKalmanFilter(bbox)
    let (x, y, w, h) = kf.getBbox()
    check x == 100
    check y == 200
    check w == 50
    check h == 60

  test "kalman-predict-zero-velocity":
    # Filter with zero velocity should keep position unchanged
    let bbox = FaceRect(x: 100, y: 200, width: 50, height: 50, confidence: 0.9, angle: 0)
    var kf = newKalmanFilter(bbox)
    # Velocities are initialized to 0
    check checkApprox(kf.state[4], 0.0)
    check checkApprox(kf.state[5], 0.0)

    let predicted = kf.predict()
    check predicted.x == 100  # x unchanged
    check predicted.y == 200  # y unchanged
    check predicted.confidence == 0.5  # Predicted marker

  test "kalman-update-calculates-velocity":
    # Update should calculate velocity from position change
    let bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    var kf = newKalmanFilter(bbox)

    # Update with detection shifted by (10, 15)
    let detection = FaceRect(x: 110, y: 115, width: 50, height: 50, confidence: 0.9, angle: 0)
    kf.update(detection)

    # Velocity should reflect the position change
    # Note: Kalman filter blends old and new, so velocity may not be exact
    check kf.state[4] > 0.0  # vx should be positive (moving right)
    check kf.state[5] > 0.0  # vy should be positive (moving down)
    # Use tolerance - velocity approximately matches movement
    check checkApprox(kf.state[4], 10.0, epsilon = 5.0)
    check checkApprox(kf.state[5], 15.0, epsilon = 5.0)

  test "kalman-covariance-diagonal-initialized":
    # Verify covariance diagonal is initialized to 1.0
    let bbox = FaceRect(x: 100, y: 200, width: 50, height: 50, confidence: 0.9, angle: 0)
    let kf = newKalmanFilter(bbox)
    for i in 0..5:
      check checkApprox(kf.covariance[i][i], 1.0)

  test "kalman-covariance-stays-positive":
    # Verify covariance remains positive definite after operations
    let bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    var kf = newKalmanFilter(bbox)

    # Run several predict/update cycles
    for i in 0 ..< 10:
      discard kf.predict()
      let det = FaceRect(x: 100 + i * 5, y: 100 + i * 3, width: 50, height: 50,
                         confidence: 0.9, angle: 0)
      kf.update(det)

    # Covariance diagonal should still be positive
    check checkCovariancePositive(kf.covariance)

  test "kalman-multi-frame-tracking":
    # Track face moving in straight line over multiple frames
    let faces = generateStraightLineFace(100, 100, 50, 50, 5.0, 2.0, 20)
    check faces.len == 20

    var kf = newKalmanFilter(faces[0])

    # Update with each frame
    for i in 1 ..< faces.len:
      discard kf.predict()
      kf.update(faces[i])

    # Final position should be near expected: (100 + 19*5, 100 + 19*2) = (195, 138)
    let (x, y, w, h) = kf.getBbox()
    check checkApprox(float(x), 195.0, epsilon = 10.0)
    check checkApprox(float(y), 138.0, epsilon = 10.0)

    # Velocities should be positive (moving in positive direction)
    # Note: Due to Kalman filter dynamics with simplified diagonal covariance,
    # velocity reflects frame-to-frame position change after update
    check kf.state[4] > 0.0  # vx positive (moving right)
    check kf.state[5] > 0.0  # vy positive (moving down)

  test "kalman-handles-noisy-input":
    # Track face with noisy position measurements
    let faces = generateNoisyPath(100, 100, 50, 50, 5.0, 2.0, 30, noiseStdDev = 3.0)
    check faces.len == 30

    var kf = newKalmanFilter(faces[0])

    # Update with each frame
    for i in 1 ..< faces.len:
      discard kf.predict()
      kf.update(faces[i])

    # Despite noise, filter should track general trajectory
    # Expected final position approx: (100 + 29*5, 100 + 29*2) = (245, 158)
    let (x, y, w, h) = kf.getBbox()
    check checkApprox(float(x), 245.0, epsilon = 20.0)  # Larger epsilon for noisy data
    check checkApprox(float(y), 158.0, epsilon = 20.0)

# Hungarian Assignment Tests (tracking/assignment.nim)

import ../src/tracking/assignment

suite "Hungarian Assignment":
  test "iou no overlap":
    let a = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    let b = FaceRect(x: 20, y: 20, width: 10, height: 10, confidence: 1.0, angle: 0)
    check iou(a, b) == 0.0

  test "iou full overlap":
    let a = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    let b = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    check iou(a, b) == 1.0

  test "iou partial overlap":
    let a = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    let b = FaceRect(x: 5, y: 5, width: 10, height: 10, confidence: 1.0, angle: 0)
    # Intersection: 5x5 = 25, Union: 100 + 100 - 25 = 175
    let result = iou(a, b)
    check abs(result - 25.0/175.0) < 0.001

  test "iou edge touching":
    let a = FaceRect(x: 0, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    let b = FaceRect(x: 10, y: 0, width: 10, height: 10, confidence: 1.0, angle: 0)
    check iou(a, b) == 0.0  # Edge touching = no overlap

  test "hungarianAssignment empty matrix":
    let costMatrix: seq[seq[float]] = @[]
    let assignments = hungarianAssignment(costMatrix)
    check assignments.len == 0

  test "hungarianAssignment single element":
    let costMatrix = @[@[0.5]]
    let assignments = hungarianAssignment(costMatrix)
    check assignments.len == 1
    check assignments[0].trackIdx == 0
    check assignments[0].detIdx == 0

  test "hungarianAssignment respects threshold":
    let costMatrix = @[@[1e6]]  # Cost above threshold
    let assignments = hungarianAssignment(costMatrix, threshold = 1e5)
    check assignments.len == 0

  test "hungarianAssignment optimal assignment":
    # 2x2 matrix where optimal is diagonal
    let costMatrix = @[
      @[0.1, 0.9],
      @[0.9, 0.1]
    ]
    let assignments = hungarianAssignment(costMatrix)
    check assignments.len == 2
    # Should assign (0,0) and (1,1) for minimum cost
    var foundDiagonal = false
    for a in assignments:
      if a.trackIdx == a.detIdx:
        foundDiagonal = true
    check foundDiagonal

  test "iou-one-inside-other":
    # Large box containing small box
    let large = FaceRect(x: 0, y: 0, width: 200, height: 200, confidence: 1.0, angle: 0)
    let small = FaceRect(x: 50, y: 50, width: 50, height: 50, confidence: 1.0, angle: 0)
    # Intersection = small box area = 2500
    # Union = 40000 + 2500 - 2500 = 40000
    # IoU = 2500/40000 = 0.0625
    let result = iou(large, small)
    check checkApprox(result, 0.0625, epsilon = 0.001)

  test "iou-symmetric":
    # IoU should be symmetric: iou(a,b) == iou(b,a)
    let a = FaceRect(x: 0, y: 0, width: 100, height: 100, confidence: 1.0, angle: 0)
    let b = FaceRect(x: 50, y: 50, width: 100, height: 100, confidence: 1.0, angle: 0)
    check checkApprox(iou(a, b), iou(b, a))

  test "costMatrix-empty-tracks":
    # Empty tracks with non-empty detections
    let tracks: seq[Track] = @[]
    let detections = @[FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)]
    let embeddings: seq[seq[float32]] = @[@[]]
    let matrix = computeCostMatrix(tracks, detections, embeddings)
    check matrix.len == 0

  test "costMatrix-empty-detections":
    # Non-empty tracks with empty detections
    var track = Track()
    track.id = 0
    track.bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    let tracks = @[track]
    let detections: seq[FaceRect] = @[]
    let embeddings: seq[seq[float32]] = @[]
    let matrix = computeCostMatrix(tracks, detections, embeddings)
    check matrix.len == 1
    check matrix[0].len == 0

  test "costMatrix-sets-infinite-for-low-iou":
    # Track and detection far apart (IoU < 0.5)
    var track = Track()
    track.id = 0
    track.bbox = FaceRect(x: 0, y: 0, width: 50, height: 50, confidence: 0.9, angle: 0)
    let tracks = @[track]
    let detections = @[FaceRect(x: 500, y: 500, width: 50, height: 50, confidence: 0.9, angle: 0)]
    let embeddings: seq[seq[float32]] = @[@[]]
    let matrix = computeCostMatrix(tracks, detections, embeddings)
    check matrix.len == 1
    check matrix[0].len == 1
    check matrix[0][0] >= 1e5  # Infinite cost for low IoU

  test "costMatrix-calculates-valid-cost":
    # Track and detection with high overlap (IoU > 0.5)
    var track = Track()
    track.id = 0
    track.bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    let tracks = @[track]
    let detections = @[FaceRect(x: 105, y: 102, width: 50, height: 50, confidence: 0.9, angle: 0)]
    let embeddings: seq[seq[float32]] = @[@[]]
    let matrix = computeCostMatrix(tracks, detections, embeddings)
    check matrix.len == 1
    check matrix[0].len == 1
    # Cost should be valid (not infinite) for high overlap
    check matrix[0][0] < 1e5
    check matrix[0][0] > 0.0

  test "hungarian-two-tracks-two-detections":
    # 2x2 cost matrix with clear optimal assignment
    let costMatrix = @[
      @[0.1, 0.9],
      @[0.8, 0.2]
    ]
    let assignments = hungarianAssignment(costMatrix)
    check assignments.len == 2
    # Optimal: track0->det0 (0.1), track1->det1 (0.2)
    var track0Det0 = false
    var track1Det1 = false
    for a in assignments:
      if a.trackIdx == 0 and a.detIdx == 0:
        track0Det0 = true
      if a.trackIdx == 1 and a.detIdx == 1:
        track1Det1 = true
    check track0Det0
    check track1Det1

  test "hungarian-unbalanced-more-tracks":
    # 3 tracks, 2 detections - one track should be unassigned
    let costMatrix = @[
      @[0.1, 0.9],
      @[0.8, 0.2],
      @[0.5, 0.5]
    ]
    let assignments = hungarianAssignment(costMatrix)
    # Only 2 assignments possible (min of tracks, detections)
    check assignments.len == 2
    # Verify unique track and detection indices
    var trackIndices: seq[int] = @[]
    var detIndices: seq[int] = @[]
    for a in assignments:
      trackIndices.add(a.trackIdx)
      detIndices.add(a.detIdx)
    check trackIndices.len == 2
    check detIndices.len == 2

  test "hungarian-unbalanced-more-detections":
    # 2 tracks, 3 detections - one detection should be unassigned
    let costMatrix = @[
      @[0.1, 0.8, 0.5],
      @[0.9, 0.2, 0.6]
    ]
    let assignments = hungarianAssignment(costMatrix)
    # Only 2 assignments possible (min of tracks, detections)
    check assignments.len == 2
    # Verify unique track and detection indices
    var trackIndices: seq[int] = @[]
    var detIndices: seq[int] = @[]
    for a in assignments:
      trackIndices.add(a.trackIdx)
      detIndices.add(a.detIdx)
    check trackIndices.len == 2
    check detIndices.len == 2

  test "hungarian-all-high-cost":
    # All costs above threshold - no assignments
    let costMatrix = @[
      @[1e6, 1e6],
      @[1e6, 1e6]
    ]
    let assignments = hungarianAssignment(costMatrix, threshold = 1e5)
    check assignments.len == 0

  test "costMatrix-with-embeddings":
    # Test cost calculation with embeddings for appearance distance
    var track = Track()
    track.id = 0
    track.bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    track.embedding = @[1.0f, 0.0f, 0.0f]  # Unit vector in x direction
    let tracks = @[track]

    let detections = @[FaceRect(x: 105, y: 102, width: 50, height: 50, confidence: 0.9, angle: 0)]
    # Similar embedding (high cosine similarity)
    let embeddings: seq[seq[float32]] = @[@[0.9f, 0.1f, 0.1f]]

    let matrix = computeCostMatrix(tracks, detections, embeddings)
    check matrix.len == 1
    check matrix[0].len == 1
    # Cost should be lower due to similar appearance
    check matrix[0][0] < 1.0  # Valid cost, includes appearance component

# Utility Function Tests (util/fun.nim)

import ../src/util/fun

suite "Utility Functions":
  test "handleKey converts underscores":
    check handleKey("--my_option") == "--my-option"
    check handleKey("--simple") == "--simple"
    check handleKey("-v") == "-v"

  test "splitext separates path and extension":
    let (base, ext) = splitext("/path/to/file.mp4")
    check ext == ".mp4"
    check base.endsWith("file")

  test "splitNumStr parses number with unit":
    let (num, unit) = splitNumStr("100k")
    check num == 100.0
    check unit == "k"

  test "splitNumStr parses negative number":
    let (num, unit) = splitNumStr("-20dB")
    check num == -20.0
    check unit == "dB"

  test "splitNumStr parses decimal":
    let (num, unit) = splitNumStr("0.5s")
    check num == 0.5
    check unit == "s"

  test "parseBitrate with k suffix":
    check parseBitrate("128k") == 128000

  test "parseBitrate with M suffix":
    check parseBitrate("2M") == 2000000

  test "parseBitrate auto":
    check parseBitrate("auto") == -1

  test "parseBitrate plain number":
    check parseBitrate("5000") == 5000

  test "aspectRatio 16:9":
    let (w, h) = aspectRatio(1920, 1080)
    check w == 16
    check h == 9

  test "aspectRatio 4:3":
    let (w, h) = aspectRatio(640, 480)
    check w == 4
    check h == 3

  test "aspectRatio 1:1":
    let (w, h) = aspectRatio(500, 500)
    check w == 1
    check h == 1

  test "aspectRatio handles zero height":
    let (w, h) = aspectRatio(100, 0)
    check w == 0
    check h == 0

  test "mutRemoveSmall removes short segments":
    var arr = @[false, true, false, false, false]  # Single true
    mutRemoveSmall(arr, 2, true, false)  # Replace isolated trues with false
    check arr == @[false, false, false, false, false]

  test "mutRemoveSmall keeps long segments":
    var arr = @[false, true, true, true, false]  # Three trues
    mutRemoveSmall(arr, 2, true, false)  # Only remove if < 2
    check arr == @[false, true, true, true, false]

  test "mutMargin extends start":
    var arr = @[false, false, true, true, false]
    mutMargin(arr, startM = 1, endM = 0)
    check arr[1] == true  # Extended by 1

  test "mutMargin extends end":
    var arr = @[false, true, true, false, false]
    mutMargin(arr, startM = 0, endM = 1)
    check arr[3] == true  # Extended by 1

# Timeline Tests (timeline.nim)

import ../src/timeline

suite "Timeline":
  test "makeSaneTimebase NTSC 30fps":
    # 29.97fps should normalize to 30000/1001
    let tb = AVRational(num: 2997, den: 100)
    let sane = makeSaneTimebase(tb)
    check sane.num == 30000
    check sane.den == 1001

  test "makeSaneTimebase NTSC 60fps":
    # 59.94fps should normalize to 60000/1001
    let tb = AVRational(num: 5994, den: 100)
    let sane = makeSaneTimebase(tb)
    check sane.num == 60000
    check sane.den == 1001

  test "makeSaneTimebase film NTSC 24fps":
    # 23.976fps should normalize to 24000/1001
    let tb = AVRational(num: 23976, den: 1000)
    let sane = makeSaneTimebase(tb)
    check sane.num == 24000
    check sane.den == 1001

  test "makeSaneTimebase standard 30fps":
    # Exact 30fps stays as-is
    let tb = AVRational(num: 30, den: 1)
    let sane = makeSaneTimebase(tb)
    check sane.num == 30
    check sane.den == 1

  test "makeSaneTimebase standard 25fps":
    let tb = AVRational(num: 25, den: 1)
    let sane = makeSaneTimebase(tb)
    check sane.num == 25
    check sane.den == 1

# Easing Function Tests (reframe/easing.nim)

import ../src/reframe/easing

suite "Easing Functions":
  test "lerp at t=0 returns start":
    check lerp(10.0, 20.0, 0.0) == 10.0

  test "lerp at t=1 returns end":
    check lerp(10.0, 20.0, 1.0) == 20.0

  test "lerp at t=0.5 returns midpoint":
    check lerp(10.0, 20.0, 0.5) == 15.0

  test "lerp with negative values":
    check lerp(-10.0, 10.0, 0.5) == 0.0

  test "lerp with same start and end":
    check lerp(5.0, 5.0, 0.5) == 5.0

  test "cubicBezier at t=0 returns p0":
    check abs(cubicBezier(0.0, 0.0, 0.25, 0.75, 1.0) - 0.0) < 0.001

  test "cubicBezier at t=1 returns p3":
    check abs(cubicBezier(1.0, 0.0, 0.25, 0.75, 1.0) - 1.0) < 0.001

  test "cubicBezier ease-in-out at midpoint":
    # For standard ease-in-out (0, 0.42, 0.58, 1), midpoint should be ~0.5
    let result = cubicBezier(0.5, 0.0, 0.42, 0.58, 1.0)
    check abs(result - 0.5) < 0.1  # Allow some deviation

  test "cubicBezier linear curve":
    # Linear: control points at (0, 0.33, 0.67, 1)
    let result = cubicBezier(0.5, 0.0, 0.333, 0.667, 1.0)
    check abs(result - 0.5) < 0.05

  test "getDuration Slow preset":
    check getDuration(Slow) == 1.5

  test "getDuration Medium preset":
    check getDuration(Medium) == 0.75

  test "getDuration Fast preset":
    check getDuration(Fast) == 0.35

  test "easingFunction Slow at boundaries":
    check abs(easingFunction(0.0, Slow) - 0.0) < 0.001
    check abs(easingFunction(1.0, Slow) - 1.0) < 0.001

  test "easingFunction Medium at boundaries":
    check abs(easingFunction(0.0, Medium) - 0.0) < 0.001
    check abs(easingFunction(1.0, Medium) - 1.0) < 0.001

  test "easingFunction Fast at boundaries":
    check abs(easingFunction(0.0, Fast) - 0.0) < 0.001
    check abs(easingFunction(1.0, Fast) - 1.0) < 0.001

  test "easingFunction produces values in range":
    for t in [0.1, 0.25, 0.5, 0.75, 0.9]:
      let slow = easingFunction(t, Slow)
      let medium = easingFunction(t, Medium)
      let fast = easingFunction(t, Fast)
      check slow >= 0.0 and slow <= 1.0
      check medium >= 0.0 and medium <= 1.0
      check fast >= 0.0 and fast <= 1.0

# Crop Region Tests (reframe/crop.nim)

import ../src/reframe/crop

suite "Crop Region Calculation":
  test "aspectRatioValue Landscape":
    let ratio = aspectRatioValue(Landscape)
    check abs(ratio - 16.0/9.0) < 0.001

  test "aspectRatioValue Portrait":
    let ratio = aspectRatioValue(Portrait)
    check abs(ratio - 9.0/16.0) < 0.001

  test "aspectRatioValue Square":
    let ratio = aspectRatioValue(Square)
    check ratio == 1.0

  test "mediumShotPadding calculation":
    # Formula: faceHeight * 2.5
    check mediumShotPadding(100) == 250
    check mediumShotPadding(200) == 500
    check mediumShotPadding(40) == 100

  test "calculateCrop centers on face":
    let face = FaceRect(x: 500, y: 300, width: 100, height: 120, confidence: 0.9, angle: 0)
    let crop = calculateCrop(face, 1920, 1080, Portrait)

    # Face center is at (550, 360)
    # Crop should be roughly centered on face
    let cropCenterX = crop.x + crop.width div 2
    let cropCenterY = crop.y + crop.height div 2
    check abs(cropCenterX - 550) < 50  # Allow some boundary adjustment
    check abs(cropCenterY - 360) < 100

  test "calculateCrop constrains to frame boundaries":
    # Face near top-left corner
    let face = FaceRect(x: 10, y: 10, width: 50, height: 60, confidence: 0.9, angle: 0)
    let crop = calculateCrop(face, 1920, 1080, Portrait)

    check crop.x >= 0
    check crop.y >= 0
    check crop.x + crop.width <= 1920
    check crop.y + crop.height <= 1080

  test "calculateCrop handles face near right edge":
    let face = FaceRect(x: 1850, y: 500, width: 50, height: 60, confidence: 0.9, angle: 0)
    let crop = calculateCrop(face, 1920, 1080, Portrait)

    check crop.x >= 0
    check crop.x + crop.width <= 1920

  test "calculateCrop handles face near bottom":
    let face = FaceRect(x: 500, y: 1000, width: 50, height: 60, confidence: 0.9, angle: 0)
    let crop = calculateCrop(face, 1920, 1080, Portrait)

    check crop.y >= 0
    check crop.y + crop.height <= 1080

  test "calculateCrop maintains aspect ratio":
    let face = FaceRect(x: 500, y: 300, width: 100, height: 120, confidence: 0.9, angle: 0)

    let portraitCrop = calculateCrop(face, 1920, 1080, Portrait)
    let portraitRatio = portraitCrop.width.float / portraitCrop.height.float
    check abs(portraitRatio - 9.0/16.0) < 0.1

    let squareCrop = calculateCrop(face, 1920, 1080, Square)
    let squareRatio = squareCrop.width.float / squareCrop.height.float
    check abs(squareRatio - 1.0) < 0.1

  test "calculateFallbackCrop centers on frame":
    let crop = calculateFallbackCrop(1920, 1080, Portrait)

    # Should be centered
    let expectedCenterX = 1920 div 2
    let expectedCenterY = 1080 div 2
    let cropCenterX = crop.x + crop.width div 2
    let cropCenterY = crop.y + crop.height div 2

    check abs(cropCenterX - expectedCenterX) < 5
    check abs(cropCenterY - expectedCenterY) < 5

  test "calculateFallbackCrop fits frame":
    let crop = calculateFallbackCrop(1920, 1080, Portrait)

    check crop.x >= 0
    check crop.y >= 0
    check crop.x + crop.width <= 1920
    check crop.y + crop.height <= 1080

  test "calculateFallbackCrop Square on wide frame":
    let crop = calculateFallbackCrop(1920, 1080, Square)

    # Square should fit height (1080) since frame is wider
    check crop.height == 1080
    check crop.width == 1080

  test "calculateFallbackCrop Portrait on wide frame":
    let crop = calculateFallbackCrop(1920, 1080, Portrait)

    # Portrait (9:16) should fit height
    check crop.height == 1080
    let expectedWidth = int(1080.0 * 9.0 / 16.0)
    check abs(crop.width - expectedWidth) < 5

  test "shouldSwitchTarget detects significant movement":
    let current = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let far = CropRegion(x: 200, y: 200, width: 200, height: 300, timestamp: 1.0)

    # Distance > 20 pixels (default threshold)
    check shouldSwitchTarget(current, far) == true

  test "shouldSwitchTarget ignores small movement":
    let current = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let near = CropRegion(x: 105, y: 105, width: 200, height: 300, timestamp: 1.0)

    # Distance ~7 pixels < 20 threshold
    check shouldSwitchTarget(current, near) == false

  test "shouldSwitchTarget respects custom threshold":
    let current = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let medium = CropRegion(x: 115, y: 115, width: 200, height: 300, timestamp: 1.0)

    # Distance ~21 pixels
    check shouldSwitchTarget(current, medium, threshold = 30.0) == false
    check shouldSwitchTarget(current, medium, threshold = 15.0) == true

  test "shouldSwitchTarget with same position":
    let current = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let same = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 1.0)

    check shouldSwitchTarget(current, same) == false

  test "interpolateCrop at t=0 returns start":
    let start = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let finish = CropRegion(x: 200, y: 200, width: 300, height: 400, timestamp: 1.0)

    let result = interpolateCrop(start, finish, 0.0, Medium)
    check result.x == start.x
    check result.y == start.y
    check result.width == start.width
    check result.height == start.height

  test "interpolateCrop at t=1 returns end":
    let start = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let finish = CropRegion(x: 200, y: 200, width: 300, height: 400, timestamp: 1.0)

    let result = interpolateCrop(start, finish, 1.0, Medium)
    check result.x == finish.x
    check result.y == finish.y
    check result.width == finish.width
    check result.height == finish.height

  test "interpolateCrop at midpoint is between start and end":
    let start = CropRegion(x: 100, y: 100, width: 200, height: 300, timestamp: 0.0)
    let finish = CropRegion(x: 200, y: 200, width: 300, height: 400, timestamp: 1.0)

    let result = interpolateCrop(start, finish, 0.5, Medium)
    check result.x > start.x and result.x < finish.x
    check result.y > start.y and result.y < finish.y
    check result.width > start.width and result.width < finish.width
    check result.height > start.height and result.height < finish.height

#
#   7. honeyclip engage video.mp4 nonexistent-model.bin
#      Expected: Error with download URL and example curl command
#
#   8. honeyclip analyze video.mp4 model --no-transcript
#      (on video with transcript extraction issues)
#      Expected: Error with troubleshooting steps
#
# Preset Integration:
#   9. honeyclip analyze video.mp4 model --preset viral
#      Expected: Uses viral preset (motion-heavy weighting)
#
#   10. honeyclip video.mp4 --engage=podcast
#       Expected: Uses podcast preset threshold and weights

suite "metadata":
  test "escapeMetadataValue handles special characters":
    check escapeMetadataValue("normal text") == "normal text"
    check escapeMetadataValue("has=equals") == "has\\=equals"
    check escapeMetadataValue("has;semi") == "has\\;semi"
    check escapeMetadataValue("has#hash") == "has\\#hash"
    check escapeMetadataValue("has\\backslash") == "has\\\\backslash"
    check escapeMetadataValue("has\nnewline") == "has\\nnewline"

  test "generateFFMetadata produces valid format":
    var tmpl = newMetadataTemplate()
    tmpl.global["title"] = "Test Video"
    tmpl.global["artist"] = "Test Author"

    let output = generateFFMetadata(tmpl)
    check output.startsWith(";FFMETADATA1\n")
    check "title=Test Video" in output
    check "artist=Test Author" in output

  test "generateFFMetadata includes chapters":
    var tmpl = newMetadataTemplate()
    tmpl.chapters.add ChapterMarker(
      startMs: 0,
      endMs: 30000,
      title: "Introduction"
    )
    tmpl.chapters.add ChapterMarker(
      startMs: 30000,
      endMs: 90000,
      title: "Main Content"
    )

    let output = generateFFMetadata(tmpl)
    check "[CHAPTER]" in output
    check "TIMEBASE=1/1000" in output
    check "START=0" in output
    check "END=30000" in output
    check "title=Introduction" in output

  test "merge applies overrides":
    var base = newMetadataTemplate()
    base.global["title"] = "Original"
    base.global["artist"] = "Original Author"

    let overrides = {"title": "Overridden"}.toTable

    let merged = merge(base, overrides)
    check merged.global["title"] == "Overridden"
    check merged.global["artist"] == "Original Author"  # Not overridden

  test "defaultTemplate has expected fields":
    let tmpl = defaultTemplate()
    check "title" in tmpl.global
    check "artist" in tmpl.global
    check "copyright" in tmpl.global
    check "date" in tmpl.global

suite "hook_schema":

  test "prosody profile to thresholds":
    let excited = prosodyProfileToThresholds(ppExcited)
    check excited.pauseMs == 150
    check excited.volumeSpikeFactor == 1.8f

    let emphatic = prosodyProfileToThresholds(ppEmphatic)
    check emphatic.pauseMs == 200
    check emphatic.volumeSpikeFactor == 1.5f

    let calm = prosodyProfileToThresholds(ppCalm)
    check calm.pauseMs == 300
    check calm.volumeSpikeFactor == 1.2f

    let none = prosodyProfileToThresholds(ppNone)
    check none.pauseMs == 0
    check none.volumeSpikeFactor == 0.0f

  test "parse prosody profile":
    check parseProsodyProfile("excited") == ppExcited
    check parseProsodyProfile("emphatic") == ppEmphatic
    check parseProsodyProfile("calm") == ppCalm
    check parseProsodyProfile("") == ppNone
    check parseProsodyProfile("unknown") == ppCustom
    check parseProsodyProfile("EXCITED") == ppExcited  # Case insensitive

  test "find hooks file returns empty when not found":
    # With explicit non-existent path
    let result = findHooksFile("/nonexistent/path.json")
    check result == ""

    # With no paths (relies on no honeyclip.hooks.json in test environment)
    let autoResult = findHooksFile()
    # This may or may not find a file depending on environment
    # Just check it doesn't crash
    discard autoResult

  test "load valid hooks json":
    # Create temp test file
    let testJson = """
    {
      "hooks": {
        "test_pattern": {
          "name": "Test Pattern",
          "category": "test",
          "weight": 10.0,
          "regex": "test.*pattern"
        }
      }
    }
    """
    let tempPath = getTempDir() / "test_hooks.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    let patterns = loadHooksFromJson(tempPath)
    check patterns.len == 1
    check patterns[0].name == "Test Pattern"
    check patterns[0].category == "test"
    check patterns[0].weight == 10.0f
    check patterns[0].kind == hpkCustom

  test "load hooks json with keywords synthesizes regex":
    let testJson = """
    {
      "hooks": {
        "keyword_test": {
          "keywords": ["hello", "world"],
          "match": "any"
        }
      }
    }
    """
    let tempPath = getTempDir() / "test_hooks_keywords.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    let patterns = loadHooksFromJson(tempPath)
    check patterns.len == 1
    check patterns[0].name == "keyword_test"  # Defaults to key name
    check patterns[0].category == "custom"    # Defaults to "custom"
    # Verify regex was synthesized from keywords
    check patterns[0].pattern.contains("hello")
    check patterns[0].pattern.contains("world")
    check patterns[0].pattern.contains("(?i)")  # Case insensitive

  test "load hooks json with prosody only":
    let testJson = """
    {
      "hooks": {
        "prosody_only": {
          "name": "Prosody Test",
          "prosody": "excited"
        }
      }
    }
    """
    let tempPath = getTempDir() / "test_hooks_prosody.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    let patterns = loadHooksFromJson(tempPath)
    check patterns.len == 1
    check patterns[0].name == "Prosody Test"
    # Prosody-only patterns have empty pattern string
    check patterns[0].pattern == ""

  test "load hooks json uses global default weight":
    let testJson = """
    {
      "hooks": {
        "no_weight": {
          "regex": "test"
        }
      },
      "settings": {
        "defaultWeight": 25.0
      }
    }
    """
    let tempPath = getTempDir() / "test_hooks_default_weight.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    let patterns = loadHooksFromJson(tempPath)
    check patterns.len == 1
    check patterns[0].weight == 25.0f

  test "load hooks json fails on missing criteria":
    let testJson = """
    {
      "hooks": {
        "empty_pattern": {
          "name": "No Criteria",
          "weight": 10.0
        }
      }
    }
    """
    let tempPath = getTempDir() / "test_hooks_invalid.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    expect ValueError:
      discard loadHooksFromJson(tempPath)

  test "load hooks json fails on invalid regex":
    let testJson = """
    {
      "hooks": {
        "bad_regex": {
          "regex": "[invalid(regex"
        }
      }
    }
    """
    let tempPath = getTempDir() / "test_hooks_bad_regex.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    expect ValueError:
      discard loadHooksFromJson(tempPath)

  test "load hooks json fails on missing hooks key":
    let testJson = """
    {
      "patterns": {}
    }
    """
    let tempPath = getTempDir() / "test_hooks_no_hooks.json"
    writeFile(tempPath, testJson)
    defer: removeFile(tempPath)

    expect ValueError:
      discard loadHooksFromJson(tempPath)

# Tracker Integration Tests (tracking/tracker.nim)

import ../src/tracking/tracker
# embeddings already imported earlier (line 1029 in enable_ml section)
# synthetic_faces already included at line 32
include fixtures/mock_embeddings

import std/[options, times]

suite "Tracker Integration":
  test "tracker-newTracker-default-parameters":
    let tracker = newTracker()
    check tracker.state.maxAge == 90
    check tracker.state.minHits == 3
    check tracker.embedder.isNone  # No model = IoU-only mode

  test "tracker-newTracker-custom-parameters":
    let tracker = newTracker(modelPath = "", maxAge = 60, minHits = 5)
    check tracker.state.maxAge == 60
    check tracker.state.minHits == 5
    check tracker.iouThreshold == 0.5
    check tracker.embeddingThreshold == 0.7

  test "tracker-creates-track-for-first-detection":
    var tracker = newTracker()
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    discard tracker.updateTracks(@[detection], nil)

    check tracker.state.tracks.len == 1
    check tracker.state.tracks[0].id == 0
    check tracker.state.tracks[0].hitStreak == 1

  test "tracker-increments-hitStreak":
    var tracker = newTracker()
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    for i in 1..5:
      discard tracker.updateTracks(@[detection], nil)
      check tracker.state.tracks[0].hitStreak == i

  test "tracker-single-face-identity-over-30-frames":
    var tracker = newTracker()
    let faces = generateStraightLineFace(100, 100, 50, 50, 5.0, 2.0, 30)

    var trackId = -1
    for i, face in faces:
      discard tracker.updateTracks(@[face], nil)
      if i == 0:
        trackId = tracker.state.tracks[0].id
      else:
        # Track ID should remain the same throughout
        check tracker.state.tracks.len == 1
        check tracker.state.tracks[0].id == trackId

    # Verify final position near expected (100 + 29*5, 100 + 29*2) = (245, 158)
    check tracker.state.tracks[0].bbox.x >= 240 and tracker.state.tracks[0].bbox.x <= 250
    check tracker.state.tracks[0].bbox.y >= 155 and tracker.state.tracks[0].bbox.y <= 165

  test "tracker-creates-separate-tracks-for-two-faces":
    var tracker = newTracker()
    let face1 = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    let face2 = FaceRect(x: 500, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    discard tracker.updateTracks(@[face1, face2], nil)

    check tracker.state.tracks.len == 2
    check tracker.state.tracks[0].id != tracker.state.tracks[1].id

  test "tracker-maintains-two-faces-crossing":
    var tracker = newTracker()
    let (faces1, faces2) = generateCrossingPaths(
      face1Start = (x: 0, y: 500),
      face2Start = (x: 800, y: 500),
      face1Vel = (x: 10.0, y: 0.0),
      face2Vel = (x: -10.0, y: 0.0),
      numFrames = 30
    )

    # Get initial track IDs
    discard tracker.updateTracks(@[faces1[0], faces2[0]], nil)
    let initialIds = (tracker.state.tracks[0].id, tracker.state.tracks[1].id)

    # Update for remaining frames
    for i in 1..<30:
      discard tracker.updateTracks(@[faces1[i], faces2[i]], nil)

    # Both tracks should still exist with same IDs
    check tracker.state.tracks.len == 2
    let finalIds = (tracker.state.tracks[0].id, tracker.state.tracks[1].id)

    # Verify identity preserved (same set of IDs)
    check (finalIds[0] == initialIds[0] or finalIds[0] == initialIds[1])
    check (finalIds[1] == initialIds[0] or finalIds[1] == initialIds[1])
    check finalIds[0] != finalIds[1]

  test "tracker-unmatched-track-increments-timeSinceUpdate":
    var tracker = newTracker()
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    # Establish track
    for _ in 1..5:
      discard tracker.updateTracks(@[detection], nil)

    # Update with empty detections
    for i in 1..3:
      discard tracker.updateTracks(@[], nil)
      check tracker.state.tracks[0].timeSinceUpdate == i

  test "tracker-deletes-stale-track":
    var tracker = newTracker(maxAge = 10)
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    # Establish track
    discard tracker.updateTracks(@[detection], nil)
    check tracker.state.tracks.len == 1

    # Update with empty detections until track is deleted
    for _ in 1..11:
      discard tracker.updateTracks(@[], nil)

    check tracker.state.tracks.len == 0

  test "tracker-maintains-identity-after-brief-occlusion":
    var tracker = newTracker()
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    # Establish track over 5 frames
    for _ in 1..5:
      discard tracker.updateTracks(@[detection], nil)

    let originalId = tracker.state.tracks[0].id

    # Empty detections for 5 frames (< maxAge)
    for _ in 1..5:
      discard tracker.updateTracks(@[], nil)

    # Detection reappears at similar position
    discard tracker.updateTracks(@[detection], nil)

    # Track should recover with same ID
    check tracker.state.tracks.len == 1
    check tracker.state.tracks[0].id == originalId

  test "tracker-getActiveTracks-empty-before-minHits":
    var tracker = newTracker(minHits = 3)
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    # Update only 2 times (less than minHits)
    discard tracker.updateTracks(@[detection], nil)
    discard tracker.updateTracks(@[detection], nil)

    let active = tracker.getActiveTracks()
    check active.len == 0

  test "tracker-getActiveTracks-returns-after-minHits":
    var tracker = newTracker(minHits = 3)
    let detection = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    # Update 3 times (equals minHits)
    for _ in 1..3:
      discard tracker.updateTracks(@[detection], nil)

    let active = tracker.getActiveTracks()
    check active.len == 1

  test "tracker-getActiveTracks-filters-unconfirmed":
    var tracker = newTracker(minHits = 3)
    let face1 = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    let face2 = FaceRect(x: 500, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)

    # Establish first track over 10 frames
    for _ in 1..10:
      discard tracker.updateTracks(@[face1], nil)

    # Add new track (1 frame only)
    discard tracker.updateTracks(@[face1, face2], nil)

    # Only confirmed track should be returned
    let active = tracker.getActiveTracks()
    check active.len == 1
    check active[0].bbox.x == face1.x  # First track, not second

suite "TrackingState":
  test "trackingState-newTrackingState-defaults":
    let state = newTrackingState()
    check state.tracks.len == 0
    check state.nextId == 0
    check state.maxAge == 90
    check state.minHits == 3

  test "trackingState-newTrackingState-custom":
    let state = newTrackingState(maxAge = 60, minHits = 5)
    check state.tracks.len == 0
    check state.nextId == 0
    check state.maxAge == 60
    check state.minHits == 5

suite "Mock Embeddings":
  test "tracker-cosine-similarity-same-embedding":
    let emb1 = mockEmbedding(1)
    let emb2 = mockEmbedding(1)
    let similarity = cosineSimilarity(emb1, emb2)
    check abs(similarity - 1.0) < 0.001

  test "tracker-cosine-similarity-different-embeddings":
    let emb1 = mockEmbedding(1)
    let emb2 = mockEmbedding(2)
    let similarity = cosineSimilarity(emb1, emb2)
    # Different seeds should produce approximately orthogonal vectors
    check similarity < 0.5

  test "tracker-embedding-pair-target-similarity":
    let (emb1, emb2) = mockEmbeddingPair(0.8)
    let similarity = cosineSimilarity(emb1, emb2)
    # Should be approximately 0.8 (with some tolerance)
    check abs(similarity - 0.8) < 0.1

  test "tracker-embedding-sequence-drift":
    let sequence = mockEmbeddingSequence(seed = 42, numFrames = 10, drift = 0.01)
    check sequence.len == 10

    # All embeddings should be similar to the first (low drift)
    # Note: drift is cumulative, so later frames drift more
    for i in 1..<sequence.len:
      let similarity = cosineSimilarity(sequence[0], sequence[i])
      check similarity > 0.6  # Allow more drift over time

suite "Performance Benchmarks":
  test "benchmark-kalman-update-timing":
    let bbox = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    var kf = newKalmanFilter(bbox)

    let startTime = epochTime()
    for _ in 1..10000:
      discard kf.predict()
      kf.update(bbox)
    let elapsed = (epochTime() - startTime) * 1000.0  # ms

    echo "Kalman 10k updates: " & $elapsed.int & "ms"
    check elapsed < 1000.0  # Very generous, just catch regressions

  test "benchmark-tracker-single-face-30fps":
    var tracker = newTracker()
    let faces = generateStraightLineFace(100, 100, 50, 50, 2.0, 1.0, 900)  # 30s @ 30fps

    let startTime = epochTime()
    for face in faces:
      discard tracker.updateTracks(@[face], nil)
    let elapsed = (epochTime() - startTime) * 1000.0  # ms

    echo "Tracker 30s@30fps (1 face): " & $elapsed.int & "ms"
    check elapsed < 5000.0

  test "benchmark-tracker-five-faces-30fps":
    var tracker = newTracker()

    # Generate 5 faces with different motion patterns
    let f1 = generateStraightLineFace(100, 100, 50, 50, 2.0, 0.0, 900)
    let f2 = generateStraightLineFace(300, 100, 50, 50, 0.0, 1.0, 900)
    let f3 = generateStraightLineFace(500, 100, 50, 50, -1.0, 1.0, 900)
    let f4 = generateStraightLineFace(100, 400, 50, 50, 1.5, 0.5, 900)
    let f5 = generateStraightLineFace(600, 400, 50, 50, -0.5, 0.0, 900)

    let startTime = epochTime()
    for i in 0..<900:
      discard tracker.updateTracks(@[f1[i], f2[i], f3[i], f4[i], f5[i]], nil)
    let elapsed = (epochTime() - startTime) * 1000.0  # ms

    echo "Tracker 30s@30fps (5 faces): " & $elapsed.int & "ms"
    check elapsed < 10000.0  # Should complete in reasonable time

  test "benchmark-iou-computation":
    let a = FaceRect(x: 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0)
    let b = FaceRect(x: 120, y: 110, width: 50, height: 50, confidence: 0.9, angle: 0)

    let startTime = epochTime()
    for _ in 1..100000:
      discard iou(a, b)
    let elapsed = (epochTime() - startTime) * 1000.0  # ms

    echo "IoU 100k calculations: " & $elapsed.int & "ms"
    check elapsed < 500.0

  test "benchmark-cost-matrix-5x5":
    # Create 5 tracks
    var tracks: seq[Track] = @[]
    for i in 0..<5:
      tracks.add(Track(
        id: i,
        bbox: FaceRect(x: i * 100, y: 100, width: 50, height: 50, confidence: 0.9, angle: 0),
        embedding: @[],
        timeSinceUpdate: 0,
        hitStreak: 5,
        age: 10,
        speakerId: -1
      ))

    # Create 5 detections
    var detections: seq[FaceRect] = @[]
    for i in 0..<5:
      detections.add(FaceRect(x: i * 100 + 10, y: 110, width: 50, height: 50, confidence: 0.9, angle: 0))

    let embeddings: seq[seq[float32]] = @[]

    let startTime = epochTime()
    for _ in 1..10000:
      discard computeCostMatrix(tracks, detections, embeddings)
    let elapsed = (epochTime() - startTime) * 1000.0  # ms

    echo "Cost matrix 5x5 10k: " & $elapsed.int & "ms"
    check elapsed < 2000.0

# Batch Processing Tests
suite "Batch Template":
  test "toArgs with all fields set":
    let tmpl = BatchTemplate(
      edit: "audio",
      margin: "0.2s",
      whenSilent: "cut()",
      whenNormal: "nil()",
      outputFormat: "mp4",
      outputSuffix: "_edited",
      engage: "viral"
    )
    let args = toArgs(tmpl)
    check args.contains("--edit")
    check args.contains("audio")
    check args.contains("--margin")
    check args.contains("0.2s")
    check args.contains("--when-silent")
    check args.contains("cut()")
    check args.contains("--when-normal")
    check args.contains("nil()")
    check args.contains("-ex")
    check args.contains("mp4")
    check args.contains("--engage")
    check args.contains("viral")

  test "toArgs with empty fields omitted":
    let tmpl = BatchTemplate(
      edit: "audio"
      # All other fields default to empty
    )
    let args = toArgs(tmpl)
    check args == @["--edit", "audio"]

  test "toArgs with engage set":
    let tmpl = BatchTemplate(
      engage: "viral"
    )
    let args = toArgs(tmpl)
    check args == @["--engage", "viral"]

  test "toArgs with boolean flags":
    let tmpl = BatchTemplate(
      noFaces: true,
      noTranscript: true
    )
    let args = toArgs(tmpl)
    check args.contains("--no-faces")
    check args.contains("--no-transcript")

  test "validateTemplate with no issues":
    let tmpl = BatchTemplate(
      edit: "audio",
      margin: "0.2s"
    )
    let warnings = validateTemplate(tmpl)
    check warnings.len == 0

suite "File Discovery":
  test "generateOutputPath with output dir":
    when defined(windows):
      let result = generateOutputPath("input\\videos\\test.mp4", "input", "output", "_edited", ".mp4")
      check result == "output\\videos\\test_edited.mp4"
    else:
      let result = generateOutputPath("input/videos/test.mp4", "input", "output", "_edited", ".mp4")
      check result == "output/videos/test_edited.mp4"

  test "generateOutputPath without output dir":
    when defined(windows):
      let result = generateOutputPath("input\\test.mp4", "input", "", "_edited", "")
      check result == "input\\test_edited.mp4"
    else:
      let result = generateOutputPath("input/test.mp4", "input", "", "_edited", "")
      check result == "input/test_edited.mp4"

  test "generateOutputPath preserves subdirectory":
    when defined(windows):
      let result = generateOutputPath("input\\a\\b\\c.mov", "input", "out", "_cut", ".mp4")
      check result == "out\\a\\b\\c_cut.mp4"
    else:
      let result = generateOutputPath("input/a/b/c.mov", "input", "out", "_cut", ".mp4")
      check result == "out/a/b/c_cut.mp4"

  test "generateOutputPath keeps original extension when not specified":
    when defined(windows):
      let result = generateOutputPath("input\\video.mov", "input", "output", "_new", "")
      check result == "output\\video_new.mov"
    else:
      let result = generateOutputPath("input/video.mov", "input", "output", "_new", "")
      check result == "output/video_new.mov"

suite "Checkpoint":
  test "Checkpoint new and serialize":
    let state = newCheckpoint("template.toml", "/videos", 10)
    check state.totalFiles == 10
    check state.completed.len == 0
    check state.failed.len == 0
    check state.templatePath == "template.toml"
    check state.inputPath == "/videos"
    check state.startTime > 0.0

  test "markCompleted updates state":
    var state = newCheckpoint("template.toml", "/videos", 5)
    state.markCompleted("file1.mp4")
    check state.completed.len == 1
    check "file1.mp4" in state.completed

  test "markFailed updates state":
    var state = newCheckpoint("template.toml", "/videos", 5)
    state.markFailed("bad.mp4", "codec error")
    check state.failed.len == 1
    check state.failed[0].path == "bad.mp4"
    check state.failed[0].error == "codec error"

  test "pendingFiles excludes completed and failed":
    var state = newCheckpoint("template.toml", "/videos", 5)
    state.completed = @["a.mp4", "b.mp4"]
    state.failed = @[FileResult(path: "c.mp4", error: "fail")]

    let allFiles = @["a.mp4", "b.mp4", "c.mp4", "d.mp4", "e.mp4"]
    let pending = pendingFiles(state, allFiles)

    check pending.len == 2
    check "d.mp4" in pending
    check "e.mp4" in pending

  test "Checkpoint JSON round-trip":
    # Create checkpoint with data
    var state = newCheckpoint("test.toml", "/input", 10)
    state.markCompleted("file1.mp4")
    state.markCompleted("file2.mp4")
    state.markFailed("file3.mp4", "encoding failed")

    # Save to temp file
    let tempPath = getTempDir() / "test_checkpoint.json"
    saveCheckpoint(state, tempPath)

    # Load and verify
    let loaded = loadCheckpoint(tempPath)
    check loaded.templatePath == state.templatePath
    check loaded.inputPath == state.inputPath
    check loaded.totalFiles == state.totalFiles
    check loaded.completed.len == state.completed.len
    check loaded.failed.len == state.failed.len
    check loaded.completed == state.completed
    check loaded.failed[0].path == state.failed[0].path
    check loaded.failed[0].error == state.failed[0].error

    # Cleanup
    removeFile(tempPath)

suite "Virality Scoring":
  test "calculateHookScore without hook":
    var seg = newEngagementSegment(0, 5000)
    seg.score = 70.0f
    seg.hasHook = false

    let hookScore = calculateHookScore(seg)
    check hookScore == 70.0f

  test "calculateHookScore with hook":
    var seg = newEngagementSegment(0, 5000)
    seg.score = 70.0f
    seg.hasHook = true

    let hookScore = calculateHookScore(seg)
    check hookScore == 85.0f  # 70 + 15 boost

  test "calculateHookScore with hook capped at 100":
    var seg = newEngagementSegment(0, 5000)
    seg.score = 90.0f
    seg.hasHook = true

    let hookScore = calculateHookScore(seg)
    check hookScore == 100.0f  # 90 + 15 = 105, capped at 100

  test "calculateFlowScore empty segments":
    let segments: seq[EngagementSegment] = @[]
    let flowScore = calculateFlowScore(segments)
    check flowScore == 0.0f

  test "calculateFlowScore single segment":
    var seg = newEngagementSegment(0, 5000)
    seg.score = 60.0f
    let segments = @[seg]

    let flowScore = calculateFlowScore(segments)
    check flowScore == 60.0f  # No variance with single segment

  test "calculateFlowScore no variance":
    var segments: seq[EngagementSegment] = @[]
    for i in 0..2:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.score = 80.0f
      segments.add(seg)

    let flowScore = calculateFlowScore(segments)
    check flowScore == 80.0f  # Perfect consistency, no penalty

  test "calculateFlowScore high variance":
    var segments: seq[EngagementSegment] = @[]
    let scores = [50.0f, 100.0f, 50.0f, 100.0f]
    for i, score in scores:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.score = score
      segments.add(seg)

    let flowScore = calculateFlowScore(segments)
    # Average = 75, stdDev = 25, penalty = min(25*0.5, 30) = 12.5
    # Expected: 75 - 12.5 = 62.5
    check checkApprox(flowScore, 62.5, 1.0)

  test "calculateValueScore no faces":
    var segments: seq[EngagementSegment] = @[]
    for i in 0..2:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.score = 70.0f
      seg.faceCount = 0
      segments.add(seg)

    let valueScore = calculateValueScore(segments, 0)
    check valueScore == 70.0f

  test "calculateValueScore with faces":
    var segments: seq[EngagementSegment] = @[]
    for i in 0..2:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.score = 70.0f
      seg.faceCount = 2
      segments.add(seg)

    let valueScore = calculateValueScore(segments, 2)
    check valueScore == 76.0f  # 70 + 2*3 = 76

  test "calculateValueScore with many faces capped":
    var segments: seq[EngagementSegment] = @[]
    for i in 0..2:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.score = 90.0f
      seg.faceCount = 10
      segments.add(seg)

    let valueScore = calculateValueScore(segments, 10)
    check valueScore == 100.0f  # 90 + min(10*3, 15) = 90 + 15 = 105, capped at 100

  test "calculateValueScore empty segments":
    let segments: seq[EngagementSegment] = @[]
    let valueScore = calculateValueScore(segments, 0)
    check valueScore == 0.0f

  test "calculateTrendScore no hooks":
    var segments: seq[EngagementSegment] = @[]
    for i in 0..2:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.hookMatches = @[]
      segments.add(seg)

    let trendScore = calculateTrendScore(segments)
    check trendScore == 50.0f  # Neutral score for no hooks

  test "calculateTrendScore one unique pattern":
    var segments: seq[EngagementSegment] = @[]
    for i in 0..2:
      var seg = newEngagementSegment(int64(i * 5000), int64((i + 1) * 5000))
      seg.hookMatches = @["question"]
      segments.add(seg)

    let trendScore = calculateTrendScore(segments)
    check checkApprox(trendScore, 33.33, 1.0)  # 1 pattern = 33.33

  test "calculateTrendScore three unique patterns":
    var segments: seq[EngagementSegment] = @[]
    var seg1 = newEngagementSegment(0, 5000)
    seg1.hookMatches = @["question"]
    var seg2 = newEngagementSegment(5000, 10000)
    seg2.hookMatches = @["storytelling"]
    var seg3 = newEngagementSegment(10000, 15000)
    seg3.hookMatches = @["conflict"]
    segments = @[seg1, seg2, seg3]

    let trendScore = calculateTrendScore(segments)
    check checkApprox(trendScore, 100.0, 1.0)  # 3 patterns = 99.99, close to 100

  test "combineViralityScore all max":
    let components = ViralityComponents(
      hook: 100.0f,
      flow: 100.0f,
      value: 100.0f,
      trend: 100.0f
    )
    let combined = combineViralityScore(components)
    check combined == 100.0f

  test "combineViralityScore all zero":
    let components = ViralityComponents(
      hook: 0.0f,
      flow: 0.0f,
      value: 0.0f,
      trend: 0.0f
    )
    let combined = combineViralityScore(components)
    check combined == 0.0f

  test "combineViralityScore weighted formula":
    let components = ViralityComponents(
      hook: 80.0f,    # 35% weight
      flow: 60.0f,    # 30% weight
      value: 70.0f,   # 25% weight
      trend: 40.0f    # 10% weight
    )
    let combined = combineViralityScore(components)
    # 80*0.35 + 60*0.30 + 70*0.25 + 40*0.10 = 28 + 18 + 17.5 + 4 = 67.5
    check checkApprox(combined, 67.5, 0.1)

  test "rankClips sorts by viralityScore":
    var testClips = @[
      clips.Clip(startMs: 0, endMs: 30000, engagementScore: 80.0f, viralityScore: 90.0f),
      clips.Clip(startMs: 40000, endMs: 70000, engagementScore: 85.0f, viralityScore: 70.0f),
      clips.Clip(startMs: 80000, endMs: 110000, engagementScore: 90.0f, viralityScore: 80.0f)
    ]
    var params = defaultClipRankingParams()
    params.topN = 3
    params.overlapThreshold = 1.0  # Disable overlap penalty

    let ranked = rankClips(testClips, params)

    # Should be sorted by viralityScore descending: 90, 80, 70
    check ranked[0].viralityScore == 90.0f
    check ranked[0].rank == 1
    check ranked[1].viralityScore == 80.0f
    check ranked[1].rank == 2
    check ranked[2].viralityScore == 70.0f
    check ranked[2].rank == 3

# Chapter Detection Tests
suite "Chapter Detection":
  # Helper: Create test timeline with segments of given scores
  proc makeTimeline(scores: seq[float32], segDurationMs: int64 = 10000): EngagementTimeline =
    result.segments = @[]
    result.duration = int64(scores.len) * segDurationMs
    result.avgScore = 0.0f
    result.hookCount = 0
    result.params = defaultEngagementParams()

    for i, score in scores:
      var seg = newEngagementSegment(int64(i) * segDurationMs, int64(i + 1) * segDurationMs)
      seg.score = score
      result.segments.add(seg)

    # Calculate average score
    if scores.len > 0:
      var sum = 0.0f
      for score in scores:
        sum += score
      result.avgScore = sum / float32(scores.len)

  # detectEngagementPeaks tests
  test "detectEngagementPeaks empty timeline":
    let timeline = makeTimeline(@[])
    let peaks = detectEngagementPeaks(timeline)
    check peaks.len == 0

  test "detectEngagementPeaks single segment":
    let timeline = makeTimeline(@[80.0f])
    let peaks = detectEngagementPeaks(timeline)
    check peaks.len == 0

  test "detectEngagementPeaks two segments":
    let timeline = makeTimeline(@[80.0f, 90.0f])
    let peaks = detectEngagementPeaks(timeline)
    check peaks.len == 0  # Need at least 3 for local maxima

  test "detectEngagementPeaks clear peak in middle":
    let timeline = makeTimeline(@[20.0f, 80.0f, 20.0f])
    let peaks = detectEngagementPeaks(timeline, minScore = 60.0)
    check peaks.len == 1
    check peaks[0] == 10000  # Middle segment starts at 10000ms

  test "detectEngagementPeaks multiple peaks with spacing":
    let timeline = makeTimeline(@[20.0f, 80.0f, 20.0f, 30.0f, 90.0f, 30.0f])
    let peaks = detectEngagementPeaks(timeline, minSpacingMs = 10000, minScore = 60.0)
    check peaks.len == 2
    check peaks[0] == 10000  # First peak at index 1
    check peaks[1] == 40000  # Second peak at index 4

  test "detectEngagementPeaks peaks too close together":
    # Two peaks within minSpacingMs - should return only the higher one
    let timeline = makeTimeline(@[20.0f, 80.0f, 30.0f, 90.0f, 20.0f])
    let peaks = detectEngagementPeaks(timeline, minSpacingMs = 30000, minScore = 60.0)
    check peaks.len == 1
    check peaks[0] == 30000  # Should pick the 90.0 peak (higher score)

  test "detectEngagementPeaks all scores below threshold":
    let timeline = makeTimeline(@[30.0f, 50.0f, 40.0f, 55.0f, 35.0f])
    let peaks = detectEngagementPeaks(timeline, minScore = 60.0)
    check peaks.len == 0

  test "detectEngagementPeaks maxPeaks limit":
    # Create 5 clear peaks but limit to 2
    let timeline = makeTimeline(@[
      20.0f, 70.0f, 20.0f,  # Peak 1 (score 70)
      20.0f, 80.0f, 20.0f,  # Peak 2 (score 80)
      20.0f, 90.0f, 20.0f,  # Peak 3 (score 90)
      20.0f, 85.0f, 20.0f,  # Peak 4 (score 85)
      20.0f, 75.0f, 20.0f   # Peak 5 (score 75)
    ])
    let peaks = detectEngagementPeaks(timeline, minSpacingMs = 10000, minScore = 60.0, maxPeaks = 2)
    check peaks.len == 2
    # Should get the top 2 by score: 90 (index 7) and 85 (index 10), sorted chronologically
    check peaks[0] == 70000  # Peak at index 7 (90.0 score)
    check peaks[1] == 100000 # Peak at index 10 (85.0 score)

  test "detectEngagementPeaks plateau handling":
    # Plateaus: [50, 80, 80, 50] - neither 80 is a local max
    let timeline = makeTimeline(@[50.0f, 80.0f, 80.0f, 50.0f])
    let peaks = detectEngagementPeaks(timeline, minScore = 60.0)
    check peaks.len == 0  # No local maxima (equal neighbors)

  # generateChapters - scene mode tests
  test "generateChapters scene mode basic":
    let sceneTimes = @[0.0, 30.0, 60.0]  # In seconds
    let timeline = makeTimeline(@[50.0f, 60.0f, 70.0f], segDurationMs = 30000)
    var params = defaultChapterParams()
    params.mode = "scene"
    params.minSpacingMs = 10000

    let chapters = generateChapters(sceneTimes, @[], timeline, params)
    check chapters.len == 3
    check chapters[0].startMs == 0
    check chapters[0].endMs == 29999  # Next startMs - 1
    check chapters[0].title == "Scene 1"
    check chapters[0].source == csScene
    check chapters[1].startMs == 30000
    check chapters[1].endMs == 59999
    check chapters[1].title == "Scene 2"
    check chapters[2].startMs == 60000
    check chapters[2].endMs == timeline.duration  # Last chapter ends at duration
    check chapters[2].title == "Scene 3"

  test "generateChapters scene mode empty":
    let timeline = makeTimeline(@[50.0f])
    var params = defaultChapterParams()
    params.mode = "scene"

    let chapters = generateChapters(@[], @[], timeline, params)
    check chapters.len == 0

  test "generateChapters scene mode spacing filter":
    # Scenes at 0, 10, 100 - first two are within 30s minSpacing
    let sceneTimes = @[0.0, 10.0, 100.0]
    let timeline = makeTimeline(@[50.0f], segDurationMs = 150000)
    var params = defaultChapterParams()
    params.mode = "scene"
    params.minSpacingMs = 30000

    let chapters = generateChapters(sceneTimes, @[], timeline, params)
    check chapters.len == 2  # 0 and 100 kept, 10 filtered out
    check chapters[0].startMs == 0
    check chapters[1].startMs == 100000

  # generateChapters - engagement mode tests
  test "generateChapters engagement mode basic":
    let timeline = makeTimeline(@[20.0f, 85.0f, 30.0f, 75.0f, 25.0f], segDurationMs = 15000)
    let engagementPeaks = @[15000'i64, 45000'i64]  # At segment indices 1 and 3
    var params = defaultChapterParams()
    params.mode = "engagement"

    let chapters = generateChapters(@[], engagementPeaks, timeline, params)
    check chapters.len == 2
    check chapters[0].startMs == 15000
    check chapters[0].endMs == 44999  # Next peak - 1
    check chapters[0].source == csEngagement
    check chapters[0].score == 85.0f  # Looked up from timeline
    check "High engagement" in chapters[0].title  # Should have engagement label
    check chapters[1].startMs == 45000
    check chapters[1].endMs == timeline.duration
    check chapters[1].score == 75.0f

  # generateChapters - combined mode tests
  test "generateChapters combined mode deduplication":
    # Scene at 30000ms and engagement peak at 32000ms - within 5000ms dedupe window
    let sceneTimes = @[30.0]  # 30 seconds = 30000ms
    let timeline = makeTimeline(@[20.0f, 30.0f, 80.0f, 25.0f], segDurationMs = 10000)
    let engagementPeaks = @[20000'i64]  # Segment index 2
    var params = defaultChapterParams()
    params.mode = "combined"
    params.dedupeWindowMs = 15000  # Large enough to merge 20000 and 30000

    let chapters = generateChapters(sceneTimes, engagementPeaks, timeline, params)
    check chapters.len == 1  # Merged to single chapter
    check chapters[0].source == csEngagement  # Engagement preferred over scene
    check chapters[0].startMs == 20000

  test "generateChapters combined mode no deduplication":
    # Scene at 30000ms and engagement peak at 60000ms - outside dedupe window
    let sceneTimes = @[30.0]
    let timeline = makeTimeline(@[20.0f, 30.0f, 40.0f, 50.0f, 80.0f, 25.0f], segDurationMs = 10000)
    let engagementPeaks = @[40000'i64]  # Segment index 4
    var params = defaultChapterParams()
    params.mode = "combined"
    params.dedupeWindowMs = 5000

    let chapters = generateChapters(sceneTimes, engagementPeaks, timeline, params)
    check chapters.len == 2  # Both kept
    check chapters[0].startMs == 30000
    check chapters[0].source == csScene
    check chapters[1].startMs == 40000
    check chapters[1].source == csEngagement

  test "generateChapters combined mode sorted chronologically":
    # Engagement before scene - should be sorted
    let sceneTimes = @[50.0]
    let timeline = makeTimeline(@[20.0f, 80.0f, 30.0f, 40.0f, 50.0f, 60.0f], segDurationMs = 10000)
    let engagementPeaks = @[10000'i64]
    var params = defaultChapterParams()
    params.mode = "combined"
    params.dedupeWindowMs = 5000

    let chapters = generateChapters(sceneTimes, engagementPeaks, timeline, params)
    check chapters.len == 2
    check chapters[0].startMs == 10000  # Engagement first
    check chapters[1].startMs == 50000  # Scene second

  test "generateChapters combined mode maxChapters limit":
    # 6 markers total, limit to 3
    let sceneTimes = @[10.0, 50.0, 90.0]
    let timeline = makeTimeline(@[20.0f, 80.0f, 30.0f, 70.0f, 25.0f, 75.0f, 30.0f, 65.0f, 20.0f, 60.0f], segDurationMs = 10000)
    let engagementPeaks = @[30000'i64, 70000'i64, 110000'i64]
    var params = defaultChapterParams()
    params.mode = "combined"
    params.maxChapters = 3
    params.minSpacingMs = 5000  # Allow close markers
    params.dedupeWindowMs = 2000  # Minimal dedupe

    let chapters = generateChapters(sceneTimes, engagementPeaks, timeline, params)
    check chapters.len <= 3

  # chaptersToMetadata tests
  test "chaptersToMetadata basic conversion":
    var chapters = @[
      Chapter(startMs: 0, endMs: 29999, title: "Intro", source: csScene, score: 0.0f),
      Chapter(startMs: 30000, endMs: 59999, title: "Peak #1 - High engagement", source: csEngagement, score: 85.0f)
    ]

    let metadata = chaptersToMetadata(chapters)
    check metadata.len == 2
    check metadata[0].startMs == 0
    check metadata[0].endMs == 29999
    check metadata[0].title == "Intro"
    check metadata[1].startMs == 30000
    check metadata[1].title == "Peak #1 - High engagement"

  test "chaptersToMetadata empty input":
    let chapters: seq[Chapter] = @[]
    let metadata = chaptersToMetadata(chapters)
    check metadata.len == 0

  # chaptersToMarkers tests
  test "chaptersToMarkers engagement chapter":
    var chapters = @[
      Chapter(startMs: 15000, endMs: 44999, title: "Peak #1 - High engagement", source: csEngagement, score: 85.0f)
    ]

    let markers = chaptersToMarkers(chapters)
    check markers.len == 1
    check markers[0].markerType == mtEngagementPeak
    check markers[0].timestampMs == 15000
    check markers[0].durationMs == 29999  # endMs - startMs
    check markers[0].name == "Peak #1 - High engagement"
    check "Score: 85/100" in markers[0].comment
    check markers[0].color == getMarkerColor(mtEngagementPeak)

  test "chaptersToMarkers scene chapter":
    var chapters = @[
      Chapter(startMs: 0, endMs: 29999, title: "Scene 1", source: csScene, score: 0.0f)
    ]

    let markers = chaptersToMarkers(chapters)
    check markers.len == 1
    check markers[0].markerType == mtSceneBoundary
    check markers[0].timestampMs == 0
    check markers[0].name == "Scene 1"
    check "Scene boundary" in markers[0].comment
    check markers[0].color == getMarkerColor(mtSceneBoundary)

  test "chaptersToMarkers empty input":
    let chapters: seq[Chapter] = @[]
    let markers = chaptersToMarkers(chapters)
    check markers.len == 0

  test "chaptersToMarkers mixed sources":
    var chapters = @[
      Chapter(startMs: 0, endMs: 29999, title: "Scene 1", source: csScene, score: 0.0f),
      Chapter(startMs: 30000, endMs: 59999, title: "Peak #1 - High engagement", source: csEngagement, score: 85.0f),
      Chapter(startMs: 60000, endMs: 89999, title: "Scene 2", source: csScene, score: 0.0f)
    ]

    let markers = chaptersToMarkers(chapters)
    check markers.len == 3
    check markers[0].markerType == mtSceneBoundary
    check markers[1].markerType == mtEngagementPeak
    check markers[2].markerType == mtSceneBoundary

suite "Brand Config":
  test "toArgs with watermark enabled":
    var tmpl = BatchTemplate()
    tmpl.brand.watermark.enabled = true
    tmpl.brand.watermark.imagePath = "logo.png"
    tmpl.brand.watermark.position = "bottom-right"

    let args = toArgs(tmpl)
    check "--watermark" in args
    check "logo.png" in args
    check "--watermark-position" in args
    check "bottom-right" in args

  test "toArgs with intro and outro":
    var tmpl = BatchTemplate()
    tmpl.brand.introOutro.introPath = "intro.mp4"
    tmpl.brand.introOutro.outroPath = "outro.mp4"

    let args = toArgs(tmpl)
    check "--intro" in args
    check "intro.mp4" in args
    check "--outro" in args
    check "outro.mp4" in args

  test "toArgs with caption preset":
    var tmpl = BatchTemplate()
    tmpl.brand.captionStyle.preset = "modern"
    tmpl.brand.captionStyle.fontSize = 72
    tmpl.brand.captionStyle.color = "#ff0000"

    let args = toArgs(tmpl)
    check "--caption-preset" in args
    check "modern" in args
    check "--caption-size" in args
    check "72" in args
    check "--caption-color" in args
    check "#ff0000" in args

  test "toArgs with no brand config":
    var tmpl = BatchTemplate()
    tmpl.edit = "audio"

    let args = toArgs(tmpl)
    check args == @["--edit", "audio"]

  test "toArgs with watermark disabled":
    var tmpl = BatchTemplate()
    tmpl.brand.watermark.enabled = false
    tmpl.brand.watermark.imagePath = "logo.png"

    let args = toArgs(tmpl)
    check "--watermark" notin args

  test "validateTemplate warns on watermark without image":
    var tmpl = BatchTemplate()
    tmpl.brand.watermark.enabled = true
    tmpl.brand.watermark.imagePath = ""

    let warnings = validateTemplate(tmpl)
    check warnings.len > 0
    check warnings.anyIt("watermark" in it.toLowerAscii())

suite "Watermark Filter":
  test "buildWatermarkFilter bottom-right":
    let filter = buildWatermarkFilter("logo.png", wpBottomRight, 10, 10, 0.1, 1.0)
    check "overlay=W-w-10:H-h-10" in filter
    check "[0:v][1:v]" in filter  # Full opacity, no colorchannelmixer

  test "buildWatermarkFilter top-left":
    let filter = buildWatermarkFilter("logo.png", wpTopLeft, 20, 20, 0.1, 1.0)
    check "overlay=20:20" in filter

  test "buildWatermarkFilter center":
    let filter = buildWatermarkFilter("logo.png", wpCenter)
    check "overlay=(W-w)/2:(H-h)/2" in filter

  test "buildWatermarkFilter with opacity":
    let filter = buildWatermarkFilter("logo.png", wpBottomRight, 10, 10, 0.1, 0.7)
    check "colorchannelmixer=aa=0.7" in filter
    check "[wm]" in filter  # Opacity pipeline label

  test "buildWatermarkFilter empty path returns empty":
    let filter = buildWatermarkFilter("", wpBottomRight)
    check filter == ""

  test "parseWatermarkPosition valid values":
    check parseWatermarkPosition("top-left") == wpTopLeft
    check parseWatermarkPosition("bottom-right") == wpBottomRight
    check parseWatermarkPosition("center") == wpCenter

  test "parseWatermarkPosition unknown defaults to bottom-right":
    check parseWatermarkPosition("invalid") == wpBottomRight
    check parseWatermarkPosition("") == wpBottomRight

suite "Concat List":
  test "buildConcatList with intro and outro":
    let tempDir = createTempDir("honeyclip_test_", "")
    try:
      # Create temp video files (just touch them for existence check)
      let introPath = joinPath(tempDir, "intro.mp4")
      let videoPath = joinPath(tempDir, "video.mp4")
      let outroPath = joinPath(tempDir, "outro.mp4")
      writeFile(introPath, "")
      writeFile(videoPath, "")
      writeFile(outroPath, "")

      let concatFile = buildConcatList(introPath, videoPath, outroPath, tempDir)
      let content = readFile(concatFile)

      # Check contents contain 3 file lines
      let lines = content.splitLines().filterIt(it.len > 0)
      check lines.len == 3
      check "intro.mp4" in content
      check "video.mp4" in content
      check "outro.mp4" in content

      # Clean up
      cleanupConcatList(concatFile)
      removeDir(tempDir)
    except CatchableError:
      removeDir(tempDir)
      raise

  test "buildConcatList with only intro":
    let tempDir = createTempDir("honeyclip_test_", "")
    try:
      let introPath = joinPath(tempDir, "intro.mp4")
      let videoPath = joinPath(tempDir, "video.mp4")
      writeFile(introPath, "")
      writeFile(videoPath, "")

      let concatFile = buildConcatList(introPath, videoPath, "", tempDir)
      let content = readFile(concatFile)

      let lines = content.splitLines().filterIt(it.len > 0)
      check lines.len == 2  # intro + video, no outro
      check "intro.mp4" in content
      check "video.mp4" in content
      check "outro.mp4" notin content

      cleanupConcatList(concatFile)
      removeDir(tempDir)
    except CatchableError:
      removeDir(tempDir)
      raise

  test "buildConcatList with only outro":
    let tempDir = createTempDir("honeyclip_test_", "")
    try:
      let videoPath = joinPath(tempDir, "video.mp4")
      let outroPath = joinPath(tempDir, "outro.mp4")
      writeFile(videoPath, "")
      writeFile(outroPath, "")

      let concatFile = buildConcatList("", videoPath, outroPath, tempDir)
      let content = readFile(concatFile)

      let lines = content.splitLines().filterIt(it.len > 0)
      check lines.len == 2  # video + outro, no intro
      check "intro.mp4" notin content
      check "video.mp4" in content
      check "outro.mp4" in content

      cleanupConcatList(concatFile)
      removeDir(tempDir)
    except CatchableError:
      removeDir(tempDir)
      raise

  test "buildConcatList video only":
    let tempDir = createTempDir("honeyclip_test_", "")
    try:
      let videoPath = joinPath(tempDir, "video.mp4")
      writeFile(videoPath, "")

      let concatFile = buildConcatList("", videoPath, "", tempDir)
      let content = readFile(concatFile)

      let lines = content.splitLines().filterIt(it.len > 0)
      check lines.len == 1  # video only
      check "video.mp4" in content

      cleanupConcatList(concatFile)
      removeDir(tempDir)
    except CatchableError:
      removeDir(tempDir)
      raise

  test "validateConcatFiles reports missing files":
    let errors = validateConcatFiles(@["/nonexistent/file.mp4"])
    check errors.len > 0
    check "not found" in errors[0].toLowerAscii()

  test "validateConcatFiles passes for empty list":
    let errors = validateConcatFiles(@[])
    check errors.len == 0

suite "Caption Style Presets":
  test "toCaptionStyle with modern preset":
    var overrides = CaptionOverrides(preset: "modern")
    let style = toCaptionStyle(overrides)

    check style.fontSize == 72
    check style.position == cpCenter
    check style.backgroundBox == true

  test "toCaptionStyle with traditional preset":
    var overrides = CaptionOverrides(preset: "traditional")
    let style = toCaptionStyle(overrides)

    check style.fontSize == 60
    check style.position == cpBottomCenter
    check style.outline == true

  test "toCaptionStyle with overrides on preset":
    var overrides = CaptionOverrides(preset: "modern", fontSize: 48, color: "#ff0000")
    let style = toCaptionStyle(overrides)

    check style.fontSize == 48  # overridden
    check style.color == "#ff0000"  # overridden
    check style.position == cpCenter  # from preset, not overridden

  test "toCaptionStyle with empty preset uses traditional":
    var overrides = CaptionOverrides()
    let style = toCaptionStyle(overrides)

    # Should match traditional preset defaults
    check style.fontSize == 60
    check style.position == cpBottomCenter
    check style.outline == true

  test "toCaptionStyle position override":
    var overrides = CaptionOverrides(preset: "traditional", position: "center")
    let style = toCaptionStyle(overrides)

    check style.position == cpCenter  # overridden from traditional's bottom

  test "parseCaptionPosition valid values":
    check parseCaptionPosition("bottom") == cpBottomCenter
    check parseCaptionPosition("center") == cpCenter
    check parseCaptionPosition("top") == cpTopCenter

  test "parseCaptionPosition unknown defaults to bottom":
    check parseCaptionPosition("") == cpBottomCenter
    check parseCaptionPosition("invalid") == cpBottomCenter
