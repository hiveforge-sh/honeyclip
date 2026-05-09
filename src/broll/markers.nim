## Marker JSON output for B-roll insertions in honeyclip
##
## Writes a pretty-printed JSON file describing each B-roll insertion point,
## the visual prompt used, and the result of clip generation.

import std/[json, strutils]
import ../analyze/broll as brollAnalyze
import comfyui  # for ClipResult

proc writeBrollMarkersJson*(sourceVideo: string,
                            insertions: seq[brollAnalyze.BrollInsertion],
                            clips: seq[ClipResult],
                            prompts: seq[string],
                            outputPath: string) =
  ## Write JSON with shape:
  ## {"sourceVideo": "...", "insertions": [{startMs, endMs, pauseMs, score,
  ##   sourceTag, contextText, prompt, clipPath, actualDurationMs, success}, ...]}
  var arr = newJArray()
  for i, ins in insertions:
    let clip = if i < clips.len: clips[i] else: ClipResult()
    let prompt = if i < prompts.len: prompts[i] else: ""
    arr.add %*{
      "startMs": ins.startMs,
      "endMs": ins.endMs,
      "pauseMs": ins.pauseMs,
      "score": ins.score,
      "sourceTag": ins.sourceTag,
      "contextText": ins.contextText,
      "prompt": prompt,
      "clipPath": clip.clipPath,
      "actualDurationMs": clip.actualDurationMs,
      "success": clip.success
    }
  let doc = %*{
    "sourceVideo": sourceVideo,
    "insertions": arr
  }
  writeFile(outputPath, doc.pretty)
