import std/[re, json, algorithm, tables]

type
  HookPatternKind* = enum
    hpkQuestion,      # Questions (what, why, how...)
    hpkEmphasis,      # Strong words (never, always, must)
    hpkStorytelling,  # Narrative openings (imagine, picture this)
    hpkCustom         # User-defined patterns

  HookPattern* = object
    pattern*: string      # Regex pattern string
    name*: string         # Human-readable name
    category*: string     # Pattern category for grouping (e.g., "questions", "callouts")
    kind*: HookPatternKind
    weight*: float32      # Score weight (1.0 = normal, 1.5 = strong)

  HookResult* = object
    isHook*: bool              # Combined text+prosody detection
    textMatches*: seq[string]  # Which text patterns matched
    hasProsodyIndicator*: bool # Volume spike or unusual pause
    confidence*: float32       # 0-1 combined confidence

# Import hook_schema after types are defined to avoid circular dependency
import hook_schema
export hook_schema.findHooksFile, hook_schema.generateStarterTemplate, hook_schema.loadHooksFromJson

proc loadBuiltinPatterns*(): seq[HookPattern] =
  ## Returns built-in hook patterns for common engagement indicators
  result = @[]

  # Question patterns
  result.add(HookPattern(
    pattern: r"(?i)^(what|why|how|when|where|who)\b",
    name: "question_opening",
    category: "questions",
    kind: hpkQuestion,
    weight: 1.5
  ))

  result.add(HookPattern(
    pattern: r"\?$",
    name: "question_ending",
    category: "questions",
    kind: hpkQuestion,
    weight: 1.2
  ))

  # Emphasis patterns
  result.add(HookPattern(
    pattern: r"(?i)\b(never|always|must|shocking|revealed|secret|truth)\b",
    name: "emphasis_words",
    category: "emphasis",
    kind: hpkEmphasis,
    weight: 1.3
  ))

  result.add(HookPattern(
    pattern: r"(?i)^(you need to|you have to|listen)\b",
    name: "direct_address",
    category: "emphasis",
    kind: hpkEmphasis,
    weight: 1.3
  ))

  # Storytelling patterns
  result.add(HookPattern(
    pattern: r"(?i)^(imagine|picture this|here's the thing|let me tell you)\b",
    name: "storytelling_opening",
    category: "storytelling",
    kind: hpkStorytelling,
    weight: 1.4
  ))

proc loadPatternsFromFile*(path: string): seq[HookPattern] =
  ## Load custom hook patterns from JSON file
  ## Format: [{"pattern": "...", "name": "...", "kind": "...", "weight": 1.0}]
  result = @[]

  let content = readFile(path)
  let jsonData = parseJson(content)

  for item in jsonData:
    let kindStr = item["kind"].getStr()
    let kind = case kindStr
      of "question": hpkQuestion
      of "emphasis": hpkEmphasis
      of "storytelling": hpkStorytelling
      else: hpkCustom

    result.add(HookPattern(
      pattern: item["pattern"].getStr(),
      name: item["name"].getStr(),
      kind: kind,
      weight: item["weight"].getFloat(1.0).float32
    ))

proc matchTextPatterns*(text: string, patterns: seq[HookPattern]): seq[string] =
  ## Returns names of patterns that match the text
  result = @[]

  for pattern in patterns:
    let regex = re(pattern.pattern)
    if text.contains(regex):
      result.add(pattern.name)

proc detectProsodyHook*(audioSegment: seq[float32],
                        avgEnergy: float32): tuple[hasIndicator: bool,
                                                    indicatorType: string] =
  ## Detect prosody-based hooks using heuristics:
  ## - Unusual pause before segment (silence > 200ms)
  ## - Volume spike (peak > 1.5x average)

  if audioSegment.len == 0:
    return (false, "")

  # Check first 6 samples for silence (approximates 200ms at 30fps)
  let silenceThreshold = 0.05 * avgEnergy
  var isSilent = true
  let checkSamples = min(6, audioSegment.len)

  for i in 0..<checkSamples:
    if audioSegment[i] > silenceThreshold:
      isSilent = false
      break

  if isSilent:
    return (true, "pause")

  # Check for volume spike
  var maxSample = 0.0f
  for sample in audioSegment:
    if sample > maxSample:
      maxSample = sample

  if maxSample > avgEnergy * 1.5:
    return (true, "volume_spike")

  return (false, "")

proc detectHook*(text: string, audioSegment: seq[float32],
                 avgEnergy: float32, patterns: seq[HookPattern]): HookResult =
  ## Combined hook detection requiring BOTH text AND prosody indicators

  let textMatches = matchTextPatterns(text, patterns)
  let (hasProsodyIndicator, indicatorType) = detectProsodyHook(audioSegment, avgEnergy)

  # Hook requires BOTH text pattern match AND prosody indicator
  let isHook = textMatches.len > 0 and hasProsodyIndicator

  # Calculate confidence
  var confidence = 0.0f
  if isHook:
    # Find best pattern weight
    var bestWeight = 1.0f
    for pattern in patterns:
      if pattern.name in textMatches and pattern.weight > bestWeight:
        bestWeight = pattern.weight

    # Normalize weight to 0-1 range (assuming max weight ~2.0)
    let textScore = min(bestWeight / 2.0, 1.0)

    # Prosody indicator contributes 0.5
    let prosodyScore = 0.5f

    # Combined confidence
    confidence = (textScore * 0.5f) + (prosodyScore * 0.5f)

  result = HookResult(
    isHook: isHook,
    textMatches: textMatches,
    hasProsodyIndicator: hasProsodyIndicator,
    confidence: confidence
  )

proc rateLimitHooks*(hooks: seq[tuple[timestampMs: int64, result: HookResult]],
                     maxPerMinute: int = 3): seq[int64] =
  ## Returns timestamps of hooks that pass rate limiting
  ## Keeps highest confidence hooks within each minute window

  result = @[]

  if hooks.len == 0:
    return

  # Group hooks by minute
  var minuteBuckets: seq[seq[tuple[timestampMs: int64, result: HookResult]]]
  var currentMinute = -1

  for hook in hooks:
    let minute = hook.timestampMs div 60000  # Convert to minutes

    if minute != currentMinute:
      currentMinute = minute.int
      minuteBuckets.add(@[])

    minuteBuckets[^1].add(hook)

  # Select top N hooks per minute by confidence
  for bucket in minuteBuckets:
    # Sort by confidence descending
    var sortedBucket = bucket
    sortedBucket.sort(proc(a, b: tuple[timestampMs: int64, result: HookResult]): int =
      if b.result.confidence > a.result.confidence: 1
      elif b.result.confidence < a.result.confidence: -1
      else: 0
    )

    # Take top maxPerMinute
    for i in 0..<min(maxPerMinute, sortedBucket.len):
      result.add(sortedBucket[i].timestampMs)

proc mergeHookPatterns*(builtins, custom: seq[HookPattern]): seq[HookPattern] =
  ## Merge custom hooks with built-ins
  ## Custom patterns with same name override built-ins
  result = @[]

  # Track which names have been added
  var seen = initTable[string, bool]()

  # Add custom patterns first (priority)
  for pattern in custom:
    result.add(pattern)
    seen[pattern.name] = true

  # Add built-ins that weren't overridden
  for pattern in builtins:
    if not seen.hasKey(pattern.name):
      result.add(pattern)

proc loadAllHooks*(explicitPath: string = "",
                   videoDir: string = "",
                   verbose: bool = false): tuple[patterns: seq[HookPattern],
                                                 customPath: string] =
  ## Load all hooks: built-ins + custom from discovered file
  ## Returns patterns and path to custom file (empty if none loaded)
  ##
  ## If explicitPath is provided but doesn't exist, generates starter template

  let builtins = loadBuiltinPatterns()
  var customPatterns: seq[HookPattern] = @[]
  var loadedPath = ""

  # Try to find hooks file
  let hooksPath = findHooksFile(explicitPath, videoDir)

  if hooksPath != "":
    # Load custom hooks from discovered file
    try:
      customPatterns = loadHooksFromJson(hooksPath)
      loadedPath = hooksPath
      if verbose:
        echo "Loaded custom hooks from: ", hooksPath
        echo "  Custom patterns: ", customPatterns.len
    except ValueError as e:
      # Re-raise with context
      raise newException(ValueError, e.msg)
  elif explicitPath != "":
    # Explicit path specified but not found - generate template
    if generateStarterTemplate(explicitPath):
      echo "Generated starter hooks template: ", explicitPath
      echo "  Edit this file and run again to use custom hooks"
    else:
      raise newException(IOError, "Failed to generate hooks template at: " & explicitPath)

  # Merge patterns
  result.patterns = mergeHookPatterns(builtins, customPatterns)
  result.customPath = loadedPath

  if verbose:
    echo "Active hook patterns: ", result.patterns.len
    for p in result.patterns:
      echo "  - ", p.name, " (", p.kind, ", weight: ", p.weight, ")"

when isMainModule:
  # Test hook detection
  let patterns = loadBuiltinPatterns()

  # Test 1: Question with volume spike should be detected
  echo "Test 1: Question with volume spike"
  let audioWithSpike = @[0.1f, 0.2f, 0.8f, 0.3f, 0.1f]  # Has spike > 1.5x avg
  let result1 = detectHook("What if I told you?", audioWithSpike, 0.3f, patterns)
  echo "  isHook: ", result1.isHook, " (expected: true)"
  echo "  textMatches: ", result1.textMatches
  echo "  hasProsodyIndicator: ", result1.hasProsodyIndicator
  echo "  confidence: ", result1.confidence

  # Test 2: Mid-sentence "what" without prosody should not be detected
  echo "\nTest 2: Mid-sentence 'what' without prosody"
  let flatAudio = @[0.3f, 0.3f, 0.3f, 0.3f, 0.3f]  # No spike or pause
  let result2 = detectHook("the what", flatAudio, 0.3f, patterns)
  echo "  isHook: ", result2.isHook, " (expected: false)"
  echo "  textMatches: ", result2.textMatches
  echo "  hasProsodyIndicator: ", result2.hasProsodyIndicator

  # Test 3: Question without prosody should not be hook
  echo "\nTest 3: Question without prosody"
  let result3 = detectHook("What is this?", flatAudio, 0.3f, patterns)
  echo "  isHook: ", result3.isHook, " (expected: false - no prosody)"
  echo "  textMatches: ", result3.textMatches
  echo "  hasProsodyIndicator: ", result3.hasProsodyIndicator
