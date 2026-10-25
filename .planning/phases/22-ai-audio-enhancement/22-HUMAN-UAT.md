---
status: partial
phase: 22-ai-audio-enhancement
source: [22-VERIFICATION.md]
started: 2026-10-24T22:05:00Z
updated: 2026-10-24T22:05:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Local backend with real DeepFilterNet
Run `honeyclip enhance <video> --backend=local` on a machine with `pip install deepfilternet`.
expected: Output file produced with audibly reduced noise, loudness normalized, A/V in sync
result: [pending]

### 2. ElevenLabs backend with a real API key
Run `honeyclip enhance <short clip> --backend=elevenlabs --yes` with a real ELEVENLABS_API_KEY; then once without `--yes` to see the cost prompt.
expected: Voice Isolator response accepted, decoded and loudness-normalized into the output; cost prompt appears without --yes
result: [pending]

### 3. Listening test and long-file chunking
Listen to ffmpeg-backend and neural-backend output; check chunking on a real file longer than one hour.
expected: No audible seams at chunk crossfades; A/V stays in sync over the full duration
result: [pending]
note: Sync and track preservation were measured (not listened to) on a copy of a 2h49m, 6-track OBS recording with `--backend=ffmpeg`: every track 2:49:36.00, tracks 2-6 bit-identical. The listening part is still open.

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
