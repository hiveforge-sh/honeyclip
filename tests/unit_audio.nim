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
