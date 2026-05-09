## Configuration resolution for honeyclip
##
## Reads API keys and service URLs from environment variables first, then falls
## back to a TOML config file at the platform-appropriate path. Secrets are
## never passed through log calls (T-21-02 compliance).

import std/[os, strutils]
import toml_serialization
import log

type
  ApiSection* = object
    geminiKey*: string
    comfyuiUrl*: string

  HoneyclipConfig* = object
    api*: ApiSection

proc configPath*(): string =
  ## Return the platform-appropriate config file path.
  ## On Windows: %APPDATA%/honeyclip/config.toml
  ## On Linux/macOS: $XDG_CONFIG_HOME/honeyclip/config.toml (or ~/.config/honeyclip/config.toml)
  when defined(windows):
    let appData = getEnv("APPDATA")
    if appData == "": return ""
    return appData / "honeyclip" / "config.toml"
  else:
    let xdg = getEnv("XDG_CONFIG_HOME")
    let base = if xdg != "": xdg else: getHomeDir() / ".config"
    return base / "honeyclip" / "config.toml"

proc loadConfig*(pathOverride: string = ""): HoneyclipConfig =
  ## Load config from TOML file. Returns zero-valued config when file is
  ## missing or unparseable. Never logs parsed field values.
  let path = if pathOverride != "": pathOverride else: configPath()
  if path == "" or not fileExists(path):
    return
  try:
    result = Toml.loadFile(path, HoneyclipConfig)
  except CatchableError as e:
    # Never include the path content (might contain secrets) in the warning.
    warning "Failed to parse config.toml at " & path & ": " & e.msg

proc resolveGeminiKey*(pathOverride: string = ""): string =
  ## Return GEMINI_API_KEY from env first, then TOML fallback.
  ## Returns "" when neither source provides a key.
  result = getEnv("GEMINI_API_KEY")
  if result == "":
    result = loadConfig(pathOverride).api.geminiKey

proc resolveComfyUrl*(pathOverride: string = ""): string =
  ## Return ComfyUI URL from HONEYCLIP_COMFYUI_URL env first, then TOML,
  ## defaulting to "http://127.0.0.1:8188" when neither source provides one.
  result = getEnv("HONEYCLIP_COMFYUI_URL")
  if result == "":
    let cfg = loadConfig(pathOverride).api.comfyuiUrl
    result = if cfg != "": cfg else: "http://127.0.0.1:8188"
