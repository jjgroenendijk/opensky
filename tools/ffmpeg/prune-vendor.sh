#!/bin/sh
# Replace per-worktree copies of the vendored ffmpeg with symlinks to the shared one.
#
# Worktrees created before tools/ffmpeg/link-vendor.sh existed, or built with an explicit
# OPENSKY_FFMPEG_FORCE=1, hold their own full `.vendor` directory. Every one of those is a
# byte-identical rebuild of the prefix the main checkout owns, so this walks the worktree
# list, deletes each real `.vendor` directory in a linked worktree and puts a symlink to
# the shared `.vendor` in its place.
#
# Nothing is removed unless the shared prefix is complete, so a prune can never leave a
# worktree without a usable ffmpeg. A worktree that happens to be building at that moment
# can still fail that one build, because its libraries move mid-flight; run this when the
# machine is idle.
#
# Invoked by `make vendor-prune`.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)
shared_lib="$shared/.vendor/ffmpeg/lib"

for name in libavutil libavcodec libswresample; do
  if [ ! -f "$shared_lib/$name.dylib" ]; then
    echo "[ERROR] shared vendored ffmpeg is incomplete: $shared_lib/$name.dylib missing." >&2
    echo "        Run 'make ffmpeg' in $shared first; nothing was pruned." >&2
    exit 1
  fi
done

list=$(mktemp)
trap 'rm -f "$list"' EXIT
git worktree list --porcelain | sed -n 's/^worktree //p' >"$list"

reclaimed_kb=0
pruned=0

while IFS= read -r worktree; do
  [ -n "$worktree" ] || continue
  # The main checkout owns the shared prefix and must keep its real directory.
  [ "$worktree" != "$shared" ] || continue
  [ -d "$worktree/.vendor" ] || continue
  [ ! -L "$worktree/.vendor" ] || continue

  size_kb=$(du -sk "$worktree/.vendor" | awk '{print $1}')
  rm -rf "$worktree/.vendor"
  ln -s "$shared/.vendor" "$worktree/.vendor"
  reclaimed_kb=$((reclaimed_kb + size_kb))
  pruned=$((pruned + 1))
  echo "  [ OK ] $worktree/.vendor -> $shared/.vendor ($((size_kb / 1024)) MB reclaimed)"
done <"$list"

if [ "$pruned" -eq 0 ]; then
  echo "  [INFO] no per-worktree .vendor directories to prune"
else
  echo "  [ OK ] pruned $pruned worktree(s), $((reclaimed_kb / 1024)) MB reclaimed total"
fi
