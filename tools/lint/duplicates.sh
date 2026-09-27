#!/bin/sh
# Copy-paste gate: fail when a Swift clone appears that is not in the baseline.
#
# jscpd fingerprints every clone of at least minTokens tokens and minLines lines
# (tools/lint/.jscpd.json) by content, so moving code or shifting lines leaves a
# baselined clone recognised. The baseline records the clones that predate the
# gate; the open cleanup lives in a GitHub issue, not here.
#
# Usage: tools/lint/duplicates.sh PATH...      check (make dup-check)
#        tools/lint/duplicates.sh -u PATH...   rewrite the baseline after removing
#                                              clones (make dup-baseline)
set -eu

cd "$(git rev-parse --show-toplevel)"

config="tools/lint/.jscpd.json"
baseline="tools/lint/jscpd-baseline.json"

if ! command -v jscpd >/dev/null 2>&1; then
  printf '[FAIL] jscpd not found. Run: make bootstrap\n' >&2
  exit 1
fi

if [ "${1:-}" = "-u" ]; then
  shift
  jscpd -c "$config" --baseline "$baseline" --update-baseline -r silent --no-colors "$@"
  exit 0
fi

[ "$#" -ge 1 ] || { echo "[ERROR] usage: duplicates.sh [-u] PATH..." >&2; exit 2; }

report_dir="$(mktemp -d)"
trap 'rm -rf "$report_dir"' EXIT

if jscpd -c "$config" --baseline "$baseline" -r json -o "$report_dir" --absolute \
  --no-colors "$@" >"$report_dir/transcript.txt" 2>&1; then
  echo "[ OK ] no new duplicated Swift blocks"
  exit 0
fi

# The console reporter lists every clone, baselined or not. Print only the new
# ones, which are what the author has to act on.
if [ -f "$report_dir/jscpd-report.json" ]; then
  root="$(pwd)/"
  jq -r --arg root "$root" '.duplicates[] | select(.isNew) |
    "[ERROR] \(.lines) duplicated lines: " +
    "\(.firstFile.name | ltrimstr($root)):\(.firstFile.start)-\(.firstFile.end) and " +
    "\(.secondFile.name | ltrimstr($root)):\(.secondFile.start)-\(.secondFile.end)"' \
    "$report_dir/jscpd-report.json" >&2
else
  cat "$report_dir/transcript.txt" >&2
fi
printf '[FAIL] New duplicated code. Extract the shared part instead of copying it.\n' >&2
exit 1
