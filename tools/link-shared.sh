#!/bin/sh
# Point a linked git worktree at the main checkout's vendored ffmpeg and compilation
# cache, so a fresh worktree neither rebuilds ffmpeg nor recompiles the project from
# nothing. Both are byte-identical across worktrees. Run first by every building make
# target (`make link-shared`) and by tools/vendor-ffmpeg.sh. Idempotent, and silent when
# there is nothing to do.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

# In the main checkout --git-common-dir is the checkout's own .git, so `shared` resolves
# back to `root`.
common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)

# Vendored ffmpeg: `.vendor` -> `<main checkout>/.vendor`. An existing `.vendor` is never
# touched, so a worktree that deliberately holds its own copy keeps it.
if [ "$root" != "$shared" ] && [ ! -e "$root/.vendor" ] && [ ! -L "$root/.vendor" ]; then
  # Create the target first so the symlink is never dangling, which would break the
  # `mkdir -p` below.
  mkdir -p "$shared/.vendor"
  ln -s "$shared/.vendor" "$root/.vendor"
  echo "  [ OK ] linked $root/.vendor -> $shared/.vendor"
fi

# The Xcode project lists embed-inputs.xcfilelist as an input of the ffmpeg phases, and
# Xcode resolves inputs before any phase runs. An empty list lets planning finish, so the
# "Check vendored ffmpeg" phase can say `make bootstrap` is needed. Rewriting the list is
# also the change that makes Xcode re-run those phases after the prefix vanished.
prefix="$root/.vendor/ffmpeg"
if [ ! -d "$prefix/lib" ]; then
  mkdir -p "$prefix"
  : >"$prefix/embed-inputs.xcfilelist"
  : >"$prefix/embed-outputs.xcfilelist"
fi

# Compilation cache. Config/Build/Debug.xcconfig maps the checkout path to /^src before a
# cache key is computed, so two worktrees produce the same keys and can share one store
# (docs/tools/build-system.md). A worktree's own store holds only cache entries, so
# replacing it loses nothing.
[ "$root" != "$shared" ] || exit 0
derived="${OPENSKY_DERIVED_DATA:-$root/DerivedData}"
link="$derived/CompilationCache.noindex"
target="$shared/DerivedData/CompilationCache.noindex"
[ "$(readlink "$link" 2>/dev/null || true)" != "$target" ] || exit 0
mkdir -p "$target" "$derived"
rm -rf "$link"
ln -s "$target" "$link"
echo "  [ OK ] linked $link -> $target"
