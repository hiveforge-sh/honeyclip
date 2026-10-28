## Locating the external FFmpeg tools without ever running a binary from the
## current directory. On Windows both std/os.findExe and a bare command name
## given to cmd.exe or CreateProcess look in the CWD first, so running
## honeyclip inside a downloaded folder could execute a planted ffmpeg.exe.

import std/[os, strutils]

proc findExeOnPath*(exe: string): string =
  ## Like std/os.findExe, but never looks in the current directory and skips
  ## relative PATH entries such as "." or "". Returns the absolute path, or
  ## "" when not found.
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

proc besideApp(exe: string): string =
  ## exe in the honeyclip binary's own directory or its build/ tree.
  let appDir = getAppDir()
  for dir in [appDir, appDir / "build", appDir / "build" / "bin"]:
    for name in [exe & ".exe", exe]:
      if fileExists(dir / name): return dir / name
  ""

proc ffmpegBin*(): string =
  ## HONEYCLIP_FFMPEG override, then the in-tree build next to the honeyclip
  ## binary, then absolute PATH entries. "" when no ffmpeg can be found.
  let envBin = getEnv("HONEYCLIP_FFMPEG")
  if envBin != "": return envBin
  result = besideApp("ffmpeg")
  if result == "": result = findExeOnPath("ffmpeg")

proc ffprobeBin*(): string =
  ## The ffprobe that belongs to ffmpegBin() when one sits beside it, then
  ## the same lookup order as ffmpegBin. "" when none can be found.
  let ff = ffmpegBin()
  if ff != "":
    let (dir, _, ext) = ff.splitFile
    if fileExists(dir / ("ffprobe" & ext)): return dir / ("ffprobe" & ext)
  result = besideApp("ffprobe")
  if result == "": result = findExeOnPath("ffprobe")

proc ffmpegCmd*(): string =
  ## ffmpegBin() quoted for the start of a shell command string. When no
  ## ffmpeg exists the command fails cleanly instead of falling back to a
  ## bare `ffmpeg`, which the shell would resolve from the CWD.
  quoteShell(ffmpegBin())

proc ffprobeCmd*(): string =
  quoteShell(ffprobeBin())
