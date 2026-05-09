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
