#!/bin/sh
# Comment-length check. A comment block is a run of lines that start with `//`
# (so `///` too). A block over the limit usually restates the code, repeats a
# docs/formats page, or tells history. It lists each long block and fails.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX"
    for _ in 1 2 3 4 5 6 7; do echo '// why'; done >"$tree/src/Sources/OpenSkyX/A.swift"
    expect_failure "$0" "$tree" "7 comment lines"
fi

limit=6
cd "$(git rev-parse --show-toplevel)"

report="$(
  git ls-files -z -- 'src/Sources/*.swift' 'src/Sources/*.metal' 'src/Sources/*.h' \
    'src/Tests/*.swift' 'reference/*.cpp' 'reference/*.h' |
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
printf '[FAIL] %s comment blocks over %s lines. Cut each one to the why.\n' "$count" "$limit" >&2
exit 1
