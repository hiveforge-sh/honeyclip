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
result: passed (2026-10-28, measured, not listened to)
note: DeepFilterNet 0.5.6 in a Python 3.11 venv with CPU torch/torchaudio 2.2.2 plus `soundfile` (without it torchaudio has no backend on Windows and DeepFilterNet fails; honeyclip correctly exits 1). On Windows-TTS speech mixed with pink noise, `--backend=local` raised the speech-to-noise gap from 21.8 dB to 30.8 dB (FFmpeg-only chain: 25.9 dB). Stereo input stayed stereo with distinct channels; DeepFilterNet handled stereo natively, so the per-channel fallback did not run. Found one gap, below.

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
passed: 1
issues: 1
pending: 2
skipped: 0
blocked: 0

## Gaps

### G-1: loudnorm falls back to dynamic mode and lifts residual noise
status: open
found_by: test 1
detail: DeepFilterNet alone left a 35.5 dB speech-to-noise gap; after honeyclip's chain it was 30.8 dB. The two-pass `loudnorm` asks for `linear=true`, but when the gain needed for -16 LUFS would push true peak above -1.5 dBTP (here input_tp -3.24 dB, gain +4 dB), FFmpeg silently switches to dynamic normalization, which raises quiet passages and with them the leftover noise. Affects every backend; also why the 2h49m test file ended at -17.4 LUFS instead of -16.
fix_idea: apply the gain linearly and handle peaks with a true-peak limiter (or lower the target) so loudnorm never falls back to dynamic mode.
