import std/[unittest, strutils]

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
