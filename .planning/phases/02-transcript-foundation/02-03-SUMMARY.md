# Plan 02-03 Summary: Speaker Diarization via pyannote.audio

## Status: COMPLETE

## What Was Built

Speaker diarization module using pyannote.audio via nimpy Python FFI bridge.

### Files Modified
- `honeyclip.nimble` - Added nimpy dependency
- `src/transcript/diarization.nim` - New module for speaker identification

### Key Implementations

1. **Core Types**
   - `SpeakerSegment` - Timestamp range with speaker ID
   - `DiarizationResult` - Collection of segments + speaker count

2. **Main Functions**
   - `diarizeAudio(audioPath, maxSpeakers)` - Runs pyannote pipeline, returns speaker segments
   - `applySpeakersToTranscript(transcript, diarization)` - Labels words with speaker IDs
   - `checkDiarizationAvailable()` - Cached availability check

3. **Speaker Remapping**
   - `loadSpeakerMap(jsonPath)` - Parse `{"0": "John", "1": "Mary"}` format
   - `getSpeakerLabel(speakerId, map)` - Returns mapped name or "Speaker N"

### Design Decisions
- **Cached import check** - Avoid repeated pyannote import attempts
- **Majority vote for segments** - Segment speaker = most common word speaker
- **Graceful error handling** - Clear messages for missing pyannote, auth failures
- **HF_TOKEN warning** - Logs setup instructions if token not set

## Verification

- [x] nimpy added to honeyclip.nimble requires
- [x] `nim check --hints:off src/transcript/diarization.nim` compiles
- [x] checkDiarizationAvailable returns correct status
- [x] loadSpeakerMap parses JSON correctly
- [x] getSpeakerLabel returns correct display names
- [x] Human verified Python environment setup (pyannote.audio installed, HF_TOKEN set, license accepted)

## Dependencies

Requires user setup:
- Python with pyannote.audio: `pip install pyannote.audio torch`
- HuggingFace token: https://huggingface.co/settings/tokens
- Model license: https://huggingface.co/pyannote/speaker-diarization-3.1

## Commits

Code was implemented by executor agent in previous session (files already committed).
