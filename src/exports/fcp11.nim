import std/[algorithm, os, sets, tables, xmltree]
import std/[strformat, strutils]
from std/math import round

import ../media
import ../log
import ../ffmpeg
import ../timeline
import ../transcript/grouping
import ../render/captions
import markers

#[
Export a FCPXML 11 file readable with Final Cut Pro 10.6.8 or later.

See docs here:
https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference

]#


func getColorspace(mi: MediaInfo): string =
  # See: https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/asset#3686496

  if mi.v.len == 0:
    return "1-1-1 (Rec. 709)"

  let s = mi.v[0]
  if s.pix_fmt == AV_PIX_FMT_RGB24:
    return "sRGB IEC61966-2.1"
  if s.color_space == 5: # "bt470bg"
    return "5-1-6 (Rec. 601 PAL)"
  if s.color_space == 6: # "smpte170m"
    return "6-1-6 (Rec. 601 NTSC)"
  if s.color_primaries == 9: # "bt2020"
    # See: https://video.stackexchange.com/questions/22059/how-to-identify-hdr-video
    if s.color_transfer == 16 or s.color_transfer == 18: # "smpte2084" "arib-std-b67"
      return "9-18-9 (Rec. 2020 HLG)"
    return "9-1-9 (Rec. 2020)"

  return "1-1-1 (Rec. 709)"

func makeName(mi: MediaInfo, tb: AVRational): string =
  if mi.getRes()[1] == 720 and tb == 30:
    return "FFVideoFormat720p30"
  if mi.getRes()[1] == 720 and tb == 25:
    return "FFVideoFormat720p25"
  if mi.getRes() == (3840, 2160) and tb == AVRational(num: 24000, den: 1001):
    return "FFVideoFormat3840x2160p2398"
  return "FFVideoFormatRateUndefined"

proc pathToUri(a: string): string =
  let absPath = a.absolutePath()

  when defined(windows):
    let normalizedPath = absPath.replace('\\', '/')
    return "file:///" & normalizedPath
  else:
    return "file://" & absPath

proc hexToFCPXMLColor*(hex: string): string =
  ## Convert hex color (#RRGGBB) to FCPXML color format (R G B A)
  var color = hex
  if color.startsWith("#"):
    color = color[1..^1]

  # Parse RGB
  let r = parseHexInt(color[0..1])
  let g = parseHexInt(color[2..3])
  let b = parseHexInt(color[4..5])

  # Normalize to 0.0-1.0 and round to integers for FCPXML
  let rNorm = int(r.float / 255.0 + 0.5)
  let gNorm = int(g.float / 255.0 + 0.5)
  let bNorm = int(b.float / 255.0 + 0.5)

  result = &"{rNorm} {gNorm} {bNorm} 1"

proc addCaptionTrackFCPXML*(spine: XmlNode, captions: seq[Caption], style: CaptionStyle, tb: AVRational) =
  ## Add caption titles to FCPXML spine
  if captions.len == 0:
    return

  func fraction(val: int): string =
    if val == 0:
      return "0s"
    return &"{val * tb.den.int}/{tb.num}s"

  # Create gap element as container (doesn't displace video)
  let gap = newElement("gap")
  gap.attrs = {
    "name": "Caption Gap",
    "offset": "0s",
    "duration": fraction(0)  # Will be set by titles
  }.toXmlAttributes

  for index, caption in captions:
    # Convert timing from milliseconds to frames
    let startFrame = (caption.startMs * tb.num.int) div (tb.den.int * 1000)
    let endFrame = (caption.endMs * tb.num.int) div (tb.den.int * 1000)
    let durationFrames = endFrame - startFrame

    # Truncate text for name
    var titleName = caption.text
    if titleName.len > 20:
      titleName = titleName[0..16] & "..."

    let title = newElement("title")
    title.attrs = {
      "name": titleName,
      "offset": fraction(startFrame),
      "duration": fraction(durationFrames),
      "start": "3600s"  # Standard title start time
    }.toXmlAttributes

    # Add text content parameter
    let textParam = newElement("param")
    textParam.attrs = {"name": "Text", "key": "9999/10227/10228/1/100/101", "value": caption.text}.toXmlAttributes
    title.add textParam

    # Add position parameter based on style
    var posY = "0"
    case style.position
    of cpBottomCenter:
      posY = "-300"
    of cpCenter:
      posY = "0"
    of cpTopCenter:
      posY = "300"

    let posParam = newElement("param")
    posParam.attrs = {"name": "Position", "key": "9999/10227/10228/2/351", "value": &"0 {posY}"}.toXmlAttributes
    title.add posParam

    # Add flatten parameter (text layout)
    let flattenParam = newElement("param")
    flattenParam.attrs = {"name": "Flatten", "key": "9999/10227/10228/2/354", "value": "1"}.toXmlAttributes
    title.add flattenParam

    # Add text style with font and color
    let textStyle = newElement("text-style")
    textStyle.attrs = {"ref": "ts1"}.toXmlAttributes
    title.add textStyle

    # Determine color based on speaker
    var textColor = style.color
    if caption.speaker >= 0:
      textColor = getSpeakerColor(caption.speaker)

    let textStyleDef = newElement("text-style-def")
    textStyleDef.attrs = {
      "id": &"ts{index + 1}",
    }.toXmlAttributes

    let textStyleDefInner = newElement("text-style")
    textStyleDefInner.attrs = {
      "font": style.fontName,
      "fontSize": $style.fontSize,
      "fontColor": hexToFCPXMLColor(textColor)
    }.toXmlAttributes
    textStyleDef.add textStyleDefInner

    title.add textStyleDef

    # Add word-level timing if highlighting enabled
    if style.highlightEnabled and caption.words.len > 0:
      # Create keyframed color for word timing
      for i, word in caption.words:
        let wordOffsetMs = word.startMs - caption.startMs
        let wordFrame = (wordOffsetMs * tb.num.int) div (tb.den.int * 1000)

        let keyframe = newElement("text-style-def")
        keyframe.attrs = {
          "id": &"ts{index + 1}w{i}",
        }.toXmlAttributes

        let keyframeStyle = newElement("text-style")
        keyframeStyle.attrs = {
          "fontColor": hexToFCPXMLColor(textColor)
        }.toXmlAttributes
        keyframe.add keyframeStyle

        title.add keyframe

    gap.add title

  spine.add gap

proc parseSMPTE*(val: string, fps: AVRational): int =
  if val.len == 0:
    return 0

  try:
    let parts = val.replace(";", ":").split(":")
    if len(parts) != 4:
      raise newException(ValueError, "Invalid SMPTE format")

    let hours = parseInt(parts[0])
    let minutes = parseInt(parts[1])
    let seconds = parseInt(parts[2])
    let frames = parseInt(parts[3])

    if hours < 0 or minutes < 0 or minutes >= 60 or seconds < 0 or seconds >=
        60 or frames < 0:
      raise newException(ValueError, "Invalid SMPTE values")

    let timecodeFps = int(round(fps.num / fps.den))
    if frames >= timecodeFps:
      raise newException(ValueError, &"Frame count {frames} exceeds timecode fps {timecodeFps}")

    return (hours * 3600 + minutes * 60 + seconds) * timecodeFps + frames
  except ValueError as e:
    error(&"Cannot parse SMPTE timecode '{val}': {e.msg}")

func timecode(self: MediaInfo): string = # In SMPTE
  for d in self.d:
    if d.timecode.len > 0:
      return d.timecode
  for v in self.v:
    if v.timecode.len > 0:
      return v.timecode
  return "00:00:00:00"

proc writeCaptionOnlyFCPXML*(videoPath: string, captions: seq[Caption], style: CaptionStyle, outputPath: string) =
  ## Write FCPXML file with caption track only
  ## videoPath must be an actual video file path (not JSON transcript)
  let mi = initMediaInfo(videoPath)
  let (width, height) = mi.getRes()
  # Get framerate from video stream, default to 30fps if no video
  let tb = if mi.v.len > 0: makeSaneTimebase(mi.v[0].avg_rate) else: AVRational(num: 30, den: 1)

  func fraction(val: int): string =
    if val == 0:
      return "0s"
    return &"{val * tb.den.int}/{tb.num}s"

  let fcpxml = <>fcpxml(version = "1.11")
  let resources = newElement("resources")
  fcpxml.add resources

  let projName = videoPath.splitFile.name
  let duration = int(mi.duration * tb)

  # Add format resource
  let formatId = "r1"
  resources.add(<>format(id = formatId, name = makeName(mi, tb),
      frameDuration = fraction(1), width = $width, height = $height,
      colorSpace = getColorspace(mi)))

  # Add asset resource
  let assetId = "r2"
  let hasVideo = (if mi.v.len > 0: "1" else: "0")
  let hasAudio = (if mi.a.len > 0: "1" else: "0")
  let audioChannels = (if mi.a.len == 0: "2" else: $mi.a[0].channels)

  let asset = <>asset(id = assetId, name = projName,
      start = "0s", hasVideo = hasVideo, format = formatId,
      hasAudio = hasAudio, audioSources = "1",
      audioChannels = audioChannels, duration = fraction(duration))

  let mediaRep = newElement("media-rep")
  mediaRep.attrs = {"kind": "original-media", "src": videoPath.pathToUri()}.toXmlAttributes
  asset.add mediaRep
  resources.add asset

  # Create library/event/project structure
  let lib = <>library()
  let evt = <>event(name = projName)
  let proj = <>project(name = projName)
  let sampleRate = if mi.a.len > 0: (if mi.a[0].sampleRate == 44100: "44.1k" else: "48k") else: "48k"
  let audioLayout = if mi.a.len > 0: mi.a[0].layout else: "stereo"
  let sequence = <>sequence(format = formatId, tcStart = "0s", tcFormat = "NDF",
      audioLayout = audioLayout, audioRate = sampleRate)
  let spine = <>spine()

  # Add video asset-clip to spine
  let assetClip = newElement("asset-clip")
  assetClip.attrs = {
    "name": projName,
    "ref": assetId,
    "offset": "0s",
    "duration": fraction(duration),
    "start": "0s",
    "tcFormat": "NDF"
  }.toXmlAttributes
  spine.add assetClip

  # Add caption track
  addCaptionTrackFCPXML(spine, captions, style, tb)

  sequence.add spine
  proj.add sequence
  evt.add proj
  lib.add evt
  fcpxml.add lib

  if outputPath == "-":
    echo $fcpxml
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $fcpxml
    writeFile(outputPath, xmlStr)

proc fcp11_write_xml*(groupName, version, output: string, resolve: bool, tl: v3) =
  func fraction(val: int): string =
    if val == 0:
      return "0s"
    return &"{val * tl.tb.den.int}/{tl.tb.num}s"

  var verStr: string
  if version == "11":
    verStr = "1.11"
  elif version == "10":
    verStr = "1.10"
  else:
    error(&"Unknown final cut pro version: {version}")

  let fcpxml = <>fcpxml(version = verStr)
  let resources = newElement("resources")
  fcpxml.add(resources)

  var srcDur = 0
  var tlDur = (if resolve: 0 else: tl.len)
  var projName: string

  var ptrToMi = initTable[ptr string, MediaInfo]()
  var i = 0

  for ptrSrc in tl.uniqueSources:
    let mi = initMediaInfo(ptrSrc[])
    ptrToMi[ptrSrc] = mi

    if i == 0:
      projName = splitFile(mi.path).name
      srcDur = int(mi.duration * tl.tb)
      if resolve:
        tlDur = srcDur

    let id = "r" & $(i * 2 + 1)
    let width = $tl.res[0]
    let height = $tl.res[1]
    resources.add(<>format(id = id, name = makeName(mi, tl.tb),
        frameDuration = fraction(1), width = width, height = height,
        colorSpace = getColorspace(mi)))

    let id2 = "r" & $(i * 2 + 2)
    let hasVideo = (if mi.v.len > 0: "1" else: "0")
    let hasAudio = (if mi.a.len > 0: "1" else: "0")
    let audioChannels = (if mi.a.len == 0: "2" else: $mi.a[0].channels)

    let startPoint = parseSMPTE(mi.timecode, tl.tb)
    let r2 = <>asset(id = id2, name = splitFile(mi.path).name,
        start = fraction(startPoint), hasVideo = hasVideo, format = id,
        hasAudio = hasAudio, audioSources = "1",
        audioChannels = audioChannels, duration = fraction(tlDur))

    let mediaRep = newElement("media-rep")
    mediaRep.attrs = {"kind": "original-media", "src": mi.path.pathToUri()}.toXmlAttributes

    r2.add mediaRep
    resources.add r2

    i += 1

  let lib = <>library()
  let evt = <>event(name = group_name)
  let proj = <>project(name = projName)
  let sequence = <>sequence(format = "r1", tcStart = "0s", tcFormat = "NDF",
      audioLayout = tl.layout, audioRate = (if tl.sr ==
      44100: "44.1k" else: "48k"))
  let spine = <>spine()

  sequence.add spine
  proj.add sequence
  evt.add proj
  lib.add evt
  fcpxml.add lib

  proc make_clip(`ref`: string, clip: Clip) =
    let src = ptrToMi[clip.src]
    let startPoint = parseSMPTE(src.timecode, tl.tb)

    let asset = newElement("asset-clip")
    asset.attrs = {
      "name": projName,
      "ref": `ref`,
      "offset": fraction(clip.start + startPoint),
      "duration": fraction(clip.dur),
      "start": fraction(clip.offset + startPoint),
      "tcFormat": "NDF"
    }.toXmlAttributes

    spine.add(asset)

    let effectGroup = tl.effects[clip.effects]
    for effect in effectGroup:
      if effect.kind == actSpeed:
        # See the "Time Maps" section.
        # https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/story_elements/timemap/

        let timemap = newElement("timeMap")
        let timept1 = newElement("timept")
        timept1.attrs = {"time": "0s", "value": "0s", "interp": "smooth2"}.toXmlAttributes
        timemap.add(timept1)

        let timept2 = newElement("timept")
        timept2.attrs = {
          "time": fraction(int(srcDur.float / effect.val)),
          "value": fraction(srcDur),
          "interp": "smooth2"
        }.toXmlAttributes
        timemap.add(timept2)

        asset.add(timemap)
        break

  var clips: seq[Clip]
  if tl.v.len > 0 and tl.v[0].len > 0:
    clips = tl.v[0]
  elif tl.a.len > 0 and tl.a[0].len > 0:
    clips = tl.a[0]

  var all_refs: seq[string] = @["r2"]
  if resolve:
    for i in 1 ..< tl.a.len:
      all_refs.add("r" & $((i + 1) * 2))

  for my_ref in all_refs.reversed:
    for clip in clips:
      make_clip(my_ref, clip)

  if output == "-":
    echo $fcpxml
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $fcpxml
    writeFile(output, xmlStr)

proc addMarkerFCPXML*(parent: XmlNode, marker: Marker, tb: AVRational) =
  ## Add a single marker element to FCPXML
  ##
  ## FCPXML marker format (simpler than FCP7):
  ## <marker start="10s" duration="1s" value="Peak #1" note="Score: 85/100"/>
  ##
  ## FCPXML uses rational time (e.g., "1001/30000s") or simple seconds
  ##
  ## Note: FCPXML markers don't support custom colors in the XML,
  ## color is set by marker type in Final Cut Pro
  ##
  ## Args:
  ##   parent: The clip or spine element to add marker to
  ##   marker: Marker data
  ##   tb: Timebase for timing calculation
  func fraction(val: int64): string =
    if val == 0:
      return "0s"
    return &"{val * tb.den.int}/{tb.num}s"

  # Convert milliseconds to frame-based timing
  # timestampMs -> frames: (ms * fps_num) / (fps_den * 1000)
  let startFrame = (marker.timestampMs * tb.num.int64) div (tb.den.int64 * 1000)
  let durationFrame = (marker.durationMs * tb.num.int64) div (tb.den.int64 * 1000)

  let markerElem = newElement("marker")
  markerElem.attrs = {
    "start": fraction(startFrame),
    "duration": fraction(if durationFrame > 0: durationFrame else: 1),
    "value": marker.name,
    "note": marker.comment
  }.toXmlAttributes

  parent.add markerElem

proc addMarkersFCPXML*(parent: XmlNode, markers: seq[Marker], tb: AVRational) =
  ## Add multiple markers to a parent element (clip, gap, or spine)
  for marker in markers:
    addMarkerFCPXML(parent, marker, tb)

proc writeMarkersFCPXML*(videoPath: string, markers: seq[Marker], outputPath: string) =
  ## Write FCPXML file with markers on video clip
  ## Creates: fcpxml > resources + library > event > project > sequence > spine > asset-clip with markers
  let mi = initMediaInfo(videoPath)
  let (width, height) = mi.getRes()
  # Get framerate from video stream, default to 30fps if no video
  let tb = if mi.v.len > 0: makeSaneTimebase(mi.v[0].avg_rate) else: AVRational(num: 30, den: 1)

  func fraction(val: int): string =
    if val == 0:
      return "0s"
    return &"{val * tb.den.int}/{tb.num}s"

  let fcpxml = <>fcpxml(version = "1.11")
  let resources = newElement("resources")
  fcpxml.add resources

  let projName = videoPath.splitFile.name
  let duration = int(mi.duration * tb)

  # Add format resource
  let formatId = "r1"
  resources.add(<>format(id = formatId, name = makeName(mi, tb),
      frameDuration = fraction(1), width = $width, height = $height,
      colorSpace = getColorspace(mi)))

  # Add asset resource
  let assetId = "r2"
  let hasVideo = (if mi.v.len > 0: "1" else: "0")
  let hasAudio = (if mi.a.len > 0: "1" else: "0")
  let audioChannels = (if mi.a.len == 0: "2" else: $mi.a[0].channels)

  let asset = <>asset(id = assetId, name = projName,
      start = "0s", hasVideo = hasVideo, format = formatId,
      hasAudio = hasAudio, audioSources = "1",
      audioChannels = audioChannels, duration = fraction(duration))

  let mediaRep = newElement("media-rep")
  mediaRep.attrs = {"kind": "original-media", "src": videoPath.pathToUri()}.toXmlAttributes
  asset.add mediaRep
  resources.add asset

  # Create library/event/project structure
  let lib = <>library()
  let evt = <>event(name = projName)
  let proj = <>project(name = projName)
  let sampleRate = if mi.a.len > 0: (if mi.a[0].sampleRate == 44100: "44.1k" else: "48k") else: "48k"
  let audioLayout = if mi.a.len > 0: mi.a[0].layout else: "stereo"
  let sequence = <>sequence(format = formatId, tcStart = "0s", tcFormat = "NDF",
      audioLayout = audioLayout, audioRate = sampleRate)
  let spine = <>spine()

  # Add video asset-clip to spine
  let assetClip = newElement("asset-clip")
  assetClip.attrs = {
    "name": projName,
    "ref": assetId,
    "offset": "0s",
    "duration": fraction(duration),
    "start": "0s",
    "tcFormat": "NDF"
  }.toXmlAttributes

  # Add markers to the asset-clip element
  addMarkersFCPXML(assetClip, markers, tb)

  spine.add assetClip
  sequence.add spine
  proj.add sequence
  evt.add proj
  lib.add evt
  fcpxml.add lib

  if outputPath == "-":
    echo $fcpxml
  else:
    let xmlStr = "<?xml version='1.0' encoding='utf-8'?>\n" & $fcpxml
    writeFile(outputPath, xmlStr)
