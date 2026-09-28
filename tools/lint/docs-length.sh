#!/bin/sh
# Docs page length limit. A docs page holds only what the code cannot show, so
# a long page usually repeats the code or the history. The limit is in lines
# because every prose line wraps at 100 characters (markdownlint MD013), so
# 400 lines is about twenty minutes of reading. A page over the limit is split by
# topic or cut.
set -eu

limit=400
cd "$(git rev-parse --show-toplevel)"

status=0
for page in $(find docs -name '*.md' | LC_ALL=C sort); do
  lines="$(wc -l <"$page" | tr -d ' ')"
  if [ "$lines" -gt "$limit" ]; then
    printf '[FAIL] %s has %s lines; the limit is %s. Split or cut it.\n' \
      "$page" "$lines" "$limit" >&2
    status=1
  fi
done

[ "$status" -eq 0 ] && printf '[ OK ] docs pages within %s lines\n' "$limit"
exit "$status"
