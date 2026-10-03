#!/bin/sh
# Panel text check. The app panels exist to check that a feature works, so they
# hold controls and short readouts, not prose. It fails on a wrapping label built
# from text in panel code, and on a tooltip literal over the limit.
set -eu

limit=100
cd "$(git rev-parse --show-toplevel)"

report="$(
  git ls-files -z -- 'Sources/OpenSky/Shell/*.swift' 'Sources/OpenSky/Panels/*.swift' 'Sources/OpenSky/Launcher/*.swift' |
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
