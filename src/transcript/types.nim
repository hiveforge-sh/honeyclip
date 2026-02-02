import std/strformat

type
  Word* = object
    text*: string
    startMs*: int64        # Milliseconds from start
    endMs*: int64
    confidence*: float     # 0.0-1.0, from whisper "p" field
    isNonSpeech*: bool     # true for [music], [noise]
    label*: string         # "music", "noise", empty for speech
    speaker*: int          # -1 = unassigned, 0+ = speaker index

  TranscriptSegment* = object
    words*: seq[Word]
    startMs*: int64
    endMs*: int64
    text*: string          # Combined text of all words
    speaker*: int

  Transcript* = object
    segments*: seq[TranscriptSegment]
    words*: seq[Word]      # Flat list of all words
    duration*: int64       # Total duration in ms
    language*: string      # Detected or specified language

# Helper constructors
proc newWord*(text: string, startMs: int64, endMs: int64, confidence: float): Word =
  result.text = text
  result.startMs = startMs
  result.endMs = endMs
  result.confidence = confidence
  result.isNonSpeech = false
  result.label = ""
  result.speaker = -1

proc newTranscript*(): Transcript =
  result.segments = @[]
  result.words = @[]
  result.duration = 0
  result.language = ""

proc addWord*(transcript: var Transcript, word: Word) =
  ## Add a word to the transcript
  transcript.words.add(word)

  # Update duration
  if word.endMs > transcript.duration:
    transcript.duration = word.endMs

  # Add to current segment or create new one
  if transcript.segments.len == 0:
    var segment = TranscriptSegment(
      words: @[word],
      startMs: word.startMs,
      endMs: word.endMs,
      text: word.text,
      speaker: word.speaker
    )
    transcript.segments.add(segment)
  else:
    # Add to last segment
    var lastSegment = addr transcript.segments[^1]
    lastSegment.words.add(word)
    lastSegment.endMs = word.endMs
    if lastSegment.text.len > 0:
      lastSegment.text &= " " & word.text
    else:
      lastSegment.text = word.text

proc formatTimestamp*(ms: int64, usePeriod: bool = false): string =
  ## Convert milliseconds to timestamp format
  ## SRT uses comma (default): HH:MM:SS,mmm
  ## VTT uses period: HH:MM:SS.mmm
  let totalSeconds = ms div 1000
  let milliseconds = ms mod 1000
  let hours = totalSeconds div 3600
  let minutes = (totalSeconds mod 3600) div 60
  let seconds = totalSeconds mod 60

  let separator = if usePeriod: "." else: ","
  result = &"{hours:02}:{minutes:02}:{seconds:02}{separator}{milliseconds:03}"

proc isLowConfidence*(word: Word, threshold: float = 0.5): bool =
  ## Check if a word has low confidence
  word.confidence < threshold
