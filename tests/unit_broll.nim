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

# ============================================================
# Suite: comfyui workflow substitution
# ============================================================
import ../src/broll/workflow
import ../src/broll/comfyui
import ../src/analyze/broll as brollAnalyze

suite "comfyui workflow substitution":
  test "substituteWorkflow replaces all three placeholders":
    let wf = """{"text":"{{PROMPT}}","seed":"{{SEED}}","len":"{{LENGTH}}"}"""
    let result2 = substituteWorkflow(wf, "a cat", 42'i64, 24)
    check "{{PROMPT}}" notin result2
    check "{{SEED}}" notin result2
    check "{{LENGTH}}" notin result2
    check "a cat" in result2
    check "42" in result2
    check "24" in result2

  test "escapeJsonString handles quotes and newlines":
    let s = "she said \"hi\"\nbye"
    let esc = escapeJsonString(s)
    check "\\\"hi\\\"" in esc
    check "\\n" in esc
    # The result, when wrapped in quotes, must be parseable JSON:
    discard parseJson("\"" & esc & "\"")

# ============================================================
# Suite: comfyui provider
# ============================================================

suite "comfyui provider":
  test "isComfyReachable true on 200":
    let m = newMockHttpClient()
    m.register("GET", "/system_stats", 200, "{}")
    check isComfyReachable(m, "http://127.0.0.1:8188") == true

  test "isComfyReachable false on 500":
    let m = newMockHttpClient()
    m.register("GET", "/system_stats", 500, "")
    check isComfyReachable(m, "http://127.0.0.1:8188") == false

  test "isComfyReachable false when not registered":
    let m = newMockHttpClient()
    check isComfyReachable(m, "http://127.0.0.1:8188") == false

  test "comfyuiGenerate full happy path":
    let m = newMockHttpClient()
    m.register("POST", "/prompt", 200, "{\"prompt_id\":\"abc\"}")
    m.register("GET", "/history/abc", 200,
               "{\"abc\":{\"outputs\":{\"9\":{\"videos\":[{\"filename\":\"out.mp4\",\"subfolder\":\"\",\"type\":\"output\"}]}}}}")
    m.register("GET", "/view", 200, "FAKE_MP4_BYTES")
    let outDir = getTempDir() / "honeyclip_test_broll"
    let ins = brollAnalyze.BrollInsertion(startMs: 18000, endMs: 21000, pauseMs: 3000)
    let r = comfyuiGenerate(m, "http://127.0.0.1:8188",
                             FixturesDir / "comfyui_workflow.json",
                             ins, "a city street at night", outDir,
                             pollIntervalMs = 0, maxAttempts = 2)
    check r.success == true
    check r.clipPath.endsWith(".mp4")
    check fileExists(r.clipPath)
    check m.callCount("POST", "/prompt") == 1
    check m.callCount("GET", "/view") == 1
    removeDir(outDir)

  test "comfyuiGenerate returns failure on POST 500":
    let m = newMockHttpClient()
    m.register("POST", "/prompt", 500, "internal error")
    let ins = brollAnalyze.BrollInsertion(startMs: 0, endMs: 3000, pauseMs: 3000)
    let r = comfyuiGenerate(m, "http://127.0.0.1:8188",
                             FixturesDir / "comfyui_workflow.json",
                             ins, "x", getTempDir(), pollIntervalMs = 0, maxAttempts = 1)
    check r.success == false
    check "500" in r.error

# ============================================================
# Suite: veo + flash (QueueMock helper + tests)
# ============================================================
import ../src/broll/veo
import ../src/broll/flash
import std/tables

## QueueMock: extends HttpClientLike to return different responses per call
## for a given URL substring (used to simulate LRO state machine transitions).
## Falls back to a registered MockHttpClient for non-queued URLs.
## Uses a read-index per queue key instead of seq.delete(0) to avoid O(n) shifts.
type QueueMock = ref object of HttpClientLike
  inner: MockHttpClient
  queues: Table[string, seq[HttpResponse]]  # key = url substring, value = fifo
  indices: Table[string, int]               # current read position per queue key

proc newQueueMock*(): QueueMock =
  QueueMock(inner: newMockHttpClient(),
            queues: initTable[string, seq[HttpResponse]](),
            indices: initTable[string, int]())

proc register*(q: QueueMock, meth: string, urlSubstring: string,
               status: int, body: string) =
  q.inner.register(meth, urlSubstring, status, body)

proc enqueue*(q: QueueMock, meth: string, urlSubstring: string,
              status: int, body: string) =
  let key = meth.toUpperAscii & ":" & urlSubstring
  if key notin q.queues:
    q.queues[key] = @[]
    q.indices[key] = 0
  q.queues[key].add (status, body)

method get*(q: QueueMock, url: string): HttpResponse =
  for k, queue in q.queues.pairs:
    if k.startsWith("GET:") and url.contains(k[4..^1]):
      let idx = q.indices.getOrDefault(k, 0)
      if idx < queue.len:
        q.indices[k] = idx + 1
        return queue[idx]
  return q.inner.get(url)

method post*(q: QueueMock, url: string, body: string,
             contentType: string = "application/json"): HttpResponse =
  for k, queue in q.queues.pairs:
    if k.startsWith("POST:") and url.contains(k[5..^1]):
      let idx = q.indices.getOrDefault(k, 0)
      if idx < queue.len:
        q.indices[k] = idx + 1
        return queue[idx]
  return q.inner.post(url, body, contentType)

suite "veo cost":
  test "estimateVeoCost fast tier":
    # 2 clips * 8s * $0.15 = $2.40
    let cost = estimateVeoCost(2, "veo-3.0-fast-generate-001")
    check abs(cost - 2.4) < 0.001

  test "estimateVeoCost standard tier":
    # 1 clip * 8s * $0.40 = $3.20
    let cost = estimateVeoCost(1, "veo-3.0-generate-001")
    check abs(cost - 3.20) < 0.001

  test "confirmVeoCost passes with autoYes":
    check confirmVeoCost(5, "veo-3.0-fast-generate-001", isTty=false, autoYes=true) == true

  test "confirmVeoCost rejects non-tty without autoYes":
    check confirmVeoCost(5, "veo-3.0-fast-generate-001", isTty=false, autoYes=false) == false

  test "confirmVeoCost reads y on tty":
    check confirmVeoCost(1, "veo-3.0-fast-generate-001", isTty=true, autoYes=false,
                          readLineFn = proc(): string = "y") == true

  test "confirmVeoCost reads n on tty":
    check confirmVeoCost(1, "veo-3.0-fast-generate-001", isTty=true, autoYes=false,
                          readLineFn = proc(): string = "no") == false

suite "veo provider":
  test "veoGenerate empty key short-circuits":
    let m = newMockHttpClient()
    let ins = brollAnalyze.BrollInsertion(startMs: 0, endMs: 8000, pauseMs: 8000)
    let r = veoGenerate(m, "", "veo-3.0-fast-generate-001", ins, "p", getTempDir(),
                         pollIntervalMs=0, maxAttempts=1)
    check r.success == false
    check "GEMINI_API_KEY" in r.error

  test "veoGenerate full happy path with completed LRO":
    let fixture = parseJson(readFile(FixturesDir / "veo_lro_response.json"))
    let inProgressStr = $fixture["inProgress"]
    let completedStr = $fixture["completed"]
    let q = newQueueMock()
    # POST :predictLongRunning returns the inProgress payload (has the operation name)
    q.register("POST", ":predictLongRunning", 200, inProgressStr)
    # First GET /operations/ -> inProgress (done=false), second -> completed (done=true)
    q.enqueue("GET", "/operations/", 200, inProgressStr)
    q.enqueue("GET", "/operations/", 200, completedStr)
    # Download the video file bytes
    q.register("GET", "/files/xyz", 200, "FAKE_VEO_MP4")
    let ins = brollAnalyze.BrollInsertion(startMs: 0, endMs: 8000, pauseMs: 8000)
    let testOutDir = getTempDir() / "honeyclip_veo_test"
    let r = veoGenerate(q, "FAKE_KEY", "veo-3.0-fast-generate-001", ins, "p",
                         testOutDir, pollIntervalMs=0, maxAttempts=5)
    check r.success == true
    check r.actualDurationMs == 8000
    check fileExists(r.clipPath)
    removeDir(testOutDir)

  test "veoGenerate surfaces error from errored LRO":
    let fixture = parseJson(readFile(FixturesDir / "veo_lro_response.json"))
    let erroredStr = $fixture["errored"]
    let m = newMockHttpClient()
    m.register("POST", ":predictLongRunning", 200,
               """{"name":"models/veo-3.0-fast-generate-001/operations/err1"}""")
    m.register("GET", "/operations/err1", 200, erroredStr)
    let ins = brollAnalyze.BrollInsertion(startMs: 0, endMs: 8000, pauseMs: 8000)
    let r = veoGenerate(m, "FAKE_KEY", "veo-3.0-fast-generate-001", ins, "p",
                         getTempDir(), pollIntervalMs=0, maxAttempts=2)
    check r.success == false
    check "Quota" in r.error

suite "flash rewrite":
  test "rewritePrompt returns context on empty key":
    let m = newMockHttpClient()
    check rewritePrompt(m, "", "hello world") == "hello world"

  test "rewritePrompt extracts candidates[0].content.parts[0].text":
    let m = newMockHttpClient()
    m.register("POST", ":generateContent", 200,
               """{"candidates":[{"content":{"parts":[{"text":"a sunny park"}]}}]}""")
    check rewritePrompt(m, "K", "we walked outside") == "a sunny park"

  test "rewritePrompt falls back on non-200":
    let m = newMockHttpClient()
    m.register("POST", ":generateContent", 500, "")
    check rewritePrompt(m, "K", "fallback text") == "fallback text"

# ============================================================
# Suite: fitting strategy + provider selection
# ============================================================
import ../src/broll/fitting
import ../src/broll/provider

suite "fitting strategy":
  test "fsNone when within tolerance":
    check selectFittingStrategy(3000, 3100) == fsNone
    check selectFittingStrategy(3000, 2850) == fsNone

  test "fsTruncate when actual exceeds":
    check selectFittingStrategy(8000, 3000) == fsTruncate

  test "fsPadFreeze for small gap":
    check selectFittingStrategy(2700, 3100) == fsPadFreeze  # gap 400ms

  test "fsPadSpeedRamp for medium gap":
    check selectFittingStrategy(1500, 3000) == fsPadSpeedRamp  # gap 1500ms

  test "fsRequestExtra for large gap":
    check selectFittingStrategy(1000, 5000) == fsRequestExtra  # gap 4000ms

  test "buildFittingCmd truncate has -t flag":
    let cmd = buildFittingCmd("in.mp4", 3000, 8000, fsTruncate, "out.mp4")
    check "-t" in cmd
    check "3.000" in cmd

  test "buildFittingCmd padFreeze has tpad":
    let cmd = buildFittingCmd("in.mp4", 3000, 2700, fsPadFreeze, "out.mp4")
    check "tpad=stop_mode=clone" in cmd

  test "buildFittingCmd padSpeedRamp has setpts":
    let cmd = buildFittingCmd("in.mp4", 3000, 1500, fsPadSpeedRamp, "out.mp4")
    check "setpts=" in cmd

suite "provider selection":
  test "forced comfyui without workflow raises":
    let m = newMockHttpClient()
    expect ValueError:
      discard resolveProvider("comfyui", "http://x", "", "", "veo-3.0-fast-generate-001", m)

  test "forced veo without key raises":
    let m = newMockHttpClient()
    expect ValueError:
      discard resolveProvider("veo", "http://x", "wf.json", "", "veo-3.0-fast-generate-001", m)

  test "auto picks comfyui when reachable":
    let m = newMockHttpClient()
    m.register("GET", "/system_stats", 200, "{}")
    let p = resolveProvider("auto", "http://127.0.0.1:8188",
                            FixturesDir / "comfyui_workflow.json",
                            "FAKE_KEY", "veo-3.0-fast-generate-001", m)
    check p.kind == bpComfyUI

  test "auto falls back to veo when comfy unreachable + key set":
    let m = newMockHttpClient()
    let p = resolveProvider("auto", "http://127.0.0.1:9999", "wf.json",
                            "FAKE_KEY", "veo-3.0-fast-generate-001", m)
    check p.kind == bpVeo

  test "auto raises when neither available":
    let m = newMockHttpClient()
    expect ValueError:
      discard resolveProvider("auto", "http://127.0.0.1:9999", "wf.json", "",
                              "veo-3.0-fast-generate-001", m)

# ============================================================
# Suite: render plan + marker JSON
# ============================================================
import ../src/broll/render
import ../src/broll/markers

suite "render plan":
  test "empty insertions yields single source segment":
    let plan = buildSegmentPlan(60000, @[])
    check plan.len == 1
    check plan[0].kind == skSource
    check plan[0].endMs == 60000

  test "two insertions yield 5 alternating segments":
    let inserts = @[
      brollAnalyze.BrollInsertion(startMs: 10000, endMs: 13000, pauseMs: 3000),
      brollAnalyze.BrollInsertion(startMs: 40000, endMs: 43000, pauseMs: 3000)
    ]
    let plan = buildSegmentPlan(60000, inserts)
    check plan.len == 5
    check plan[0].kind == skSource and plan[0].endMs == 10000
    check plan[1].kind == skBroll and plan[1].sourceIndex == 0
    check plan[2].kind == skSource and plan[2].startMs == 13000 and plan[2].endMs == 40000
    check plan[3].kind == skBroll and plan[3].sourceIndex == 1
    check plan[4].kind == skSource and plan[4].endMs == 60000

  test "buildConcatList interleaves correctly":
    let plan = @[
      SegmentPlan(kind: skSource, startMs: 0, endMs: 10000, sourceIndex: -1),
      SegmentPlan(kind: skBroll, startMs: 10000, endMs: 13000, sourceIndex: 0),
      SegmentPlan(kind: skSource, startMs: 13000, endMs: 60000, sourceIndex: -1)
    ]
    let txt = buildConcatList(plan, @["s0.mp4", "s1.mp4"], @["b0.mp4"])
    check "file 's0.mp4'" in txt
    check "file 'b0.mp4'" in txt
    check "file 's1.mp4'" in txt
    check txt.count("file '") == 3

  test "normalizeBrollClipCmd contains scale and libx264":
    let cmd = normalizeBrollClipCmd("in.mp4", 1920, 1080, 24.0, "out.mp4")
    check "scale=1920:1080" in cmd
    check "libx264" in cmd
    check "fps=24.000" in cmd

suite "marker json":
  test "writeBrollMarkersJson produces parseable JSON with all required keys":
    let outPath = getTempDir() / "honeyclip_marker_test.json"
    let inserts = @[brollAnalyze.BrollInsertion(
      startMs: 18000, endMs: 21000, pauseMs: 3000,
      score: 75.5'f32, sourceTag: "boundary", contextText: "hello world")]
    let clips2 = @[ClipResult(success: true, clipPath: "/tmp/x.mp4", actualDurationMs: 3000)]
    writeBrollMarkersJson("input.mp4", inserts, clips2, @["a sunny park"], outPath)
    let parsed = parseJson(readFile(outPath))
    check parsed["sourceVideo"].getStr == "input.mp4"
    check parsed["insertions"].len == 1
    let ins0 = parsed["insertions"][0]
    for k in ["startMs", "endMs", "pauseMs", "score", "sourceTag",
              "contextText", "prompt", "clipPath", "actualDurationMs", "success"]:
      check ins0.hasKey(k)
    check ins0["prompt"].getStr == "a sunny park"
    removeFile(outPath)

# ============================================================
# Suite: broll cli
# ============================================================
import ../src/cmds/broll  # compile test: if this compiles, broll module is valid

suite "broll cli":
  test "broll module compiles":
    # If unit_broll compiles successfully with ../src/cmds/broll imported, this passes.
    discard

  test "main.nim registers broll":
    let mainSrc = readFile("src/main.nim")
    check "broll" in mainSrc
    check "\"broll\"" in mainSrc

  test "help text prints all required flags (binary smoke -- only if built)":
    skip()
