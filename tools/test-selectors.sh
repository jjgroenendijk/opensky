#!/bin/sh
# Fail when a test selector matched no test in a result bundle. xcodebuild runs
# zero tests for a misspelled -only-testing selector and still exits 0.
#
# A selector is Target[/Suite[/test()]]. It matches a test whose identifier is
# the selector itself or starts with the selector and a slash.
#
# Usage: tools/test-selectors.sh BUNDLE.xcresult SELECTOR...
set -eu

if [ "$#" -lt 2 ]; then
    echo "[ERROR] usage: tools/test-selectors.sh BUNDLE.xcresult SELECTOR..." >&2
    exit 2
fi
bundle="$1"
shift

tests_json="$(mktemp -t opensky-test-selectors)"
trap 'rm -f "$tests_json"' EXIT INT TERM
if ! xcrun xcresulttool get test-results tests --path "$bundle" --format json \
    >"$tests_json" 2>/dev/null; then
    echo "[ERROR] cannot read the tests in $bundle" >&2
    exit 2
fi

python3 - "$tests_json" "$@" <<'PY'
import json
import sys

PREFIX = "test://com.apple.xcode/"

with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)

identifiers = set()


def walk(node):
    url = node.get("nodeIdentifierURL", "")
    if node.get("nodeType") == "Test Case" and url.startswith(PREFIX):
        # The URL path is Project/Target/Suite.../test(); drop the project.
        identifiers.add(url[len(PREFIX):].split("/", 1)[-1])
    for child in node.get("children", []):
        walk(child)


for root in data.get("testNodes", []):
    walk(root)

unmatched = [
    selector
    for selector in sys.argv[2:]
    if not any(
        test == selector or test.startswith(selector.rstrip("/") + "/")
        for test in identifiers
    )
]
for selector in unmatched:
    print(f"[ERROR] selector matched no test: {selector}", file=sys.stderr)
sys.exit(1 if unmatched else 0)
PY
