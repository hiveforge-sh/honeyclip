## AudioProvider variant + backend resolution. Full enhance() dispatch lands in 22-03.
import std/strutils
import ./deepfilter
import ../log

type
  AudioProviderKind* = enum apLocal, apElevenlabs
  AudioProvider* = object
    case kind*: AudioProviderKind
    of apLocal: discard
    of apElevenlabs: apiKey*: string
  AudioResult* = object
    outputPath*: string
    backendUsed*: AudioProviderKind

proc resolveProvider*(forceBackend, apiKey: string;
                      dfAvailable: bool): AudioProvider =
  ## Core logic with DeepFilterNet availability injected (deterministic tests).
  case forceBackend.toLowerAscii
  of "local":
    if not dfAvailable:
      raise newException(ValueError,
        "Backend 'local' requires DeepFilterNet: pip install deepfilternet")
    return AudioProvider(kind: apLocal)
  of "elevenlabs":
    if apiKey == "":
      raise newException(ValueError,
        "Backend 'elevenlabs' requires ELEVENLABS_API_KEY env var or config.toml [elevenlabs] apiKey")
    return AudioProvider(kind: apElevenlabs, apiKey: apiKey)
  of "auto", "":
    if dfAvailable:
      return AudioProvider(kind: apLocal)
    if apiKey != "":
      info "DeepFilterNet not found; falling back to ElevenLabs"
      return AudioProvider(kind: apElevenlabs, apiKey: apiKey)
    raise newException(ValueError,
      "No audio backend available.\n" &
      "Install DeepFilterNet locally:  pip install deepfilternet\n" &
      "Or set ELEVENLABS_API_KEY for the ElevenLabs API path (or [elevenlabs] apiKey in config.toml)")
  else:
    raise newException(ValueError, "Unknown --backend: " & forceBackend)

proc resolveProvider*(forceBackend, apiKey: string): AudioProvider =
  ## Detects DeepFilterNet lazily (only when it can matter).
  let needsDf = forceBackend.toLowerAscii in ["local", "auto", ""]
  resolveProvider(forceBackend, apiKey, needsDf and isDeepFilterAvailable())
