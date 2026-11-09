#!/bin/sh
# A docs page holds only what the code cannot show, so a long one usually repeats
# the code or the history. Prose wraps at 100 columns, so 400 lines is about twenty
# minutes of reading. Split or cut a page over it; do not raise it.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/docs"
    seq 401 >"$tree/docs/long.md"
    expect_failure "$0" "$tree" "docs/long.md has 401 lines"
fi
cd "$(git rev-parse --show-toplevel)"
git ls-files -z -- 'docs/*.md' | xargs -0 wc -l | awk '$2 != "total" && $1 > 400 {
    printf "[FAIL] %s has %s lines; the limit is 400. Split or cut it.\n", $2, $1; bad = 1 }
    END { if (!bad) print "[ OK ] docs pages within 400 lines"; exit bad }'
