import std/[unittest, strutils, os, json]

# ============================================================
# Suite: http_client mock
# ============================================================
import ../src/http_client

suite "http_client":
  test "mock GET returns registered response":
    let m = newMockHttpClient()
    m.register("GET", "/system_stats", 200, "{}")
    let (code, body) = m.get("http://127.0.0.1:8188/system_stats")
    check code == 200
    check body == "{}"

  test "mock POST records body and returns response":
    let m = newMockHttpClient()
    m.register("POST", "/prompt", 200, "{\"prompt_id\":\"abc\"}")
    let (code, body) = m.post("http://127.0.0.1:8188/prompt", "{\"x\":1}")
    check code == 200
    check body.contains("abc")
    check m.calls.len == 1
    check m.calls[0].body == "{\"x\":1}"

  test "mock raises on unregistered URL":
    let m = newMockHttpClient()
    expect ValueError:
      discard m.get("http://nope/")

  test "callCount counts matching calls":
    let m = newMockHttpClient()
    m.register("GET", "/system_stats", 200, "{}")
    discard m.get("http://127.0.0.1:8188/system_stats")
    discard m.get("http://127.0.0.1:8188/system_stats")
    check m.callCount("GET", "/system_stats") == 2

# ============================================================
# Suite: fixtures smoke tests
# ============================================================

const FixturesDir = currentSourcePath().parentDir() / "fixtures"

suite "fixtures":
  test "broll_transcript.json has 8 segments and duration 200000":
    let raw = readFile(FixturesDir / "broll_transcript.json")
    let d = parseJson(raw)
    check d["duration"].getInt == 200000
    check d["transcript"]["segments"].len == 8

  test "broll_transcript.json engagement has 6 segments":
    let raw = readFile(FixturesDir / "broll_transcript.json")
    let d = parseJson(raw)
    check d["engagement"]["segments"].len == 6

  test "comfyui_workflow.json contains all placeholders":
    let raw = readFile(FixturesDir / "comfyui_workflow.json")
    check raw.contains("{{PROMPT}}")
    check raw.contains("{{SEED}}")
    check raw.contains("{{LENGTH}}")
    # Verify it also parses as valid JSON
    let d = parseJson(raw)
    check d.kind == JObject

  test "veo_lro_response.json has inProgress, completed, errored":
    let raw = readFile(FixturesDir / "veo_lro_response.json")
    let d = parseJson(raw)
    check d.hasKey("inProgress")
    check d.hasKey("completed")
    check d.hasKey("errored")

  test "veo inProgress has done=false":
    let raw = readFile(FixturesDir / "veo_lro_response.json")
    let d = parseJson(raw)
    check d["inProgress"]["done"].getBool == false

  test "veo completed has done=true and generatedSamples":
    let raw = readFile(FixturesDir / "veo_lro_response.json")
    let d = parseJson(raw)
    check d["completed"]["done"].getBool == true
    check d["completed"]["response"]["generateVideoResponse"]["generatedSamples"].len == 1

# ============================================================
# Suite: config
# ============================================================
import ../src/config

suite "config":
  setup:
    putEnv("GEMINI_API_KEY", "")
    putEnv("HONEYCLIP_COMFYUI_URL", "")

  test "configPath is non-empty":
    let p = configPath()
    when defined(windows):
      # On Windows: requires APPDATA to be set (normally always set)
      let appData = getEnv("APPDATA")
      if appData != "":
        check p.endsWith("config.toml")
        check p.contains("honeyclip")
    else:
      check p.endsWith("honeyclip/config.toml") or p.endsWith("honeyclip\\config.toml")

  test "resolveGeminiKey returns env var when set":
    putEnv("GEMINI_API_KEY", "ENV_KEY_123")
    check resolveGeminiKey() == "ENV_KEY_123"

  test "resolveGeminiKey returns TOML key when env unset":
    putEnv("GEMINI_API_KEY", "")
    let tmp = getTempDir() / "honeyclip_cfg_test.toml"
    writeFile(tmp, "[api]\ngeminiKey = \"FILE_KEY_456\"\n")
    check resolveGeminiKey(tmp) == "FILE_KEY_456"
    removeFile(tmp)

  test "resolveGeminiKey returns empty when neither set":
    putEnv("GEMINI_API_KEY", "")
    check resolveGeminiKey("/nonexistent/path.toml") == ""

  test "resolveComfyUrl defaults to localhost":
    putEnv("HONEYCLIP_COMFYUI_URL", "")
    check resolveComfyUrl("/nonexistent/path.toml") == "http://127.0.0.1:8188"

  test "loadConfig returns zero-value when file missing":
    let cfg = loadConfig("/nonexistent/path.toml")
    check cfg.api.geminiKey == ""

# ============================================================
# Suite: broll detection
# ============================================================
import ../src/transcript/types as transcriptTypes
import ../src/analyze/engagement_types
import ../src/analyze/broll

proc loadTranscriptFromJson(d: JsonNode): Transcript =
  ## Parse a simplified broll_transcript.json structure into Transcript type.
  ## speaker field in JSON is int (0+ = speaker index, matches TranscriptSegment.speaker).
  result = newTranscript()
  result.duration = d["duration"].getInt.int64
  for segNode in d["transcript"]["segments"]:
    var seg = TranscriptSegment(
      startMs: segNode["startMs"].getInt.int64,
      endMs: segNode["endMs"].getInt.int64,
      text: segNode["text"].getStr,
      speaker: segNode["speaker"].getInt,
      words: @[]
    )
    for wNode in segNode["words"]:
      seg.words.add Word(
        text: wNode["text"].getStr,
        startMs: wNode["startMs"].getInt.int64,
        endMs: wNode["endMs"].getInt.int64,
        speaker: wNode["speaker"].getInt
      )
    result.segments.add(seg)

proc loadEngagementFromJson(d: JsonNode): EngagementTimeline =
  ## Parse the "engagement" section of broll_transcript.json.
  result.duration = d["engagement"]["duration"].getInt.int64
  result.segments = @[]
  for segNode in d["engagement"]["segments"]:
    result.segments.add EngagementSegment(
      startMs: segNode["startMs"].getInt.int64,
      endMs: segNode["endMs"].getInt.int64,
      score: segNode["score"].getFloat.float32
    )

suite "broll detection":
  var t: Transcript
  var e: EngagementTimeline

  setup:
    let raw = readFile(FixturesDir / "broll_transcript.json")
    let d = parseJson(raw)
    t = loadTranscriptFromJson(d)
    e = loadEngagementFromJson(d)

  test "rejects pauses shorter than minPauseMs":
    # pauses: 9000-9500 (500ms), 35000-35400 (400ms), 46000-46100 (100ms) must be absent
    let candidates = detectBrollInsertions(t, e, defaultBrollParams())
    for c in candidates:
      check c.pauseMs >= 800

  test "speaker change boosts boundary component":
    # The 18000-21000 pause has speaker 0->1 (speaker change); score must reflect
    # boundary contribution of 0.3 * 100 = 30 at minimum.
    let candidates = detectBrollInsertions(t, e, defaultBrollParams())
    var found = false
    for c in candidates:
      if c.startMs == 18000:
        check c.score >= 30.0'f32
        found = true
    check found

  test "selection respects min-spacing":
    let candidates = detectBrollInsertions(t, e, defaultBrollParams())
    let picked = selectInsertions(candidates, defaultBrollParams(), 200000)
    for i in 1 ..< picked.len:
      check picked[i].startMs - picked[i-1].startMs >= 30_000

  test "selection caps at maxInsertions when set":
    var p = defaultBrollParams()
    p.maxInsertions = 2
    let candidates = detectBrollInsertions(t, e, p)
    let picked = selectInsertions(candidates, p, 200000)
    check picked.len <= 2

  test "endMs clamped to maxPauseMs":
    let candidates = detectBrollInsertions(t, e, defaultBrollParams())
    for c in candidates:
      check c.endMs - c.startMs <= 6000

  test "fixture produces at least 3 selected insertions with defaults":
    let candidates = detectBrollInsertions(t, e, defaultBrollParams())
    let picked = selectInsertions(candidates, defaultBrollParams(), 200000)
    check picked.len >= 3
