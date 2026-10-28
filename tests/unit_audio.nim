import std/[unittest, json, os, strutils, osproc, strformat]
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

  test "CR-02: ffmpegBin never resolves to a binary in the current directory":
    let saved = getEnv("HONEYCLIP_FFMPEG")
    let oldCwd = getCurrentDir()
    let d = getTempDir() / ("hc_plant_" & $getCurrentProcessId())
    removeDir(d)
    createDir(d / "build")
    for n in ["ffmpeg.exe", "ffmpeg", "build/ffmpeg.exe", "build/ffmpeg"]:
      writeFile(d / n, "planted")
    delEnv("HONEYCLIP_FFMPEG")
    setCurrentDir(d)
    let bin = ffmpegBin()
    let onPath = findExeOnPath("ffmpeg")
    setCurrentDir(oldCwd)
    if saved != "": putEnv("HONEYCLIP_FFMPEG", saved)
    check not bin.startsWith(d)
    check not onPath.startsWith(d)
    check bin == "" or bin.isAbsolute
    removeDir(d)

  test "WR-07: createPrivateTempDir makes a fresh unique directory":
    let a = createPrivateTempDir("hc_priv_")
    let b = createPrivateTempDir("hc_priv_")
    check a != b
    check dirExists(a) and dirExists(b)
    check extractFilename(a).startsWith("hc_priv_")
    check $getCurrentProcessId() notin extractFilename(a)
    when defined(posix):
      check getFilePermissions(a) == {fpUserRead, fpUserWrite, fpUserExec}
    removeDir(a)
    removeDir(b)

  test "ffmpegBin honours HONEYCLIP_FFMPEG first":
    let saved = getEnv("HONEYCLIP_FFMPEG")
    putEnv("HONEYCLIP_FFMPEG", "/custom/ffmpeg")
    check ffmpegBin() == "/custom/ffmpeg"
    if saved != "": putEnv("HONEYCLIP_FFMPEG", saved) else: delEnv("HONEYCLIP_FFMPEG")

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
    check (w == "" or "deepFilter" in w or w.endsWith("-m df.enhance"))

  test "command construction quotes both paths":
    let c = buildDeepFilterCmd("deepFilter", "in dir/a b.wav", "out dir")
    check c == "deepFilter --no-suffix -o " & quoteShell("out dir") & " " & quoteShell("in dir/a b.wav")

  test "CR-01: output resolves the --no-suffix name, else a suffixed one":
    let d = getTempDir() / ("hc_df_resolve_" & $getCurrentProcessId())
    removeDir(d)
    createDir(d)
    check resolveDeepFilterOutput("x/resampled.wav", d) == ""
    writeFile(d / "resampled_DeepFilterNet3.wav", "RIFF")
    check resolveDeepFilterOutput("x/resampled.wav", d) == d / "resampled_DeepFilterNet3.wav"
    writeFile(d / "resampled.wav", "RIFF")
    check resolveDeepFilterOutput("x/resampled.wav", d) == d / "resampled.wav"
    removeDir(d)

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
    check buildDeepFilterCmd("python -m df.enhance", "a.wav", "o").startsWith("python -m df.enhance --no-suffix -o ")

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
  test "WR-08: EOF at the prompt is a no, not a crash":
    let eof = proc(): string = raise newException(EOFError, "EOF")
    check not confirmElevenlabsCost(6000.0, true, false, eof)
    check not confirmElevenlabsCost(0.0, true, false, eof)
  test "WR-01: unknown duration is not auto-approved":
    check not confirmElevenlabsCost(0.0, false, false)
    check not confirmElevenlabsCost(0.0, true, false, proc(): string = "n")
    check confirmElevenlabsCost(0.0, true, false, proc(): string = "y")
    check confirmElevenlabsCost(0.0, false, true)

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
  test "WR-10: auto with neither falls back to ffmpeg, naming both remediations":
    let p = resolveProvider("auto", "", false)
    check p.kind == apFfmpeg
    check p.fromAuto
    check "pip install deepfilternet" in noNeuralBackendMsg
    check "ELEVENLABS_API_KEY" in noNeuralBackendMsg
  test "WR-10: only auto-resolved providers are marked fromAuto":
    check resolveProvider("auto", "", true).fromAuto
    check resolveProvider("auto", "k", false).fromAuto
    check not resolveProvider("local", "", true).fromAuto
    check not resolveProvider("elevenlabs", "k").fromAuto
    check not resolveProvider("ffmpeg", "").fromAuto
  test "WR-10: a failing backend is reported as backendFailed":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 500, "boom")
    let r = AudioProvider(kind: apElevenlabs, apiKey: "k").enhance(
      m, "tests/fixtures/audio_clean.wav", getTempDir() / ("hc_bf_" & $getCurrentProcessId()),
      EnhancementFlags(denoise: true), true, false)
    check r.outputPath == ""
    check r.backendFailed
    removeDir(getTempDir() / ("hc_bf_" & $getCurrentProcessId()))
  test "invalid backend names the bad value":
    try:
      discard resolveProvider("bogus", "")
      check false
    except ValueError as e:
      check "bogus" in e.msg
  test "WR-05: elevenlabs turns voice isolation on unless it is forced off":
    var f = EnhancementFlags()
    check applyProviderStages(AudioProvider(kind: apElevenlabs, apiKey: "k"), f, smAuto).len == 0
    check f.voiceIsolation
    var g = EnhancementFlags()
    discard applyProviderStages(AudioProvider(kind: apElevenlabs, apiKey: "k"), g, smOff)
    check not g.voiceIsolation
  test "WR-05: forcing voice isolation on a local backend warns":
    var f = EnhancementFlags(voiceIsolation: true)
    let w = applyProviderStages(AudioProvider(kind: apFfmpeg), f, smOn)
    check w.len == 1
    check "elevenlabs" in w[0]
    check not f.voiceIsolation
    var g = EnhancementFlags()
    check applyProviderStages(AudioProvider(kind: apLocal), g, smAuto).len == 0
  test "2-arg overload resolves with key present":
    check resolveProvider("auto", "k").kind in {apLocal, apElevenlabs}

import ../src/audio/[ffmpeg_chain, render]

proc freshDir(name: string): string =
  result = getTempDir() / ("hc_test_" & name & "_" & $getCurrentProcessId())
  removeDir(result)
  createDir(result)

suite "ffmpeg chain":
  let tmp = freshDir("chain")
  test "hum 50Hz notch":
    check "equalizer=f=50:t=h:w=10:g=-40" in buildHumDeessCmd("a.wav", "b.wav", true, false, false)
  test "hum 60Hz notch":
    check "equalizer=f=60:t=h:w=10:g=-40" in buildHumDeessCmd("a.wav", "b.wav", false, true, false)
  test "deesser":
    check "deesser=" in buildHumDeessCmd("a.wav", "b.wav", false, false, true)
  test "all off -> anull":
    check "anull" in buildHumDeessCmd("a.wav", "b.wav", false, false, false)
  test "paths with spaces and shell metacharacters are quoted":
    let c = buildHumDeessCmd("my file & x.wav", "o;ut.wav", false, false, false)
    check quoteShell("my file & x.wav") in c
    check quoteShell("o;ut.wav") in c
  test "runHumDeess produces output":
    let o = tmp / "hd.wav"
    check runHumDeess("tests/fixtures/audio_hum_50hz.wav", o,
                      EnhancementFlags(humRemoval: true, deEss: true))
    check fileExists(o)
  test "loudnorm two-pass":
    let o = tmp / "ln.wav"
    check runLoudnormTwoPassSubprocess("tests/fixtures/audio_clean.wav", o)
    check fileExists(o)
  test "loudness step is one constant gain, so quiet noise is not lifted":
    # 6 s of quiet noise, then a tone with one near-full-scale click: the
    # gain to -16 LUFS would push that click past the true-peak limit,
    # which made loudnorm fall back to dynamic mode and raise the noise
    # (on this input the old pass lifted the noise 13.7 dB more than the tone).
    let src = tmp / "quiet_then_peak.wav"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y " &
      "-f lavfi -i " & quoteShell("anoisesrc=d=6:c=pink:a=0.02:r=48000") &
      " -f lavfi -i " & quoteShell("sine=f=300:d=6:r=48000") &
      " -f lavfi -i " & quoteShell("aevalsrc=if(between(t\\,1\\,1.002)\\,0.95\\,0):d=6:s=48000") &
      " -filter_complex " & quoteShell("[1:a]volume=0.1[t];[t][2:a]amix=inputs=2:normalize=0[tc];" &
                                       "[0:a][tc]concat=n=2:v=0:a=1") & " " & quoteShell(src))
    let o = tmp / "ln_linear.wav"
    check runLoudnormTwoPassSubprocess(src, o)
    proc segRms(path: string; a, b: float): float =
      let (txt, _) = execCmdEx("ffmpeg -hide_banner -nostats -i " & quoteShell(path) &
        " -af " & quoteShell(&"atrim={a}:{b},astats=measure_overall=RMS_level:measure_perchannel=none") &
        " -f null -")
      for line in txt.splitLines:
        if "RMS level dB:" in line:
          return parseFloat(line.split("RMS level dB:")[1].strip)
      -999.0
    let quietGain = segRms(o, 0.5, 5.5) - segRms(src, 0.5, 5.5)
    let toneGain = segRms(o, 7.5, 11.5) - segRms(src, 7.5, 11.5)  # away from the click
    check quietGain > 1.0                    # it was quiet enough to need gain
    check abs(quietGain - toneGain) < 0.5    # same gain everywhere: linear
  test "linear loudness filter: constant gain, then an oversampled limiter":
    let f = buildLinearLoudnessFilter(-20.0, 48000)
    check f.startsWith("volume=4.00dB,aresample=192000,alimiter=")
    check "level=0" in f
    check f.endsWith("aresample=48000")
    check "loudnorm" notin f
  test "decodeMp3ToWav":
    let o = tmp / "dec.wav"
    check decodeMp3ToWav("tests/fixtures/elevenlabs_isolator_response.bin", o)
    check probeAudio(o).sampleRate > 0
  test "resampleTo48k keeps the source channels":
    let o = tmp / "r48.wav"
    check resampleTo48k("tests/fixtures/audio_44k_stereo.wav", o)
    let pr = probeAudio(o)
    check pr.sampleRate == 48000
    check pr.channels == 2
  test "split then join channels round-trips a 5.1 layout":
    let src = tmp / "s51.wav"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("sine=f=440:d=2") & " -af " &
      quoteShell("pan=5.1(side)|FL=c0|FR=0.5*c0|FC=0.2*c0|LFE=0*c0|SL=0.1*c0|SR=0.3*c0") &
      " -ar 48000 " & quoteShell(src))
    let pr = probeAudio(src)
    check pr.channels == 6
    check pr.layout == "5.1(side)"
    let parts = splitChannels(src, tmp / "split51", 6)
    check parts.len == 6
    for part in parts: check probeAudio(part).channels == 1
    let joined = tmp / "j51.wav"
    check joinChannels(parts, joined, pr.layout)
    let pj = probeAudio(joined)
    check pj.channels == 6
    check pj.layout == "5.1(side)"
    # Channel order must survive exactly, not just the layout name.
    proc fileMd5(path: string): string =
      execCmdEx("ffmpeg -loglevel error -i " & quoteShell(path) & " -f md5 -").output
    check fileMd5(joined) == fileMd5(src)
  test "join keeps input order and names the layout without remixing":
    let c = buildJoinChannelsCmd(@["a", "b"], "o.wav", "stereo")
    check "amerge=inputs=2,channelmap=map=0|1:channel_layout=stereo" in c
    check "channelmap" notin buildJoinChannelsCmd(@["a", "b", "c"], "o.wav", "3 channels")
  test "resampleFromWav restores rate/channels":
    let o = tmp / "back.wav"
    check resampleFromWav("tests/fixtures/audio_clean.wav", o, 44100, 2)
    let pr = probeAudio(o)
    check pr.sampleRate == 44100
    check pr.channels == 2
  test "WR-11: channel layouts with suffixes and named layouts":
    check parseChannels(" mono") == 1
    check parseChannels(" stereo") == 2
    check parseChannels(" 5.1") == 6
    check parseChannels(" 5.1(side)") == 6
    check parseChannels(" 7.1(wide)") == 8
    check parseChannels(" 7.1(wide-side)") == 8
    check parseChannels(" 5.0(side)") == 5
    check parseChannels(" quad(side)") == 4
    check parseChannels(" downmix") == 2
    check parseChannels(" hexagonal") == 6
    check parseChannels(" 7.1.4") == 12
    check parseChannels(" 22.2") == 24
    check parseChannels(" 3 channels") == 3
    check parseChannels(" 6 channels (FL+FR+FC+LFE+BL+BR)") == 6
    check parseChannels(" FL+FR+LFE") == 3
    check parseChannels(" fltp") == 0
  test "WR-11: a 5.1(side) source keeps 6 channels through enhance":
    let src = tmp / "surround.wav"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("sine=f=440:d=2") & " -af " &
      quoteShell("aformat=channel_layouts=5.1(side)") & " -ar 48000 " & quoteShell(src))
    check probeAudio(src).channels == 6
    let r = AudioProvider(kind: apFfmpeg).enhance(newMockHttpClient(), src, tmp / "surr",
      EnhancementFlags(denoise: true), false, false)
    check r.outputPath != ""
    check probeAudio(r.outputPath).channels == 6
  test "probeAudio duration":
    check abs(probeAudio("tests/fixtures/audio_clean.wav").durationSec - 5.0) < 0.1
  removeDir(tmp)

suite "audio enhance dispatch":
  let tmp = freshDir("dispatch")
  let allOn = EnhancementFlags(denoise: true, humRemoval: true, deEss: true)

  proc makeGapped(path: string, sec: int) =
    # 440 Hz tone with a 1s silent gap every 10s (chunk boundaries).
    let cmd = "ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("sine=frequency=440:duration=" & $sec) &
      " -af " & quoteShell("volume='if(lt(mod(t,10),9),1,0)':eval=frame") &
      " -ar 48000 -ac 1 " & quoteShell(path)
    discard execCmdEx(cmd)

  test "chunkAtSilence splits a 30s file":
    let src = tmp / "g30.wav"
    makeGapped(src, 30)
    let chunks = chunkAtSilence(src, 10.5, tmp / "chunks")
    check chunks.len >= 2
    for c in chunks:
      check probeAudio(c).durationSec <= 11.5
  test "chunk then reassemble preserves total duration":
    # Each crossfade must consume chunk overlap, not source audio (A/V sync).
    let src = tmp / "g45.wav"
    makeGapped(src, 45)
    let chunks = chunkAtSilence(src, 10.5, tmp / "rt_chunks")
    check chunks.len >= 4
    let o = tmp / "rt.wav"
    check reassembleWithCrossfade(chunks, o)
    check abs(probeAudio(o).durationSec - probeAudio(src).durationSec) < 0.02
  test "WR-06: chunkBounds never leaves a tail shorter than 1s":
    let b = chunkBounds(1200.02, 600.0, @[], 0.05)
    check b[0] == 0.0 and b[^1] == 1200.02
    check b[^1] - b[^2] >= 1.0 - 1e-9
    for i in 0 ..< b.len - 1:
      check b[i+1] - b[i] <= 600.0 + 1e-9
    # a silence just before the end must not be chosen as the last cut
    let s = chunkBounds(21.02, 10.5, @[20.9], 0.05)
    check s.len == 4
    check s[^1] - s[^2] >= 1.0 - 1e-9
    for i in 0 ..< s.len - 1:
      check s[i+1] - s[i] <= 10.5 + 1e-9
    # ordinary case unchanged: cut at the silence
    check chunkBounds(15.0, 10.0, @[8.0], 0.05) == @[0.0, 8.0, 15.0]
  test "chunkAtSilence short file returns input":
    check chunkAtSilence("tests/fixtures/audio_clean.wav", 60.0) ==
      @["tests/fixtures/audio_clean.wav"]
  test "reassembleWithCrossfade duration":
    let a = tmp / "ca.wav"
    let b = tmp / "cb.wav"
    makeGapped(a, 4)
    makeGapped(b, 4)
    let o = tmp / "cx.wav"
    check reassembleWithCrossfade(@[a, b], o, 50)
    check abs(probeAudio(o).durationSec - 7.95) < 0.1
  test "ffmpeg-only backend end to end":
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), "tests/fixtures/audio_noisy.wav", tmp / "o1", allOn, false, false)
    check r.outputPath != ""
    check fileExists(r.outputPath)
    check not dirExists(tmp / "o1.tmp")
  test "chunked path end to end":
    let src = tmp / "g30b.wav"
    makeGapped(src, 30)
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), src, tmp / "o2", allOn, false, false,
      chunkTriggerSec = 5.0, chunkSec = 10.5)
    check r.outputPath != ""
    check abs(probeAudio(r.outputPath).durationSec - 30.0) < 0.5
  test "local backend (skipped without DeepFilterNet)":
    if not isDeepFilterAvailable():
      skip()
    else:
      let r = AudioProvider(kind: apLocal).enhance(
        newMockHttpClient(), "tests/fixtures/audio_noisy.wav", tmp / "o3", allOn, false, false)
      check fileExists(r.outputPath)
  test "elevenlabs backend uses mock and decodes MP3":
    let m = newMockHttpClient()
    m.register("POST", "/audio-isolation", 200,
               readFile("tests/fixtures/elevenlabs_isolator_response.bin"))
    let r = AudioProvider(kind: apElevenlabs, apiKey: "k").enhance(
      m, "tests/fixtures/audio_noisy.wav", tmp / "o4", allOn, false, false)
    check r.outputPath != ""
    check fileExists(r.outputPath)
    check m.calls.len == 1
    check m.calls[0].meth == "POST_MULTIPART"
  test "cost gate denial makes no HTTP call":
    let long = tmp / "long.wav"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("anullsrc=r=8000:cl=mono") & " -t 700 " & quoteShell(long))
    let m = newMockHttpClient()
    let r = AudioProvider(kind: apElevenlabs, apiKey: "k").enhance(
      m, long, tmp / "o5", allOn, false, false)
    check r.outputPath == ""
    check m.calls.len == 0
  test "writeAudioOnly copies":
    let o = tmp / "ao.wav"
    check writeAudioOnly("tests/fixtures/audio_clean.wav", o)
    check fileExists(o)
  test "WR-04: writeAudioOnly transcodes to the output extension":
    let o = tmp / "ao.mp3"
    check writeAudioOnly("tests/fixtures/audio_clean.wav", o)
    check fileExists(o)
    check not readFile(o).startsWith("RIFF")
    check "mp3" in execCmdEx("ffmpeg -hide_banner -i " & quoteShell(o)).output
  test "mux command copies video and maps streams":
    let c = buildMuxCmd("v.mp4", "a.wav", "out.mp4")
    check "-c:v copy" in c
    check "-map 0:v? -map 1:a" in c
  test "WR-03: mux keeps subtitles, attachments and chapters":
    let c = buildMuxCmd("v.mkv", "a.wav", "out.mkv")
    check "-map 0:s? -map 0:t? -c:s copy -c:t copy" in c
    check "-map_chapters 0" in c
    let bare = buildMuxCmd("v.mkv", "a.wav", "out.mkv", keepExtra = false)
    check "0:s?" notin bare
    check "-map 0:v? -map 0:a:0 -map 1:a:0" in
      buildMuxCmd("v.mkv", "a.wav", "out.mkv", 1, 2)
  test "multi-track mux replaces one track in place, copies the rest":
    let c = buildMuxCmd("v.mp4", "a.wav", "out.mp4", audioTrack = 1, trackCount = 3)
    check "-map 0:v? -map 0:a:0 -map 1:a:0 -map 0:a:2" in c
    check "-c:a copy -c:a:1 aac" in c
    check "-map_metadata:s:a:1 0:s:a:1" in c
  test "multi-track mux keeps other tracks bit-identical":
    let vid = tmp / "mt.mp4"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("testsrc=duration=2:size=160x120:rate=10") & " -f lavfi -i " &
      quoteShell("sine=f=300:d=2") & " -f lavfi -i " & quoteShell("sine=f=900:d=2") &
      " -map 0 -map 1 -map 2 -pix_fmt yuv420p -c:a aac -shortest " & quoteShell(vid))
    check probeAudio(vid).audioTracks == 2
    let o = tmp / "mt_out.mp4"
    check muxEnhancedAudio(vid, "tests/fixtures/audio_clean.wav", o, 0, 2)
    check probeAudio(o).audioTracks == 2
    proc md5Of(path: string; track: int): string =
      execCmdEx("ffmpeg -loglevel error -i " & quoteShell(path) &
                " -map 0:a:" & $track & " -c copy -f md5 -").output
    check md5Of(vid, 1) == md5Of(o, 1)
    check md5Of(vid, 0) != md5Of(o, 0)
  test "WR-03: mux preserves a subtitle track":
    let srt = tmp / "s.srt"
    writeFile(srt, "1\n00:00:00,000 --> 00:00:01,500\nhello\n\n")
    let vid = tmp / "sub.mp4"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("testsrc=duration=2:size=160x120:rate=10") & " -i " & quoteShell(srt) &
      " -map 0 -map 1 -pix_fmt yuv420p -c:s mov_text " & quoteShell(vid))
    let o = tmp / "sub_out.mp4"
    check muxEnhancedAudio(vid, "tests/fixtures/audio_clean.wav", o)
    let banner = execCmdEx("ffmpeg -hide_banner -i " & quoteShell(o)).output
    check "Subtitle:" in banner
    check "Audio:" in banner
  test "WR-03: mux into an audio-only container (no video stream)":
    let src = tmp / "aonly.mka"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -i " &
      quoteShell("tests/fixtures/audio_clean.wav") & " -c:a flac " & quoteShell(src))
    let o = tmp / "aonly_out.mka"
    check muxEnhancedAudio(src, "tests/fixtures/audio_clean.wav", o)
    check probeAudio(o).sampleRate > 0
  test "WR-09: mux shifts the enhanced audio by the source offset":
    check "-i " & quoteShell("v.mp4") & " -itsoffset 0.478667 -i " & quoteShell("a.wav") in
      buildMuxCmd("v.mp4", "a.wav", "out.mp4", audioOffset = 0.478667)
    check "itsoffset" notin buildMuxCmd("v.mp4", "a.wav", "out.mp4")
    check "itsoffset" notin buildMuxCmd("v.mp4", "a.wav", "out.mp4", audioOffset = 0.0001)
  test "WR-09: audioStartOffset measures an audio delay":
    let plain = tmp / "plain_av.mp4"
    let delayed = tmp / "delayed_av.mp4"
    let gen = "ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("testsrc=duration=2:size=160x120:rate=10")
    discard execCmdEx(gen & " -i " & quoteShell("tests/fixtures/audio_clean.wav") &
      " -t 2 -pix_fmt yuv420p -c:a aac " & quoteShell(plain))
    discard execCmdEx(gen & " -itsoffset 0.5 -i " & quoteShell("tests/fixtures/audio_clean.wav") &
      " -t 2 -pix_fmt yuv420p -c:a aac " & quoteShell(delayed))
    check abs(audioStartOffset(plain)) < 0.03
    check abs(audioStartOffset(delayed) - 0.5) < 0.05
    let o = tmp / "delayed_out.mp4"
    check muxEnhancedAudio(delayed, "tests/fixtures/audio_clean.wav", o,
                           audioOffset = audioStartOffset(delayed))
    check abs(audioStartOffset(o) - audioStartOffset(delayed)) < 0.05
  test "mux produces video with new audio":
    let vid = tmp / "v.mp4"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("testsrc=duration=2:size=160x120:rate=10") & " -pix_fmt yuv420p " & quoteShell(vid))
    let o = tmp / "muxed.mp4"
    check muxEnhancedAudio(vid, "tests/fixtures/audio_clean.wav", o)
    check probeAudio(o).sampleRate > 0
  removeDir(tmp)

suite "resample contract":
  let tmp = freshDir("resample")
  let allOn = EnhancementFlags(denoise: true, humRemoval: true, deEss: true)
  test "44.1kHz stereo in -> 44.1kHz stereo out":
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), "tests/fixtures/audio_44k_stereo.wav", tmp / "a", allOn, false, false)
    let pr = probeAudio(r.outputPath)
    check pr.sampleRate == 44100
    check pr.channels == 2
  test "48kHz mono in -> 48kHz mono out":
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), "tests/fixtures/audio_clean.wav", tmp / "b", allOn, false, false)
    let pr = probeAudio(r.outputPath)
    check pr.sampleRate == 48000
    check pr.channels == 1
  test "probe of 44.1kHz fixture":
    let pr = probeAudio("tests/fixtures/audio_44k_stereo.wav")
    check pr.sampleRate == 44100
    check pr.channels == 2
  test "intermediate resampled.wav is 48kHz in the source layout (keepTmp)":
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), "tests/fixtures/audio_44k_stereo.wav", tmp / "c", allOn, false, false,
      keepTmp = true)
    check r.outputPath != ""
    let pr = probeAudio(tmp / "c.tmp" / "resampled.wav")
    check pr.sampleRate == 48000
    check pr.channels == 2
  test "stereo image survives the chain (left and right stay different)":
    # Left 300 Hz, right 900 Hz: a mono downmix would make them identical.
    let src = tmp / "lr.wav"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("sine=f=300:d=3") & " -f lavfi -i " & quoteShell("sine=f=900:d=3") &
      " -filter_complex " & quoteShell("[0:a][1:a]join=inputs=2:channel_layout=stereo") &
      " -ar 48000 " & quoteShell(src))
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), src, tmp / "lr", allOn, false, false)
    check r.outputPath != ""
    check probeAudio(r.outputPath).channels == 2
    proc channelMd5(path: string; ch: int): string =
      execCmdEx("ffmpeg -loglevel error -i " & quoteShell(path) & " -af " &
                quoteShell(&"pan=mono|c0=c{ch}") & " -f md5 -").output
    check channelMd5(r.outputPath, 0) != channelMd5(r.outputPath, 1)
  test "5.1 in -> 5.1 out through the whole chain":
    let src = tmp / "in51.wav"
    discard execCmdEx("ffmpeg -hide_banner -loglevel error -y -f lavfi -i " &
      quoteShell("sine=f=440:d=3") & " -af " &
      quoteShell("pan=5.1|FL=c0|FR=0.5*c0|FC=0.8*c0|LFE=0.1*c0|BL=0.2*c0|BR=0.3*c0") &
      " -ar 48000 " & quoteShell(src))
    let r = AudioProvider(kind: apFfmpeg).enhance(
      newMockHttpClient(), src, tmp / "o51", allOn, false, false)
    check r.outputPath != ""
    let pr = probeAudio(r.outputPath)
    check pr.channels == 6
    check pr.layout.startsWith("5.1")
  test "AAC bitrate scales with channel count":
    check aacBitrateK(1) == 192
    check aacBitrateK(2) == 192
    check aacBitrateK(6) == 448
    check "-b:a 448k" in buildMuxCmd("v.mp4", "a.wav", "out.mp4", channels = 6)
  removeDir(tmp)

import ../src/cmds/enhance as enhanceCmd

suite "cli enhance":
  test "defaults":
    let (o, code) = enhanceCmd.parseArgs(@["input.mp4"])
    check code == 0
    check o.inputPath == "input.mp4"
    check o.backend == "auto"
    check o.denoise == smAuto and o.voiceIsolation == smAuto and
          o.deReverb == smAuto and o.deEss == smAuto and o.humRemoval == smAuto
    check not o.audioOnly
    check not o.autoYes
  test "explicit flags":
    let (o, code) = enhanceCmd.parseArgs(@["--backend=elevenlabs", "--denoise=on",
      "--hum-removal=off", "--audio-only", "--yes", "input.mp4"])
    check code == 0
    check o.backend == "elevenlabs"
    check o.denoise == smOn
    check o.humRemoval == smOff
    check o.audioOnly
    check o.autoYes
    check o.inputPath == "input.mp4"
  test "per-stage flags and -o with separate value":
    let (o, code) = enhanceCmd.parseArgs(@["--voice-isolation=auto", "--de-reverb=on",
      "--de-ess=off", "-o", "/tmp/out.mp4", "input.mp4"])
    check code == 0
    check o.voiceIsolation == smAuto
    check o.deReverb == smOn
    check o.deEss == smOff
    check o.outputPath == "/tmp/out.mp4"
    check o.inputPath == "input.mp4"
  test "--audio-track defaults to 1 and parses both forms":
    check enhanceCmd.parseArgs(@["x.mp4"]).opts.audioTrack == 1
    check enhanceCmd.parseArgs(@["--audio-track=3", "x.mp4"]).opts.audioTrack == 3
    check enhanceCmd.parseArgs(@["--audio-track", "2", "x.mp4"]).opts.audioTrack == 2
  test "--audio-track rejects 0 and non-numbers":
    check enhanceCmd.parseArgs(@["--audio-track=0", "x.mp4"]).code != 0
    check enhanceCmd.parseArgs(@["--audio-track=two", "x.mp4"]).code != 0
  test "unknown flag returns nonzero":
    check enhanceCmd.parseArgs(@["--bogus", "input.mp4"]).code != 0
  test "bad stage value returns nonzero":
    check enhanceCmd.parseArgs(@["--denoise=maybe", "input.mp4"]).code != 0
  test "--help returns 0 and flags help":
    let (o, code) = enhanceCmd.parseArgs(@["--help"])
    check code == 0
    check o.helpShown
    check "usage: honeyclip enhance" in enhanceCmd.helpText
  test "-q and --debug":
    let (o, _) = enhanceCmd.parseArgs(@["-q", "--debug", "x.mp4"])
    check o.quiet and o.debug and o.inputPath == "x.mp4"
  test "registered in main.nim and cli.nim":
    check "(\"enhance\"" in readFile("src/main.nim")
    check "(\"enhance\"" in readFile("src/cli.nim")
