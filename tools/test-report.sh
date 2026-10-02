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

# Coverage. It reads the profile with llvm-cov, as coverage-floor.sh does:
# `xccov` sees only the app, because each package module is its own framework
# under PackageFrameworks and the result bundle lists none of them. The profile
# is from the last test run, which a filtered run makes read low.
build="${OPENSKY_DERIVED_DATA:-$PWD/DerivedData}/Build"
# shellcheck disable=SC2012  # newest-by-mtime of a few fixed-name files
profile="$(ls -t "$build"/ProfileData/*/Coverage.profdata 2>/dev/null | head -1)"
if [ -z "$profile" ]; then
    printf '\n[INFO] no coverage profile under %s/ProfileData\n' "$build"
    exit 0
fi
set -- "$build/Products/Debug/OpenSky.app/Contents/MacOS/OpenSky.debug.dylib"
for framework in "$build"/Products/Debug/PackageFrameworks/*.framework; do
    set -- "$@" -object "$framework/$(basename "$framework" .framework)"
done
coverage_json="$(mktemp -t opensky-coverage-report)"
trap 'rm -f "$tests_json" "$coverage_json"' EXIT INT TERM
if ! xcrun llvm-cov export -summary-only -instr-profile "$profile" "$@" \
    >"$coverage_json" 2>/dev/null; then
    printf '\n[INFO] llvm-cov could not read %s\n' "$profile"
    exit 0
fi
python3 - "$coverage_json" "$profile" <<'PY'
import collections
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    files = json.load(stream)["data"][0]["files"]

modules = collections.defaultdict(lambda: [0, 0])
for entry in files:
    if "/Sources/" not in entry["filename"]:
        continue
    module = entry["filename"].split("/Sources/", 1)[1].split("/", 1)[0]
    lines = entry["summary"]["lines"]
    modules[module][0] += lines["covered"]
    modules[module][1] += lines["count"]


def line(label, covered, count):
    percent = 100.0 * covered / count if count else 0.0
    print(f"  {label:<28} {percent:6.2f}%  ({covered}/{count} lines)")


print(f"\n[INFO] code coverage from {sys.argv[2]}:")
line("overall", sum(c for c, _ in modules.values()), sum(n for _, n in modules.values()))
for name, (covered, count) in sorted(modules.items()):
    line(name, covered, count)
PY
