## DeepFilterNet local provider: detection + subprocess + path resolution.
## All user-derived paths are passed through quoteShell (T-22-03).
import std/[osproc, os, strformat]

proc pythonExe(): string =
  ## "python3" on Linux/macOS; on Windows only "python" is usually present.
  if findExe("python3") != "": "python3"
  elif findExe("python") != "": "python"
  else: ""

proc isDeepFilterAvailable*(): bool =
  ## Detect DeepFilterNet via Python module import. Never raises.
  let py = pythonExe()
  if py == "": return false
  try:
    let (_, code) = execCmdEx(py & " -c \"import df\"")
    result = code == 0
  except CatchableError:
    result = false

proc whichDeepFilter*(): string =
  ## Command prefix: "deepFilter" (PATH script), "<python> -m df.enhance", or "".
  try:
    if findExe("deepFilter") != "":
      let (_, code1) = execCmdEx("deepFilter --help")
      if code1 == 0:
        return "deepFilter"
    let py = pythonExe()
    if py != "":
      let (_, code2) = execCmdEx(py & " -c \"import df.enhance\"")
      if code2 == 0:
        return py & " -m df.enhance"
  except CatchableError:
    discard
  return ""

proc buildDeepFilterCmd*(cmdPrefix, inputWav, outDir: string): string =
  ## Pure command construction (testable); every path is shell-quoted.
  &"{cmdPrefix} -o {quoteShell(outDir)} {quoteShell(inputWav)}"

proc runDeepFilter*(inputWav, outDir: string
                   ): tuple[ok: bool, outputPath: string, err: string] =
  ## Run DeepFilterNet on a 48kHz WAV (caller must resample first).
  ## Output lands at outDir / extractFilename(inputWav) (Pitfall 7).
  createDir(outDir)
  let cmdPrefix = whichDeepFilter()
  if cmdPrefix == "":
    return (false, "", "DeepFilterNet not installed. Run: pip install deepfilternet")
  let cmd = buildDeepFilterCmd(cmdPrefix, inputWav, outDir)
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    return (false, "", output)
  let outFile = outDir / extractFilename(inputWav)
  if not fileExists(outFile):
    return (false, "", &"DeepFilterNet finished (rc=0) but output {outFile} missing")
  return (true, outFile, "")
