#!/bin/sh
# Duplicated-code gate: fail when jscpd finds any Swift clone of at least the
# token and line counts in the config. No baseline: the tree starts at zero.
#
# Usage: tools/lint/duplicates.sh CONFIG PATH...
set -eu

[ "$#" -ge 2 ] || { echo "[ERROR] usage: duplicates.sh CONFIG PATH..." >&2; exit 2; }
config="$1"
shift
cd "$(git rev-parse --show-toplevel)"

if ! command -v jscpd >/dev/null 2>&1; then
  printf '[FAIL] jscpd not found. Run: make bootstrap\n' >&2
  exit 1
fi

report_dir="$(mktemp -d)"
trap 'rm -rf "$report_dir"' EXIT

jscpd -c "$config" -r json -o "$report_dir" --no-colors --silent "$@" >/dev/null 2>&1 || true
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
