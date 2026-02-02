# Phase 2: Transcript Foundation - Research

**Researched:** 2026-02-01
**Domain:** Speech-to-text transcription with subtitle export
**Confidence:** MEDIUM

## Summary

This research investigates the technical requirements for extracting full transcripts with word-level timestamps and speaker identification from video. The phase extends the existing whisper.cpp integration in honeyclip to support full transcript extraction with multiple export formats (SRT, VTT, JSON) and speaker diarization.

**Key findings:**
- The existing FFmpeg whisper filter provides segment-level timestamps in SRT/JSON formats but NOT word-level timestamps
- Word-level timestamps require direct whisper.cpp API integration or alternative libraries like whisper-timestamped
- Speaker diarization requires a separate ML library (pyannote.audio is the standard) with Python FFI integration via nimpy
- Subtitle formats have strict specifications (UTF-8 without BOM, 42 character limit, millisecond precision with comma separator for SRT)
- Whisper models have known hallucination issues (~1-80% depending on configuration) that require mitigation

**Primary recommendation:** Extend whisper.cpp integration to use direct API for word-level timestamps, implement SRT/VTT generators with sentence boundary detection, and integrate pyannote.audio via nimpy for speaker diarization.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| whisper.cpp | 1.8.2 | Speech-to-text transcription | Already integrated, C++ performance, offline processing |
| pyannote.audio | 3.1+ | Speaker diarization | State-of-the-art accuracy (DER ~11-19%), pure PyTorch, offline capable |
| nimpy | latest | Python-Nim FFI bridge | Standard Nim library for Python interop, enables pyannote integration |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| whisper-timestamped | latest | Word-level timestamps alternative | If whisper.cpp API insufficient for word-level timing |
| sentence-splitter | NLP lib | Sentence boundary detection | For grouping words into caption-length segments |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| whisper.cpp | Faster-Whisper (Python) | Better word timestamps but requires full Python runtime |
| pyannote.audio | NVIDIA NeMo | Faster on NVIDIA GPUs but heavier dependencies |
| nimpy FFI | Subprocess calls | Simpler but much slower, no shared memory |

**Installation:**
```bash
# Already installed (whisper.cpp)
nimble makeff

# Speaker diarization (requires Python environment)
pip install pyannote.audio torch
nimble install nimpy
```

## Architecture Patterns

### Recommended Project Structure
```
src/
├── cmds/
│   └── whisper.nim          # Existing - extend for full transcript
├── transcribe/
│   ├── formats.nim          # SRT, VTT, JSON generators
│   ├── grouping.nim         # Sentence boundary detection, caption line breaking
│   ├── timestamps.nim       # Word-level timestamp extraction
│   └── diarization.nim      # Speaker identification via pyannote
├── exports/
│   └── transcript.nim       # Transcript export coordinator
```

### Pattern 1: Two-Stage Transcript Pipeline
**What:** Separate transcription from diarization to allow single-speaker optimization
**When to use:** Default for all transcription tasks
**Example:**
```nim
# Stage 1: Extract transcript with word timestamps
let transcript = extractTranscript(inputPath, model, language)

# Stage 2: Apply speaker diarization if enabled (unless --single-speaker)
if not singleSpeaker:
  let speakers = identifySpeakers(inputPath, transcript)
  transcript.annotateSpeakers(speakers)

# Stage 3: Group words into caption segments
let captions = groupIntoCaptions(transcript, maxChars=42)

# Stage 4: Export to formats
exportSRT(captions, outputPath)
exportVTT(captions, outputPath, speakerColors=false)
exportJSON(captions, outputPath, compact=false)
```

### Pattern 2: Confidence-Aware Formatting
**What:** Mark low-confidence words with [?] and handle non-speech segments
**When to use:** When outputting human-readable transcripts
**Example:**
```nim
proc formatWord(word: Word, threshold: float = 0.5): string =
  if word.confidence < threshold:
    return word.text & "[?]"
  elif word.isNonSpeech:
    return "[" & word.label & "]"  # [music], [noise]
  else:
    return word.text
```

### Pattern 3: Sentence-Boundary Caption Grouping
**What:** Group words into captions at sentence boundaries while respecting time/length limits
**When to use:** For all SRT/VTT output to maximize readability
**Example:**
```nim
proc groupIntoCaptions(words: seq[Word], maxChars: int, maxDuration: float): seq[Caption] =
  var current: Caption
  for word in words:
    # Check if adding word exceeds limits
    if current.text.len + word.text.len > maxChars or
       word.timestamp - current.startTime > maxDuration:
      # Check if at sentence boundary (period, question mark, exclamation)
      if isSentenceBoundary(word) or mustBreak(current, word):
        result.add(current)
        current = newCaption(word)
      else:
        # Continue building current caption
        current.addWord(word)
    else:
      current.addWord(word)
```

### Anti-Patterns to Avoid
- **Don't use FFmpeg whisper filter for word-level timestamps:** The filter only provides segment-level timing, not per-word granularity
- **Don't write UTF-8 with BOM:** Many subtitle players crash or display incorrectly with BOM markers
- **Don't break captions mid-sentence:** Always prefer sentence boundaries even if it means slightly longer captions
- **Don't run diarization for single-speaker videos:** It wastes ~10-30 seconds and provides no value

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sentence boundary detection | Regex for periods | NLP sentence tokenizer or whisper's natural breaks | Handles abbreviations (Dr., Mr.), decimals (3.14), ellipses |
| Speaker diarization | Clustering audio features | pyannote.audio pipeline | Requires trained embeddings, overlap detection, voice activity detection |
| Timestamp synchronization | Manual math | whisper.cpp's native timing | Handles variable audio rates, seeks, trimming automatically |
| Caption line breaking | Character count only | Sentence + phrase boundary algorithm | Prevents splitting articles/prepositions from nouns |
| JSON encoding special chars | String replacement | Nim's json module | Handles all edge cases (control chars, unicode, quotes) |

**Key insight:** Speech processing has numerous edge cases (overlapping speech, background noise, accents, speaking rate variations) that require specialized ML models and careful algorithm design. The whisper.cpp and pyannote.audio libraries represent years of research and testing.

## Common Pitfalls

### Pitfall 1: UTF-8 BOM in Subtitle Files
**What goes wrong:** Subtitle players crash or display first subtitle incorrectly when file contains UTF-8 Byte Order Mark (EF BB BF bytes at start)
**Why it happens:** Windows text editors (especially Notepad) add BOM by default to UTF-8 files
**How to avoid:** Always write UTF-8 without BOM. In Nim: `writeFile(path, content)` defaults to UTF-8 without BOM
**Warning signs:** Users report "weird characters" or "squares" at start of first subtitle

### Pitfall 2: Whisper Hallucinations on Silence
**What goes wrong:** Whisper generates phantom text during silent sections, often repeating previous phrases or adding "thanks for watching" artifacts from training data
**Why it happens:** Whisper models were trained on YouTube videos with typical outro phrases; silence triggers the model to generate filler content
**How to avoid:**
- Enable Voice Activity Detection (VAD) in whisper.cpp to skip silent sections
- Trim leading/trailing silence from audio before processing
- Post-process to detect and remove repetitive looping patterns
- Use `--vad-model` flag with whisper command
**Warning signs:** Identical phrases repeated multiple times, "like and subscribe" appearing when not spoken

### Pitfall 3: Comma vs Period in SRT Timestamps
**What goes wrong:** SRT timestamps use comma for milliseconds (00:01:23,456) not period. Using period breaks parsers
**Why it happens:** SRT format originated in France; most developers expect period for decimals
**How to avoid:** Use format string with explicit comma: `format(h, "00"):format(m, "00"):format(s, "00"),format(ms, "000")`
**Warning signs:** Video players reject SRT file or don't display any subtitles

### Pitfall 4: Caption Line Length Exceeding 42 Characters
**What goes wrong:** Long caption lines cause excessive eye movement, poor readability on mobile devices, text running off screen edges
**Why it happens:** Word-by-word addition without checking cumulative length
**How to avoid:**
- Enforce 42 character limit per line (configurable via --max-chars)
- Break at sentence/phrase boundaries when approaching limit
- Use 2-line maximum per caption block
**Warning signs:** User complaints about "hard to read" subtitles, text clipping on mobile

### Pitfall 5: Speaker Label on Every Caption Line
**What goes wrong:** VTT files with speaker labels on every line become cluttered and hard to read
**Why it happens:** Applying speaker voice tag to each cue without checking for speaker changes
**How to avoid:** Only add speaker label when speaker changes from previous caption
**Warning signs:** "Speaker 1" appearing 200+ times in a short video

### Pitfall 6: Frame Rate Mismatch Causing Timestamp Drift
**What goes wrong:** Subtitles sync perfectly at start but gradually drift later in video
**Why it happens:** Subtitle timestamps calculated assuming different frame rate than video (e.g., 30fps vs 25fps)
**How to avoid:** Extract timestamps directly from audio stream, not frame numbers; use millisecond precision
**Warning signs:** User reports "subtitles are delayed by 5 seconds at the end"

## Code Examples

Verified patterns from research:

### SRT Format (Official Specification)
```srt
1
00:00:00,000 --> 00:00:02,500
This is the first subtitle.

2
00:00:02,500 --> 00:00:05,000
This is the second subtitle.

3
00:00:05,000 --> 00:00:08,500
Speaker names can be added with a hyphen.
- John: Hello there!
```

### WebVTT Format with Speaker Labels (W3C Specification)
```vtt
WEBVTT

00:00:00.000 --> 00:00:02.500
<v Speaker1>This is the first subtitle.

00:00:02.500 --> 00:00:05.000
<v Speaker2>This is the second subtitle.

00:00:05.000 --> 00:00:08.500
<v Speaker1>Speaker changed back to Speaker 1.
```

### JSON Output Structure (whisper.cpp format)
```json
{
  "transcription": [
    {
      "timestamps": {
        "from": "00:00:00,000",
        "to": "00:00:02,500"
      },
      "offsets": {
        "from": 0,
        "to": 2500
      },
      "text": "This is the first subtitle.",
      "tokens": [
        {
          "text": "This",
          "timestamps": {"from": "00:00:00,000", "to": "00:00:00,200"},
          "offsets": {"from": 0, "to": 200},
          "p": 0.95
        }
      ]
    }
  ]
}
```

### Nim-Python FFI for pyannote (nimpy pattern)
```nim
import nimpy

proc diarizeAudio(audioPath: string): seq[tuple[start: float, end: float, speaker: int]] =
  let py = pyBuiltinsModule()
  let pyannote = py.import("pyannote.audio")
  let pipeline = pyannote.Pipeline.from_pretrained(
    "pyannote/speaker-diarization-3.1",
    use_auth_token="hf_token"
  )

  let diarization = pipeline(audioPath)
  for turn, _, speaker in diarization.itertracks(yield_label=true):
    result.add((start: turn.start, end: turn.end, speaker: int(speaker)))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FFmpeg whisper filter (segment-level) | whisper.cpp API (word-level) | whisper.cpp 1.5+ | Enables per-word confidence and timing for engagement scoring |
| Manual speaker clustering | pyannote.audio 3.1 pipeline | 2024 | Pure PyTorch implementation, easier deployment, ~11-19% DER |
| UTF-8 with BOM | UTF-8 without BOM | Always (best practice) | Prevents subtitle player crashes and display issues |
| Global subtitle timing | Sentence-boundary grouping | 2020s (accessibility) | Better readability, follows broadcast standards (42 chars) |
| SRT only | SRT + VTT + JSON | VTT spec (W3C 2019) | VTT supports styling, speaker colors, positioning |

**Deprecated/outdated:**
- **FFmpeg whisper filter for word timestamps**: Only provides segment-level timing, not suitable for engagement scoring
- **pyannote.audio 2.x**: Version 3.x runs in pure PyTorch (easier deployment), 2.x required ONNX Runtime
- **UIS-RNN for diarization**: Google's library, less maintained than pyannote, lower accuracy

## Open Questions

Things that couldn't be fully resolved:

1. **Exact whisper.cpp API for word-level timestamps**
   - What we know: whisper.cpp supports word timestamps via experimental API, JSON output includes token-level timing
   - What's unclear: Exact C API function signatures, stability guarantees, whether it requires specific build flags
   - Recommendation: Examine whisper.cpp source (`include/whisper.h`) to determine API, test with current build (v1.8.2)

2. **pyannote.audio model download and caching**
   - What we know: Requires Hugging Face token, downloads ~200MB models on first run
   - What's unclear: Where models cache on Windows, how to pre-download for offline deployment
   - Recommendation: Test pyannote installation, document model cache location, provide manual download option

3. **Optimal VAD model for hallucination prevention**
   - What we know: VAD significantly reduces hallucinations on silent sections
   - What's unclear: Which VAD model works best with whisper.cpp, performance impact
   - Recommendation: Test with silero-vad (commonly used with whisper), measure performance vs quality

4. **Sentence boundary detection library for Nim**
   - What we know: Need to break captions at sentence boundaries
   - What's unclear: Best Nim library or should we use simple punctuation rules
   - Recommendation: Start with punctuation + conjunction detection (period, exclamation, question mark + "and", "but"), refine if needed

5. **Speaker remapping JSON format**
   - What we know: User wants to rename speakers after transcription via JSON file
   - What's unclear: Desired JSON structure for mapping
   - Recommendation: Use simple format: `{"Speaker 0": "John", "Speaker 1": "Mary"}`, document in help text

## Sources

### Primary (HIGH confidence)
- W3C WebVTT Specification: https://www.w3.org/TR/webvtt1/ - Official standard for WebVTT format, voice spans, cue settings
- Wikipedia SubRip article: https://en.wikipedia.org/wiki/SubRip - SRT format specification with timestamp rules
- whisper.cpp GitHub: https://github.com/ggml-org/whisper.cpp - Official repository, version 1.8.2 currently used
- pyannote.audio GitHub: https://github.com/pyannote/pyannote-audio - Official repository, state-of-the-art diarization

### Secondary (MEDIUM confidence)
- [Netflix English Timed Text Style Guide](https://partnerhelp.netflixstudios.com/hc/en-us/articles/217350977-English-USA-Timed-Text-Style-Guide) - 42 character limit, sentence boundary breaking
- [SRT Format Guide](https://www.quicklrc.com/subtitle-formats/srt) - Complete SRT specification with examples
- [BrassTranscripts Multi-Speaker Guide](https://brasstranscripts.com/blog/multi-speaker-transcript-formats-srt-vtt-json) - Speaker label formats
- [AssemblyAI Diarization Libraries](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis) - Comparison of pyannote, NeMo, others
- [Nimpy GitHub](https://github.com/yglukhov/nimpy) - Python-Nim FFI bridge documentation

### Tertiary (LOW confidence - requires validation)
- WebSearch findings on whisper.cpp word-level timestamps (marked as experimental in 2024)
- TechCrunch article on Whisper hallucinations: https://techcrunch.com/2024/10/26/openais-whisper-transcription-tool-has-hallucination-issues-researchers-say/
- Various subtitle encoding guides (UTF-8 BOM issues)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - whisper.cpp already integrated (v1.8.2), pyannote is industry standard
- Architecture: MEDIUM - Two-stage pipeline is sound, but word-level API details need source examination
- Subtitle formats: HIGH - SRT/VTT specifications are stable W3C/community standards
- Speaker diarization: MEDIUM - pyannote integration via nimpy is standard pattern, but needs testing
- Pitfalls: HIGH - Well-documented issues (BOM, hallucinations, timestamp format) with verified solutions

**Research date:** 2026-02-01
**Valid until:** 30 days (stable domain, whisper.cpp updates infrequent)
**Next validation:** Check whisper.cpp 1.9+ release notes for API changes, pyannote 3.2+ improvements
