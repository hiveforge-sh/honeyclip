## ComfyUI HTTP client for honeyclip B-roll generation
##
## Provides ComfyUI API integration: submit workflow, poll history, download result.
## All HTTP goes through HttpClientLike so unit tests can inject MockHttpClient.
## All HTTP goes through HttpClientLike — no direct stdlib newHttpClient calls (T-21-01).

import std/[json, os, random, strformat, strutils]
import ../http_client
import ../analyze/broll as brollAnalyze
import ../log
import workflow

type
  ClipResult* = object
    success*: bool
    clipPath*: string
    actualDurationMs*: int64
    error*: string

proc isComfyReachable*(client: HttpClientLike, baseUrl: string): bool =
  ## Check if ComfyUI server is reachable by probing /system_stats.
  ## Returns true on HTTP 200, false on any non-200 or exception.
  try:
    let (code, _) = client.get(baseUrl & "/system_stats")
    result = code == 200
  except CatchableError:
    result = false

proc comfyuiGenerate*(client: HttpClientLike, baseUrl: string,
                      workflowPath: string,
                      insertion: brollAnalyze.BrollInsertion,
                      prompt: string, outDir: string,
                      pollIntervalMs: int = 1_000,
                      maxAttempts: int = 300): ClipResult =
  ## Submit a workflow to ComfyUI, poll /history/{prompt_id}, download the result.
  ## Synchronous; ComfyUI polls are short-lived (seconds).
  ## Returns ClipResult with success=false and a human-readable error on failure.
  if not fileExists(workflowPath):
    return ClipResult(success: false,
                      error: &"workflow file not found: {workflowPath}")

  let workflowRaw = readFile(workflowPath)
  let lengthFrames = max(8, int(insertion.pauseMs * 24 div 1000))
  randomize()
  let seed = rand(int64.high div 2)
  let substituted = substituteWorkflow(workflowRaw, prompt, seed, lengthFrames)
  # Wrap substituted workflow (which is already a JSON object) as the "prompt" key.
  let body = "{\"prompt\":" & substituted & ",\"client_id\":\"honeyclip\"}"

  try:
    let (postCode, postResp) = client.post(baseUrl & "/prompt", body)
    if postCode notin 200 .. 299:
      return ClipResult(success: false,
                        error: &"ComfyUI /prompt returned {postCode}: {postResp}")

    let promptId = parseJson(postResp){"prompt_id"}.getStr
    if promptId == "":
      return ClipResult(success: false, error: "ComfyUI did not return prompt_id")

    for attempt in 0 ..< maxAttempts:
      if pollIntervalMs > 0:
        sleep(pollIntervalMs)
      let (histCode, histResp) = client.get(baseUrl & "/history/" & promptId)
      if histCode != 200:
        continue
      let hist = parseJson(histResp)
      if not hist.hasKey(promptId):
        continue
      let outputs = hist[promptId]{"outputs"}
      if outputs == nil or outputs.kind != JObject:
        continue
      for nodeId, nodeOut in outputs.pairs:
        discard nodeId
        for kind in ["videos", "gifs", "images"]:
          if nodeOut.hasKey(kind) and nodeOut[kind].len > 0:
            let f = nodeOut[kind][0]
            let filename = f{"filename"}.getStr
            let subfolder = f{"subfolder"}.getStr
            let viewUrl = &"{baseUrl}/view?filename={filename}&subfolder={subfolder}&type=output"
            let (dlCode, dlBody) = client.get(viewUrl)
            if dlCode != 200:
              return ClipResult(success: false,
                                error: &"ComfyUI /view returned {dlCode}")
            createDir(outDir)
            let outPath = outDir / &"broll_{insertion.startMs}.mp4"
            writeFile(outPath, dlBody)
            return ClipResult(success: true, clipPath: outPath,
                              actualDurationMs: insertion.pauseMs)

    return ClipResult(success: false,
                      error: &"ComfyUI timeout after {maxAttempts * pollIntervalMs} ms")
  except CatchableError as e:
    return ClipResult(success: false, error: e.msg)
