## DeepFilterNet local provider: detection + subprocess + path resolution.
## All user-derived paths are passed through quoteShell (T-22-03).
import std/[osproc, os, strformat, strutils, algorithm]
import ../analyze/audio_enhance  # findExeOnPath

proc pythonExe(): string =
  ## Absolute path of python3 (Linux/macOS) or python (often the only one on
  ## Windows), found on PATH only, never in the current directory (CR-02).
  result = findExeOnPath("python3")
  if result == "": result = findExeOnPath("python")

proc whichDeepFilter*(): string =
  ## Command prefix: the quoted absolute path of the `deepFilter` PATH script,
  ## "<quoted python> -m df.enhance", or "".
  try:
    let dfExe = findExeOnPath("deepFilter")
    if dfExe != "":
      let (_, code1) = execCmdEx(quoteShell(dfExe) & " --help")
      if code1 == 0:
        return quoteShell(dfExe)
    let py = pythonExe()
    if py != "":
      let (_, code2) = execCmdEx(quoteShell(py) & " -c \"import df.enhance\"")
      if code2 == 0:
        return quoteShell(py) & " -m df.enhance"
  except CatchableError:
    discard
  return ""

proc isDeepFilterAvailable*(): bool =
  ## True only when DeepFilterNet can actually run: the same check
  ## runDeepFilter uses (`deepFilter --help` or `import df.enhance`, which
  ## needs torch), not a bare `import df` that a partial install passes
  ## (WR-10). Never raises.
  try: whichDeepFilter() != ""
  except CatchableError: false

proc buildDeepFilterCmd*(cmdPrefix, inputWav, outDir: string): string =
  ## Pure command construction (testable); every path is shell-quoted.
  ## --no-suffix: without it DeepFilterNet names the output
  ## `<stem>_DeepFilterNet3.wav` (or `..._pf.wav`), not `<stem>.wav`.
  &"{cmdPrefix} --no-suffix -o {quoteShell(outDir)} {quoteShell(inputWav)}"

proc resolveDeepFilterOutput*(inputWav, outDir: string): string =
  ## The enhanced file DeepFilterNet wrote for inputWav, or "" if none.
  ## Prefers the --no-suffix name; falls back to a `<stem>*.wav` file in
  ## outDir in case the installed version ignores --no-suffix.
  let exact = outDir / extractFilename(inputWav)
  if fileExists(exact): return exact
  let stem = splitFile(inputWav).name
  var found: seq[string]
  for kind, path in walkDir(outDir):
    if kind notin {pcFile, pcLinkToFile}: continue
    let (_, name, ext) = splitFile(path)
    if ext.toLowerAscii == ".wav" and name.startsWith(stem):
      found.add path
  if found.len == 0: return ""
  found.sort()
  found[0]

proc runDeepFilter*(inputWav, outDir: string
                   ): tuple[ok: bool, outputPath: string, err: string] =
  ## Run DeepFilterNet on a 48kHz WAV (caller must resample first).
  ## Output lands at outDir / extractFilename(inputWav) (--no-suffix), or a
  ## suffixed `<stem>*.wav` from versions that ignore the flag.
  createDir(outDir)
  let cmdPrefix = whichDeepFilter()
  if cmdPrefix == "":
    return (false, "", "DeepFilterNet not installed. Run: pip install deepfilternet soundfile")
  let cmd = buildDeepFilterCmd(cmdPrefix, inputWav, outDir)
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    return (false, "", output)
  let outFile = resolveDeepFilterOutput(inputWav, outDir)
  if outFile == "":
    return (false, "", &"DeepFilterNet finished (rc=0) but wrote no output for " &
                       extractFilename(inputWav) & " in " & outDir)
  return (true, outFile, "")
