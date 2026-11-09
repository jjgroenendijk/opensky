#!/bin/sh
# Point a linked git worktree at the main checkout's vendored ffmpeg, so a fresh
# worktree does not rebuild it. Run by the Makefile's vendored-library file targets,
# which every building target depends on. Idempotent, and silent when there is
# nothing to do. The compilation cache needs no link: tools/xcodebuild.sh names
# one shared store on every xcodebuild command line.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

# In the main checkout --git-common-dir is the checkout's own .git, so `shared` resolves
# back to `root`.
common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)

# Xcode reads every file under the package folder at each start, so a worktree inside
# it slows every build (docs/tools/build-system.md, the start-up scan).
nested=$(git worktree list --porcelain | sed -n 's/^worktree //p' | grep -F "/src/" || true)
if [ -n "$nested" ]; then
  printf '[ERROR] a worktree sits inside a package folder (src/):\n%s\n' "$nested" >&2
  echo "Fix: git worktree move <path> $shared/.claude/worktrees/<name>" >&2
  exit 1
fi

# Vendored ffmpeg: `src/.vendor` -> `<main checkout>/src/.vendor`. An existing one is
# never touched, so a worktree that deliberately holds its own copy keeps it.
vendor="src/.vendor"
if [ "$root" != "$shared" ] && [ ! -e "$root/$vendor" ] && [ ! -L "$root/$vendor" ]; then
  # Create the target first so the symlink is never dangling, which would break the
  # `mkdir -p` below.
  mkdir -p "$shared/$vendor"
  ln -s "$shared/$vendor" "$root/$vendor"
  echo "  [ OK ] linked $root/$vendor -> $shared/$vendor"
fi

# The Xcode project lists embed-inputs.xcfilelist as an input of the ffmpeg phases, and
# Xcode resolves inputs before any phase runs. An empty list lets planning finish, so the
# "Check vendored ffmpeg" phase can say `make bootstrap` is needed. Rewriting the list is
# also the change that makes Xcode re-run those phases after the prefix vanished.
prefix="$root/$vendor/ffmpeg"
if [ ! -d "$prefix/lib" ]; then
  mkdir -p "$prefix"
  : >"$prefix/embed-inputs.xcfilelist"
  : >"$prefix/embed-outputs.xcfilelist"
fi
