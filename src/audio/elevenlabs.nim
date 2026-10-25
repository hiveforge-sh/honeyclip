## ElevenLabs Voice Isolator HTTP client + cost gate.
## T-22-02: the API key is only ever sent as the xi-api-key header; never logged.
import std/[strformat, os, strutils]
import ../http_client
import ../log

const
  elevenlabsBase* = "https://api.elevenlabs.io/v1"
  elevenlabsCostPerMin* = 0.10  ## USD per minute of audio

proc elevenlabsBaseUrl*(): string =
  ## HONEYCLIP_ELEVENLABS_URL overrides the endpoint (used by the E2E tests to
  ## point at a localhost mock); defaults to the real API.
  let o = getEnv("HONEYCLIP_ELEVENLABS_URL")
  if o != "": o.strip(leading = false, chars = {'/'}) else: elevenlabsBase

proc estimateElevenlabsCost*(durationSec: float): float =
  (durationSec / 60.0) * elevenlabsCostPerMin

proc confirmElevenlabsCost*(durationSec: float; isTty, autoYes: bool;
                            readLineFn: proc(): string = nil): bool =
  ## autoYes -> true; cost <= $1 -> true; non-TTY above $1 -> false; else prompt.
  if autoYes: return true
  let cost = estimateElevenlabsCost(durationSec)
  if cost <= 1.0 + 1e-9: return true
  if not isTty:
    warning &"ElevenLabs would cost ~${cost:.2f} for {int(durationSec)}s; refusing without --yes on non-TTY"
    return false
  echo &"ElevenLabs audio isolation: {int(durationSec)}s audio, ~${cost:.2f} USD. Continue? [y/N]"
  let line = if readLineFn != nil: readLineFn() else: stdin.readLine()
  return line.strip.toLowerAscii in ["y", "yes"]

proc elevenlabsIsolate*(http: HttpClientLike; apiKey, inputWavPath, outPath: string
                       ): tuple[ok: bool, err: string] =
  if apiKey == "":
    return (false, "ElevenLabs requires ELEVENLABS_API_KEY env var or config.toml [elevenlabs]")
  try:
    let audioBytes = readFile(inputWavPath)
    let (code, body) = http.postMultipart(
      &"{elevenlabsBaseUrl()}/audio-isolation/stream",
      "audio", audioBytes, "audio.wav",
      [(key: "xi-api-key", val: apiKey)])
    if code notin 200 .. 299:
      return (false, &"ElevenLabs returned HTTP {code}")
    # Atomic write (WR-02 / T-22-05): temp file then rename.
    writeFile(outPath & ".tmp", body)
    moveFile(outPath & ".tmp", outPath)
    return (true, "")
  except CatchableError as e:
    return (false, e.msg)
