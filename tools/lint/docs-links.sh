#!/bin/sh
# Verify links between pages in docs/ resolve. A link is relative to the page
# that holds it, [BSA](../formats/bsa.md), because GitHub and editors read a
# leading "/" as the repository root, not as docs/.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
  tree="$(self_check_tree)"
  mkdir -p "$tree/docs/engine" "$tree/docs/formats"
  printf 'x\n' >"$tree/docs/formats/bsa.md"
  printf 'See [ok](../formats/bsa.md#a), [gone](gone.md), [root](/formats/bsa.md).\n' \
    >"$tree/docs/engine/a.md"
  expect_failure "$0" "$tree" "dangling link gone.md" "root-absolute link /formats/bsa.md"
fi

root="$(git rev-parse --show-toplevel)"
docs="$root/docs"

# Every "](target)" occurrence, one per line as "line:match". Web links, mail
# links, and links to a heading on the same page are skipped; a "#section"
# anchor is stripped. grep exits 1 on files without links -> mask with true.
misses="$(
  find "$docs" -name '*.md' -print | LC_ALL=C sort \
    | while IFS= read -r f; do
      dir="$(dirname "$f")"
      grep -noE '\]\([^)[:space:]]+\)' "$f" 2>/dev/null \
        | while IFS=: read -r line match; do
          target="${match#*(}"
          target="${target%)}"
          case "$target" in
            (http:* | https:* | mailto:* | '#'*) continue ;;
            (/*)
              printf '%s:%s: root-absolute link %s; write it relative to the page\n' \
                "${f#"$root"/}" "$line" "$target"
              continue
              ;;
          esac
          target="${target%%#*}"
          [ -e "$dir/$target" ] \
            || printf '%s:%s: dangling link %s\n' "${f#"$root"/}" "$line" "$target"
        done || true
    done
)"

checked="$(find "$docs" -name '*.md' | wc -l | tr -d ' ')"
if [ -n "$misses" ]; then
  printf '%s\n' "$misses" >&2
  printf '[FAIL] broken docs/ links. Fix each link to name an existing page, relative to it.\n' >&2
  exit 1
fi
printf '[ OK ] docs links resolve (%s files)\n' "$checked"
