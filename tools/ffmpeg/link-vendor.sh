#!/bin/sh
# Make the vendored ffmpeg prefix usable from a linked git worktree, and make a missing
# prefix fail with a readable message instead of an Xcode planning error.
#
# The build is byte-identical for every worktree of this repository, so rebuilding it per
# worktree would cost minutes and hundreds of megabytes for nothing. Instead a linked
# worktree gets a symlink, `.vendor` -> `<main checkout>/.vendor`, and shares the one
# prefix the main checkout owns. An existing `.vendor` is never touched, so a worktree that
# deliberately holds its own copy keeps it.
#
# The placeholder .xcfilelist files matter for the same reason. The Xcode project declares
# `$(SRCROOT)/.vendor/ffmpeg/embed-inputs.xcfilelist` as a build input of all three ffmpeg
# phases, and Xcode resolves build inputs before it runs any phase. With the file absent the
# build dies on an unresolvable input, which says nothing useful; with an empty file
# present, planning finishes and the "Check vendored ffmpeg" phase runs and reports that the
# prefix needs `make bootstrap`. Placeholders are only ever written when the prefix has no
# `lib/` directory, so a real build is never overwritten.
#
# Truncating the list is also what makes a vanished prefix re-run the check phases at all.
# They are no longer declared alwaysOutOfDate and skip themselves once their stamp file
# exists, so the list file is declared as an input in its own right and this rewrite of it
# is the change Xcode notices.
#
# Invoked by `make vendor-link`, by every xcodebuild-driving make target, and by
# tools/vendor-ffmpeg.sh. Idempotent, and silent when there is nothing to do.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

# In the main checkout --git-common-dir is the checkout's own .git, so `shared` resolves
# back to `root` and the rest of this script covers both cases with one code path.
common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)

if [ "$root" != "$shared" ] && [ ! -e "$root/.vendor" ] && [ ! -L "$root/.vendor" ]; then
  # Create the shared directory first so the new symlink is never dangling, which would
  # break `mkdir -p` on the placeholder prefix below.
  mkdir -p "$shared/.vendor"
  ln -s "$shared/.vendor" "$root/.vendor"
  echo "  [ OK ] linked $root/.vendor -> $shared/.vendor"
fi

prefix="$root/.vendor/ffmpeg"

if [ ! -d "$prefix/lib" ]; then
  mkdir -p "$prefix"
  : >"$prefix/embed-inputs.xcfilelist"
  : >"$prefix/embed-outputs.xcfilelist"
fi
