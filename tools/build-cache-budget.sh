#!/bin/sh
# Keep the build trees under OPENSKY_CACHE_ROOT within OPENSKY_BUILD_CACHE_GB
# (default 200). Many worktrees stay alive at once, so removing only the trees of
# gone worktrees does not hold the disk. A tree rebuilds from the shared
# compilation cache in about two minutes (docs/tools/build-system.md).
#
#   tools/build-cache-budget.sh record TREE   store TREE's size, after a build
#   tools/build-cache-budget.sh evict TREE    delete the trees under CACHE_ROOT built
#                                             longest ago until the rest fit; never TREE
#
# A full size scan costs about a second per tree, so each build measures only its
# own tree and stores the result in TREE/.opensky-size; its time stamp is when the
# tree was last built. tools/xcodebuild-lib.sh runs it while it holds TREE's lock.
set -eu

size_file=.opensky-size

# The lock a build of TREE holds. The -optimized and -index trees build under the
# lock of the checkout's own tree (tools/xcodebuild-lib.sh).
tree_lock() {
    case "$1" in
        *-optimized | *-index) printf '%s.build.lock\n' "${1%-*}" ;;
        *) printf '%s.build.lock\n' "$1" ;;
    esac
}

record() {
    [ -d "$1" ] || return 0
    du -sk "$1" 2>/dev/null | awk '{ print $1 }' >"$1/$size_file.tmp"
    mv "$1/$size_file.tmp" "$1/$size_file"
}

# One line per tree: "<last built epoch> <size KB> <path>". A tree without a
# stored size is measured once, and counts as built when its folder last changed.
list_trees() {
    for tree in "$1"/*; do
        [ -d "$tree" ] || continue
        case "$(basename "$tree")" in *.lock | *.lock.*) continue ;; esac
        [ -s "$tree/$size_file" ] || record "$tree"
        printf '%s %s %s\n' "$(stat -f %m "$tree/$size_file")" \
            "$(cat "$tree/$size_file")" "$tree"
    done
}

evict() {
    keep="$1"
    # Only CACHE_ROOT holds build trees. CI keeps its tree beside the compilation
    # store instead, and that folder must never be listed.
    root="${OPENSKY_CACHE_ROOT:?}"
    budget_kb=$((${OPENSKY_BUILD_CACHE_GB:-200} * 1024 * 1024))
    # TREE is about to be built, so it counts first, whenever it was last built.
    used_kb="$(cat "$keep/$size_file" 2>/dev/null || echo 0)"
    list_trees "$root" | sort -rn | while read -r _ kb tree; do
        [ "$tree" != "$keep" ] || continue
        used_kb=$((used_kb + kb))
        [ "$used_kb" -gt "$budget_kb" ] || continue
        # Taking the tree's lock keeps a build from starting in it mid-delete; a
        # tree whose lock is held is building now, so it stays.
        lock="$(tree_lock "$tree")"
        [ "$lock" != "$(tree_lock "$keep")" ] || continue
        mkdir "$lock" 2>/dev/null || continue
        rm -rf "$tree"
        rm -rf "$lock"
        printf '[INFO] build cache over %s GB: removed %s (%s MB)\n' \
            "${OPENSKY_BUILD_CACHE_GB:-200}" "$(basename "$tree")" "$((kb / 1024))"
    done
}

case "${1:-}" in
    record) record "$2" ;;
    evict) evict "$2" ;;
    *)
        echo "[ERROR] usage: tools/build-cache-budget.sh record|evict TREE" >&2
        exit 2
        ;;
esac
