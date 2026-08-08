#!/bin/sh
# Record and check which exact tree content the full test gate last passed on
# (issue #417). `make test` and `make cli` write a stamp after a green run; the
# pre-push hook skips its rebuild of the same gate when the pushed tree is
# byte-identical to a stamped one. A skip can therefore only ever skip work
# that already passed on identical content; anything else — dirty tree, missing
# or mismatched stamp — runs the full gate.
#
# The stamp is the git tree hash of what was actually tested: `git stash
# create` snapshots the tracked working-tree content without touching refs or
# the index (it prints nothing on a clean tree, where HEAD's tree is the
# answer). Untracked files are not in either hash, and that is safe in the
# skip direction: committing a new file changes the commit's tree away from
# every stamp, so the gate runs.
#
# Stamps live under DerivedData/green-stamps/ — per-worktree, gitignored, and
# swept by `make clean`, which is exactly when confidence in old build state
# should reset.
#
# Usage: tools/green-stamp.sh write NAME
#        tools/green-stamp.sh check NAME...   (exit 0 iff HEAD's tree is clean
#                                              and every NAME stamp matches it)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"
stamp_dir="$OPENSKY_DERIVED_DATA/green-stamps"

command="${1:-}"
shift 2>/dev/null || true

tested_tree() {
    stash="$(git -C "$root" stash create 2>/dev/null || true)"
    if [ -n "$stash" ]; then
        git -C "$root" rev-parse "$stash^{tree}"
    else
        git -C "$root" rev-parse 'HEAD^{tree}'
    fi
}

case "$command" in
    write)
        [ "$#" -eq 1 ] || { echo "[ERROR] usage: green-stamp.sh write NAME" >&2; exit 2; }
        mkdir -p "$stamp_dir"
        tested_tree >"$stamp_dir/$1.tree"
        ;;
    check)
        [ "$#" -ge 1 ] || { echo "[ERROR] usage: green-stamp.sh check NAME..." >&2; exit 2; }
        [ -z "$(git -C "$root" status --porcelain)" ] || exit 1
        head_tree="$(git -C "$root" rev-parse 'HEAD^{tree}')"
        for name in "$@"; do
            [ "$(cat "$stamp_dir/$name.tree" 2>/dev/null)" = "$head_tree" ] || exit 1
        done
        ;;
    *)
        echo "[ERROR] usage: tools/green-stamp.sh write|check NAME..." >&2
        exit 2
        ;;
esac
