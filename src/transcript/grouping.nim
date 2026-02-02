import std/strutils
import types

type
  Caption* = object
    words*: seq[Word]
    startMs*: int64
    endMs*: int64
    text*: string
    speaker*: int          # -1 if mixed/unknown
    speakerChanged*: bool  # True if speaker changed from previous caption

const
  # Common abbreviations that don't end sentences
  Abbreviations = [
    "Dr.", "Mr.", "Mrs.", "Ms.", "Prof.", "Jr.", "Sr.",
    "vs.", "etc.", "i.e.", "e.g."
  ]

  # Small words that should not start a new line
  SmallWords = [
    "a", "an", "the", "to", "of", "in", "on", "at",
    "and", "or", "but", "for", "with"
  ]

proc isSentenceEnd(word: Word): bool =
  ## Check if a word ends a sentence
  let text = word.text.strip()
  if text.len == 0:
    return false

  let lastChar = text[^1]
  if lastChar notin {'.', '?', '!'}:
    return false

  # Check if it's an abbreviation
  for abbrev in Abbreviations:
    if text.endsWith(abbrev):
      return false

  return true

proc shouldBreakBefore(word: Word): bool =
  ## Check if we should avoid breaking before this word
  let text = word.text.strip().toLowerAscii()
  text in SmallWords

proc groupIntoCaptions*(transcript: Transcript, maxChars: int = 42, maxDuration: float = 5.0): seq[Caption] =
  ## Group words into readable caption segments
  ##
  ## Args:
  ##   transcript: The transcript to group
  ##   maxChars: Maximum characters per caption (default 42)
  ##   maxDuration: Maximum duration per caption in seconds (default 5.0)
  ##
  ## Returns:
  ##   Sequence of Caption objects

  result = @[]

  if transcript.words.len == 0:
    return

  let maxDurationMs = int64(maxDuration * 1000.0)
  var currentCaption: Caption
  var currentLength = 0
  var currentText = ""
  var lastSpeaker = -2  # Track previous caption's speaker

  proc finishCaption() =
    if currentCaption.words.len > 0:
      currentCaption.text = currentText.strip()
      currentCaption.startMs = currentCaption.words[0].startMs
      currentCaption.endMs = currentCaption.words[^1].endMs

      # Check if speaker changed from previous caption
      currentCaption.speakerChanged = (currentCaption.speaker != lastSpeaker)
      lastSpeaker = currentCaption.speaker

      result.add(currentCaption)

      # Reset for next caption
      currentCaption = Caption(words: @[], speaker: -1)
      currentLength = 0
      currentText = ""

  # Initialize first caption
  currentCaption = Caption(words: @[], speaker: transcript.words[0].speaker)

  for i, word in transcript.words:
    let wordText = word.text.strip()
    if wordText.len == 0:
      continue

    # Calculate what the new length would be
    var newLength = currentLength + wordText.len
    if currentLength > 0:
      newLength += 1  # Space before word

    # Calculate duration if we add this word
    let startMs = if currentCaption.words.len > 0: currentCaption.words[0].startMs else: word.startMs
    let durationMs = word.endMs - startMs

    # Check if we need to break
    var shouldBreak = false
    var reason = ""

    # Speaker change always breaks
    if currentCaption.words.len > 0 and word.speaker != currentCaption.speaker and currentCaption.speaker != -1:
      shouldBreak = true
      reason = "speaker_change"

    # Duration exceeded
    elif durationMs > maxDurationMs:
      shouldBreak = true
      reason = "duration"

    # Character limit exceeded
    elif newLength > maxChars:
      # Check if we're close to a sentence boundary (within 20% of limit)
      if currentLength >= int(float(maxChars) * 0.8):
        # Look for recent sentence end
        var foundSentenceEnd = false
        if currentCaption.words.len > 0:
          for j in countdown(currentCaption.words.len - 1, max(0, currentCaption.words.len - 3)):
            if isSentenceEnd(currentCaption.words[j]):
              foundSentenceEnd = true
              break

        if not foundSentenceEnd:
          # Don't break if next word is small
          if not shouldBreakBefore(word):
            shouldBreak = true
            reason = "length"
        else:
          shouldBreak = true
          reason = "sentence"
      else:
        # Don't break if next word is small
        if not shouldBreakBefore(word):
          shouldBreak = true
          reason = "length"

    # Sentence boundary - prefer to break here if we have content
    elif isSentenceEnd(word) and currentCaption.words.len > 0:
      # Add this word first, then break
      currentCaption.words.add(word)
      if currentLength > 0:
        currentText &= " " & wordText
      else:
        currentText = wordText
      currentLength = newLength

      # Break after sentence end if we're approaching limits
      if currentLength >= int(float(maxChars) * 0.6) or durationMs >= int64(float(maxDurationMs) * 0.6):
        finishCaption()
        # Start new caption with current word's speaker
        if i + 1 < transcript.words.len:
          currentCaption.speaker = transcript.words[i + 1].speaker
        else:
          currentCaption.speaker = word.speaker

      continue

    if shouldBreak:
      finishCaption()
      # Start new caption with current word
      currentCaption.speaker = word.speaker

    # Add word to current caption
    currentCaption.words.add(word)
    if currentLength > 0:
      currentText &= " " & wordText
    else:
      currentText = wordText
    currentLength = newLength

  # Finish last caption
  finishCaption()
