## BrollProvider object variant for honeyclip
##
## Provides the BrollProvider variant type (ComfyUI or Veo backends),
## provider resolution with auto-fallback, and dispatch of generate().
## All provider resolution uses HttpClientLike for testability (T-21-01).

import std/[strformat, strutils]
import ../http_client
import ../log
import ../analyze/broll as brollAnalyze
import comfyui
import veo
export comfyui.ClipResult

type
  BrollProviderKind* = enum
    bpComfyUI
    bpVeo

  BrollProvider* = object
    case kind*: BrollProviderKind
    of bpComfyUI:
      comfyUrl*: string
      workflowPath*: string
    of bpVeo:
      apiKey*: string
      model*: string

proc resolveProvider*(forceBackend, comfyUrl, workflowPath, apiKey, model: string,
                      http: HttpClientLike): BrollProvider =
  ## Resolve which provider to use based on forceBackend flag and availability.
  ## Selection logic (mirrors CONTEXT.md):
  ##   "comfyui"  -> use ComfyUI; error if --workflow not provided
  ##   "veo"      -> use Veo; error if no GEMINI_API_KEY
  ##   "auto"/"" -> try ComfyUI first; fall back to Veo if key available; else error
  case forceBackend.toLowerAscii
  of "comfyui":
    if workflowPath == "":
      raise newException(ValueError, "--workflow PATH required when --backend comfyui")
    return BrollProvider(kind: bpComfyUI, comfyUrl: comfyUrl, workflowPath: workflowPath)
  of "veo":
    if apiKey == "":
      raise newException(ValueError,
        "Backend 'veo' requires GEMINI_API_KEY env var or config.toml [api] geminiKey")
    return BrollProvider(kind: bpVeo, apiKey: apiKey, model: model)
  of "auto", "":
    if isComfyReachable(http, comfyUrl):
      if workflowPath == "":
        raise newException(ValueError,
          &"ComfyUI reachable at {comfyUrl} but --workflow PATH not provided")
      return BrollProvider(kind: bpComfyUI, comfyUrl: comfyUrl, workflowPath: workflowPath)
    if apiKey != "":
      info &"ComfyUI not reachable at {comfyUrl}; falling back to Veo"
      return BrollProvider(kind: bpVeo, apiKey: apiKey, model: model)
    raise newException(ValueError,
      &"No backend available. Start ComfyUI at {comfyUrl} or set GEMINI_API_KEY.")
  else:
    raise newException(ValueError, &"unknown --backend: {forceBackend}")

proc generate*(p: BrollProvider, http: HttpClientLike,
               insertion: brollAnalyze.BrollInsertion,
               prompt: string, outDir: string,
               pollIntervalMs: int = -1,
               maxAttempts: int = -1): ClipResult =
  ## Dispatch to the appropriate provider's generate function.
  case p.kind
  of bpComfyUI:
    let pi = if pollIntervalMs < 0: 1_000 else: pollIntervalMs
    let ma = if maxAttempts < 0: 300 else: maxAttempts
    result = comfyuiGenerate(http, p.comfyUrl, p.workflowPath, insertion, prompt,
                             outDir, pi, ma)
  of bpVeo:
    let pi = if pollIntervalMs < 0: 10_000 else: pollIntervalMs
    let ma = if maxAttempts < 0: 60 else: maxAttempts
    result = veoGenerate(http, p.apiKey, p.model, insertion, prompt, outDir, pi, ma)
