
const commands*: seq[tuple[name: string, help: string]] = @[
  ("cache", ""),
  ("desc", "Display a media file's description metadata"),
  ("info", "Retrieve information and properties about media files"),
  ("levels", "Display loudness over time"),
  ("subdump", "Dump text-based subtitles to stdout with formatting stripped out"),
  ("transcript", "Extract transcript with word timestamps, speaker diarization, export to SRT/VTT/JSON"),
  ("whisper", "Whisper front-end"),
]
