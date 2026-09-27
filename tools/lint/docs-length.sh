#!/bin/sh
# Docs page length limit (issue #567). A docs page holds only what the code
# cannot show, so a long page usually repeats the code or the history. The
# limit is in lines because every prose line wraps at 100 characters
# (markdownlint MD013), so 200 lines is about ten minutes of reading.
#
# docs-length-baseline.txt lists the older pages that were already over the
# limit when the check arrived. The list may only shrink: a listed page that
# is now under the limit fails the check too, so its entry gets removed in the
# same commit that shortens it.
set -eu

limit=200
cd "$(git rev-parse --show-toplevel)"
baseline=tools/lint/docs-length-baseline.txt

status=0
for page in $(find docs -name '*.md' | LC_ALL=C sort); do
  lines="$(wc -l <"$page" | tr -d ' ')"
  listed=0
  grep -qxF "$page" "$baseline" && listed=1
  if [ "$lines" -gt "$limit" ] && [ "$listed" -eq 0 ]; then
    printf '[FAIL] %s has %s lines; the limit is %s. Split or cut it.\n' \
      "$page" "$lines" "$limit" >&2
    status=1
  elif [ "$lines" -le "$limit" ] && [ "$listed" -eq 1 ]; then
    printf '[FAIL] %s is now within the limit; remove it from %s.\n' \
      "$page" "$baseline" >&2
    status=1
  fi
done

while IFS= read -r page; do
  [ -f "$page" ] && continue
  printf '[FAIL] %s no longer exists; remove it from %s.\n' "$page" "$baseline" >&2
  status=1
done <"$baseline"

[ "$status" -eq 0 ] && printf '[ OK ] docs pages within %s lines\n' "$limit"
exit "$status"
