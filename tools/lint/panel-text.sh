#!/bin/sh
# Panel text check. The launcher and Settings pages hold controls and short
# readouts, not prose. It fails on a wrapping label built from text in their
# code, and on a tooltip literal over the limit.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSky/Shell"
    printf 'view.toolTip = "%0150d"\n' 0 >"$tree/src/Sources/OpenSky/Shell/A.swift"
    expect_failure "$0" "$tree" "tooltip over 100 characters"
fi

limit=100
cd "$(git rev-parse --show-toplevel)"

report="$(
  git ls-files -z -- 'src/Sources/OpenSky/Shell/*.swift' 'src/Sources/OpenSky/Launcher/*.swift' |
    xargs -0 awk -v limit="$limit" "
      /wrappingLabelWithString: *\"[^\"]/ {
        printf \"%s:%d: wrapping label with text; use a tooltip\\n\", FILENAME, FNR
      }
      /toolTip = \"/ {
        text = \$0
        sub(/.*toolTip = /, \"\", text)
        if (length(text) > limit + 2)
          printf \"%s:%d: tooltip over %d characters\\n\", FILENAME, FNR, limit
      }
    "
)"

if [ -z "$report" ]; then
  printf '[ OK ] panel text is short\n'
  exit 0
fi
printf '%s\n' "$report"
printf '[FAIL] panel text too long. Keep one short sentence per control.\n' >&2
exit 1
