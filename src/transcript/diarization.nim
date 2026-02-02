import std/[os, tables, strformat, json, options, strutils]
import nimpy
import ./types

type
  SpeakerSegment* = object
    startMs*: int64
    endMs*: int64
    speaker*: int

  DiarizationResult* = object
    segments*: seq[SpeakerSegment]
    numSpeakers*: int

var diarizationAvailableCache: Option[bool] = none(bool)

proc checkDiarizationAvailable*(): bool =
  ## Check if pyannote.audio is available via Python
  ## Returns true if pyannote can be imported, false otherwise
  ## Caches result to avoid repeated import attempts
  if diarizationAvailableCache.isSome:
    return diarizationAvailableCache.get()

  try:
    let pyannote = pyImport("pyannote.audio")
    diarizationAvailableCache = some(true)
    return true
  except:
    diarizationAvailableCache = some(false)
    return false

proc diarizeAudio*(audioPath: string, maxSpeakers: int = 10): DiarizationResult =
  ## Perform speaker diarization on audio file using pyannote.audio
  ## Returns speaker segments with timestamps and speaker IDs
  ## Raises on error if pyannote not available or diarization fails
  result.segments = @[]
  result.numSpeakers = 0

  # Check if HF_TOKEN is set
  let hfToken = getEnv("HF_TOKEN", "")
  if hfToken.len == 0:
    echo "WARNING: HF_TOKEN environment variable not set. Model download may fail."
    echo "Get token from: https://huggingface.co/settings/tokens"
    echo "Set via: export HF_TOKEN=your_token_here"

  try:
    # Import pyannote.audio
    let pyannote = pyImport("pyannote.audio")

    # Load pre-trained pipeline
    echo &"Loading pyannote speaker-diarization-3.1 model..."
    let Pipeline = pyannote.Pipeline
    let pipelineObj = Pipeline.from_pretrained(
      "pyannote/speaker-diarization-3.1",
      use_auth_token = hfToken
    )

    # Run diarization
    echo &"Running diarization on {audioPath}..."
    let diarization = pipelineObj.callMethod("__call__", audioPath)

    # Extract speaker segments
    var speakerIds = initTable[string, int]()
    var nextSpeakerId = 0

    # Iterate through diarization results
    for item in diarization.itertracks(yield_label = true):
      # item is a tuple of (turn, _, speaker_label)
      let turn = item[0]
      let speakerLabel = $item[2]  # Convert PyObject to string

      # Map speaker label to integer ID
      if speakerLabel notin speakerIds:
        speakerIds[speakerLabel] = nextSpeakerId
        nextSpeakerId += 1

      let speakerId = speakerIds[speakerLabel]

      # Extract start and end times (in seconds from pyannote)
      let startSec = turn.start.to(float)
      let endSec = turn.end.to(float)

      # Convert to milliseconds
      let segment = SpeakerSegment(
        startMs: int64(startSec * 1000.0),
        endMs: int64(endSec * 1000.0),
        speaker: speakerId
      )

      result.segments.add(segment)

    result.numSpeakers = speakerIds.len
    echo &"Diarization complete: {result.numSpeakers} speakers, {result.segments.len} segments"

  except Exception as e:
    # Provide helpful error messages
    let errMsg = $e.msg
    if errMsg.contains("ModuleNotFoundError") or errMsg.contains("No module named"):
      raise newException(IOError,
        "pyannote.audio not installed. Install via: pip install pyannote.audio torch")
    elif errMsg.contains("401") or errMsg.contains("Unauthorized"):
      raise newException(IOError,
        "Model access denied. Set HF_TOKEN and accept license at:\n" &
        "https://huggingface.co/pyannote/speaker-diarization-3.1")
    else:
      raise newException(IOError, &"Diarization failed: {errMsg}")

proc applySpeakersToTranscript*(transcript: var Transcript, diarization: DiarizationResult) =
  ## Apply speaker labels from diarization to transcript words
  ## Words are matched to speaker segments by timestamp overlap
  ## Words with no matching segment get speaker = -1 (Unknown)

  # Apply speakers to words
  for word in transcript.words.mitems:
    var matched = false

    # Find overlapping speaker segment
    for segment in diarization.segments:
      # Check if word start time falls within segment
      if word.startMs >= segment.startMs and word.startMs < segment.endMs:
        word.speaker = segment.speaker
        matched = true
        break

    # Mark as unknown if no match
    if not matched:
      word.speaker = -1

  # Update segment speakers based on majority vote
  for segment in transcript.segments.mitems:
    if segment.words.len == 0:
      segment.speaker = -1
      continue

    # Count speakers in segment
    var speakerCounts = initTable[int, int]()
    for word in segment.words:
      if word.speaker >= 0:
        speakerCounts[word.speaker] = speakerCounts.getOrDefault(word.speaker, 0) + 1

    # Find majority speaker
    var maxCount = 0
    var majoritySpeaker = -1
    for speaker, count in speakerCounts:
      if count > maxCount:
        maxCount = count
        majoritySpeaker = speaker

    segment.speaker = majoritySpeaker

proc loadSpeakerMap*(mapPath: string): Table[int, string] =
  ## Load speaker name mapping from JSON file
  ## Format: {"0": "John", "1": "Mary", ...}
  ## Returns empty table if file doesn't exist (not an error)
  result = initTable[int, string]()

  if not fileExists(mapPath):
    return

  try:
    let jsonContent = readFile(mapPath)
    let jsonNode = parseJson(jsonContent)

    for key, value in jsonNode.pairs:
      let speakerId = parseInt(key)
      let speakerName = value.getStr()
      result[speakerId] = speakerName

  except Exception as e:
    echo &"WARNING: Failed to load speaker map from {mapPath}: {e.msg}"
    # Return empty table on error

proc getSpeakerLabel*(speakerId: int, speakerMap: Table[int, string]): string =
  ## Get display label for speaker ID
  ## Checks speakerMap first, then falls back to default labels
  if speakerId == -1:
    return "Unknown"

  if speakerId in speakerMap:
    return speakerMap[speakerId]

  # Default: 1-indexed speaker number
  return &"Speaker {speakerId + 1}"
