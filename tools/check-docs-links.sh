#!/bin/sh
# Verify intra-wiki links in docs/ resolve (issue #102). OKF docs link
# bundle-absolute from the docs/ root: [BSA](/formats/bsa.md). Files move or
# get removed -> links dangle silently; this makes the break visible at
# commit time (AGENTS.md "if a machine can check a rule...").
#
# Policy: docs/log.md is skipped — append-only history whose entries may
# reference docs that existed when written (e.g. decisions/ui-approach.md,
# removed 2026-07-23). Everything else must resolve.
#
# Report -> stdout/stderr; full run log -> logs/docs-links.log.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
docs="$root/docs"
log_dir="$root/logs"
log="$log_dir/docs-links.log"
mkdir -p "$log_dir"

# Every "](/...)" occurrence, one per line as "file:line:target"; anchors
# (#section) stripped. grep exits 1 on files without links -> mask with true.
misses="$(
  find "$docs" -name '*.md' ! -name 'log.md' -print | LC_ALL=C sort \
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

checked="$(find "$docs" -name '*.md' ! -name 'log.md' | wc -l | tr -d ' ')"
{
  printf '[INFO] checked %s docs files (log.md skipped)\n' "$checked"
  [ -z "$misses" ] || printf '%s\n' "$misses"
} >"$log"

if [ -n "$misses" ]; then
  printf '%s\n' "$misses" >&2
  printf '[FAIL] dangling docs/ links (report: %s)\n' "$log" >&2
  exit 1
fi
printf '[ OK ] docs links resolve (%s files)\n' "$checked"
