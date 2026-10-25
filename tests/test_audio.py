#!/usr/bin/env python3
"""Phase 22 end-to-end tests for the `honeyclip enhance` subcommand.

Run standalone:   python tests/test_audio.py
Run via:          python tests/test.py   (invoked after the main suite)

No third-party packages are needed: output properties are probed with the
same ffmpeg the binary uses (HONEYCLIP_FFMPEG, build/ffmpeg, or PATH).

Network: ElevenLabs is replaced by a localhost HTTP mock selected through the
HONEYCLIP_ELEVENLABS_URL override. No real request is ever made. DeepFilterNet
is replaced by a stub `df.enhance` module on PYTHONPATH (copies the input).
"""

import http.server
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
MP3_RESPONSE = FIXTURES / "elevenlabs_isolator_response.bin"


def find_binary() -> str:
    for c in (ROOT / "honeyclip", ROOT / "honeyclip.exe",
              ROOT / "build" / "honeyclip", ROOT / "build" / "honeyclip.exe"):
        if c.exists():
            return str(c)
    raise FileNotFoundError("honeyclip binary not found; run `nimble make` first")


def find_ffmpeg() -> str:
    env = os.environ.get("HONEYCLIP_FFMPEG")
    if env and Path(env).exists():
        return env
    for c in (ROOT / "build" / "ffmpeg", ROOT / "build" / "ffmpeg.exe"):
        if c.exists():
            return str(c)
    found = shutil.which("ffmpeg")
    if found:
        return found
    raise FileNotFoundError("no ffmpeg (HONEYCLIP_FFMPEG, build/ffmpeg or PATH)")


def probe(path: Path) -> dict:
    """Parse the `ffmpeg -i` banner: audio rate/channels, video present, duration."""
    r = subprocess.run([find_ffmpeg(), "-hide_banner", "-i", str(path)],
                       capture_output=True, text=True)
    text = r.stderr
    info = {"video": bool(re.search(r"Stream #.*Video:", text)),
            "audio": bool(re.search(r"Stream #.*Audio:", text)),
            "rate": None, "dur": None}
    m = re.search(r"Audio:.*?(\d+) Hz", text)
    if m:
        info["rate"] = int(m.group(1))
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", text)
    if m:
        info["dur"] = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    return info


class MockElevenLabs:
    """Localhost server that records requests and answers with an MP3 fixture."""

    def __init__(self):
        outer = self
        self.requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                self.rfile.read(n)
                outer.requests.append((self.path, self.headers.get("xi-api-key")))
                body = MP3_RESPONSE.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "audio/mpeg")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        class Quiet(http.server.ThreadingHTTPServer):
            def handle_error(self, request, client_address):
                pass  # clients may drop idle keep-alive sockets

        self.server = Quiet(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/v1"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def python_has_df() -> bool:
    for py in ("python3", "python"):
        if shutil.which(py):
            r = subprocess.run([py, "-c", "import df"], capture_output=True)
            return r.returncode == 0
    return False


STUB_DF_ENHANCE = '''\
import shutil, sys
from pathlib import Path

def main():
    args = sys.argv[1:]
    out = Path(args[args.index("-o") + 1])
    src = Path(args[-1])
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, out / src.name)

if __name__ == "__main__":
    main()
'''


class EnhanceE2E(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = find_binary()
        cls.ffmpeg = find_ffmpeg()
        cls.tmp = Path(tempfile.mkdtemp(prefix="hc_enhance_e2e_"))
        cls.video = cls.tmp / "noisy.mp4"
        cls.make_video(cls.video, FIXTURES / "audio_noisy.wav")
        # Stub DeepFilterNet: `python -m df.enhance` copies the input.
        cls.stub_dir = cls.tmp / "stub"
        (cls.stub_dir / "df").mkdir(parents=True)
        (cls.stub_dir / "df" / "__init__.py").write_text("")
        (cls.stub_dir / "df" / "enhance.py").write_text(STUB_DF_ENHANCE)
        cls.py_dir = cls.tmp / "pybin"
        cls.py_dir.mkdir()
        nl = chr(10)
        if os.name == "nt":
            (cls.py_dir / "python3.cmd").write_text(
                '@"%s" %%*' % sys.executable + nl)
        else:
            sh = cls.py_dir / "python3"
            sh.write_text("#!/bin/sh" + nl + 'exec "%s" "$@"' % sys.executable + nl)
            sh.chmod(0o755)
        cls.cfg_dir = cls.tmp / "cfg"
        cls.cfg_dir.mkdir()
        cls.real_df = python_has_df()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def make_video(cls, path: Path, audio: Path, dur: int = 3):
        subprocess.run(
            [cls.ffmpeg, "-y", "-v", "error", "-f", "lavfi", "-i",
             f"testsrc=duration={dur}:size=320x240:rate=15", "-i", str(audio),
             "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p",
             "-c:a", "aac", str(path)],
            check=True, capture_output=True)

    def env(self, stub_df=False, mock=None, key=None):
        e = os.environ.copy()
        e.pop("ELEVENLABS_API_KEY", None)
        e.pop("HONEYCLIP_ELEVENLABS_URL", None)
        # Keep a developer's real config.toml (and key) out of the run.
        e["APPDATA"] = e["XDG_CONFIG_HOME"] = str(self.cfg_dir)
        e["HOME"] = e["USERPROFILE"] = str(self.cfg_dir)
        e["HONEYCLIP_FFMPEG"] = self.ffmpeg
        if stub_df:
            e["PYTHONPATH"] = str(self.stub_dir)
            # The binary looks for `python3` first (on Windows that is often the
            # Store alias), so shadow it with an interpreter that sees the stub.
            e["PATH"] = str(self.py_dir) + os.pathsep + e["PATH"]
        if mock is not None:
            e["HONEYCLIP_ELEVENLABS_URL"] = mock.url
        if key:
            e["ELEVENLABS_API_KEY"] = key
        return e

    def run_enhance(self, args, **envkw):
        return subprocess.run([self.binary, "enhance", *args], capture_output=True,
                              encoding="utf-8", errors="replace",
                              env=self.env(**envkw), timeout=600,
                              stdin=subprocess.DEVNULL)

    def out(self, name):
        d = self.tmp / ("o_" + name)
        d.mkdir(exist_ok=True)
        return d

    def mock(self):
        m = MockElevenLabs()
        self.addCleanup(m.close)
        return m

    # -- CLI surface ---------------------------------------------------------

    def test_help(self):
        r = self.run_enhance(["--help"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("usage: honeyclip enhance", r.stdout)
        for flag in ("--backend", "--audio-only", "--yes", "--denoise", "--hum-removal"):
            self.assertIn(flag, r.stdout)

    def test_arg_error_unknown_flag(self):
        r = self.run_enhance(["--bogus", str(self.video)])
        self.assertEqual(r.returncode, 2)

    def test_arg_error_bad_stage_mode(self):
        r = self.run_enhance(["--denoise=maybe", str(self.video)])
        self.assertEqual(r.returncode, 2)

    def test_missing_input_file(self):
        r = self.run_enhance([str(self.tmp / "nope.mp4")])
        self.assertEqual(r.returncode, 1)

    # -- backends ------------------------------------------------------------

    def test_enhance_local_path(self):
        """--backend=local with the stubbed DeepFilterNet: default output is
        {input}.enhanced.mp4 with video preserved and audio replaced."""
        src = self.out("local") / "noisy.mp4"
        shutil.copyfile(self.video, src)
        r = self.run_enhance(["--backend=local", "--denoise=on", str(src)], stub_df=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        out = src.with_name("noisy.enhanced.mp4")
        self.assertTrue(out.exists())
        p = probe(out)
        self.assertTrue(p["video"] and p["audio"])
        self.assertEqual(p["rate"], 48000)

    def test_enhance_api_path(self):
        """--backend=elevenlabs against the HTTP mock, cost under $1."""
        m = self.mock()
        out = self.out("api") / "a.wav"
        r = self.run_enhance(["--backend=elevenlabs", "--denoise=on", "--audio-only", "-o", str(out),
                              str(self.video)], mock=m, key="test-key-not-real")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(m.requests), 1)
        self.assertTrue(m.requests[0][0].endswith("/v1/audio-isolation/stream"))
        self.assertEqual(m.requests[0][1], "test-key-not-real")
        self.assertTrue(out.exists())
        self.assertTrue(probe(out)["audio"])
        self.assertNotIn("test-key-not-real", r.stdout + r.stderr)

    def test_enhance_audio_only(self):
        out = self.out("aonly") / "clean.wav"
        r = self.run_enhance(["--backend=local", "--denoise=on", "--audio-only", "-o", str(out),
                              str(self.video)], stub_df=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        p = probe(out)
        self.assertFalse(p["video"])
        self.assertEqual(p["rate"], 48000)
        self.assertAlmostEqual(p["dur"], 3.0, delta=0.5)

    def test_enhance_auto_prefers_local_when_available(self):
        m = self.mock()
        out = self.out("auto_local") / "o.wav"
        r = self.run_enhance(["--denoise=on", "--audio-only", "-o", str(out),
                              str(self.video)], stub_df=True, mock=m, key="test-key-not-real")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(m.requests, [], "auto must use local when DeepFilterNet exists")

    def test_enhance_auto_fallback(self):
        """--backend=auto with no DeepFilterNet but a key falls back to ElevenLabs."""
        if self.real_df:
            self.skipTest("a real DeepFilterNet is installed")
        m = self.mock()
        out = self.out("auto_api") / "o.wav"
        r = self.run_enhance(["--denoise=on", "--audio-only", "-o", str(out), str(self.video)],
                             mock=m, key="test-key-not-real")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(m.requests), 1)

    def test_no_backend_available_clean_error(self):
        if self.real_df:
            self.skipTest("a real DeepFilterNet is installed")
        r = self.run_enhance([str(self.video)])
        self.assertEqual(r.returncode, 1)
        text = (r.stdout + r.stderr).lower()
        self.assertIn("deepfilternet", text)
        self.assertIn("elevenlabs_api_key", text)

    def test_ffmpeg_backend_needs_no_model_or_key(self):
        out = self.out("ffbk") / "o.wav"
        r = self.run_enhance(["--backend=ffmpeg", "--audio-only", "-o", str(out),
                              str(self.video)])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(probe(out)["audio"])

    # -- cost gate (T-22-04) -------------------------------------------------

    def _long_video(self):
        if not hasattr(self, "_long"):
            wav = self.tmp / "long.wav"
            subprocess.run([self.ffmpeg, "-y", "-v", "error", "-f", "lavfi", "-i",
                            "sine=frequency=300:duration=660", "-ar", "16000",
                            "-ac", "1", str(wav)], check=True, capture_output=True)
            self._long = wav
        return self._long

    def test_cost_gate_non_tty_no_yes_denies(self):
        """11 min => ~$1.10 > $1: without --yes on a non-TTY the binary must refuse
        before any HTTP call and write no output."""
        m = self.mock()
        src = self.out("gate") / "long.wav"
        shutil.copyfile(self._long_video(), src)
        r = self.run_enhance(["--backend=elevenlabs", "--denoise=on", str(src)], mock=m,
                             key="test-key-not-real")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(m.requests, [], "no request may be sent when the gate denies")
        self.assertFalse(src.with_name("long.enhanced.wav").exists())

    def test_enhance_cost_gate_yes(self):
        m = self.mock()
        src = self.out("gate_yes") / "long.wav"
        shutil.copyfile(self._long_video(), src)
        out = src.with_name("clean.wav")
        r = self.run_enhance(["--backend=elevenlabs", "--denoise=on", "--yes", "-o", str(out), str(src)],
                             mock=m, key="test-key-not-real")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(len(m.requests), 1)
        self.assertTrue(out.exists())

    # -- stage opt-out -------------------------------------------------------

    def test_enhance_denoise_off(self):
        """With denoise and voice isolation off, the API backend is not used at all."""
        m = self.mock()
        out = self.out("dn_off") / "o.wav"
        r = self.run_enhance(["--backend=elevenlabs", "--denoise=off",
                              "--voice-isolation=off", "--hum-removal=on",
                              "--audio-only", "-o", str(out), str(self.video)],
                             mock=m, key="test-key-not-real")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(m.requests, [])
        self.assertTrue(out.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
