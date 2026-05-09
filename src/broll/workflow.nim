## ComfyUI workflow JSON placeholder substitution for honeyclip
##
## Handles template substitution of {{PROMPT}}, {{SEED}}, and {{LENGTH}} in
## ComfyUI API-format workflow JSON exports. The prompt is JSON-string-escaped
## so that user text with quotes, backslashes, and control characters does not
## break the resulting JSON.

import std/strutils

proc escapeJsonString*(s: string): string =
  ## Escape a string so it's safe to embed inside an existing JSON string literal.
  ## Returns the content without the surrounding quotes.
  result = newStringOfCap(s.len + 8)
  for ch in s:
    case ch
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    of '\b': result.add "\\b"
    of '\f': result.add "\\f"
    else:
      if ch.ord < 0x20:
        result.add "\\u00" & toHex(ch.ord, 2)
      else:
        result.add ch

proc substituteWorkflow*(workflowJson: string, prompt: string,
                          seed: int64, lengthFrames: int): string =
  ## Replace {{PROMPT}}, {{SEED}}, and {{LENGTH}} placeholders in the workflow JSON.
  ## The prompt is JSON-string-escaped before substitution.
  result = workflowJson
    .replace("{{PROMPT}}", escapeJsonString(prompt))
    .replace("{{SEED}}", $seed)
    .replace("{{LENGTH}}", $lengthFrames)
