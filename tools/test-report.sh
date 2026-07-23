#!/bin/sh
# Print a deterministic pass/fail summary + per-failure detail from the newest
# test result bundle. Prefers the fixed bundle written by `make test`/`test-one`
# (build/test-results/*.xcresult) so it never races a parallel run's DerivedData
# bundle; falls back to the DerivedData glob when no fixed bundle exists.
#
# A result bundle is only readable once xcodebuild finalizes it (writes
# Info.plist). A bare `xcresulttool` call right after the test process exits can
# hit a half-written bundle and fail with "Failed to create result bundle
# reader" — indistinguishable from a real failure. This script waits briefly for
# finalization and reports "bundle not ready" as its own state.
#
# Usage: tools/test-report.sh [RESULTS_DIR]   (default build/test-results)
set -eu

results_dir="${1:-build/test-results}"

newest() {
    # Newest *.xcresult under $1 by mtime, or empty.
    # shellcheck disable=SC2012  # bundle names are controlled; need mtime sort
    ls -td "$1"/*.xcresult 2>/dev/null | head -1
}

bundle="$(newest "$results_dir")"
if [ -z "$bundle" ]; then
    # shellcheck disable=SC2012  # need newest-by-mtime across the DerivedData glob
    bundle="$(ls -td \
        "$HOME"/Library/Developer/Xcode/DerivedData/opensky-*/Logs/Test/*.xcresult \
        2>/dev/null | head -1)"
fi
if [ -z "$bundle" ]; then
    echo "[ERROR] no .xcresult found (looked in $results_dir, then DerivedData)" >&2
    echo "        run 'make test' or 'make test-one T=...' first" >&2
    exit 1
fi

# Wait up to ~10s for finalization rather than misreport a half-written bundle.
i=0
while [ ! -e "$bundle/Info.plist" ]; do
    i=$((i + 1))
    if [ "$i" -gt 20 ]; then
        echo "[ERROR] result bundle not finalized (no Info.plist): $bundle" >&2
        echo "        tests may still be running, or the run crashed mid-write" >&2
        exit 2
    fi
    sleep 0.5
done

echo "[INFO] $bundle"
xcrun xcresulttool get test-results summary --path "$bundle"

# Summary above prints counts; now name each failing test + its message so a
# failure is actionable without hand-parsing JSON (the recurring pain point).
# Write the JSON to a temp file and pass its path as argv — a heredoc script on
# stdin would otherwise override piped input (shellcheck SC2259).
tests_json="$(mktemp -t opensky-test-report)"
trap 'rm -f "$tests_json"' EXIT INT TERM
xcrun xcresulttool get test-results tests --path "$bundle" --format json \
    >"$tests_json" 2>/dev/null || : >"$tests_json"

python3 - "$tests_json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        data = json.load(stream)
except (OSError, json.JSONDecodeError, ValueError):
    sys.exit(0)

fails = []


def walk(node):
    if isinstance(node, dict):
        if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
            name = node.get("name", "<unknown>")
            msgs = [
                child.get("name", "")
                for child in node.get("children", [])
                if child.get("nodeType") == "Failure Message"
            ]
            fails.append((name, msgs))
        for child in node.get("children", []):
            walk(child)
    elif isinstance(node, list):
        for child in node:
            walk(child)


walk(data)

if fails:
    print(f"\n[FAIL] {len(fails)} failing test(s):")
    for name, msgs in fails:
        print(f"  - {name}")
        for msg in msgs:
            print(f"      {msg}")
else:
    print("\n[INFO] no failing tests in this bundle")
PY
