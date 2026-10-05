#!/bin/sh
# Point a linked git worktree at the main checkout's vendored ffmpeg, so a fresh
# worktree does not rebuild it. Run first by every building make target
# (`make link-shared`) and by tools/vendor-ffmpeg.sh. Idempotent, and silent when
# there is nothing to do. The compilation cache needs no link: the Makefile names
# one shared store on every xcodebuild command line. A store left at its old
# visible path moves to the hidden one, because xcodebuild scans every visible
# file under the package root at each start (docs/tools/build-system.md).
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

# In the main checkout --git-common-dir is the checkout's own .git, so `shared` resolves
# back to `root`.
common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)

old_store="$shared/DerivedData/CompilationCache.noindex"
store="$shared/.cache/CompilationCache.noindex"
if [ -d "$old_store" ] && [ ! -L "$old_store" ] && [ ! -e "$store" ]; then
  mkdir -p "$shared/.cache"
  mv "$old_store" "$store"
  echo "  [ OK ] moved the compilation cache store to $store"
fi
# Run output moved from the visible logs/ to .logs/, which the scan skips.
if [ -d "$root/logs" ] && [ ! -L "$root/logs" ] && [ ! -e "$root/.logs" ]; then
  mv "$root/logs" "$root/.logs"
  echo "  [ OK ] moved run output to $root/.logs"
fi
# An older version of this script linked a worktree's DerivedData/ to the store.
if [ -L "$root/DerivedData/CompilationCache.noindex" ]; then
  rm "$root/DerivedData/CompilationCache.noindex"
  rmdir "$root/DerivedData" 2>/dev/null || true
fi

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
