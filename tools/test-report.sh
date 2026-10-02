#!/bin/sh
# Print a deterministic pass/fail summary + per-failure detail from the newest
# test result bundle. Prefers the bundles the make test-* targets write
# (DerivedData/TestResults/*.xcresult) so it never races a parallel run's DerivedData
# bundle; falls back to the DerivedData glob when no fixed bundle exists.
#
# A result bundle is only readable once xcodebuild finalizes it (writes
# Info.plist). A bare `xcresulttool` call right after the test process exits can
# hit a half-written bundle and fail with "Failed to create result bundle
# reader" — indistinguishable from a real failure. This script waits briefly for
# finalization and reports "bundle not ready" as its own state.
#
# Usage: tools/test-report.sh [RESULTS_DIR]   (default DerivedData/TestResults)
set -eu

results_dir="${1:-${OPENSKY_DERIVED_DATA:-$PWD/DerivedData}/TestResults}"

newest() {
    # Newest *.xcresult under $1 by mtime, or empty. Bundles sit one run
    # directory deep (TestResults/<name>/<timestamp>/*.xcresult, issue
    # #347); `latest` symlinks are not followed, so no bundle is seen twice.
    find "$1" -maxdepth 3 -name '*.xcresult' -prune -exec stat -f '%m %N' {} + \
        2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

bundle="$(newest "$results_dir")"
if [ -z "$bundle" ]; then
    # shellcheck disable=SC2012  # need newest-by-mtime across the DerivedData glob
    bundle="$(ls -td \
        "${OPENSKY_DERIVED_DATA:-$PWD/DerivedData}"/Logs/Test/*.xcresult \
        2>/dev/null | head -1)"
fi
if [ -z "$bundle" ]; then
    echo "[ERROR] no .xcresult found (looked in $results_dir, then DerivedData)" >&2
    echo "        run 'make test-unit' first" >&2
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
        # The root object holds the tree under "testNodes", every node below it
        # under "children". Recursing on "children" alone walked nothing at all,
        # so this printed "no failing tests" for every bundle including failing
        # ones (issue #381).
        for child in node.get("children", []) + node.get("testNodes", []):
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

# Pass, fail, and time per shared tag. The result bundle does not carry Swift
# Testing tags, so each test is matched to the tags its suite and @Test declare
# in the sources. Times from a parallel run include waits for the main actor.
python3 - "$tests_json" "$(git rev-parse --show-toplevel)/Tests" <<'PY'
import collections
import json
import pathlib
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        data = json.load(stream)
except (OSError, json.JSONDecodeError, ValueError):
    sys.exit(0)

PARENS = r"((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)"
SUITE = re.compile(r"@Suite\(" + PARENS + r"\)\s*(?:@\w+\s*)*(?:\w+\s+)*(?:struct|class|enum|actor)\s+(\w+)")
TEST = re.compile(r"@Test\(" + PARENS + r"\)\s*(?:@\w+\s*)*(?:\w+\s+)*func\s+(\w+)")
TAGS = re.compile(r"\.tags\(([^)]*)\)")


def tags_in(args):
    return {tag.strip().lstrip(".") for group in TAGS.findall(args) for tag in group.split(",") if tag.strip()}


suite_tags = collections.defaultdict(set)
test_tags = collections.defaultdict(set)
for target in pathlib.Path(sys.argv[2]).iterdir():
    for path in target.rglob("*.swift") if target.is_dir() else []:
        text = path.read_text(errors="ignore")
        for args, name in SUITE.findall(text):
            suite_tags[(target.name, name)] |= tags_in(args)
        for args, name in TEST.findall(text):
            test_tags[(target.name, name)] |= tags_in(args)

rows = collections.defaultdict(lambda: [0, 0, 0.0])


def walk(node, bundle):
    if node.get("nodeType") == "Unit test bundle":
        bundle = node.get("name")
    if node.get("nodeType") == "Test Case" and node.get("nodeIdentifier"):
        parts = node["nodeIdentifier"].split("/")
        tags = set().union(*(suite_tags[(bundle, part)] for part in parts[:-1]))
        tags |= test_tags[(bundle, parts[-1].split("(")[0])]
        for tag in tags or {"(untagged)"}:
            row = rows[tag]
            row[0] += 1
            row[1] += node.get("result") == "Failed"
            row[2] += node.get("durationInSeconds", 0.0)
    for child in node.get("children", []) + node.get("testNodes", []):
        walk(child, bundle)


walk(data, None)
if rows:
    print("\n[INFO] per tag:")
    print(f"  {'tag':<12} {'tests':>6} {'failed':>7} {'seconds':>9}")
    for tag, (count, failed, seconds) in sorted(rows.items()):
        print(f"  {tag:<12} {count:>6} {failed:>7} {seconds:>9.1f}")
PY

# Coverage (issue #382). The UnitTests and AllTests plans gather it for the
# `OpenSky` target, so every bundle from `make test-unit` carries it and the
# percentage arrives through the same command as the pass/fail counts rather
# than out of a hand-parsed .xcresult. A bundle from a run that gathered none
# still has to report as a missing number rather than a failure, so a non-zero
# xccov exit prints one line and moves on.
coverage_json="$(mktemp -t opensky-coverage-report)"
trap 'rm -f "$tests_json" "$coverage_json"' EXIT INT TERM
if xcrun xccov view --report --json "$bundle" >"$coverage_json" 2>/dev/null; then
    python3 - "$coverage_json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        report = json.load(stream)
except (OSError, json.JSONDecodeError, ValueError):
    sys.exit(0)


def line(label, node):
    covered = node.get("coveredLines", 0)
    executable = node.get("executableLines", 0)
    percent = 100.0 * node.get("lineCoverage", 0.0)
    print(f"{label} {percent:6.2f}%  ({covered}/{executable} lines)")


targets = report.get("targets", [])
print("\n[INFO] code coverage:")
line("  overall            ", report)
# The plans scope coverage to the one app target, so the per-target breakdown
# repeats the overall line verbatim and is only worth printing once a second
# target is in scope.
if len(targets) > 1:
    for target in targets:
        line(f"  {target.get('name', '<unknown>'):<19}", target)
PY
else
    printf '\n[INFO] no coverage data in this bundle\n'
fi
