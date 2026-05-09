## Veo LRO HTTP client for honeyclip B-roll generation
##
## Provides Google Veo video generation via Long-Running Operations (LRO):
## submit, poll, download. All HTTP goes through HttpClientLike so unit tests
## can inject MockHttpClient with no real network calls (T-21-01 compliance).
##
## Secret-leak gate (T-21-02): apiKey is NEVER passed to log procs.

import std/[json, os, strformat, strutils]
import ../http_client
import ../analyze/broll as brollAnalyze
import ../log
import comfyui  # ClipResult is defined there; re-exported from provider.nim

const
  veoBase* = "https://generativelanguage.googleapis.com/v1beta"
  veoFastSecPrice* = 0.15
  veoStandardSecPrice* = 0.40
  veoFixedClipSeconds* = 8

proc estimateVeoCost*(numClips: int, model: string): float =
  ## Estimate Veo generation cost in USD.
  ## Fast-tier models (containing "fast") cost $0.15/s; others cost $0.40/s.
  ## Veo always generates 8-second clips.
  let perSec = if "fast" in model.toLowerAscii: veoFastSecPrice
               else: veoStandardSecPrice
  result = numClips.float * veoFixedClipSeconds.float * perSec

proc confirmVeoCost*(numClips: int, model: string,
                     isTty: bool, autoYes: bool,
                     readLineFn: proc(): string = nil): bool =
  ## Cost gate for Veo generation. Policy:
  ## - autoYes=true  -> always proceed
  ## - non-TTY without autoYes -> refuse with error message, return false
  ## - TTY without autoYes -> ask user, return true iff user types "y" or "yes"
  if autoYes:
    return true
  let cost = estimateVeoCost(numClips, model)
  if not isTty:
    warning &"Veo would generate {numClips} clips (~${cost:.2f}); refusing without --yes on non-TTY"
    return false
  echo &"Veo will generate {numClips} clips x {veoFixedClipSeconds}s (~${cost:.2f} USD). Continue? [y/N]"
  let line = if readLineFn != nil: readLineFn() else: stdin.readLine()
  return line.strip.toLowerAscii in ["y", "yes"]

proc veoGenerate*(client: HttpClientLike, apiKey: string, model: string,
                  insertion: brollAnalyze.BrollInsertion,
                  prompt: string, outDir: string,
                  pollIntervalMs: int = 10_000,
                  maxAttempts: int = 60): ClipResult =
  ## Submit a Veo LRO, poll until done, download the resulting MP4.
  ## Returns ClipResult with success=false and human-readable error on failure.
  ## API key is NEVER logged (T-21-02 compliance).
  if apiKey == "":
    return ClipResult(success: false, error: "Veo requires GEMINI_API_KEY")
  try:
    let body = $(%*{
      "instances": [{"prompt": prompt}],
      "parameters": {"aspectRatio": "16:9", "personGeneration": "allow_adult"}
    })
    # Key is in query string only — never in log messages
    let submitUrl = &"{veoBase}/models/{model}:predictLongRunning?key={apiKey}"
    let (postCode, postResp) = client.post(submitUrl, body)
    if postCode notin 200 .. 299:
      return ClipResult(success: false, error: &"Veo submit returned {postCode}")

    let opName = parseJson(postResp){"name"}.getStr
    if opName == "":
      return ClipResult(success: false, error: "Veo did not return operation name")

    let pollUrl = &"{veoBase}/{opName}?key={apiKey}"
    for attempt in 0 ..< maxAttempts:
      discard attempt
      if pollIntervalMs > 0:
        sleep(pollIntervalMs)
      let (pollCode, pollResp) = client.get(pollUrl)
      if pollCode != 200:
        continue
      let op = parseJson(pollResp)
      if not (op.hasKey("done") and op["done"].getBool):
        continue
      if op.hasKey("error"):
        return ClipResult(success: false,
                          error: op["error"]{"message"}.getStr("Veo error"))
      let samples = op{"response"}{"generateVideoResponse"}{"generatedSamples"}
      if samples == nil or samples.kind != JArray or samples.len == 0:
        return ClipResult(success: false, error: "Veo response: generatedSamples is empty")
      let videoUri = samples[0]{"video"}{"uri"}.getStr
      if videoUri == "":
        return ClipResult(success: false, error: "Veo response missing video URI")
      # Append key to download URL — never log the URL
      let dlUrl = if "?" in videoUri: videoUri & "&key=" & apiKey
                  else: videoUri & "?key=" & apiKey
      let (dlCode, dlBody) = client.get(dlUrl)
      if dlCode != 200:
        return ClipResult(success: false, error: &"Veo download returned {dlCode}")
      createDir(outDir)
      let outPath = outDir / &"broll_veo_{insertion.startMs}.mp4"
      writeFile(outPath, dlBody)
      return ClipResult(success: true, clipPath: outPath,
                        actualDurationMs: int64(veoFixedClipSeconds * 1000))

    return ClipResult(success: false, error: "Veo timeout")
  except CatchableError as e:
    return ClipResult(success: false, error: e.msg)
