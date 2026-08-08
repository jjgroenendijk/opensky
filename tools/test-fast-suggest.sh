#!/bin/sh
# Near-match suggestions for a test selector that ran zero tests (issue #417).
# This replaces the per-run `-enumerate-tests` validation pass tools/realtest.sh
# used to make before every single-test run — an entire extra xcodebuild
# invocation on the hot path guarding against nothing but typos. Enumeration
# now happens only on the failure path, against the cached .xctestrun (no
# build), and the flat list itself is cached beside the derived data and reused
# until the .xctestrun changes. A green run pays nothing.
#
# Usage: tools/test-fast-suggest.sh XCTESTRUN SELECTOR
set -eu

if [ "$#" -ne 2 ]; then
    echo "[ERROR] usage: tools/test-fast-suggest.sh XCTESTRUN SELECTOR" >&2
    exit 2
fi
xctestrun="$1"
selector="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"

cache="$OPENSKY_DERIVED_DATA/Build/Products/$(basename "$xctestrun" .xctestrun).tests.txt"
if [ ! -f "$cache" ] || [ "$xctestrun" -nt "$cache" ]; then
    # A temp directory, not mktemp's file: xcodebuild refuses to write the
    # enumeration into a path that already exists, and mktemp creates the file.
    json_dir="$(mktemp -d -t opensky-enumeration)"
    json="$json_dir/tests.json"
    trap 'rm -rf "$json_dir"' EXIT INT TERM
    # `-enumerate-tests` rejects `-derivedDataPath` outright (usage error,
    # Xcode 26.6), so this one invocation cannot be pointed at the checkout's
    # cache and drops a small session-log directory under Xcode's default
    # location instead. Snapshot the directory list first and remove exactly
    # what the run created — this is the rare failure path, not the hot loop.
    xcode_dd="$HOME/Library/Developer/Xcode/DerivedData"
    before="$(ls "$xcode_dd" 2>/dev/null || true)"
    xcodebuild test-without-building -xctestrun "$xctestrun" \
        -destination 'platform=macOS' \
        -enumerate-tests -test-enumeration-style flat \
        -test-enumeration-format json \
        -test-enumeration-output-path "$json" >/dev/null 2>&1
    after="$(ls "$xcode_dd" 2>/dev/null || true)"
    printf '%s\n' "$after" | while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        case "$entry" in opensky-*) ;; *) continue ;; esac
        printf '%s\n' "$before" | grep -qxF "$entry" \
            || rm -rf "${xcode_dd:?}/$entry"
    done
    # disabledTests included deliberately: an .xctestrun carrying baked
    # OnlyTestIdentifiers -- what a plan's own (inert) test selection leaves
    # behind -- reports every Swift Testing test as disabled, and those are
    # exactly the identifiers a typo should be corrected against.
    python3 - "$json" <<'PY' >"$cache"
import json, sys
with open(sys.argv[1], "rb") as stream:
    data = json.load(stream)
seen = set()
for value in data.get("values", []):
    for group in ("enabledTests", "disabledTests"):
        for test in value.get(group, []):
            identifier = test.get("identifier")
            if identifier and identifier not in seen:
                seen.add(identifier)
                print(identifier)
PY
fi

# Match on the last path component (the method name) first, then the suite.
method="$(printf '%s\n' "$selector" | awk -F/ '{print $NF}' | tr -d '()')"
suite="$(printf '%s\n' "$selector" | awk -F/ '{print $(NF-1)}')"
matches="$(grep -iF -e "$method" -e "$suite" "$cache" | head -n 10 || true)"
if [ -n "$matches" ]; then
    echo "[INFO] closest known tests:"
    printf '%s\n' "$matches" | sed 's/^/        /'
else
    echo "[INFO] no similar test found; the flat list is in $cache"
fi
