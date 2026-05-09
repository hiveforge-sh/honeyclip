## Gemini Flash prompt-rewrite client for honeyclip
##
## Rewrites a transcript window into a concrete visual prompt suitable
## for text-to-video models. All HTTP goes through HttpClientLike so unit
## tests can inject MockHttpClient with no real network calls (T-21-01 compliance).
##
## Secret-leak gate (T-21-02): apiKey is NEVER passed to log procs.

import std/[json, strformat, strutils]
import ../http_client
import ../log

const flashModel* = "gemini-2.5-flash"
const flashBase* = "https://generativelanguage.googleapis.com/v1beta"

proc rewritePrompt*(client: HttpClientLike, apiKey: string,
                    contextText: string): string =
  ## Rewrite a transcript window into a concrete visual scene description.
  ## On any failure, returns contextText unchanged after logging a warning.
  ## API key is NEVER logged (T-21-02 compliance).
  if apiKey == "" or contextText == "":
    return contextText
  let instruction = "Rewrite this spoken transcript snippet into a concise visual scene description suitable for a text-to-video model. Output ONLY the scene description, no preamble. Snippet: " & contextText
  let body = $(%*{
    "contents": [{"parts": [{"text": instruction}]}]
  })
  try:
    # Key is in query string only — never in log messages
    let url = &"{flashBase}/models/{flashModel}:generateContent?key={apiKey}"
    let (code, resp) = client.post(url, body)
    if code != 200:
      warning &"Gemini Flash returned {code}; using raw transcript"
      return contextText
    let parsed = parseJson(resp)
    let txt = parsed{"candidates"}[0]{"content"}{"parts"}[0]{"text"}.getStr
    if txt == "":
      return contextText
    return txt.strip
  except CatchableError as e:
    warning &"Gemini Flash rewrite failed: {e.msg}; using raw transcript"
    return contextText
