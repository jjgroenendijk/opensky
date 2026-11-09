#!/bin/sh
# Duplicated-code gate: fail when jscpd finds any Swift clone of at least the
# token and line counts in the config. No baseline: the tree starts at zero.
# The whole tree in under a second; a scan of changed files would miss a new copy
# of code that did not change.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX"
    for file in A B; do
        for line in $(seq 30); do echo "let value$line = compute($line, $line + 1, \"$line\")"; done \
            >"$tree/src/Sources/OpenSkyX/$file.swift"
    done
    expect_failure "$0" "$tree" "duplicated code"
fi

config="$OPENSKY_TOOLS/lint/.jscpd.json"
cd "$(git rev-parse --show-toplevel)"

if ! command -v jscpd >/dev/null 2>&1; then
  printf '[FAIL] jscpd not found. Run: make bootstrap\n' >&2
  exit 1
fi

report_dir="$(mktemp -d)"
trap 'rm -rf "$report_dir"' EXIT

jscpd -c "$config" -r json -o "$report_dir" --no-colors --silent src >/dev/null 2>&1 || true
report="$report_dir/jscpd-report.json"
if [ ! -f "$report" ]; then
  printf '[FAIL] jscpd wrote no report\n' >&2
  exit 1
fi

clones="$(jq -r '.duplicates[] |
  "\(.firstFile.name):\(.firstFile.start)-\(.firstFile.end) and " +
  "\(.secondFile.name):\(.secondFile.start)-\(.secondFile.end) (\(.lines) lines)"' "$report")"
if [ -z "$clones" ]; then
  echo "[ OK ] no duplicated Swift blocks"
  exit 0
fi
printf '%s\n' "$clones" | sed 's/^/[ERROR] duplicated code: /' >&2
printf '[FAIL] Extract the shared part instead of copying it.\n' >&2
exit 1
