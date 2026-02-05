#!/usr/bin/env python3
"""
Coverage threshold enforcement for Nim tracking modules.

Parses lcov.info and verifies each module meets minimum coverage.
Exits with error if any module is below threshold.

Usage: python3 scripts/check_coverage.py lcov.info 80
"""

import sys
from pathlib import Path


def parse_lcov(lcov_path: str) -> dict[str, tuple[int, int]]:
    """
    Parse lcov.info and return per-file coverage.

    Returns:
        Dict mapping filename -> (lines_hit, lines_found)
    """
    coverage = {}
    current_file = None
    lines_found = 0
    lines_hit = 0

    with open(lcov_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("SF:"):
                # New source file
                if current_file:
                    coverage[current_file] = (lines_hit, lines_found)
                current_file = line[3:]
                lines_found = 0
                lines_hit = 0
            elif line.startswith("LF:"):
                lines_found = int(line[3:])
            elif line.startswith("LH:"):
                lines_hit = int(line[3:])
            elif line == "end_of_record":
                if current_file:
                    coverage[current_file] = (lines_hit, lines_found)
                current_file = None

    return coverage


def filter_modules(coverage: dict, patterns: list[str]) -> dict[str, tuple[int, int]]:
    """
    Filter coverage to only include files matching patterns.
    """
    filtered = {}
    for filepath, (hit, found) in coverage.items():
        for pattern in patterns:
            if pattern in filepath:
                # Use just the filename for cleaner output
                name = Path(filepath).name
                filtered[name] = (hit, found)
                break
    return filtered


def check_coverage(coverage: dict, threshold: float) -> tuple[bool, list[str]]:
    """
    Check if all modules meet threshold.

    Returns:
        (passed, failed_modules) where failed_modules lists modules below threshold
    """
    failed = []
    for module, (hit, found) in sorted(coverage.items()):
        if found == 0:
            pct = 100.0
        else:
            pct = (hit / found) * 100.0

        status = "PASS" if pct >= threshold else "FAIL"
        print(f"  {module}: {pct:.1f}% ({hit}/{found}) [{status}]")

        if pct < threshold:
            failed.append(f"{module}: {pct:.1f}% (need {threshold}%)")

    return len(failed) == 0, failed


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 check_coverage.py <lcov.info> <threshold>")
        print("Example: python3 check_coverage.py lcov.info 80")
        sys.exit(1)

    lcov_path = sys.argv[1]
    threshold = float(sys.argv[2])

    # Modules in scope for Phase 13 (locked by user decision)
    # 6 modules total: kalman, assignment, tracker, crop, easing, compositor
    tracking_modules = [
        "tracking/kalman.nim",
        "tracking/assignment.nim",
        "tracking/tracker.nim",
    ]
    reframe_modules = [
        "reframe/crop.nim",
        "reframe/easing.nim",
        "reframe/compositor.nim",
    ]
    all_modules = tracking_modules + reframe_modules

    print(f"\n=== Coverage Report (threshold: {threshold}%) ===\n")

    coverage = parse_lcov(lcov_path)
    filtered = filter_modules(coverage, all_modules)

    if not filtered:
        print("WARNING: No tracking/reframe modules found in coverage report!")
        print("Available files:")
        for f in sorted(coverage.keys())[:20]:
            print(f"  {f}")
        sys.exit(1)

    print("Tracking modules:")
    tracking_cov = {k: v for k, v in filtered.items()
                    if any(m.split("/")[-1] == k for m in tracking_modules)}
    passed1, failed1 = check_coverage(tracking_cov, threshold)

    print("\nReframe modules:")
    reframe_cov = {k: v for k, v in filtered.items()
                   if any(m.split("/")[-1] == k for m in reframe_modules)}
    passed2, failed2 = check_coverage(reframe_cov, threshold)

    # Calculate totals
    total_hit = sum(h for h, _ in filtered.values())
    total_found = sum(f for _, f in filtered.values())
    total_pct = (total_hit / total_found * 100) if total_found > 0 else 0

    print(f"\n=== Summary ===")
    print(f"Total: {total_pct:.1f}% ({total_hit}/{total_found})")

    all_failed = failed1 + failed2
    if all_failed:
        print(f"\n{len(all_failed)} module(s) below {threshold}% threshold:")
        for f in all_failed:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print(f"\nAll modules meet {threshold}% threshold!")
        sys.exit(0)


if __name__ == "__main__":
    main()
