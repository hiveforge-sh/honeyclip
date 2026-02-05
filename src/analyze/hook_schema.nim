## JSON schema loading and validation for custom hook patterns
##
## Enables users to define custom hook detection patterns in a JSON file,
## extending the built-in patterns for engagement analysis.

import std/[json, os, strutils, re]
import hooks

type
  ProsodyProfile* = enum
    ppNone,      ## No prosody requirement
    ppExcited,   ## High energy: volumeSpike 1.8x, pause 150ms
    ppEmphatic,  ## Strong delivery: volumeSpike 1.5x, pause 200ms
    ppCalm,      ## Measured pace: volumeSpike 1.2x, pause 300ms
    ppCustom     ## User provides explicit thresholds

  ProsodyThresholds* = object
    pauseMs*: int              ## Milliseconds of silence before segment
    volumeSpikeFactor*: float32  ## Factor above average energy

const DefaultWeight* = 15.0f

proc prosodyProfileToThresholds*(profile: ProsodyProfile): ProsodyThresholds =
  ## Map named profiles to numeric thresholds
  case profile
  of ppExcited: ProsodyThresholds(pauseMs: 150, volumeSpikeFactor: 1.8f)
  of ppEmphatic: ProsodyThresholds(pauseMs: 200, volumeSpikeFactor: 1.5f)
  of ppCalm: ProsodyThresholds(pauseMs: 300, volumeSpikeFactor: 1.2f)
  of ppNone, ppCustom: ProsodyThresholds(pauseMs: 0, volumeSpikeFactor: 0.0f)

proc parseProsodyProfile*(profile: string): ProsodyProfile =
  ## Parse string to prosody profile enum
  case profile.toLowerAscii()
  of "excited": ppExcited
  of "emphatic": ppEmphatic
  of "calm": ppCalm
  of "": ppNone
  else: ppCustom

proc loadHooksFromJson*(path: string): seq[HookPattern] =
  ## Load and validate custom hooks from JSON file
  ##
  ## JSON format:
  ## {
  ##   "hooks": {
  ##     "pattern_key": {
  ##       "name": "Display Name",        // optional, defaults to key
  ##       "category": "callouts",         // optional, defaults to "custom"
  ##       "weight": 15.0,                 // optional, defaults to 15.0
  ##       "regex": "text pattern",        // at least one criterion required
  ##       "keywords": ["word1", "word2"], // at least one criterion required
  ##       "prosody": "excited",           // at least one criterion required
  ##       "match": "all"                  // optional, "all" or "any"
  ##     }
  ##   },
  ##   "settings": {
  ##     "defaultWeight": 15.0            // optional
  ##   }
  ## }
  ##
  ## Raises ValueError on invalid schema or regex compilation failure
  result = @[]

  var root: JsonNode
  try:
    root = parseFile(path)
  except IOError:
    raise newException(ValueError, "Schema validation failed for '" & path & "': Cannot read file - " & getCurrentExceptionMsg())
  except OSError:
    raise newException(ValueError, "Schema validation failed for '" & path & "': Cannot read file - " & getCurrentExceptionMsg())
  except JsonParsingError:
    raise newException(ValueError, "Schema validation failed for '" & path & "': Invalid JSON - " & getCurrentExceptionMsg())

  # Validate top-level structure
  if not root.hasKey("hooks"):
    raise newException(ValueError, "Schema validation failed for '" & path & "': Missing required field 'hooks'")

  let hooksNode = root["hooks"]
  if hooksNode.kind != JObject:
    raise newException(ValueError, "Schema validation failed for '" & path & "': Field 'hooks' must be an object")

  # Get global settings
  let settingsNode = root{"settings"}
  let globalDefaultWeight = if settingsNode != nil and settingsNode.hasKey("defaultWeight"):
    settingsNode["defaultWeight"].getFloat(DefaultWeight).float32
  else:
    DefaultWeight

  # Parse each hook pattern
  for patternKey, patternNode in hooksNode.pairs:
    # Use {} accessor for optional fields with defaults
    let name = patternNode{"name"}.getStr(patternKey)
    let category = patternNode{"category"}.getStr("custom")
    let weight = patternNode{"weight"}.getFloat(globalDefaultWeight.float).float32

    # Check for matching criteria
    let hasRegex = patternNode.hasKey("regex") and patternNode["regex"].getStr("") != ""
    let hasKeywords = patternNode.hasKey("keywords") and patternNode["keywords"].kind == JArray and patternNode["keywords"].len > 0
    let hasProsody = patternNode.hasKey("prosody") and patternNode["prosody"].getStr("") != ""

    # Validate at least one criterion exists
    if not (hasRegex or hasKeywords or hasProsody):
      raise newException(ValueError,
        "Schema validation failed for '" & path & "': Pattern '" & name & "' must have at least one criterion: regex, keywords, or prosody")

    # Build the pattern string
    var patternStr = ""

    if hasRegex:
      # Add case-insensitive prefix
      patternStr = "(?i)" & patternNode["regex"].getStr()
    elif hasKeywords:
      # Synthesize regex from keywords: (?i)\b(keyword1|keyword2)\b
      var keywords: seq[string] = @[]
      for kw in patternNode["keywords"]:
        keywords.add(kw.getStr())
      patternStr = "(?i)\\b(" & keywords.join("|") & ")\\b"

    # Validate regex compiles (if we have a pattern)
    if patternStr != "":
      try:
        discard re(patternStr)
      except RegexError:
        raise newException(ValueError,
          "Schema validation failed for '" & path & "': Pattern '" & name & "' has invalid regex: " & getCurrentExceptionMsg())

    # Create the HookPattern
    result.add(HookPattern(
      pattern: patternStr,
      name: name,
      category: category,
      kind: hpkCustom,
      weight: weight
    ))

proc findHooksFile*(explicitPath: string = "", videoDir: string = ""): string =
  ## Discover hooks file with priority order
  ## Returns: path to hooks file or empty string if not found
  ##
  ## Priority:
  ## 1. Explicit CLI path (--hooks flag)
  ## 2. Video directory (honeyclip.hooks.json alongside video)
  ## 3. Current working directory
  ## 4. XDG config directory (~/.config/honeyclip/)

  # Priority 1: Explicit CLI path
  if explicitPath != "":
    if fileExists(explicitPath):
      return explicitPath
    else:
      return ""  # Caller handles missing explicit path

  # Priority 2: Video directory (if provided)
  if videoDir != "":
    let videoPath = videoDir / "honeyclip.hooks.json"
    if fileExists(videoPath):
      return videoPath

  # Priority 3: Current working directory
  let localPath = getCurrentDir() / "honeyclip.hooks.json"
  if fileExists(localPath):
    return localPath

  # Priority 4: XDG config directory (~/.config/honeyclip/)
  let configDir = getConfigDir() / "honeyclip"
  let xdgPath = configDir / "honeyclip.hooks.json"
  if fileExists(xdgPath):
    return xdgPath

  return ""  # No hooks file found

proc generateStarterTemplate*(path: string): bool =
  ## Generate starter hooks template at path
  ## Creates parent directories if needed
  ## Returns true on success

  const templateContent = staticRead("../../resources/honeyclip.hooks.template.json")

  # Create parent directory if it doesn't exist
  let parentDir = parentDir(path)
  if parentDir != "" and not dirExists(parentDir):
    try:
      createDir(parentDir)
    except OSError:
      return false

  try:
    writeFile(path, templateContent)
    return true
  except IOError:
    return false
