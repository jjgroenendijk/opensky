"""Print what a result bundle holds: build errors and warnings, then test totals and failures.

Usage: python3 tools/xcresult_summary.py BUNDLE.xcresult
Exits 1 when the bundle holds an error or a failed test, or cannot be read.
"""

import json
import pathlib
import subprocess
import sys
import urllib.parse

MAX_ERRORS = 40
MAX_WARNINGS = 10


def read(kind, bundle):
    """One `xcresulttool get` report as JSON, or None when the bundle has none."""
    command = ["xcrun", "xcresulttool", "get", *kind, "--path", str(bundle), "--compact"]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    return json.loads(result.stdout) if result.returncode == 0 and result.stdout else None


def location(issue):
    """`src/...:line` from an issue's source URL; prefix mapping writes `/^src`."""
    url = urllib.parse.urlparse(issue.get("sourceURL", ""))
    path = urllib.parse.unquote(url.path).replace("/^src/", "src/")
    line = urllib.parse.parse_qs(url.fragment).get("StartingLineNumber", [""])[0]
    return f"{path}:{int(line) + 1}" if line.isdigit() else path


def issues(entries, label, limit):
    seen = []
    for issue in entries:
        text = f"{label}: {location(issue)}: {issue.get('message', '').strip()}"
        if text not in seen:
            seen.append(text)
    for text in seen[:limit]:
        print(text)
    if len(seen) > limit:
        print(f"[INFO] {len(seen) - limit} more {label}s not shown")
    return len(seen)


def tests(summary):
    failed = summary.get("failedTests", 0)
    passed = summary.get("passedTests", 0)
    skipped = summary.get("skippedTests", 0)
    for failure in summary.get("testFailures", [])[:MAX_ERRORS]:
        name = failure.get("testIdentifierString", failure.get("testName", "?"))
        print(f"[FAIL] {name}: {failure.get('failureText', '').strip()}")
    mark = "[FAIL]" if failed else "[ OK ]"
    print(f"{mark} tests: {passed} passed, {failed} failed, {skipped} skipped")
    return failed


def main(bundle):
    if not (bundle / "Info.plist").exists():
        print(f"[ERROR] no finished result bundle at {bundle}")
        return 1
    build = read(["build-results"], bundle) or {}
    errors = issues(build.get("errors", []), "error", MAX_ERRORS)
    issues(build.get("warnings", []), "warning", MAX_WARNINGS)
    summary = read(["test-results", "summary"], bundle)
    # A build-only bundle still answers the test summary, with every count 0.
    ran = summary and summary.get("totalTestCount", sum(summary.get(k, 0) for k in ("passedTests", "failedTests", "skippedTests")))
    failed = tests(summary) if ran else 0
    if not ran and not errors:
        print("[ OK ] build succeeded")
    return 1 if errors or failed else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("[ERROR] usage: python3 tools/xcresult_summary.py BUNDLE.xcresult")
    sys.exit(main(pathlib.Path(sys.argv[1])))
