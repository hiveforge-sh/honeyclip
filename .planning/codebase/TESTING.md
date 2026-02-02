# Testing Patterns

**Analysis Date:** 2026-02-01

## Test Framework

**Runner:**
- Nim built-in `unittest` module (standard library)
- Config: No separate test config file; tests run via `ae.nimble test` task (line 38-39 of `ae.nimble`)
- Command: `nim c {flags} -r tests/unit`

**Assertion Library:**
- Nim's built-in `check` macro from `unittest` module
- Syntax: `check expression` where expression evaluates to bool

**Run Commands:**
```bash
nimble test              # Run all unit tests (Nim)
python3 tests/test.py    # Run E2E tests (Python)
```

## Test File Organization

**Location:**
- Nim unit tests: `tests/unit.nim` (single file)
- Python E2E tests: `tests/test.py`
- Test utilities: `tests/ffwrapper.py`

**Naming:**
- Test functions: `test "description": ...` syntax (Nim unittest)
- Python test methods: `def test_*(self)` convention

**Structure:**
```
tests/
├── unit.nim         # Nim unit tests (~180 lines)
├── test.py          # Python E2E tests (~400+ lines)
└── ffwrapper.py     # FFmpeg wrapper utilities
```

## Test Structure

**Nim Suite Organization:**

Unit tests in `tests/unit.nim` use Nim's `test` block syntax:

```nim
test "avrational":
  let a = AVRational(num: 3, den: 4)
  let b = AVRational(num: 3, den: 4)
  check a + b == AVRational(num: 3, den: 2)
  check a + a == a * 2
```

**Patterns:**
- Setup: Local variable initialization within test block
- Teardown: `defer:` blocks for cleanup (see `tests/unit.nim` line 109-113)
  - Example: `let tempDir = createTempDir("tmp", ""); defer: removeDir(tempDir)`
- Assertions: `check` macro with boolean expressions

**Python Test Structure:**

E2E tests use class-based runner (`tests/test.py` lines 60-105):

```python
class Runner:
    def __init__(self) -> None:
        self.program = ["./honeyclip"]
        self.temp_dir = mkdtemp()

    def main(self, inputs: list[str], cmd: list[str], output: str | None = None) -> str:
        # Construct command, run subprocess, return output path

    def test_help(self):
        """check the help option, its short, and help on options and groups."""
        self.raw(["--help"])
        self.raw(["-h"])
```

## Mocking

**Framework:** No explicit mocking library; tests use real file I/O and subprocess calls

**Patterns:**

Nim unit tests avoid mocking by testing simple functions directly:
- AVRational arithmetic (lines 25-43 of `tests/unit.nim`)
- Color parsing (lines 45-56)
- Direct invocation of tested functions

Python E2E tests use subprocess execution for integration:
```python
def pipe_to_console(cmd: list[str]) -> tuple[int, str, str]:
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    return process.returncode, stdout.decode("utf-8"), stderr.decode("utf-8")
```

**What to Mock:**
- Not mocking: FFmpeg is real dependency, subprocess calls are actual
- Tests validate real media processing output

**What NOT to Mock:**
- File operations (tempfiles created and tested)
- Media file reading/writing
- FFmpeg codec operations

## Fixtures and Factories

**Test Data:**

Test media files located in `resources/` directory:
```python
all_files = (
    "aac.m4a",
    "alac.m4a",
    "wav/pcm-f32le.wav",
    "wav/pcm-s32le.wav",
    "multi-track.mov",
    "mov_text.mp4",
    "testsrc.mkv",
)
```

**Test Media Access:**
```python
def fileinfo(path: str) -> FileInfo:
    return FileInfo.init(path, log)
```

**Location:**
- Media files: `resources/` directory (referenced in `tests/test.py`)
- Temporary output: Created in `mkdtemp()` per test run

**Nim Test Fixtures:**
- Subtitle test: Uses real files `"resources/mono.mp3"`, `"example.mp4"` (lines 112, 124)
- WAV transcoding tests: Load actual mp3/mp4, write WAV, verify codec properties

## Coverage

**Requirements:** No enforced coverage target found in configuration

**View Coverage:**
- Coverage reporting not configured in `ae.nimble`
- Manual inspection via test execution output only

## Test Types

**Unit Tests:**
- Scope: Individual functions and type operations
- Approach: Direct function calls with assertions
- Location: `tests/unit.nim`
- Examples:
  - `test "avrational"`: Operations on AVRational type
  - `test "color"`: parseColor() and toString() functions
  - `test "encoder"`: initEncoder() initialization
  - `test "margin"`: mutMargin() list mutation

**Integration Tests:**
- Scope: Module interactions and data flow
- Approach: Test complete workflows through real I/O
- Location: `tests/unit.nim` (lines 108-130)
- Examples:
  - `test "mp3towav"`: Transcode MP3 to WAV, verify codec
  - `test "mp4towav"`: Transcode MP4 to WAV, verify layout
  - `test "size-of-objects"`: Memory layout assertions for FFmpeg types

**E2E Tests:**
- Scope: Full CLI workflows and media processing
- Framework: Python subprocess runner (`tests/test.py`)
- Approach: Execute honeyclip binary with various arguments, verify outputs
- Examples:
  - `test_example()`: Process example.mp4, verify output duration and codec
  - `test_video_to_mp3()`: Convert video to audio-only MP3
  - `test_to_mono()`: Verify audio channel layout conversion
  - `test_movflags()`: Validate faststart/fragmented output differences

## Common Patterns

**Async Testing:**
- Not used in codebase
- Tests are synchronous and blocking

**Error Testing:**

Nim error testing via `check` assertions:
```nim
test "encoder":
  let (_, encoderCtx) = initEncoder("pcm_s16le")
  check encoderCtx.codec_type == AVMEDIA_TYPE_AUDIO
```

Python error testing via exception checking:
```python
def check(self, cmd: list[str], match=None) -> None:
    returncode, stdout, stderr = pipe_to_console(self.program + cmd)
    if returncode > 0:
        if "Error!" in stderr:
            if match is not None and match not in stderr:
                raise Exception(f'Could\'t find "{match}"')
```

**Subprocess Testing Pattern:**

```python
class Runner:
    def main(self, inputs: list[str], cmd: list[str], output: str | None = None) -> str:
        cmd = self.program + inputs + cmd + ["--no-open", "--progress", "none"]
        # ... compute output path ...
        returncode, stdout, stderr = pipe_to_console(cmd + ["--output", output])
        if returncode > 0:
            raise Exception(f"Test returned: {returncode}\n{stdout}\n{stderr}\n")
        return output
```

**Test Verification Examples:**

Nim subprocess output verification (line 114-118 of `tests/unit.nim`):
```nim
let container = av.open(outFile)
defer: container.close()
check container.audio.len == 1
check $container.audio[0].name == "pcm_s16le"
```

Python media property verification (lines 168-186 of `tests/test.py`):
```python
with av.open(out) as container:
    assert container.duration is not None
    assert container.duration > 17300000 and container.duration < 2 << 24
    assert len(container.streams) == 2
    video = container.streams[0]
    audio = container.streams[1]
    assert isinstance(video, VideoStream)
    assert isinstance(audio, AudioStream)
```

## Test Invocation

**Unit Tests:**
- Command: `nimble test` or `nim c -r tests/unit`
- Compiles and immediately executes test suite
- Returns exit code 0 on success

**E2E Tests:**
- Command: `python3 tests/test.py`
- Runner instantiation and test method execution
- Optional filters via command line: `--only test_name1 test_name2`
- Parallel execution: `concurrent.futures.ThreadPoolExecutor` (line 2, 109 of `tests/test.py`)

**Test Discovery:**
- Nim: All `test "..."` blocks in `tests/unit.nim` executed
- Python: Methods prefixed with `test_` auto-discovered (no explicit discovery in code)

---

*Testing analysis: 2026-02-01*
