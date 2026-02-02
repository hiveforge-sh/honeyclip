
const commands*: seq[tuple[name: string, help: string]] = @[
  ("cache", ""),
  ("caption", "Generate and render captions from transcripts with styling and NLE export"),
  ("clips", "Detect and export engaging clips from video"),
  ("desc", "Display a media file's description metadata"),
  ("engage", "Analyze video engagement (audio, motion, speech, faces)"),
  ("info", "Retrieve information and properties about media files"),
  ("levels", "Display loudness over time"),
  ("reframe", "Auto-reframe video to center active speaker"),
  ("subdump", "Dump text-based subtitles to stdout with formatting stripped out"),
  ("transcript", "Extract transcript with word timestamps, speaker diarization, export to SRT/VTT/JSON"),
  ("whisper", "Whisper front-end"),
]
