#!/bin/sh
# Verify intra-wiki links in docs/ resolve (issue #102). OKF docs link
# bundle-absolute from the docs/ root: [BSA](/formats/bsa.md). Files move or
# get removed -> links dangle silently; this makes the break visible at
# commit time (AGENTS.md "if a machine can check a rule...").
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
  tree="$(self_check_tree)"
  mkdir -p "$tree/docs"
  printf 'See [gone](/gone.md).\n' >"$tree/docs/a.md"
  expect_failure "$0" "$tree" "dangling link /gone.md"
fi

root="$(git rev-parse --show-toplevel)"
docs="$root/docs"

# Every "](/...)" occurrence, one per line as "file:line:target"; anchors
# (#section) stripped. grep exits 1 on files without links -> mask with true.
misses="$(
  find "$docs" -name '*.md' -print | LC_ALL=C sort \
    | while IFS= read -r f; do
      grep -noE '\]\(/[^)]*\)' "$f" 2>/dev/null \
        | while IFS=: read -r line match; do
          target="${match#*(}"
          target="${target%)}"
          target="${target%%#*}"
          [ -n "$target" ] || continue
          [ -f "$docs$target" ] \
            || printf '%s:%s: dangling link %s\n' "${f#"$root"/}" "$line" "$target"
        done || true
    done
)"

checked="$(find "$docs" -name '*.md' | wc -l | tr -d ' ')"
if [ -n "$misses" ]; then
  printf '%s\n' "$misses" >&2
  printf '[FAIL] dangling docs/ links. Fix each link to name an existing page.\n' >&2
  exit 1
fi
printf '[ OK ] docs links resolve (%s files)\n' "$checked"
