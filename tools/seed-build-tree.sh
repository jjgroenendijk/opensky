#!/bin/sh
# Give a checkout without a build tree an APFS clone of the tree built most
# recently, so its first build replays far fewer tasks than from an empty tree
# (docs/tools/build-system.md#seeding-a-new-tree). A clone shares the source's
# disk blocks, so it costs no space until a build rewrites them. Run first by
# every building make target (`make link-shared`) and by the session-start hook.
# Idempotent, and it never fails: on any problem the build starts empty.
set -eu

root="$(git rev-parse --show-toplevel)"
. "$root/tools/xcodebuild-lib.sh"

tree="$OPENSKY_DERIVED_DATA"
cache_root="$OPENSKY_CACHE_ROOT"
[ ! -e "$tree" ] || exit 0
# CI keeps its tree outside CACHE_ROOT, and a tree set by hand stays as it is.
[ "$(dirname "$tree")" = "$cache_root" ] || exit 0
[ -d "$cache_root" ] || exit 0

# A tree's lock is held while it builds; holding both keeps the clone whole.
opensky_try_lock "$tree.build.lock" || exit 0
held="$tree.build.lock"
tmp="$cache_root/.seed-$(basename "$tree")"
trap 'rm -rf "$tmp" $held' EXIT
trap 'exit 1' INT TERM
# A clone stopped part-way leaves this folder; the lock says no one owns it now.
rm -rf "$tmp"

# Newest first, by the size file each build writes when it ends.
list_sources() {
    for candidate in "$cache_root"/*; do
        [ -f "$candidate/.opensky-size" ] || continue
        case "$candidate" in *-optimized | *-index) continue ;; esac
        printf '%s %s\n' "$(stat -f %m "$candidate/.opensky-size")" "$candidate"
    done | sort -rn | cut -d' ' -f2-
}
sources="$(list_sources)"

IFS='
'
for source in $sources; do
    opensky_try_lock "$source.build.lock" || continue
    held="$held
$source.build.lock"
    # The build database names the source tree's outputs by path, and every
    # build in the clone would warn that they are stale. The clone reruns each task
    # anyway, because the checkout path differs, so the database saves nothing.
    if cp -c -R "$source" "$tmp" 2>/dev/null &&
        rm -rf "$tmp/Build/Intermediates.noindex/XCBuildData" &&
        mv "$tmp" "$tree"; then
        printf '[INFO] seeded the build tree from %s\n' "$(basename "$source")"
    else
        printf '[WARNING] could not clone %s; the build starts empty\n' \
            "$(basename "$source")"
    fi
    break
done
exit 0
