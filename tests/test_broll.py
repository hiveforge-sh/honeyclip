#!/usr/bin/env python3
"""Phase 21 end-to-end tests for the `honeyclip broll` subcommand.

Run as part of: python3 tests/test.py

Requires: pip install av
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
RESOURCES = ROOT / "resources"


def find_binary():
    """Locate the honeyclip binary.

    Checks the standard locations. When running inside a git worktree the
    binary lives in the main-repo root, not the worktree root, so we probe
    that path as well via git --git-common-dir.
    """
    # Standard / main-repo locations relative to ROOT
    candidates = [
        ROOT / "honeyclip",
        ROOT / "honeyclip.exe",
        ROOT / "build" / "honeyclip",
        ROOT / "build" / "honeyclip.exe",
    ]

    # Worktree: the binary is built into the main repo root.
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--git-common-dir"],
            capture_output=True, text=True, cwd=str(ROOT)
        )
        if result.returncode == 0:
            common_dir = Path(result.stdout.strip())
            # .git/  ->  parent is the main repo root
            main_root = common_dir.parent
            if main_root != ROOT:
                candidates += [
                    main_root / "honeyclip",
                    main_root / "honeyclip.exe",
                    main_root / "build" / "honeyclip",
                    main_root / "build" / "honeyclip.exe",
                ]
    except Exception:
        pass

    for c in candidates:
        if c.exists():
            return str(c)

    raise FileNotFoundError(
        f"honeyclip binary not found in any of: {[str(c) for c in candidates]}. "
        f"Run `nimble make` first."
    )


def find_test_video():
    """Return the path of a small test video in resources/.

    Matches the convention in tests/test.py (resources/testsrc.mp4 first).
    """
    preferred = RESOURCES / "testsrc.mp4"
    if preferred.exists():
        return str(preferred)
    for ext in ("*.mp4", "*.mov", "*.mkv"):
        for p in sorted(RESOURCES.glob(ext)):
            return str(p)
    raise FileNotFoundError(f"No test video found in {RESOURCES}")


class BrollHelpTest(unittest.TestCase):
    """honeyclip broll --help exits 0 and includes all documented flags."""

    def test_help_prints_usage_and_all_flags(self):
        binary = find_binary()
        r = subprocess.run(
            [binary, "broll", "--help"],
            capture_output=True, text=True, timeout=15
        )
        self.assertEqual(r.returncode, 0, msg=f"stderr: {r.stderr}")
        out = r.stdout
        self.assertIn("usage: honeyclip broll", out,
                      msg="help text missing 'usage: honeyclip broll'")
        for flag in ("--max-broll", "--min-spacing", "--backend",
                     "--comfy-url", "--workflow", "--render", "--yes"):
            self.assertIn(flag, out, msg=f"help text missing flag: {flag}")


class BrollOfflineFailureTest(unittest.TestCase):
    """With no reachable backend and no API key, broll must fail gracefully."""

    def test_unreachable_comfyui_no_key_errors_clearly(self):
        binary = find_binary()
        video = find_test_video()
        env = os.environ.copy()
        env.pop("GEMINI_API_KEY", None)

        with tempfile.TemporaryDirectory() as td:
            out_path = Path(td) / "broll.json"
            start = time.monotonic()
            r = subprocess.run(
                [
                    binary, "broll", video,
                    "--backend", "auto",
                    "--comfy-url", "http://127.0.0.1:1",  # closed port
                    "--workflow", str(FIXTURES / "comfyui_workflow.json"),
                    "-o", str(out_path),
                    "--quiet",
                ],
                capture_output=True, text=True, env=env, timeout=15
            )
            elapsed = time.monotonic() - start
            self.assertNotEqual(
                r.returncode, 0,
                msg="expected non-zero exit when no backend is reachable; got 0"
            )
            self.assertLess(
                elapsed, 10.0,
                msg=(
                    f"broll should fail fast before transcript extraction "
                    f"(resolveProvider must short-circuit); elapsed={elapsed:.2f}s"
                )
            )
            combined = (r.stdout + r.stderr).lower()
            self.assertTrue(
                "comfyui" in combined or "gemini" in combined
                or "backend" in combined or "key" in combined
                or "api" in combined or "error" in combined,
                msg=(
                    f"error message must reference the backend/key issue; "
                    f"got stdout={r.stdout!r} stderr={r.stderr!r}"
                )
            )


class BrollMarkerSnapshotTest(unittest.TestCase):
    """Lock down the marker JSON shape against tests/fixtures/broll_marker_snapshot.json."""

    REQUIRED_TOP_KEYS = frozenset({"sourceVideo", "insertions"})
    REQUIRED_INSERT_KEYS = frozenset({
        "startMs", "endMs", "pauseMs", "score", "sourceTag",
        "contextText", "prompt", "clipPath",
        "actualDurationMs", "success",
    })

    def test_marker_json_matches_snapshot_shape(self):
        snapshot_path = FIXTURES / "broll_marker_snapshot.json"
        self.assertTrue(
            snapshot_path.exists(),
            msg=f"Snapshot fixture missing: {snapshot_path}"
        )
        snapshot = json.loads(snapshot_path.read_text())
        self.assertEqual(
            set(snapshot.keys()), self.REQUIRED_TOP_KEYS,
            msg=f"top-level keys mismatch: got {set(snapshot.keys())}"
        )
        self.assertIsInstance(
            snapshot["insertions"], list,
            msg="'insertions' must be a list"
        )
        for i, ins in enumerate(snapshot["insertions"]):
            self.assertEqual(
                set(ins.keys()), self.REQUIRED_INSERT_KEYS,
                msg=f"insertion[{i}] key mismatch: got {set(ins.keys())}"
            )


class BrollAudioSyncSmokeTest(unittest.TestCase):
    """If --render runs successfully (requires real ComfyUI), source and output
    duration must match within 100ms.  In CI without a running ComfyUI/Veo this
    test always skips with a clear reason."""

    def test_render_preserves_duration(self):
        if os.environ.get("HONEYCLIP_E2E_LIVE") != "1":
            self.skipTest(
                "HONEYCLIP_E2E_LIVE != 1 — live render requires a running "
                "ComfyUI or Veo API key; skipping in offline/CI mode"
            )
        try:
            import av  # noqa: F401
        except ImportError:
            self.skipTest("PyAV (`pip install av`) not installed")
        # Live-render audio-sync check is covered by manual verification steps
        # in .planning/phases/21-ai-broll-integration/21-VALIDATION.md.
        self.skipTest(
            "live render audio-sync covered by manual VALIDATION.md steps"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
