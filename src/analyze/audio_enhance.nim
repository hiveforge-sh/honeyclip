## Auto-detect analyzer for Phase 22 audio enhancement.
##
## Decides which enhancement stages (hum removal, de-essing, denoise) a clip
## needs by probing it with FFmpeg and applying simple, documented heuristics.
## Each stage can be forced on/off via StageMode, which overrides detection.
##
## Probes shell out to FFmpeg with every user-derived path wrapped in
## quoteShell (T-22-03).

import std/[osproc, os, strutils, json, math, tempfiles]
when defined(posix):
  import std/posix

type
  StageMode* = enum smAuto, smOn, smOff

  EnhancementFlags* = object
    denoise*: bool
    voiceIsolation*: bool  ## never detected; provider.applyProviderStages sets it
    deReverb*: bool        ## never detected; no backend implements it yet
    deEss*: bool
    humRemoval*: bool

const
  floorDb = -100.0
  humThresholdDb* = -50.0
  sibilanceRatio* = 0.15
  noiseFloorThresholdDb* = -55.0
  maxProbeSeconds = 30

proc findExeOnPath*(exe: string): string =
  ## Like std/os.findExe, but never looks in the current directory (findExe
  ## checks the CWD first on Windows) and skips relative PATH entries such as
  ## "." or "". Returns the absolute path, or "" when not found.
  if exe.len == 0: return ""
  for entry in getEnv("PATH").split(PathSep):
    var dir = entry.strip
    when defined(windows):
      if dir.len >= 2 and dir[0] == '"' and dir[^1] == '"':
        dir = dir[1 .. ^2]
    if dir.len == 0 or not dir.isAbsolute: continue
    when defined(windows):
      for ext in ExeExts:
        let cand = dir / addFileExt(exe, ext)
        if fileExists(cand): return cand
    else:
      let cand = dir / exe
      if fileExists(cand): return cand
  return ""

proc createPrivateTempDir*(prefix: string): string =
  ## A new, uniquely named directory under getTempDir() (WR-07). The random
  ## name comes from std/tempfiles and creation is atomic, so an existing
  ## directory or symlink planted by another user is never reused; on POSIX
  ## it is created 0700 so nobody else can read the audio inside.
  for _ in 0 ..< 100:
    let path = genTempPath(prefix, "")
    when defined(posix):
      if posix.mkdir(path.cstring, Mode(0o700)) == 0: return path
      if errno != EEXIST: raiseOSError(osLastError(), path)
    else:
      if not existsOrCreateDir(path): return path
  raise newException(OSError, "could not create a temporary directory in " & getTempDir())

proc ffmpegBin*(): string =
  ## HONEYCLIP_FFMPEG override, then the in-tree build next to the honeyclip
  ## binary (never the current directory: binary planting, CR-02), then
  ## absolute PATH entries. "" when no ffmpeg can be found.
  let envBin = getEnv("HONEYCLIP_FFMPEG")
  if envBin != "": return envBin
  let appDir = getAppDir()
  for cand in [appDir / "ffmpeg.exe", appDir / "ffmpeg",
               appDir / "build" / "ffmpeg.exe", appDir / "build" / "ffmpeg",
               appDir / "build" / "bin" / "ffmpeg.exe",
               appDir / "build" / "bin" / "ffmpeg"]:
    if fileExists(cand): return cand
  findExeOnPath("ffmpeg")

proc statNum(stats: JsonNode, key: string, default: float): float =
  ## Read a numeric stat that may be stored as a number or a string.
  if stats.kind != JObject or not stats.hasKey(key): return default
  let n = stats[key]
  case n.kind
  of JFloat: result = n.getFloat
  of JInt: result = n.getInt.float
  of JString:
    let s = n.getStr.strip.toLowerAscii
    if s == "-inf" or s == "-infinity": return floorDb
    try: result = parseFloat(s)
    except ValueError: result = default
  else: result = default
  if result.classify in {fcNan, fcInf, fcNegInf} or result < floorDb:
    result = floorDb

proc parseMetadata(output: string, into: JsonNode) =
  ## Parse `key=value` lines from ametadata print output (last value wins).
  for line in output.splitLines:
    let l = line.strip
    if l.startsWith("lavfi.") and '=' in l:
      let parts = l.split('=', 1)
      into[parts[0]] = newJString(parts[1].strip)

proc ffmpegProbeCmd(inputPath, filterChain: string): string =
  quoteShell(ffmpegBin()) & " -hide_banner -loglevel error -nostats -y -t " &
    $maxProbeSeconds & " -i " & quoteShell(inputPath) &
    " -af " & quoteShell(filterChain) & " -f null -"

proc probeRms(inputPath, prefilter: string): float =
  ## Overall RMS (dBFS) of the input after an optional filter prefix.
  let chain = (if prefilter != "": prefilter & "," else: "") &
              "astats=metadata=1,ametadata=print:file=-"
  let (output, code) = execCmdEx(ffmpegProbeCmd(inputPath, chain))
  if code != 0: return floorDb
  let md = newJObject()
  parseMetadata(output, md)
  statNum(md, "lavfi.astats.Overall.RMS_level", floorDb)

proc decodeMono(inputPath: string, sampleRate: int): seq[int16] =
  ## Decode up to maxProbeSeconds of audio to mono s16le samples.
  let tmpDir = try: createPrivateTempDir("honeyclip_probe_")
               except OSError: return @[]
  defer:
    try: removeDir(tmpDir) except CatchableError: discard
  let tmp = tmpDir / "probe.raw"
  let cmd = quoteShell(ffmpegBin()) & " -hide_banner -loglevel error -nostats -y -t " &
            $maxProbeSeconds & " -i " & quoteShell(inputPath) &
            " -ac 1 -ar " & $sampleRate & " -f s16le " & quoteShell(tmp)
  let (_, code) = execCmdEx(cmd)
  if code != 0 or not fileExists(tmp): return @[]
  let raw = readFile(tmp)
  result = newSeq[int16](raw.len div 2)
  for i in 0 ..< result.len:
    result[i] = cast[int16](uint16(raw[2*i].uint8) or (uint16(raw[2*i+1].uint8) shl 8))

proc bandRmsDb(samples: seq[int16], sampleRate: int, freq: float): float =
  ## Hann-windowed Goertzel: RMS level (dBFS) of a single sinusoidal component.
  let n = samples.len
  if n < 64: return floorDb
  let w = 2.0 * PI * freq / sampleRate.float
  let coeff = 2.0 * cos(w)
  var s1, s2 = 0.0
  for i in 0 ..< n:
    let win = 0.5 - 0.5 * cos(2.0 * PI * i.float / (n - 1).float)
    let s0 = samples[i].float / 32768.0 * win + coeff * s1 - s2
    s2 = s1
    s1 = s0
  let power = s1*s1 + s2*s2 - coeff*s1*s2
  let amp = 4.0 * sqrt(max(power, 0.0)) / n.float  # 4/N compensates the Hann window gain
  let rms = amp / sqrt(2.0)
  if rms <= 1e-5: floorDb else: max(floorDb, 20.0 * log10(rms))

proc runAstatsProbe*(inputPath: string): JsonNode =
  ## Probe level statistics used by the hum and sibilance detectors.
  ## Keys: rms_full_dbfs, rms_4khz_plus_dbfs, rms_50hz_band_dbfs,
  ## rms_60hz_band_dbfs, plus raw FFmpeg `lavfi.astats.*` fields.
  result = newJObject()
  if not fileExists(inputPath): return
  let (output, code) = execCmdEx(
    ffmpegProbeCmd(inputPath, "astats=metadata=1,ametadata=print:file=-"))
  if code != 0: return
  parseMetadata(output, result)
  result["rms_full_dbfs"] = newJFloat(statNum(result, "lavfi.astats.Overall.RMS_level", floorDb))
  result["rms_4khz_plus_dbfs"] = newJFloat(probeRms(inputPath, "highpass=f=4000"))
  let samples = decodeMono(inputPath, 48000)
  result["rms_50hz_band_dbfs"] = newJFloat(bandRmsDb(samples, 48000, 50.0))
  result["rms_60hz_band_dbfs"] = newJFloat(bandRmsDb(samples, 48000, 60.0))

proc runAfftdnProbe*(inputPath: string): JsonNode =
  ## Estimate the broadband noise floor as the residual level above 8 kHz,
  ## where speech carries little energy but broadband noise does. FFmpeg's
  ## afftdn does not emit its noise estimate as frame metadata, so this is a
  ## proxy stored under afftdn_noise_floor_dbfs.
  result = newJObject()
  if not fileExists(inputPath): return
  result["afftdn_noise_floor_dbfs"] = newJFloat(probeRms(inputPath, "highpass=f=8000"))

proc detectHum*(stats: JsonNode): bool =
  ## HIGH confidence: mains hum is a narrow 50/60 Hz spike.
  statNum(stats, "rms_50hz_band_dbfs", floorDb) > humThresholdDb or
    statNum(stats, "rms_60hz_band_dbfs", floorDb) > humThresholdDb

proc detectSibilance*(stats: JsonNode): bool =
  ## MEDIUM confidence: linear level ratio of >4 kHz content to full band.
  let full = statNum(stats, "rms_full_dbfs", floorDb)
  let hi = statNum(stats, "rms_4khz_plus_dbfs", floorDb)
  pow(10.0, (hi - full) / 20.0) > sibilanceRatio

proc detectNoise*(stats: JsonNode): bool =
  ## MEDIUM confidence: elevated noise floor.
  statNum(stats, "afftdn_noise_floor_dbfs", floorDb) > noiseFloorThresholdDb

proc resolveMode(mode: StageMode, heuristic: bool): bool =
  case mode
  of smOn: true
  of smOff: false
  of smAuto: heuristic

proc analyzeAudioForEnhancement*(inputPath: string,
                                 modes: tuple[denoise, voiceIsolation, deReverb,
                                              deEss, humRemoval: StageMode]
                                ): EnhancementFlags =
  ## Apply StageMode overrides; probe only when some stage is smAuto.
  var stats = newJObject()
  var fft = newJObject()
  if modes.humRemoval == smAuto or modes.deEss == smAuto:
    stats = runAstatsProbe(inputPath)
  if modes.denoise == smAuto:
    fft = runAfftdnProbe(inputPath)

  result.humRemoval = resolveMode(modes.humRemoval, detectHum(stats))
  result.deEss = resolveMode(modes.deEss, detectSibilance(stats))
  result.denoise = resolveMode(modes.denoise, detectNoise(fft))
  # deReverb / voiceIsolation are provider-driven, never heuristic-detected.
  result.deReverb = resolveMode(modes.deReverb, false)
  result.voiceIsolation = resolveMode(modes.voiceIsolation, false)
