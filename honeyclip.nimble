# Package
version = "0.1.0"
author = "hiveforge-sh"
description = "honeyclip: Extract the sweetest moments from your video"
license = "Unlicense"
srcDir = "src"
bin = @["main=honeyclip"]

# Dependencies
requires "nim >= 2.2.2"
requires "checksums"
requires "tinyre#77469f5"
requires "nimpy >= 0.2.0"
requires "toml_serialization"
requires "malebolgia"

# Tasks
import std/os
import std/[strutils, strformat, tables]
import src/cli

var disableVpx = getEnv("DISABLE_VPX").len > 0
var disableSvtAv1 = getEnv("DISABLE_SVTAV1").len > 0
var disableHevc = getEnv("DISABLE_HEVC").len > 0
var enable12bit = getEnv("ENABLE_12BIT").len > 0
var enableWhisper = getEnv("DISABLE_WHISPER").len == 0
var enableCuda = getEnv("ENABLE_CUDA").len > 0 and not defined(macosx)

var flags = ""
if not disableVpx:
  flags &= "-d:enable_vpx "
if not disableSvtAv1:
  flags &= "-d:enable_svtav1 "
if not disableHevc:
  flags &= "-d:enable_hevc "
if enableWhisper:
  flags &= "-d:enable_whisper "
if enableCuda:
  flags &= "-d:enable_cuda "
if fileExists("build/lib/libfacedetection.a"):
  flags &= "-d:enable_ml "

proc findWindowsGcc(): string =
  ## Find the MinGW GCC executable on Windows
  ## Checks choosenim's bundled MinGW first, then falls back to PATH
  when defined(windows):
    let choosenimGcc = getHomeDir() / ".choosenim/toolchains/mingw64/bin/gcc.exe"
    if fileExists(choosenimGcc):
      return choosenimGcc
    # Fall back to gcc in PATH (user must ensure correct one is first)
    return "gcc"
  else:
    return "gcc"

task test, "Run unit tests":
  when defined(windows):
    let gcc = findWindowsGcc()
    exec &"nim c {flags} --gcc.exe:\"{gcc}\" --gcc.linkerexe:\"{gcc}\" -r tests/unit"
  else:
    exec &"nim c {flags} -r tests/unit"

task bench, "Run performance benchmarks":
  echo "Running performance benchmarks..."
  when defined(windows):
    let gcc = findWindowsGcc()
    exec &"nim c {flags} --gcc.exe:\"{gcc}\" --gcc.linkerexe:\"{gcc}\" -r tests/benchmark"
  else:
    exec &"nim c {flags} -r tests/benchmark"

task validateperf, "Run end-to-end performance validation":
  echo "Running performance validation suite..."
  when defined(windows):
    let gcc = findWindowsGcc()
    exec &"nim c {flags} --gcc.exe:\"{gcc}\" --gcc.linkerexe:\"{gcc}\" -r tests/performance_validation"
  else:
    exec &"nim c {flags} -r tests/performance_validation"

task coverage, "Run tests with coverage (Linux only)":
  # Coverage via gcov/lcov is Linux-only
  when defined(linux):
    # Build with coverage flags
    exec &"nim c {flags} --passC:--coverage --passL:--coverage -r tests/unit"
    # Generate LCOV report
    exec "lcov --capture --directory . --output-file lcov.info --ignore-errors source"
    # Remove system includes
    exec "lcov --remove lcov.info '/usr/*' '*/nimcache/*' --output-file lcov.info"
    # Generate HTML report (optional, for local viewing)
    exec "genhtml lcov.info --output-directory coverage_html || true"
    # Show summary
    exec "lcov --list lcov.info"
  else:
    echo "Coverage task requires Linux (lcov). Use CI for coverage reports."
    echo "On macOS/Windows: Run 'nimble test' for tests without coverage."

task make, "Export the project":
  # LTO disabled on Windows due to GCC 11.1.0 internal compiler error (ICE in choose_baseaddr)
  when defined(windows):
    let gcc = findWindowsGcc()
    # Use explicit gcc path to avoid shim in ~/.nimble/bin that lacks cc1.exe
    exec &"nim c -d:danger --panics:on {flags} --gcc.exe:\"{gcc}\" --gcc.linkerexe:\"{gcc}\" --out:honeyclip src/main.nim"
  else:
    exec &"nim c -d:danger --panics:on {flags} --passC:-flto --passL:-flto --out:honeyclip src/main.nim"
  when defined(macosx):
    exec "strip -ur honeyclip"
    exec "stat -f \"%z bytes\" ./honeyclip"
    echo ""
  when defined(linux):
    exec "strip -s honeyclip"

task cleanff, "Remove":
  rmDir("ffmpeg_sources")
  rmDir("build")

var disableDecoders: seq[string] = @[]
var disableEncoders: seq[string] = @[]
var disableDemuxers: seq[string] = @[]
var disableMuxers: seq[string] = @[]

# Marked as 'Experimental'
disableEncoders &= "avui,dca,mlp,opus,s302m,sonic,sonic_ls,truehd,vorbis".split(",")

# Can only decode (ambiguous encoder), Video [A-C]
disableDecoders &= "4xm,aasc,agm,aic,anm,ansi,apv,arbc,argo,aura,aura2,avrn,avs,bethsoftvid,bfi,binkvideo,bmv_video,brender_pix,c93,cavs,cdgraphics,cdtoons,cdxl,clearvideo,cllc,cmv,cpia,cri,cscd,cyuv".split(",")
# [D-I]
disableDecoders &= "dds,dfa,dsicinvideo,dxa,dxtory,escape124,escape130,fic,flic,fmvc,fraps,frwu,g2m,gdv,gem,hnm4video,hq_hqa,hqx,hymt,idcin,idf,iff_ilbm,imm4,imm5,indeo2,indeo3,indeo4,indeo5,interplayvideo,ipu".split(",")
# [J-M]
disableDecoders &= "jv,kgv1,kmvc,lagarith,lead,loco,lscr,m101,mad,mdec,media100,mimic,mjpegb,mmvideo,mobiclip,motionpixels,msa1,mscc,msmpeg4v1,msp2,mss1,mss2,mszh,mts2,mv30,mvc1,mvc2,mvdv,mvha,mwsc,mxpeg".split(",")
# [N-S]
disableDecoders &= "notchlc,nuv,paf_video,pdv,pgx,photocd,pictor,pixlet,prosumer,psd,ptx,qdraw,qpeg,rasc,rl2,rscc,rtv1,rv30,rv40,rv60,sanm,scpr,screenpresso,sga,sgirle,sheervideo,simbiosis_imx,smackvideo,smvjpeg,sp5x,srgc,svq3".split(",")
# [T-VP]
disableDecoders &= "targa_y216,tdsc,tgq,tgv,thp,tiertexseqvideo,tmv,tqi,truemotion1,truemotion2,truemotion2rt,tscc,tscc2,txd,ulti,v210x,vb,vble,vc1,vc1image,vcr1,vixl,vmdvideo,vmix,vmnc,vp3,vp4,vp5,vp6,vp6a,vp6f,vp7".split(",")
# [VQ-Z]
disableDecoders &= "vqc,vvc,wcmv,wmv3,wmv3image,wnv1,ws_vqa,xan_wc3,xan_wc4,xbin,xpm,ylc,yop,zerocodec".split(",")

# Can only decode, Audio [0-A]
disableDecoders &= "8svx_exp,8svx_fib,aac_latm,acelp.kelvin,adpcm_4xm,adpcm_afc,adpcm_agm,adpcm_aica,adpcm_ct,adpcm_dtk,adpcm_ea,adpcm_ea_maxis_xa,adpcm_ea_r1,adpcm_ea_r2,adpcm_ea_r3,adpcm_ea_xas,adpcm_ima_acorn,adpcm_ima_apc".split(",")
# [B-F]
disableDecoders &= "binkaudio_dct,binkaudio_rdft,bmv_audio,bonk,cbd2_dpcm,cook,derf_dpcm,dolby_e,dsd_lsbf,dsd_lsbf_planar,dsd_msbf,dsd_msbf_planar,dsicinaudio,dss_sp,dst,dvaudio,evrc,fastaudio,ftr".split(",")
disableDemuxers.add "bethsoftvid"
# [G-Q]
disableDecoders &= "g728,g729,gremlin_dpcm,gsm,gsm_ms,hca,hcom,iac,imc,interplay_dpcm,interplayacm,mace3,mace6,metasound,misc4,mp1,mp3adu,msnsiren,musepack7,musepack8,osq,paf_audio,qcelp,qdm2,qdmc,qoa".split(",")
# [R-Z]
disableDecoders &= "ra_288,ralf,rka,sdx2_dpcm,shorten,sipr,siren,smackaud,sol_dpcm,tak,truespeech,twinvq,vmdaudio,wady_dpcm,wavarc,wavesynth,westwood_snd1,wmalossless,wmapro,wmavoice,xan_dpcm,xma1,xma2".split(",")

# Can only encode
disableEncoders &= "a64_multi,a64_multi5,ttml".split(",")

# Technically obsolete
disableDecoders &= @["flv", "snow"]
disableEncoders &= @["flv", "snow"]
disableMuxers &= @["flv", "f4v", "rso", "segafilm"]
disableDemuxers &= @["flv", "live_flv", "kux", "a64", "alp", "apm", "mm", "pp_bnk", "rso", "vmd", "sdns"]
disableDemuxers &= @["segafilm"]

# Image formats
disableDecoders &= @["tiff"]
disableEncoders &= @["tiff"]
disableMuxers &= @["ico"]
disableDemuxers &= @["ico", "image_tiff_pipe", "image_svg_pipe"]

let encodersDisabled = disableEncoders.join(",")
let decodersDisabled = disableDecoders.join(",")
let demuxersDisabled = disableDemuxers.join(",")
let muxersDisabled = disableMuxers.join(",")

type Package = object
  name: string
  sourceUrl: string
  sha256: string
  buildArguments: seq[string]
  buildSystem: string = "autoconf"
  ffFlag: string = ""
  mirrorUrl: string = ""

let nvheaders = Package(
  name: "nv-codec-headers",
  sourceUrl: "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n13.0.19.0.tar.gz",
  sha256: "86d15d1a7c0ac73a0eafdfc57bebfeba7da8264595bf531cf4d8db1c22940116",
)
let lame = Package(
  name: "lame",
  sourceUrl: "http://deb.debian.org/debian/pool/main/l/lame/lame_3.100.orig.tar.gz",
  sha256: "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e",
  buildArguments: @["--disable-frontend", "--disable-decoder", "--disable-gtktest", "--disable-dependency-tracking"],
  ffFlag: "--enable-libmp3lame",
)
let opus = Package(
  name: "opus",
  sourceUrl: "https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.tar.gz",
  sha256: "b7637334527201fdfd6dd6a02e67aceffb0e5e60155bbd89175647a80301c92c",
  buildArguments: @["--disable-doc", "--disable-extra-programs"],
  ffFlag: "--enable-libopus",
)
let vpx = Package(
  name: "libvpx",
  sourceUrl: "https://github.com/webmproject/libvpx/archive/refs/tags/v1.15.2.tar.gz",
  sha256: "26fcd3db88045dee380e581862a6ef106f49b74b6396ee95c2993a260b4636aa",
  buildArguments: "--disable-dependency-tracking --disable-examples --disable-unit-tests --enable-pic --enable-runtime-cpu-detect --enable-vp9-highbitdepth".split(" "),
  ffFlag: "--enable-libvpx",
)
let dav1d = Package(
  name: "dav1d",
  sourceUrl: "https://code.videolan.org/videolan/dav1d/-/archive/1.5.2/dav1d-1.5.2.tar.bz2",
  sha256: "c748a3214cf02a6d23bc179a0e8caea9d6ece1e46314ef21f5508ca6b5de6262",
  buildSystem: "meson",
  ffFlag: "--enable-libdav1d",
)
let svtav1 = Package(
  name: "libsvtav1",
  sourceUrl: "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v3.1.0/SVT-AV1-v3.1.0.tar.bz2",
  sha256: "8231b63ea6c50bae46a019908786ebfa2696e5743487270538f3c25fddfa215a",
  buildSystem: "cmake",
  buildArguments: @["-DBUILD_APPS=OFF", "-DBUILD_DEC=OFF", "-DBUILD_ENC=ON", "-DENABLE_NASM=ON"],
  ffFlag: "--enable-libsvtav1",
)
let whisper = Package(
  name: "whisper",
  sourceUrl: "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.8.2.tar.gz",
  sha256: "bcee25589bb8052d9e155369f6759a05729a2022d2a8085c1aa4345108523077",
  buildSystem: "cmake",
  buildArguments: @[
    "-DGGML_NATIVE=OFF", # Favor portability, don't use native CPU instructions
    "-DGGML_CUDA=" & (if enableCuda: "ON" else: "OFF"),
    "-DWHISPER_SDL2=OFF",
    "-DWHISPER_BUILD_EXAMPLES=OFF",
    "-DWHISPER_BUILD_TESTS=OFF",
    "-DWHISPER_BUILD_SERVER=OFF",
    when defined(macosx) and hostCPU == "arm64": "-DGGML_METAL=ON" else: "-DGGML_METAL=OFF",
    when defined(macosx): "-DGGML_METAL_EMBED_LIBRARY=ON" else: "-DGGML_METAL_EMBED_LIBRARY=OFF",
  ],
  ffFlag: "--enable-whisper",
)
let x264 = Package(
  name: "x264",
  sourceUrl: "https://code.videolan.org/videolan/x264/-/archive/32c3b801191522961102d4bea292cdb61068d0dd/x264-32c3b801191522961102d4bea292cdb61068d0dd.tar.bz2",
  sha256: "d7748f350127cea138ad97479c385c9a35a6f8527bc6ef7a52236777cf30b839",
  buildArguments: "--disable-cli --disable-lsmash --disable-swscale --disable-ffms --enable-strip".split(" "),
  ffFlag: "--enable-libx264",
)
let x265 = Package(
  name: "x265",
  sourceUrl: "https://bitbucket.org/multicoreware/x265_git/downloads/x265_4.1.tar.gz",
  sha256: "a31699c6a89806b74b0151e5e6a7df65de4b49050482fe5ebf8a4379d7af8f29",
  buildSystem: "x265",
  ffFlag: "--enable-libx265"
)
let ffmpeg = Package(
  name: "ffmpeg",
  sourceUrl: "https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz",
  sha256: "05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41",
)

# ML Libraries
let libfacedetectionBaseArgs = @["-DBUILD_SHARED_LIBS=OFF", "-DDEMO=OFF", "-DCMAKE_BUILD_TYPE=MinSizeRel"]

# Platform-specific SIMD flags for libfacedetection
proc getLibfacedetectionArgs(): seq[string] =
  result = libfacedetectionBaseArgs
  when defined(macosx):
    # Check if running on Apple Silicon (ARM64)
    let (arch, _) = gorgeEx("uname -m")
    if arch.strip() == "arm64":
      result.add("-DENABLE_AVX2=OFF")
      result.add("-DENABLE_AVX512=OFF")
      result.add("-DENABLE_NEON=ON")
  elif defined(linux):
    # Check architecture on Linux
    let (arch, _) = gorgeEx("uname -m")
    if arch.strip() in ["aarch64", "arm64"]:
      result.add("-DENABLE_AVX2=OFF")
      result.add("-DENABLE_AVX512=OFF")
      result.add("-DENABLE_NEON=ON")

let libfacedetection = Package(
  name: "libfacedetection",
  sourceUrl: "https://github.com/ShiqiYu/libfacedetection/archive/refs/tags/v3.0.tar.gz",
  sha256: "66dc6b47b11db4bf4ef73e8b133327aa964dbd8b2ce9e0ef4d1e94ca08d40b6a",
  buildSystem: "cmake",
  buildArguments: getLibfacedetectionArgs(),
)

let opencv = Package(
  name: "opencv",
  sourceUrl: "https://github.com/opencv/opencv/archive/refs/tags/4.10.0.tar.gz",
  sha256: "b2171af5be6b26f7a06b1229948bbb2bdaa74fcf5cd097e0af6378fce50a6eb9",
  buildSystem: "cmake",
  buildArguments: @[
    "-DCMAKE_BUILD_TYPE=MinSizeRel",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_LIST=core,imgproc,objdetect",
    "-DBUILD_opencv_apps=OFF",
    "-DBUILD_EXAMPLES=OFF",
    "-DBUILD_DOCS=OFF",
    "-DBUILD_TESTS=OFF",
    "-DBUILD_PERF_TESTS=OFF",
    # Explicitly disable unwanted modules (BUILD_LIST alone is insufficient)
    "-DBUILD_opencv_calib3d=OFF",
    "-DBUILD_opencv_features2d=OFF",
    "-DBUILD_opencv_flann=OFF",
    "-DBUILD_opencv_dnn=OFF",
    "-DBUILD_opencv_gapi=OFF",
    "-DBUILD_opencv_highgui=OFF",
    "-DBUILD_opencv_ml=OFF",
    "-DBUILD_opencv_video=OFF",
    "-DBUILD_opencv_stitching=OFF",
    "-DBUILD_opencv_videoio=OFF",
    # NOTE: opencv_photo kept for future image preprocessing
    # Disable unused 3rdparty dependencies
    "-DWITH_CAROTENE=OFF",
    "-DWITH_EIGEN=OFF",
    "-DWITH_ADE=OFF",
    "-DWITH_FLATBUFFERS=OFF",
    "-DWITH_ITT=OFF",
    # Disable system integrations
    "-DWITH_CUDA=OFF",
    "-DWITH_OPENCL=OFF",
    "-DWITH_IPP=OFF",
    "-DWITH_TBB=OFF",
    "-DWITH_GTK=OFF",
    "-DWITH_QT=OFF",
    "-DWITH_FFMPEG=OFF",
    "-DWITH_V4L=OFF",
    "-DWITH_1394=OFF",
    "-DWITH_OPENEXR=OFF",
    "-DWITH_JASPER=OFF",
    "-DWITH_TIFF=OFF",
    "-DWITH_WEBP=OFF",
    "-DWITH_PNG=OFF",
    "-DWITH_JPEG=OFF",
    "-DENABLE_LTO=ON",
  ],
)

let onnxruntime = Package(
  name: "onnxruntime",
  sourceUrl: "https://github.com/microsoft/onnxruntime/archive/refs/tags/v1.20.1.tar.gz",
  sha256: "d4c005506a2bbf88a838b14f8d1578406b8be2fb64abb50beeff908fb272529e",
  buildSystem: "onnx",
  buildArguments: @[
    "--config", "MinSizeRel",
    "--minimal_build", "extended",
    "--disable_ml_ops",
    "--skip_tests",
    "--disable_exceptions",
  ],
)

proc setupPackages(enableWhisper: bool): seq[Package] =
  result = @[]
  if not defined(macosx):
    result.add nvheaders
  if enableWhisper:
    result.add whisper
  result &= [lame, opus, dav1d, x264]
  if not disableVpx:
    result.add vpx
  if not disableSvtAv1:
    result.add svtav1
  if not disableHevc:
    result.add x265
  return result

proc setupMLPackages(): seq[Package] =
  return @[libfacedetection, opencv, onnxruntime]

func location(package: Package): string = # tar location
  if package.name == "libvpx":
    "v1.15.2.tar.gz"
  elif package.name == "nv-codec-headers":
    "n13.0.19.0.tar.gz"
  elif package.name == "whisper":
    "v1.8.2.tar.gz"
  else:
    package.sourceUrl.split("/")[^1]

func dirName(package: Package): string =
  if package.name == "libvpx":
    return "libvpx-1.15.2"
  if package.name == "nv-codec-headers":
    return "nv-codec-headers-n13.0.19.0"
  if package.name == "whisper":
    return "whisper.cpp-1.8.2"
  if package.name == "libfacedetection":
    return "libfacedetection-3.0"
  if package.name == "opencv":
    return "opencv-4.10.0"
  if package.name == "onnxruntime":
    return "onnxruntime-1.20.1"

  var name = package.location
  for ext in [".tar.gz", ".tar.xz", ".tar.bz2", ".orig"]:
    if name.endsWith(ext):
      name = name[0..^ext.len+1]

  if package.name != "x265":
    return name.replace("_", "-")
  return name


# Windows path conversion utilities for bash interop
when defined(windows):
  proc detectBashPathStyle(): string =
    ## Detect if we're in WSL (linux-gnu) or MSYS2 (msys)
    ## Returns "wsl" for /mnt/c/... paths, "msys" for /c/... paths
    try:
      let ostype = gorgeEx("bash -c 'echo $OSTYPE'").output.strip()
      if ostype.contains("linux"):
        return "wsl"    # /mnt/c/Users/...
      elif ostype.contains("msys"):
        return "msys"   # /c/Users/...
      else:
        return "msys"   # Default fallback for unknown environments
    except:
      return "msys"     # Safe default if detection fails
  
  proc toUnixPath(p: string, style: string = ""): string =
    ## Convert Windows path to Unix style for bash
    ## style: "wsl" or "msys" (auto-detect if empty)
    let actualStyle = if style.len == 0: detectBashPathStyle() else: style
    result = p.replace("\\", "/")
    if result.len >= 2 and result[1] == ':':
      let drive = result[0].toLowerAscii
      case actualStyle
      of "wsl":
        result = "/mnt/" & drive & result[2..^1]
      of "msys":
        result = "/" & drive & result[2..^1]
      else:
        result = "/" & drive & result[2..^1]  # Default to msys style


proc getFileHash(filename: string): string =
  if not fileExists(filename):
    raise newException(IOError, "File does not exist: " & filename)

  # Try sha256sum first (Git Bash/Linux), then shasum (macOS), then certutil (Windows)
  var output: string
  var exitCode: int
  (output, exitCode) = gorgeEx("sha256sum " & filename)
  if exitCode != 0:
    (output, exitCode) = gorgeEx("shasum -a 256 " & filename)
  if exitCode != 0:
    # Windows fallback using certutil
    (output, exitCode) = gorgeEx("certutil -hashfile " & filename & " SHA256")
    if exitCode == 0:
      # certutil output format is different - hash is on second line
      let lines = output.splitLines()
      if lines.len >= 2:
        return lines[1].strip().toLowerAscii()
  if exitCode != 0:
    raise newException(IOError, "Cannot hash file: " & filename)
  result = output.split()[0]
  # sha256sum prefixes hash with \ when filename contains backslashes (Windows paths)
  result = result.strip(chars = {'\\'})

proc checkHash(package: Package, filename: string) =
  let hash = getFileHash(filename)
  if package.sha256 != hash:
    echo filename
    echo &"sha256 hash of {package.name} tarball do not match!\nExpected: {package.sha256}\nGot: {hash}"
    quit(1)


proc makeInstall(packageName: string = "", buildPath: string = "") =
  when defined(macosx):
    exec "make -j$(sysctl -n hw.ncpu)"
    exec "make install"
  elif defined(linux):
    exec "make -j$(nproc)"
    exec "make install"
  elif defined(windows):
    # Use mingw32-make to avoid Chocolatey's make which has SHELL path issues
    let mingwBin = toUnixPath(getHomeDir()) & ".choosenim/toolchains/mingw64/bin"
    # libvpx uses out-of-source build on Windows (see configure section)
    let cdPrefix = if packageName == "libvpx": "cd build_vpx && " else: ""
    # Use mingw32-make instead of make to avoid Windows path space issues with libtool
    exec &"bash -c 'export PATH=\"{mingwBin}:/c/Program Files/NASM:$PATH\" && {cdPrefix}mingw32-make -j4'"

    # LAME uses libtool which breaks on Windows due to space in Git path
    # Manually install instead of using make install
    if packageName == "lame":
      echo "Installing LAME manually (bypassing libtool)..."
      mkDir(buildPath / "lib")
      mkDir(buildPath / "include" / "lame")
      cpFile("libmp3lame" / ".libs" / "libmp3lame.a", buildPath / "lib" / "libmp3lame.a")
      cpFile("include" / "lame.h", buildPath / "include" / "lame" / "lame.h")
    elif packageName == "x264":
      # x264's make install fails on Windows due to gcc-ranlib path translation issues
      # Manually install the library and headers
      echo "Installing x264 manually (bypassing ranlib path issue)..."
      mkDir(buildPath / "lib")
      mkDir(buildPath / "lib" / "pkgconfig")
      mkDir(buildPath / "include")
      cpFile("libx264.a", buildPath / "lib" / "libx264.a")
      cpFile("x264.h", buildPath / "include" / "x264.h")
      cpFile("x264_config.h", buildPath / "include" / "x264_config.h")
      cpFile("x264.pc", buildPath / "lib" / "pkgconfig" / "x264.pc")
    else:
      exec &"bash -c 'export PATH=\"{mingwBin}:/c/Program Files/NASM:$PATH\" && {cdPrefix}mingw32-make install'"
  else:
    exec "make -j4"
    exec "make install"

# Forward declarations for ML library build infrastructure
proc addCcacheIfAvailable(cmakeArgs: var seq[string])

proc cmakeBuild(package: Package, buildPath: string, crossWindows: bool = false) =
  mkDir("build_cmake")

  var cmakeArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBUILD_STATIC_LIBS=ON",
    # Required for CMake 3.27+ which removed compatibility with cmake_minimum_required < 3.5
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
  ]

  # Only add Release build type if package doesn't specify one
  var hasBuildType = false
  for arg in package.buildArguments:
    if arg.contains("CMAKE_BUILD_TYPE"):
      hasBuildType = true
      break
  if not hasBuildType:
    cmakeArgs.add("-DCMAKE_BUILD_TYPE=Release")

  cmakeArgs &= package.buildArguments

  # On Windows, use MinGW Makefiles instead of Visual Studio
  when defined(windows):
    if not crossWindows:
      let mingwPath = getHomeDir() / ".choosenim/toolchains/mingw64/bin"
      cmakeArgs.add("-G")
      cmakeArgs.add("\"MinGW Makefiles\"")
      cmakeArgs.add(&"-DCMAKE_C_COMPILER={mingwPath}/gcc.exe")
      cmakeArgs.add(&"-DCMAKE_CXX_COMPILER={mingwPath}/g++.exe")
      cmakeArgs.add(&"-DCMAKE_MAKE_PROGRAM={mingwPath}/mingw32-make.exe")

  # Add ccache if available
  addCcacheIfAvailable(cmakeArgs)

  # Add platform-specific arguments for cross-compilation
  if crossWindows:
    cmakeArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix")
    cmakeArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
    cmakeArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")

    # Platform-specific build arguments for ML libraries
    case package.name
    of "opencv":
      # Already disabled in base config, but make explicit for cross-compile
      if not cmakeArgs.contains("-DWITH_CUDA=OFF"):
        cmakeArgs.add("-DWITH_CUDA=OFF")
      if not cmakeArgs.contains("-DWITH_OPENCL=OFF"):
        cmakeArgs.add("-DWITH_OPENCL=OFF")
    of "libfacedetection":
      # Disable demos/tests for cross-build (already in base config)
      discard
    else:
      discard

  withDir "build_cmake":
    let cmakeCmd = "cmake " & cmakeArgs.join(" ") & " .."
    echo "RUN: ", cmakeCmd
    exec cmakeCmd
    makeInstall()

  # Fix whisper.pc file to include correct library order and dependencies
  if package.name == "whisper":
    # Fix library naming for cross-compilation - add lib prefix if missing
    let libDir = buildPath / "lib"
    for libFile in ["ggml.a", "ggml-base.a", "ggml-cpu.a"]:
      let srcFile = libDir / libFile
      let dstFile = libDir / ("lib" & libFile)
      if fileExists(srcFile) and not fileExists(dstFile):
        echo &"Renaming {srcFile} to {dstFile}"
        exec &"mv \"{srcFile}\" \"{dstFile}\""
    
    let pcFile = buildPath / "lib/pkgconfig/whisper.pc"
    if fileExists(pcFile):
      echo "Fixing whisper.pc file"
      var content = readFile(pcFile)

      # Replace the Libs line with correct library order and add Libs.private
      when defined(macosx) and defined(arm64):
        content = content.replace(
          "Libs: -L${libdir} -lggml  -lggml-base -lwhisper",
          "Libs: -L${libdir} -lggml -lggml-base -lwhisper -lggml-cpu -lggml-blas -lggml-metal"
        )
      elif defined(macosx):
        content = content.replace(
          "Libs: -L${libdir} -lggml  -lggml-base -lwhisper",
          "Libs: -L${libdir} -lggml -lggml-base -lwhisper -lggml-cpu -lggml-blas"
        )
      else:
        content = content.replace(
          "Libs: -L${libdir} -lggml  -lggml-base -lwhisper",
          (if enableCuda: "Libs: -L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu -lggml-cuda -L/usr/local/cuda-12.8/lib64/stubs -L/usr/local/cuda-12.8/lib64 -lcuda -lcudart -lcublas -lcublasLt"
           else: "Libs: -L${libdir} -lwhisper -lggml-base -lggml -lggml-cpu")
        )

      if not content.contains("Libs.private:"):
        var libsPrivate = ""
        when defined(macosx):
          libsPrivate = "-framework Accelerate -framework MetalKit -framework Foundation"
          when hostCPU == "arm64":
            libsPrivate = "-framework Accelerate -framework Metal -framework MetalKit -framework Foundation"

        when defined(macosx):
          libsPrivate &= " -lc++"
        else:
          libsPrivate = "-lgomp -lpthread -lm -lstdc++"
        content = content.replace(
          "Cflags: -I${includedir}",
          &"Libs.private: {libsPrivate}\nCflags: -I${{includedir}}\n\nRequires:\nConflicts:"
        )

      writeFile(pcFile, content)

proc x265Build(buildPath: string, crossWindows: bool = false) =
  # Build x265 multiple times following the Homebrew approach:
  #  1: Build 12 bits static library version in separate directory (if enabled)
  #  2: Build 10 bits static library version in separate directory
  #  3: Build 8 bits version, linking also 10 and optionally 12 bits
  # By default supports 8 and 10 bits pixel formats (12-bit disabled for size)

  # For 10/12 bits version, only x86_64 has assembly instructions available
  var highBitDepthArgs: seq[string] = @[
    "-DHIGH_BIT_DEPTH=1",
    "-DEXPORT_C_API=0",
    "-DENABLE_SHARED=0",
    "-DENABLE_CLI=0"
  ]

  let isLinuxAarch64 = defined(linux) and hostCPU == "arm64"
  let isX86_64 = hostCPU in ["amd64", "i386"] # Nim uses "amd64" for x86_64

  if not isX86_64:
    highBitDepthArgs.add("-DENABLE_ASSEMBLY=0")

  if isLinuxAarch64:
    highBitDepthArgs.add("-DENABLE_SVE2=0")

  # Common cmake args for all builds
  var commonArgs = @[
    &"-DCMAKE_INSTALL_PREFIX={buildPath}",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",  # CMake 4 compatibility for subdirectories
  ]

  # On Windows, use MinGW Makefiles instead of Visual Studio
  when defined(windows):
    if not crossWindows:
      let mingwPath = getHomeDir() / ".choosenim/toolchains/mingw64/bin"
      commonArgs.add("-G")
      commonArgs.add("\"MinGW Makefiles\"")
      commonArgs.add(&"-DCMAKE_C_COMPILER={mingwPath}/gcc.exe")
      commonArgs.add(&"-DCMAKE_CXX_COMPILER={mingwPath}/g++.exe")
      commonArgs.add(&"-DCMAKE_MAKE_PROGRAM={mingwPath}/mingw32-make.exe")

  # Add cross-compilation flags if needed
  if crossWindows:
    commonArgs.add("-DCMAKE_SYSTEM_NAME=Windows")
    commonArgs.add("-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix")
    commonArgs.add("-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix")
    commonArgs.add("-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres")
    commonArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER")
    commonArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY")
    commonArgs.add("-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY")

  # Build 12-bit version (optional, disabled by default for size)
  if enable12bit:
    echo "Building x265 12-bit..."
    var cmake12Args = @["-S", "source", "-B", "12bit", "-DMAIN12=ON"] & highBitDepthArgs & commonArgs
    let cmake12Cmd = "cmake " & cmake12Args.join(" ")
    echo "RUN: ", cmake12Cmd
    exec cmake12Cmd
    exec "cmake --build 12bit"
    exec "mv 12bit/libx265.a 12bit/libx265_main12.a"

  # Build 10-bit version
  echo "Building x265 10-bit..."
  var cmake10Args = @["-S", "source", "-B", "10bit"] & highBitDepthArgs & commonArgs
  # Not applied for size: "-DENABLE_HDR10_PLUS=ON"
  let cmake10Cmd = "cmake " & cmake10Args.join(" ")
  echo "RUN: ", cmake10Cmd
  exec cmake10Cmd
  exec "cmake --build 10bit"
  exec "mv 10bit/libx265.a 10bit/libx265_main10.a"

  # Build 8-bit version with linked 10-bit and optionally 12-bit
  echo "Building x265 8-bit with multi-bit-depth support..."

  # Create 8bit directory and copy the 10-bit library
  mkDir("8bit")
  cpFile("10bit/libx265_main10.a", "8bit/libx265_main10.a")

  # Build cmake command
  var cmake8Cmd = "cmake -S source -B 8bit"
  if enable12bit:
    # Copy 12-bit library and configure for 12-bit support
    cpFile("12bit/libx265_main12.a", "8bit/libx265_main12.a")
    cmake8Cmd &= " \"-DEXTRA_LIB=x265_main10.a;x265_main12.a\""
    cmake8Cmd &= " -DLINKED_12BIT=1"
  else:
    cmake8Cmd &= " -DEXTRA_LIB=x265_main10.a"

  cmake8Cmd &= " -DEXTRA_LINK_FLAGS=-L."
  cmake8Cmd &= " -DLINKED_10BIT=1"
  cmake8Cmd &= " -DENABLE_SHARED=0"
  cmake8Cmd &= " -DENABLE_CLI=0"
  for arg in commonArgs:
    cmake8Cmd &= " " & arg

  if isLinuxAarch64:
    cmake8Cmd &= " -DENABLE_SVE2=0"

  echo "RUN: ", cmake8Cmd
  exec cmake8Cmd
  exec "cmake --build 8bit"

  # Manually combine libraries for multi-bit-depth support
  echo "Combining x265 libraries for multi-bit-depth support..."
  when defined(macosx):
    if enable12bit:
      exec "libtool -static -o 8bit/libx265_combined.a 8bit/libx265.a 10bit/libx265_main10.a 12bit/libx265_main12.a"
    else:
      exec "libtool -static -o 8bit/libx265_combined.a 8bit/libx265.a 10bit/libx265_main10.a"
  else:
    # For Linux or cross-compilation, use ar with MRI script
    var arCommand = "ar"
    when defined(windows):
      if not crossWindows:
        # Use Unix-style path for bash
        proc toUnixPath(p: string): string =
          result = p.replace("\\", "/")
          if result.len >= 2 and result[1] == ':':
            result = "/" & result[0].toLowerAscii & result[2..^1]
        arCommand = toUnixPath(getHomeDir()) & ".choosenim/toolchains/mingw64/bin/ar.exe"
    if crossWindows:
      arCommand = "x86_64-w64-mingw32-ar"

    # Create MRI script with paths relative to 8bit directory
    withDir "8bit":
      var mriContent = "CREATE libx265_combined.a\nADDLIB libx265.a\nADDLIB libx265_main10.a\n"
      if enable12bit:
        mriContent &= "ADDLIB libx265_main12.a\n"
      mriContent &= "SAVE\nEND\n"
      writeFile("combine.mri", mriContent)
      when defined(windows):
        # On Windows, use bash to run ar with MRI input
        exec &"bash -c '{arCommand} -M < combine.mri'"
      else:
        exec &"{arCommand} -M < combine.mri"

  # Replace the 8-bit only library with the combined one
  exec "mv 8bit/libx265_combined.a 8bit/libx265.a"

  # Install from 8bit build
  exec "cmake --install 8bit"


proc mesonBuild(buildPath: string, crossWindows: bool = false) =
  mkDir("build_meson")

  # On Windows, convert buildPath to Unix-style for meson
  var prefixPath = buildPath
  when defined(windows):
    proc toUnixPath(p: string): string =
      result = p.replace("\\", "/")
      if result.len >= 2 and result[1] == ':':
        result = "/" & result[0].toLowerAscii & result[2..^1]
    prefixPath = toUnixPath(buildPath)

  var mesonArgs = @[
    &"--prefix={prefixPath}",
    "--buildtype=release",
    "--default-library=static",
    "-Denable_docs=false",
    "-Denable_tools=false",
    "-Denable_examples=false",
    "-Denable_tests=false"
  ]

  if crossWindows:
    # Create cross-compilation file for meson
    let crossFile = "build_meson/meson-cross.txt"
    writeFile(crossFile, """
[binaries]
c = 'x86_64-w64-mingw32-gcc-posix'
cpp = 'x86_64-w64-mingw32-g++-posix'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
pkgconfig = 'x86_64-w64-mingw32-pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
""")
    mesonArgs.add("--cross-file=meson-cross.txt")

  withDir "build_meson":
    let mesonCmd = "meson setup " & mesonArgs.join(" ") & " .."
    echo "RUN: ", mesonCmd
    when defined(windows):
      # Find Python Scripts directory where meson is installed
      let pythonScripts = getEnv("APPDATA") / "Python/Python314/Scripts"
      let mingwBin = toUnixPath(getHomeDir()) & ".choosenim/toolchains/mingw64/bin"
      exec &"bash -c 'export PATH=\"{pythonScripts}:{mingwBin}:$PATH\" && {mesonCmd}'"
      exec &"bash -c 'export PATH=\"{pythonScripts}:{mingwBin}:$PATH\" && ninja'"
      exec &"bash -c 'export PATH=\"{pythonScripts}:{mingwBin}:$PATH\" && ninja install'"
    else:
      exec mesonCmd
      exec "ninja"
      exec "ninja install"

proc ffmpegSetup(crossWindows: bool) =
  # Create directories
  mkDir("ffmpeg_sources")
  mkDir("build")

  let buildPath = absolutePath("build")
  let packages = setupPackages(enableWhisper=enableWhisper)

  withDir "ffmpeg_sources":
    for package in @[ffmpeg] & packages:
      if not fileExists(package.location):

        if package.mirrorUrl != "":
          exec &"curl -O -L {package.mirrorUrl}"
        else:
          exec &"curl -O -L {package.sourceUrl}"
        # Use absolute path because gorgeEx behavior with withDir varies by platform
        checkHash(package, absolutePath(package.location))

      var tarArgs = "xf"
      if package.location.endsWith("bz2"):
        tarArgs = "xjf"

      if not dirExists(package.name):
        exec &"tar {tarArgs} {package.location}"
        if package.dirName != package.name:
          mvDir(package.dirName, package.name)
        let patchFile = &"../patches/{package.name}.patch"
        if fileExists(patchFile):
          let cmd = &"patch -d {package.name} -i {absolutePath(patchFile)} -p1 --force"
          echo "Applying patch: ", cmd
          exec cmd

      if package.name == "ffmpeg": # build later
        continue

      withDir package.name:
        if package.buildSystem == "cmake":
          cmakeBuild(package, buildPath, crossWindows)
        elif package.buildSystem == "x265":
          x265build(buildPath, crossWindows)
        elif package.buildSystem == "meson":
          mesonBuild(buildPath, crossWindows)
        else:
          # Special handling for nv-codec-headers which doesn't use configure
          if package.name == "nv-codec-headers":
            when defined(windows):
              let mingwBin = toUnixPath(getHomeDir()) & ".choosenim/toolchains/mingw64/bin"
              exec &"bash -c 'export PATH=\"{mingwBin}:$PATH\" && mingw32-make install PREFIX=\"{buildPath}\"'"
            else:
              exec &"make install PREFIX=\"{buildPath}\""
          else:
            let makefileCheck = when defined(windows):
              (if package.name == "libvpx": "build_vpx/Makefile" else: "Makefile")
            else: "Makefile"
            if not fileExists(makefileCheck) or package.name == "x264":
              var args = package.buildArguments
              var envPrefix = ""
              if crossWindows:
                if package.name == "libvpx":
                  args.add("--target=x86_64-win64-gcc")
                else:
                  args.add("--host=x86_64-w64-mingw32")
                envPrefix = "CC=x86_64-w64-mingw32-gcc-posix CXX=x86_64-w64-mingw32-g++-posix AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib "
              if package.name != "x264":
                args.add "--disable-shared"
              when defined(windows):
                # Run configure through bash on Windows with MinGW compilers
                # Convert C:\Users\... to /c/Users/... for Git Bash
                proc toUnixPath(p: string): string =
                  result = p.replace("\\", "/")
                  if result.len >= 2 and result[1] == ':':
                    result = "/" & result[0].toLowerAscii & result[2..^1]
                let unixBuildPath = toUnixPath(buildPath)
                # libvpx needs out-of-source build on Windows: configure writes
                # absolute MSYS paths (/c/Users/...) that mingw32-make can't resolve.
                # Building from a subdir makes paths relative (../libs.mk).
                var cdPrefix = ""
                if package.name == "libvpx":
                  mkDir("build_vpx")
                  cdPrefix = "cd build_vpx && "
                let configurePath = if package.name == "libvpx": "../" else: "./"
                var configureCmd = &"{configurePath}configure --prefix=\"{unixBuildPath}\" --enable-static " & args.join(" ")
                let mingwBase = toUnixPath(getHomeDir()) & ".choosenim/toolchains/mingw64"
                let mingwBin = mingwBase & "/bin"
                let ccEnv = "CC=\"" & mingwBin & "/gcc.exe\" CXX=\"" & mingwBin & "/g++.exe\" "
                # Disable _FORTIFY_SOURCE: MinGW GCC 11.1.0 lacks __memset_chk/__memcpy_chk
                let fortifyFix = "CFLAGS=\"-O2 -D_FORTIFY_SOURCE=0\" CXXFLAGS=\"-O2 -D_FORTIFY_SOURCE=0\" "
                # Set CONFIG_SHELL to avoid libtool using Windows path with spaces
                configureCmd = "bash -c 'export PATH=\"" & mingwBin & ":/c/Program Files/NASM:$PATH\" && export CONFIG_SHELL=/usr/bin/sh && " & cdPrefix & fortifyFix & ccEnv & envPrefix & configureCmd & "'"
                echo "RUN: ", configureCmd
                exec configureCmd
              else:
                var configureCmd = &"./configure --prefix=\"{buildPath}\" --enable-static " & args.join(" ")
                configureCmd = envPrefix & configureCmd
                echo "RUN: ", configureCmd
                exec configureCmd
            makeInstall(package.name, buildPath)

var filters: seq[string]
if enableWhisper:
  filters.add "whisper"
filters.add "scale,pad,format,gblur,aformat,abuffer,abuffersink,aresample,atempo,anull,anullsrc,volume,loudnorm,asetrate".split(",")

proc setupCommonFlags(packages: seq[Package]): string =
  var commonFlags = &"""
    --enable-version3 \
    --enable-static \
    --disable-shared \
    --disable-programs \
    --disable-doc \
    --disable-network \
    --disable-indevs \
    --disable-outdevs \
    --disable-xlib \
    --disable-bsfs \
    --disable-protocols \
    --enable-protocol=file \
    --disable-filters \
    --enable-filter={filters.join(",")} \
    --disable-encoder={encodersDisabled} \
    --disable-decoder={decodersDisabled} \
    --disable-demuxer={demuxersDisabled} \
    --disable-muxer={muxersDisabled} \
  """

  for package in packages:
    if package.ffFlag != "":
      commonFlags &= &"  {package.ffFlag} \\\n"

  if defined(arm) or defined(arm64):
    commonFlags &= "  --enable-neon \\\n"

  if defined(macosx):
    commonFlags &= "  --enable-videotoolbox \\\n"
    commonFlags &= "  --enable-audiotoolbox \\\n"
  else:
    commonFlags &= "  --enable-nvenc \\\n"
    commonFlags &= "  --enable-ffnvcodec \\\n"

  commonFlags &= "--disable-autodetect"
  return commonFlags


proc setupWindowsShell() =
  ## On Windows, copy sh.exe to mingw64/bin to avoid path-with-spaces issues.
  ## GNU Make resolves SHELL to the Windows path of sh.exe, and if that path
  ## contains spaces (e.g. C:/Program Files/Git/usr/bin/sh.exe), libtool breaks.
  when defined(windows):
    let mingwBin = getHomeDir() / ".choosenim/toolchains/mingw64/bin"
    let shDest = mingwBin / "sh.exe"
    if not fileExists(shDest):
      # Find Git's sh.exe
      let gitShell = "C:/Program Files/Git/usr/bin/sh.exe"
      if fileExists(gitShell):
        echo "Copying sh.exe to mingw64/bin to avoid path-with-spaces issues..."
        cpFile(gitShell, shDest)
      else:
        echo "Warning: Could not find Git's sh.exe at ", gitShell

proc setupDeps() =
  setupWindowsShell()

  let (mesonOutput, mesonCode) = gorgeEx("command -v meson")
  let (ninjaOutput, ninjaCode) = gorgeEx("command -v ninja")

  var toInstall: seq[string] = @[]

  if mesonCode != 0:
    toInstall.add("meson")
  if ninjaCode != 0:
    toInstall.add("ninja")

  if toInstall.len > 0:
    when defined(macosx):
      # macOS: use Homebrew
      exec "brew install " & toInstall.join(" ")
    elif defined(linux):
      # Linux: detect package manager and install
      # ninja is named ninja-build on Debian/Ubuntu
      var linuxPackages = toInstall
      for i, pkg in linuxPackages:
        if pkg == "ninja":
          linuxPackages[i] = "ninja-build"

      if fileExists("/etc/debian_version"):
        exec "sudo apt update && sudo apt install -y " & linuxPackages.join(" ")
      elif fileExists("/etc/fedora-release") or fileExists("/etc/redhat-release"):
        exec "sudo dnf install -y " & linuxPackages.join(" ")
      elif fileExists("/etc/arch-release"):
        # Arch uses 'ninja' not 'ninja-build'
        exec "sudo pacman -Sy --noconfirm " & toInstall.join(" ")
      else:
        # Fallback to pip for unknown Linux distros
        echo "Unknown Linux distribution, using pip to install dependencies..."
        exec "pip install " & toInstall.join(" ")
    elif defined(windows):
      # Windows: use pip (meson/ninja are Python packages)
      exec "pip install " & toInstall.join(" ")
    else:
      # Fallback
      exec "pip install " & toInstall.join(" ")

# ML Library Build Infrastructure

proc setupCcacheDir(crossWindows: bool) =
  # Set separate ccache directory to prevent cache collisions
  let (ccacheCheck, ccacheCode) = gorgeEx("command -v ccache")
  if ccacheCode == 0:
    let homeDir = getEnv("HOME")
    if homeDir.len > 0:
      let ccacheDir = if crossWindows:
        homeDir / ".ccache/x86_64-w64-mingw32"
      else:
        homeDir / ".ccache/native"
      mkDir(ccacheDir)
      putEnv("CCACHE_DIR", ccacheDir)
      echo &"Using ccache directory: {ccacheDir}"

proc addCcacheIfAvailable(cmakeArgs: var seq[string]) =
  # Add ccache to CMake if available
  let (_, code) = gorgeEx("command -v ccache")
  if code == 0:
    cmakeArgs.add("-DCMAKE_C_COMPILER_LAUNCHER=ccache")
    cmakeArgs.add("-DCMAKE_CXX_COMPILER_LAUNCHER=ccache")

proc printCcacheStats() =
  # Print ccache statistics
  let (output, code) = gorgeEx("ccache -s")
  if code == 0:
    echo ""
    echo "ccache stats:"
    echo output

proc checkMLDependencies() =
  # Check for required build dependencies
  var missingDeps: seq[string] = @[]

  let (cmakeOut, cmakeCode) = gorgeEx("command -v cmake")
  if cmakeCode != 0:
    missingDeps.add("cmake")

  let (pkgConfigOut, pkgConfigCode) = gorgeEx("command -v pkg-config")
  if pkgConfigCode != 0:
    missingDeps.add("pkg-config")

  let (pythonOut, pythonCode) = gorgeEx("command -v python3")
  if pythonCode != 0:
    let (python2Out, python2Code) = gorgeEx("command -v python")
    if python2Code != 0:
      missingDeps.add("python3")

  if missingDeps.len > 0:
    echo "ERROR: Required dependencies missing:"
    for dep in missingDeps:
      echo &"  - {dep}"
    echo ""
    echo "Install with:"
    when defined(macosx):
      echo "  brew install " & missingDeps.join(" ")
    elif defined(linux):
      # Try to detect Linux distribution
      if fileExists("/etc/debian_version"):
        echo "  sudo apt install " & missingDeps.join(" ")
      elif fileExists("/etc/redhat-release"):
        echo "  sudo dnf install " & missingDeps.join(" ")
      elif fileExists("/etc/arch-release"):
        echo "  sudo pacman -S " & missingDeps.join(" ")
      else:
        echo "  Ubuntu/Debian: sudo apt install " & missingDeps.join(" ")
        echo "  Fedora: sudo dnf install " & missingDeps.join(" ")
        echo "  Arch: sudo pacman -S " & missingDeps.join(" ")
    quit(1)

proc stripMLLibraries(buildPath: string) =
  ## Strip debug symbols from ML libraries to reduce size
  ## Creates separate debug symbol files before stripping (per CONTEXT.md)
  ## Uses platform-appropriate strip command
  echo "Stripping debug symbols from ML libraries..."

  let libDir = buildPath / "lib"
  if not dirExists(libDir):
    echo "  WARNING: lib directory not found, skipping strip"
    return

  when defined(macosx):
    # macOS: create .dSYM bundles with dsymutil, then strip -x
    # dsymutil extracts debug info into .dSYM bundle for crash reports
    echo "  Creating .dSYM debug symbol files..."
    # Use find command since walkFiles is not available in NimScript
    let (findOutput, findCode) = gorgeEx(&"find {libDir} -maxdepth 1 -name '*.a'")
    if findCode == 0:
      for libFile in findOutput.strip().splitLines():
        if libFile.len > 0:
          let dsymPath = libFile & ".dSYM"
          let (dsymOut, dsymCode) = gorgeEx(&"dsymutil {libFile} -o {dsymPath}")
          if dsymCode != 0:
            echo &"    WARNING: dsymutil failed for {libFile.extractFilename}: {dsymOut}"

    echo "  Stripping libraries..."
    let (output, code) = gorgeEx(&"find {libDir} -maxdepth 1 -name '*.a' -exec strip -x {{}} \\;")
    if code != 0:
      echo &"  WARNING: Strip failed: {output}"

  elif defined(linux):
    # Linux: extract debug info with objcopy, then strip --strip-unneeded
    # Creates .debug files that can be used with gdb for debugging
    echo "  Creating .debug symbol files..."
    # Use find command since walkFiles is not available in NimScript
    let (findOutput, findCode) = gorgeEx(&"find {libDir} -maxdepth 1 -name '*.a'")
    if findCode == 0:
      for libFile in findOutput.strip().splitLines():
        if libFile.len > 0:
          let debugPath = libFile & ".debug"
          let (debugOut, debugCode) = gorgeEx(&"objcopy --only-keep-debug {libFile} {debugPath}")
          if debugCode != 0:
            echo &"    WARNING: objcopy failed for {libFile.extractFilename}: {debugOut}"

    echo "  Stripping libraries..."
    let (output, code) = gorgeEx(&"find {libDir} -maxdepth 1 -name '*.a' -exec strip --strip-unneeded {{}} \\;")
    if code != 0:
      echo &"  WARNING: Strip failed: {output}"

  else:
    # Windows or other: skip stripping
    echo "  Skipping strip on this platform"

proc reportMLLibrarySizes(buildPath: string): int =
  ## Report ML library sizes and return total size in MB
  echo ""
  echo "ML Library Size Report:"
  echo "======================="

  let libDir = buildPath / "lib"
  if not dirExists(libDir):
    echo "  ERROR: lib directory not found"
    return 0

  var totalSize = 0
  var sizesByCategory: seq[(string, int)] = @[]

  # Use find command since walkFiles is not available in NimScript
  let (findOutput, findCode) = gorgeEx(&"find {libDir} -maxdepth 1 -name '*.a'")
  if findCode == 0:
    for libFile in findOutput.strip().splitLines():
      if libFile.len == 0:
        continue

      when defined(macosx):
        let (szOut, szCode) = gorgeEx(&"stat -f%z {libFile}")
      else:
        let (szOut, szCode) = gorgeEx(&"stat -c%s {libFile}")

      if szCode == 0:
        let sizeBytes = parseInt(szOut.strip())
        totalSize += sizeBytes

        # Categorize by library type
        let name = libFile.extractFilename
        let category =
          if name.startsWith("libopencv_"): "OpenCV"
          elif name.startsWith("libonnx"): "ONNX Runtime"
          elif name.startsWith("libabsl"): "Abseil"
          elif name == "libfacedetection.a": "libfacedetection"
          elif name.startsWith("libprotobuf"): "Protocol Buffers"
          elif name.startsWith("libre2"): "RE2"
          elif name.startsWith("libnsync"): "nsync"
          else: "Other"

        sizesByCategory.add((category, sizeBytes))

  # Aggregate by category
  var categoryTotals = initTable[string, int]()
  for (cat, size) in sizesByCategory:
    categoryTotals[cat] = categoryTotals.getOrDefault(cat, 0) + size

  for cat, size in categoryTotals.pairs:
    let sizeMB = size.float / (1024.0 * 1024.0)
    echo &"  {cat:20s}: {sizeMB:6.1f} MB"

  echo "======================="
  let totalMB = totalSize div (1024 * 1024)
  echo &"  Total ML libraries: {totalMB} MB"

  return totalMB

proc validateMLLibrarySize(sizeMB: int, softLimit: int = 50, hardLimit: int = 100) =
  ## Validate ML library size against soft/hard limits
  ## Per CONTEXT.md:
  ## - Soft limit (50MB): warning + interactive prompt (skip prompt in CI)
  ## - Hard limit (100MB): warning only (no build failure)
  if sizeMB > hardLimit:
    echo ""
    echo &"WARNING: ML libraries exceed {hardLimit}MB hard limit ({sizeMB}MB)"
    echo "This exceeds the size constraint from Phase 1."
    echo ""
    echo "Possible fixes:"
    echo "  1. Verify OpenCV modules are disabled (DBUILD_opencv_*=OFF)"
    echo "  2. Verify MinSizeRel build type is being used"
    echo "  3. Check that stripping was successful"
    # NOTE: No quit(1) here - per CONTEXT.md, hard limit is warning only
  elif sizeMB > softLimit:
    echo ""
    echo &"WARNING: ML libraries exceed {softLimit}MB soft limit ({sizeMB}MB)"
    echo "Consider additional optimization to meet target."

    # Interactive prompt unless in CI environment
    if not existsEnv("CI"):
      echo ""
      echo "Continue with build? [Y/n]: "
      # In nimscript, we can't actually read stdin, so just continue
      # The warning is the important part; the prompt is aspirational
      echo "(Continuing automatically - interactive prompts not supported in nimscript)"

proc shouldRebuild(package: Package, buildPath: string): bool =
  # Check if cache metadata exists and matches source SHA
  let cacheFile = buildPath / ".cache" / (package.name & ".json")
  if not fileExists(cacheFile):
    return true

  try:
    let cacheData = readFile(cacheFile)
    return not cacheData.contains(package.sha256)
  except:
    return true

proc writeCacheMetadata(package: Package, buildPath: string) =
  # Write cache metadata with SHA256 hash
  mkDir(buildPath / ".cache")
  let cacheFile = buildPath / ".cache" / (package.name & ".json")
  let cacheData = &"""{{
  "name": "{package.name}",
  "version": "{package.sourceUrl.split("/")[^1]}",
  "sha256": "{package.sha256}"
}}"""
  writeFile(cacheFile, cacheData)

proc copyOnnxDependencies(onnxBuildDir: string, destLib: string) =
  ## Copy ONNX Runtime dependencies that aren't installed by make install
  ## These are required for static linking on macOS and Linux
  echo "  [onnxruntime] Copying dependencies..."

  # Core ONNX libraries
  let coreLibs = [
    (onnxBuildDir / "libonnx.a", destLib / "libonnx.a"),
    (onnxBuildDir / "libonnx_proto.a", destLib / "libonnx_proto.a"),
  ]
  for (src, dest) in coreLibs:
    if fileExists(src):
      cpFile(src, dest)

  # Dependencies in _deps subdirectories
  let depsDir = onnxBuildDir / "_deps"

  # nsync
  let nsyncLib = depsDir / "google_nsync-build" / "libnsync_cpp.a"
  if fileExists(nsyncLib):
    cpFile(nsyncLib, destLib / "libnsync_cpp.a")

  # protobuf
  let protobufLib = depsDir / "protobuf-build" / "libprotobuf-lite.a"
  if fileExists(protobufLib):
    cpFile(protobufLib, destLib / "libprotobuf-lite.a")

  # re2
  let re2Lib = depsDir / "re2-build" / "libre2.a"
  if fileExists(re2Lib):
    cpFile(re2Lib, destLib / "libre2.a")

  # cpuinfo
  let cpuinfoLib = depsDir / "pytorch_cpuinfo-build" / "libcpuinfo.a"
  if fileExists(cpuinfoLib):
    cpFile(cpuinfoLib, destLib / "libcpuinfo.a")

  # clog (cpuinfo dependency)
  let clogLib = depsDir / "pytorch_clog-build" / "libclog.a"
  if fileExists(clogLib):
    cpFile(clogLib, destLib / "libclog.a")

  # Abseil libraries - copy all from various subdirectories
  let abslBuildDir = depsDir / "abseil_cpp-build" / "absl"
  if dirExists(abslBuildDir):
    # Find all .a files recursively in abseil build directory
    let (findOutput, findCode) = gorgeEx(&"find {abslBuildDir} -name '*.a'")
    if findCode == 0:
      for line in findOutput.splitLines():
        let libPath = line.strip()
        if libPath.len > 0 and fileExists(libPath):
          let libName = libPath.splitFile().name & ".a"
          cpFile(libPath, destLib / libName)

proc onnxBuild(buildPath: string, crossWindows: bool = false) =
  # ONNX Runtime requires special handling with build.sh
  if crossWindows:
    echo "ERROR: ONNX Runtime cross-compilation not yet supported"
    quit(1)

  # Determine parallelism
  var nproc = "4"
  when defined(macosx):
    let (output, code) = gorgeEx("sysctl -n hw.ncpu")
    if code == 0:
      nproc = output.strip()
  elif defined(linux):
    let (output, code) = gorgeEx("nproc")
    if code == 0:
      nproc = output.strip()

  # Run build.sh with minimal build configuration (static library)
  # CMAKE_POLICY_VERSION_MINIMUM=3.5 needed for CMake 3.27+ compatibility with older CMakeLists.txt in dependencies
  exec &"./build.sh --config MinSizeRel --minimal_build extended --disable_ml_ops --skip_tests --disable_exceptions --build_shared_lib OFF --parallel {nproc} --cmake_extra_defines CMAKE_INSTALL_PREFIX={buildPath} CMAKE_POLICY_VERSION_MINIMUM=3.5"

  # Determine OS-specific build directory
  var osBuildDir: string
  when defined(macosx):
    osBuildDir = "build/MacOS/MinSizeRel"
  elif defined(linux):
    osBuildDir = "build/Linux/MinSizeRel"
  else:
    echo "ERROR: Unsupported OS for ONNX Runtime build"
    quit(1)

  # Install libraries (build.sh creates build/<OS>/MinSizeRel/)
  withDir osBuildDir:
    exec &"make install"

  # Copy dependencies that make install doesn't handle
  copyOnnxDependencies(osBuildDir, buildPath / "lib")

  # Create wrapper header for convenient include path
  let wrapperHeader = buildPath / "include" / "onnxruntime" / "onnxruntime_c_wrapper.h"
  if not fileExists(wrapperHeader):
    echo "  [onnxruntime] Creating wrapper header..."
    writeFile(wrapperHeader, """// onnxruntime_c_wrapper.h - Wrapper header for ONNX Runtime C API
// This file provides a convenient include path for honeyclip
// Auto-generated by nimble makeml

#ifndef ONNXRUNTIME_C_WRAPPER_H
#define ONNXRUNTIME_C_WRAPPER_H

#include "core/session/onnxruntime_c_api.h"

#endif // ONNXRUNTIME_C_WRAPPER_H
""")

task makeml, "Build ML libraries from source":
  echo "Building ML libraries (libfacedetection, OpenCV, ONNX Runtime)..."
  echo ""

  # Check dependencies first
  checkMLDependencies()

  # Setup ccache for native builds
  setupCcacheDir(crossWindows=false)

  let buildPath = absolutePath("build")
  let packages = setupMLPackages()

  # Create directories
  mkDir("ml_sources")
  mkDir(buildPath / ".cache")

  var buildCount = 0
  var cacheCount = 0

  withDir "ml_sources":
    for i, package in packages:
      echo &"[{i+1}/{packages.len}] Building {package.name}..."

      # Check if rebuild needed
      if not shouldRebuild(package, buildPath) and fileExists(buildPath / "lib" / ("lib" & package.name & ".a")):
        echo &"  [{package.name}] Using cached build"
        cacheCount += 1
        continue

      # Download source if needed
      if not fileExists(package.location):
        echo &"  [{package.name}] Downloading source..."
        if package.mirrorUrl != "":
          exec &"curl -O -L {package.mirrorUrl}"
        else:
          exec &"curl -O -L {package.sourceUrl}"
        # Use absolute path because gorgeEx behavior with withDir varies by platform
        checkHash(package, absolutePath(package.location))

      # Extract tarball if needed
      var tarArgs = "xf"
      if package.location.endsWith("bz2"):
        tarArgs = "xjf"

      if not dirExists(package.name):
        echo &"  [{package.name}] Extracting..."
        exec &"tar {tarArgs} {package.location} && mv {package.dirName} {package.name}"

      # Build
      echo &"  [{package.name}] Configuring..."
      withDir package.name:
        if package.buildSystem == "cmake":
          echo &"  [{package.name}] Building..."
          cmakeBuild(package, buildPath, crossWindows=false)
        elif package.buildSystem == "onnx":
          echo &"  [{package.name}] Building..."
          onnxBuild(buildPath, crossWindows=false)
        else:
          echo &"ERROR: Unknown build system: {package.buildSystem}"
          quit(1)

      echo &"  [{package.name}] Installing..."
      writeCacheMetadata(package, buildPath)
      buildCount += 1

  echo ""
  if buildCount > 0:
    echo &"ML libraries built successfully ({buildCount} built, {cacheCount} cached)"
  else:
    echo "All ML libraries up to date (using cached builds)"

  # Strip debug symbols from all ML libraries (creates .dSYM/.debug files first)
  stripMLLibraries(buildPath)

  # Validate ML library sizes
  let totalSizeMB = reportMLLibrarySizes(buildPath)
  validateMLLibrarySize(totalSizeMB)

  # Print ccache statistics
  printCcacheStats()

task makeff, "Build FFmpeg from source":
  setupDeps()
  let buildPath = absolutePath("build")
  # Set PKG_CONFIG_PATH to include both standard and architecture-specific paths
  var pkgConfigPaths = @[buildPath / "lib/pkgconfig"]
  when defined(linux):
    when defined(arm64):
      pkgConfigPaths.add(buildPath / "lib/aarch64-linux-gnu/pkgconfig")
    else:
      pkgConfigPaths.add(buildPath / "lib/x86_64-linux-gnu/pkgconfig")
    pkgConfigPaths.add(buildPath / "lib64/pkgconfig")
    # Add common cmake install paths for pkg-config files
    pkgConfigPaths.add(buildPath / "lib/cmake")
    pkgConfigPaths.add(buildPath / "share/pkgconfig")
  putEnv("PKG_CONFIG_PATH", pkgConfigPaths.join(":"))

  ffmpegSetup(crossWindows=false)

  let packages = setupPackages(enableWhisper=enableWhisper)

  withDir "ffmpeg_sources/ffmpeg":
    when defined(windows):
      let mingwBin = toUnixPath(getHomeDir()) & ".choosenim/toolchains/mingw64/bin"
      let bp = toUnixPath(buildPath)
      # Flatten common flags to single line for bash -c wrapping
      let commonFlags = setupCommonFlags(packages).replace(" \\\n", " ").replace("\n", " ").strip()
      # Add NASM to PATH (Chocolatey installs to /c/Program Files/NASM/)
      let nasmPath = "/c/Program Files/NASM"
      let ffConfigureCmd = "bash -c 'export PATH=\"" & mingwBin & ":" & nasmPath & ":$PATH\" && " &
        "CC=\"" & mingwBin & "/gcc.exe\" CXX=\"" & mingwBin & "/g++.exe\" " &
        "./configure --prefix=\"" & bp & "\" " &
        "--pkg-config-flags=\"--static\" " &
        "--extra-cflags=\"-I" & bp & "/include\" " &
        "--extra-ldflags=\"-L" & bp & "/lib\" " &
        "--extra-libs=\"-lpthread -lm\" " &
        "--disable-x86asm " &
        commonFlags & "'"
      try:
        echo "RUN: ", ffConfigureCmd
        exec ffConfigureCmd
      except OSError:
        exec "bash -c 'cat ./ffbuild/config.log'"
        quit(1)
    else:
      try:
        exec &"""./configure --prefix="{buildPath}" \
          --pkg-config-flags="--static" \
          --extra-cflags="-I{buildPath}/include" \
          --extra-ldflags="-L{buildPath}/lib" \
          --extra-libs="-lpthread -lm" \""" & "\n" & setupCommonFlags(packages)
      except OSError:
        exec "cat ./ffbuild/config.log"
        quit(1)
    makeInstall()

task makeffwin, "Build FFmpeg for Windows cross-compilation":
  setupDeps()
  let buildPath = absolutePath("build")
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")

  ffmpegSetup(crossWindows=true)

  let packages = setupPackages(enableWhisper=enableWhisper)

  # Configure and build FFmpeg with MinGW
  withDir "ffmpeg_sources/ffmpeg":
    exec (&"""CC=x86_64-w64-mingw32-gcc-posix CXX=x86_64-w64-mingw32-g++-posix AR=x86_64-w64-mingw32-ar STRIP=x86_64-w64-mingw32-strip RANLIB=x86_64-w64-mingw32-ranlib PKG_CONFIG_PATH="{buildPath}/lib/pkgconfig" ./configure --prefix="{buildPath}" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I{buildPath}/include" \
      --extra-ldflags="-L{buildPath}/lib" \
      --extra-libs="-lpthread -lm -lstdc++" \
      --arch=x86_64 \
      --target-os=mingw32 \
      --cross-prefix=x86_64-w64-mingw32- \
      --enable-cross-compile \""" & "\n" & setupCommonFlags(packages))
    makeInstall()

task makemlwin, "Build ML libraries for Windows cross-compilation":
  echo "Building ML libraries for Windows (libfacedetection, OpenCV)..."
  echo ""

  # Check dependencies first
  setupDeps()
  checkMLDependencies()

  # Check for MinGW toolchain
  let (mingwCheck, mingwCode) = gorgeEx("command -v x86_64-w64-mingw32-gcc-posix")
  if mingwCode != 0:
    echo "ERROR: MinGW-w64 toolchain not found"
    echo "Install with:"
    when defined(macosx):
      echo "  brew install mingw-w64"
    elif defined(linux):
      echo "  Ubuntu/Debian: sudo apt install mingw-w64"
      echo "  Fedora: sudo dnf install mingw64-gcc mingw64-gcc-c++"
      echo "  Arch: sudo pacman -S mingw-w64-gcc"
    quit(1)

  # Setup ccache for cross-compilation builds
  setupCcacheDir(crossWindows=true)

  let buildPath = absolutePath("build")

  # Set PKG_CONFIG_PATH for cross-compilation
  putEnv("PKG_CONFIG_PATH", buildPath / "lib/pkgconfig")

  # Note: ONNX Runtime requires Windows SDK headers for DirectML support
  # For now, only build libfacedetection and OpenCV for cross-compilation
  let packages = @[libfacedetection, opencv]

  # Create directories
  mkDir("ml_sources")
  mkDir(buildPath / ".cache")

  var buildCount = 0
  var cacheCount = 0

  withDir "ml_sources":
    for i, package in packages:
      echo &"[{i+1}/{packages.len}] Building {package.name} for Windows..."

      # Check if rebuild needed
      if not shouldRebuild(package, buildPath) and fileExists(buildPath / "lib" / ("lib" & package.name & ".a")):
        echo &"  [{package.name}] Using cached build"
        cacheCount += 1
        continue

      # Download source if needed
      if not fileExists(package.location):
        echo &"  [{package.name}] Downloading source..."
        if package.mirrorUrl != "":
          exec &"curl -O -L {package.mirrorUrl}"
        else:
          exec &"curl -O -L {package.sourceUrl}"
        # Use absolute path because gorgeEx behavior with withDir varies by platform
        checkHash(package, absolutePath(package.location))

      # Extract tarball if needed
      var tarArgs = "xf"
      if package.location.endsWith("bz2"):
        tarArgs = "xjf"

      if not dirExists(package.name):
        echo &"  [{package.name}] Extracting..."
        exec &"tar {tarArgs} {package.location} && mv {package.dirName} {package.name}"

      # Build
      echo &"  [{package.name}] Configuring for Windows cross-compilation..."
      withDir package.name:
        if package.buildSystem == "cmake":
          echo &"  [{package.name}] Building..."
          cmakeBuild(package, buildPath, crossWindows=true)
        else:
          echo &"ERROR: Unknown build system: {package.buildSystem}"
          quit(1)

      echo &"  [{package.name}] Installing..."
      writeCacheMetadata(package, buildPath)
      buildCount += 1

  echo ""
  if buildCount > 0:
    echo &"ML libraries built successfully for Windows ({buildCount} built, {cacheCount} cached)"
  else:
    echo "All ML libraries up to date (using cached builds)"

  echo ""
  echo "NOTE: ONNX Runtime cross-compilation requires Windows SDK headers"
  echo "      Only libfacedetection and OpenCV are built for Windows cross-compilation"

  # Print ccache statistics
  printCcacheStats()

task windows, "Cross-compile to Windows (requires mingw-w64)":
  echo "Cross-compiling for Windows (64-bit)..."

  if not dirExists("build"):
    echo "FFmpeg for Windows not found. Run 'nimble makeffwin' first."
  else:
    exec "nim c -d:danger " & flags & " --os:windows --cpu:amd64 --cc:gcc " &
         "--gcc.exe:x86_64-w64-mingw32-gcc-posix " &
         "--gcc.linkerexe:x86_64-w64-mingw32-gcc-posix " &
         "--passL:-lbcrypt " & # Add Windows Bcrypt library
         "--passL:-lstdc++ " & # Add C++ standard library
         "--passL:-static " &
         "--out:honeyclip.exe src/main.nim"

    # Strip the Windows binary
    exec "x86_64-w64-mingw32-strip -s honeyclip.exe"

task zshcomplete, "Generate zsh completions":
  echo "#compdef honeyclip"
  echo ""
  echo "_honeyclip() {"
  echo "  local -a subcommands"
  echo "  subcommands=("
  for (command, help) in commands:
    if help != "":
      echo "    '" & command & ":" & help.replace("'", "'\\''") & "'"
    else:
      echo "    '" & command & "'"
  echo "  )"
  echo ""
  echo "  _describe 'command' subcommands"
  echo "}"
  echo ""
  echo "_honeyclip \"$@\""
