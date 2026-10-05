#!/bin/sh
# Point a linked git worktree at the main checkout's vendored ffmpeg, so a fresh
# worktree does not rebuild it. Run first by every building make target
# (`make link-shared`) and by tools/vendor-ffmpeg.sh. Idempotent, and silent when
# there is nothing to do. The compilation cache needs no link: the Makefile names
# one shared store on every xcodebuild command line.
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
