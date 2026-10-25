import std/[unittest, json, os, strutils, osproc]
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


import ../src/audio/[deepfilter, elevenlabs, provider]

suite "deepfilter provider":
  test "isDeepFilterAvailable never raises":
    discard isDeepFilterAvailable()

  test "whichDeepFilter returns a known form":
    let w = whichDeepFilter()
    check (w == "" or w == "deepFilter" or w.endsWith("-m df.enhance"))

  test "command construction quotes both paths":
    let c = buildDeepFilterCmd("deepFilter", "in dir/a b.wav", "out dir")
    check c == "deepFilter -o " & quoteShell("out dir") & " " & quoteShell("in dir/a b.wav")

  test "runDeepFilter output path / missing-tool error":
    let tmp = getTempDir() / "hc_df_test"
    let r = runDeepFilter("tests/fixtures/audio_clean.wav", tmp)
    if whichDeepFilter() == "":
      check not r.ok
      check "pip install deepfilternet" in r.err
    elif r.ok:
      check r.outputPath == tmp / "audio_clean.wav"
    removeDir(tmp)

  test "fallback prefix form is a python -m invocation":
    check buildDeepFilterCmd("python -m df.enhance", "a.wav", "o").startsWith("python -m df.enhance -o ")

  test "T-22-03: subprocess command quotes inputWav and outDir":
    let src = readFile("src/audio/deepfilter.nim")
    check "quoteShell(outDir)" in src
    check "quoteShell(inputWav)" in src
    for line in src.splitLines:
      if "execCmdEx(" in line and not line.strip.startsWith("#"):
        check "inputWav" notin line
        check "outDir" notin line

suite "elevenlabs cost":
  test "estimate 60s = $0.10":
    check abs(estimateElevenlabsCost(60.0) - 0.10) < 1e-9
  test "estimate 600s = $1.00":
    check abs(estimateElevenlabsCost(600.0) - 1.00) < 1e-9
  test "autoYes always true":
    check confirmElevenlabsCost(6000.0, false, true)
  test "<= $1 non-TTY auto-allowed":
    check confirmElevenlabsCost(600.0, false, false)
  test "> $1 non-TTY denied":
    check not confirmElevenlabsCost(601.0, false, false)
  test "> $1 TTY y":
    check confirmElevenlabsCost(6000.0, true, false, proc(): string = "y")
  test "> $1 TTY n":
    check not confirmElevenlabsCost(6000.0, true, false, proc(): string = "n")

suite "elevenlabs provider":
  let fixture = readFile("tests/fixtures/elevenlabs_isolator_response.bin")
  test "posts multipart with xi-api-key header to /audio-isolation/stream":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation/stream", 200, fixture)
    let outP = getTempDir() / "hc_el_out1.mp3"
    let r = elevenlabsIsolate(m, "secret", "tests/fixtures/audio_clean.wav", outP)
    check r.ok
    check m.calls.len == 1
    check m.calls[0].url.contains("/audio-isolation/stream")
    check m.calls[0].body == "audio:audio.wav"
    check (key: "xi-api-key", val: "secret") in m.lastHeaders
    removeFile(outP)
  test "writes response body atomically (no .tmp left)":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 200, fixture)
    let outP = getTempDir() / "hc_el_out2.mp3"
    let r = elevenlabsIsolate(m, "k", "tests/fixtures/audio_clean.wav", outP)
    check r.ok
    check readFile(outP) == fixture
    check not fileExists(outP & ".tmp")
    removeFile(outP)
  test "empty key fails mentioning ELEVENLABS_API_KEY":
    let r = elevenlabsIsolate(newMockHttpClient(), "", "x.wav", "o.mp3")
    check not r.ok
    check "ELEVENLABS_API_KEY" in r.err
  test "non-2xx fails without writing":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 401, "no")
    let outP = getTempDir() / "hc_el_out3.mp3"
    let r = elevenlabsIsolate(m, "k", "tests/fixtures/audio_clean.wav", outP)
    check not r.ok
    check not fileExists(outP)
  test "T-22-02: apiKey never logged":
    let src = readFile("src/audio/elevenlabs.nim")
    for line in src.splitLines:
      let s = line.strip
      if s.startsWith("#"): continue
      if "info(" in s or "warning(" in s or "error(" in s or "debug(" in s or
         s.startsWith("info ") or s.startsWith("warning ") or
         s.startsWith("error ") or s.startsWith("debug "):
        check "apiKey" notin line
        check "API_KEY" notin line

suite "provider selection":
  test "local without DFN raises":
    expect ValueError: discard resolveProvider("local", "", false)
  test "local with DFN":
    check resolveProvider("local", "x", true).kind == apLocal
  test "elevenlabs without key raises mentioning key":
    try:
      discard resolveProvider("elevenlabs", "")
      check false
    except ValueError as e:
      check "ELEVENLABS_API_KEY" in e.msg
  test "elevenlabs with key":
    let p = resolveProvider("elevenlabs", "key123")
    check p.kind == apElevenlabs
    check p.apiKey == "key123"
  test "auto with DFN -> local":
    check resolveProvider("auto", "", true).kind == apLocal
  test "auto without DFN + key -> elevenlabs":
    check resolveProvider("auto", "key123", false).kind == apElevenlabs
  test "auto with neither lists both remediations":
    try:
      discard resolveProvider("auto", "", false)
      check false
    except ValueError as e:
      check "pip install deepfilternet" in e.msg
      check "ELEVENLABS_API_KEY" in e.msg
  test "invalid backend names the bad value":
    try:
      discard resolveProvider("bogus", "")
      check false
    except ValueError as e:
      check "bogus" in e.msg
  test "2-arg overload resolves with key present":
    check resolveProvider("auto", "k").kind in {apLocal, apElevenlabs}
