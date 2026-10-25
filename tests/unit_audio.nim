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

import ../src/analyze/audio_enhance

suite "audio analyzer":
  let stats = parseFile("tests/fixtures/audio_stats.json")
  let allOff = (denoise: smOff, voiceIsolation: smOff, deReverb: smOff,
                deEss: smOff, humRemoval: smOff)
  let allOn = (denoise: smOn, voiceIsolation: smOn, deReverb: smOn,
               deEss: smOn, humRemoval: smOn)
  let allAuto = (denoise: smAuto, voiceIsolation: smAuto, deReverb: smAuto,
                 deEss: smAuto, humRemoval: smAuto)

  test "detectHum true when 50Hz band above -50 dBFS":
    check detectHum(stats)

  test "detectHum false when both bands at or below -50 dBFS":
    var s = stats.copy
    s["rms_50hz_band_dbfs"] = newJFloat(-60.0)
    check not detectHum(s)

  test "detectSibilance true on fixture ratio":
    check detectSibilance(stats)
    var s = stats.copy
    s["rms_4khz_plus_dbfs"] = newJFloat(-60.0)
    check not detectSibilance(s)

  test "detectNoise true above -55 dBFS":
    check detectNoise(stats)
    var s = stats.copy
    s["afftdn_noise_floor_dbfs"] = newJFloat(-70.0)
    check not detectNoise(s)

  test "all smOff yields all-false flags":
    let f = analyzeAudioForEnhancement("tests/fixtures/audio_hum_50hz.wav", allOff)
    check not (f.denoise or f.voiceIsolation or f.deReverb or f.deEss or f.humRemoval)

  test "all smOn yields all-true flags":
    let f = analyzeAudioForEnhancement("tests/fixtures/audio_clean.wav", allOn)
    check f.denoise and f.voiceIsolation and f.deReverb and f.deEss and f.humRemoval

  test "smAuto on real fixtures":
    let hum = analyzeAudioForEnhancement("tests/fixtures/audio_hum_50hz.wav", allAuto)
    check hum.humRemoval
    let sib = analyzeAudioForEnhancement("tests/fixtures/audio_sibilant.wav", allAuto)
    check sib.deEss
    let noisy = analyzeAudioForEnhancement("tests/fixtures/audio_noisy.wav", allAuto)
    check noisy.denoise
    check noisy.humRemoval  # 60 Hz tone mixed in
    let clean = analyzeAudioForEnhancement("tests/fixtures/audio_clean.wav", allAuto)
    check not clean.humRemoval
    check not clean.deEss
    check not clean.denoise

  test "runAstatsProbe returns numeric fields":
    let s = runAstatsProbe("tests/fixtures/audio_hum_50hz.wav")
    check s.hasKey("rms_full_dbfs")
    check s["rms_full_dbfs"].kind == JFloat
    check s["rms_full_dbfs"].getFloat < 0.0
    check s.hasKey("lavfi.astats.Overall.RMS_level")
