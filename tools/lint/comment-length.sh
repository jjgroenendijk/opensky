#!/bin/sh
# Comment-length check. A comment block is a run of lines that start with `//`
# (so `///` too). A block over the limit usually restates the code, repeats a
# docs/formats page, or tells history. Report mode: it lists each long block and
# the count, and exits 0. Issue 30.39 turns it into a gate.
set -eu

limit=6
cd "$(git rev-parse --show-toplevel)"

report="$(
  git ls-files -z -- 'Sources/*.swift' 'Sources/*.metal' 'Sources/*.h' \
    'Tests/*.swift' |
    xargs -0 awk -v limit="$limit" '
      function flush() {
        if (n > limit) printf "%s:%d: %d comment lines\n", file, start, n
        n = 0
      }
      FNR == 1 { flush(); file = FILENAME }
      /^[ \t]*\/\// { if (n == 0) start = FNR; n++; next }
      { flush() }
      END { flush() }
    '
)"

if [ -z "$report" ]; then
  printf '[ OK ] no comment block over %s lines\n' "$limit"
  exit 0
fi
printf '%s\n' "$report"
count="$(printf '%s\n' "$report" | wc -l | tr -d ' ')"
printf '[WARNING] %s comment blocks over %s lines (report only)\n' "$count" "$limit"
