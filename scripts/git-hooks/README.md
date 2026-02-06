# Git Hooks for honeyclip

This directory contains Git hooks to ensure code quality and catch issues before committing.

## Installation

From the repository root:

```bash
./scripts/install-hooks.sh
```

This will install the pre-commit hook to `.git/hooks/pre-commit`.

## Pre-Commit Hook

The pre-commit hook runs automatically before each commit and validates:

### Always Run (Fast Checks)

1. **File Size** - Prevents committing large files (>5MB) accidentally
2. **Secrets Detection** - Scans for API keys, passwords, tokens
3. **Debug Code** - Warns about debug prints (e.g., `echo DEBUG`)
4. **TODO Markers** - Suggests adding issue references to TODOs
5. **Nim Syntax** - Runs `nim check` on staged .nim files
6. **Unit Tests** - Runs `nimble test` when source files change
7. **Platform Guards** - Checks for platform-specific code without `when defined()` guards

### Optional (Slow Checks)

8. **Windows Cross-Compilation** - Disabled by default (very slow)
   - Enable: `export PRECOMMIT_CHECK_WINDOWS=1`

## Configuration

### Enable Windows Cross-Compile Check

Add to `~/.bashrc` or `~/.zshrc`:

```bash
export PRECOMMIT_CHECK_WINDOWS=1
```

This enables the cross-compilation check, which verifies Windows builds work before committing. **Warning:** This adds ~2 minutes to commit time.

## Skipping Hooks

When you need to bypass the checks (use sparingly):

```bash
git commit --no-verify
```

**When to skip:**
- Emergency hotfix
- Work-in-progress commit (will be squashed later)
- False positive from hook (report the issue!)

## Uninstalling

```bash
rm .git/hooks/pre-commit
```

Or restore the old hook if backed up:

```bash
mv .git/hooks/pre-commit.old .git/hooks/pre-commit
```

## CI Integration

The hooks automatically skip in CI environments (when `$CI` is set). The CI runs its own comprehensive checks.

## Troubleshooting

### Hook fails with "permission denied"

Make the hook executable:

```bash
chmod +x .git/hooks/pre-commit
```

### Hook fails with "nimble: command not found"

Ensure Nim is in your PATH:

```bash
# Check if Nim is installed
nim --version
nimble --version

# If not, install via choosenim:
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

### Hook is too slow

1. **Disable Windows cross-compile check:**
   ```bash
   unset PRECOMMIT_CHECK_WINDOWS
   ```

2. **Skip hook for WIP commits:**
   ```bash
   git commit --no-verify -m "WIP: work in progress"
   # Later, amend with full checks:
   git commit --amend
   ```

3. **Only commit relevant files:**
   ```bash
   # Stage specific files instead of `git add .`
   git add src/specific_file.nim
   git commit  # Hook only checks staged files
   ```

### False positives

If the hook incorrectly flags code:

1. **Report it** - Open an issue so we can improve the hook
2. **Use `--no-verify`** - Bypass the check for this commit
3. **Add exception** - Modify the hook to skip your case

## Hook Details

### File Size Check

- **Limit:** 5MB
- **Exceptions:** `resources/`, `tests/resources/`, `ml_sources/`, `ffmpeg_sources/`
- **Rationale:** Prevents accidentally committing binaries or large media files

### Secrets Detection

Scans for patterns like:
- `password = "..."`
- `api_key = "..."`
- `bearer <token>`
- Private keys (RSA, DSA, etc.)

**Note:** This is not foolproof. Always review sensitive data carefully.

### Debug Code Detection

Warns about:
- `echo DEBUG`
- `debugEcho`
- `echo FIXME`
- `console.log DEBUG` (for any embedded JS)

### Platform Guard Check

Ensures cross-platform code is properly guarded:

```nim
# WRONG:
import std/posix_utils  # Only works on Unix!

# CORRECT:
when not defined(windows):
  import std/posix_utils
```

Checks for:
- Windows-specific: `mingw`, `win32`, `windows.h`, `GetProcessMemoryInfo`
- Linux-specific: `linux.h`, `/proc/`, `posix`
- macOS-specific: `darwin.h`, `mach_task`, `__APPLE__`

## Customization

To modify the hook behavior:

1. Edit `scripts/git-hooks/pre-commit`
2. Test your changes: `./scripts/git-hooks/pre-commit`
3. Reinstall: `./scripts/install-hooks.sh`

## Contributing

Improvements to the hooks are welcome! Please:

1. Test on all platforms (macOS, Linux, Windows/Git Bash)
2. Keep checks fast (<30 seconds total)
3. Provide clear error messages
4. Document new checks in this README
