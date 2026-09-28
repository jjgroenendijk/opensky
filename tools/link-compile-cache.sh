#!/bin/sh
# Share one compilation cache between the main checkout and every linked worktree.
#
# Xcode keeps its compilation cache at DerivedData/CompilationCache.noindex, one per
# derived-data tree, so every fresh worktree used to compile the whole project from
# nothing. Config/Build/Debug.xcconfig turns on prefix mapping, which rewrites the checkout
# path to /^src before a cache key is computed, so the same source compiled in two
# worktrees produces the same key. This script points a linked worktree's cache
# directory at the main checkout's, so those keys land in one store: a fresh
# worktree's unit build dropped from 169 s to 22 s (docs/testing.md).
#
# A worktree's own cache directory is replaced by the link. It holds nothing but cache
# entries, which the shared store rebuilds on demand. Run by every xcodebuild-driving
# make target (`make cache-link`); idempotent and silent when there is nothing to do.
set -eu

root=$(git rev-parse --show-toplevel)
# In the main checkout --git-common-dir is the checkout's own .git, so `shared`
# resolves back to `root` and there is nothing to link.
common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)
[ "$root" != "$shared" ] || exit 0

derived="${OPENSKY_DERIVED_DATA:-$root/DerivedData}"
link="$derived/CompilationCache.noindex"
target="$shared/DerivedData/CompilationCache.noindex"

[ "$(readlink "$link" 2>/dev/null || true)" != "$target" ] || exit 0

mkdir -p "$target" "$derived"
rm -rf "$link"
ln -s "$target" "$link"
echo "  [ OK ] linked $link -> $target"
