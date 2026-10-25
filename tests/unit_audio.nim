import std/[unittest, json, os, strutils]
import ../src/http_client

suite "http multipart":
  let fakeBytes = "ID3\x00\x01\x02binary\xff\x00bytes"

  test "mock postMultipart returns registered response":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 200, fakeBytes)
    let (code, body) = m.postMultipart("https://api.elevenlabs.io/v1/audio-isolation",
                                       "audio", "RIFF", "in.wav")
    check code == 200
    check body == fakeBytes

  test "mock records POST_MULTIPART call":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 200, "x")
    discard m.postMultipart("https://api.elevenlabs.io/v1/audio-isolation",
                            "audio", "RIFF", "in.wav")
    check m.calls.len == 1
    check m.calls[0].meth == "POST_MULTIPART"
    check m.calls[0].url.contains("/audio-isolation")
    check m.calls[0].body == "audio:in.wav"

  test "mock captures extra headers":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 200, "x")
    discard m.postMultipart("https://api.elevenlabs.io/v1/audio-isolation",
                            "audio", "RIFF", "in.wav",
                            [(key: "xi-api-key", val: "k")])
    check m.lastHeaders.len == 1
    check m.lastHeaders[0].key == "xi-api-key"

  test "base method raises CatchableError":
    let b = HttpClientLike()
    expect CatchableError:
      discard b.postMultipart("http://x", "audio", "d", "f.wav")

import ../src/config

suite "config":
  let tmpDir = getTempDir() / "honeyclip_unit_audio_cfg"
  setup:
    createDir(tmpDir)
    delEnv("ELEVENLABS_API_KEY")
  teardown:
    delEnv("ELEVENLABS_API_KEY")
    try: removeDir(tmpDir) except CatchableError: discard

  test "env var wins over TOML":
    let p = tmpDir / "c.toml"
    writeFile(p, "[elevenlabs]\napiKey = \"from-toml\"\n")
    putEnv("ELEVENLABS_API_KEY", "env-value")
    check resolveElevenlabsKey(p) == "env-value"

  test "TOML fallback when env unset":
    let p = tmpDir / "c.toml"
    writeFile(p, "[elevenlabs]\napiKey = \"from-toml\"\n")
    check resolveElevenlabsKey(p) == "from-toml"

  test "missing TOML returns empty":
    check resolveElevenlabsKey(tmpDir / "nope.toml") == ""

  test "TOML without elevenlabs section returns empty":
    let p = tmpDir / "c.toml"
    writeFile(p, "[api]\ngeminiKey = \"g\"\n")
    check resolveElevenlabsKey(p) == ""

  test "secret never co-occurs with log calls in config.nim":
    for line in readFile("src/config.nim").splitLines:
      if "apiKey" in line or "ELEVENLABS_API_KEY" in line:
        for bad in ["info(", "warning(", "error(", "debug("]:
          check bad notin line
