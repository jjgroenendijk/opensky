#!/bin/sh
# Run package test targets through `swift test`, for `make test-package`.
# SELECTORS is a comma list of Target[/Suite[/test()]]. All of them run in one
# `swift test` call. A selector that matches no test fails the run before any
# test runs, because `swift test` exits 0 for a filter that matches nothing.
#
# Usage: tools/test-package.sh SELECTORS
set -eu

usage="[ERROR] usage: make test-package T='Target[/Suite[/test()]],...'"
[ "$#" -eq 1 ] && [ -n "$1" ] || { echo "$usage" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Each selector becomes the filter ^Target\.Suite/test\(\).
filters=""
for selector in $(printf '%s' "$1" | tr ',' ' '); do
    target="${selector%%/*}"
    [ -d "src/Tests/$target" ] || {
        echo "[ERROR] no package test target $target (no src/Tests/$target/)" >&2
        exit 2
    }
    rest="${selector#"$target"}"
    rest="${rest#/}"
    filter="^$target\\.$(printf '%s' "$rest" | sed 's/[()]/\\&/g')"
    filters="$filters$selector $filter
"
done

run="$("$root/tools/run-dir.sh" test-package)"
log="$run/test-package.log"
list="$run/test-list.txt"
status=0
"$root/tools/drop-signing-temp.sh" "$root/src/.build/out/Products"
echo "[INFO] swift test list"
swift test --package-path src list >"$list" 2>"$log" || status=$?
if [ "$status" -ne 0 ]; then
    "$root/tools/failed-build-records.sh" -d "$log" src/.build/out
    grep -E '(error|warning): ' "$log" || tail -n 40 "$log"
    echo "[INFO] full transcript: $log"
    exit "$status"
fi

set --
unmatched=0
while read -r selector filter; do
    [ -n "$selector" ] || continue
    if ! grep -qE "$filter" "$list"; then
        echo "[ERROR] selector matched no test: $selector" >&2
        unmatched=1
    fi
    set -- "$@" --filter "$filter"
done <<EOF
$filters
EOF
[ "$unmatched" -eq 0 ] || exit 1

echo "[INFO] swift test --package-path src --skip-build $*"
swift test --package-path src --skip-build "$@" >>"$log" 2>&1 || status=$?
grep -E '(error|warning): |^✘|Test run with' "$log" || true
echo "[INFO] full transcript: $log"
exit "$status"
