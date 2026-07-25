#!/bin/sh
# Xcode build-phase helper for the vendored ffmpeg build. Two modes:
#
#   check  Fail the build with an actionable message when .vendor/ffmpeg is missing or
#          stale, instead of letting the link step emit "library not found for -lavcodec".
#   embed  Copy the three dylibs into the app bundle's Frameworks folder and sign them,
#          so /Applications/opensky.app is self-contained and immune to Homebrew churn.
#
# Both modes need SRCROOT; embed additionally needs BUILT_PRODUCTS_DIR and
# FRAMEWORKS_FOLDER_PATH. See docs/decisions/ffmpeg-audio.md.
set -eu

mode=${1:-}
: "${SRCROOT:?must run from an Xcode build phase}"
prefix="$SRCROOT/.vendor/ffmpeg"
libs="libavutil libavcodec libswresample"

if [ ! -d "$prefix/lib" ]; then
  echo "error: vendored ffmpeg missing at $prefix — run 'make bootstrap' (or" \
    "'make ffmpeg') to build it." >&2
  exit 1
fi

for name in $libs; do
  if [ ! -f "$prefix/lib/$name.dylib" ]; then
    echo "error: $name.dylib missing from $prefix/lib — run 'make ffmpeg' to rebuild" \
      "the vendored decode-only ffmpeg." >&2
    exit 1
  fi
done

[ "$mode" = "embed" ] || exit 0

: "${BUILT_PRODUCTS_DIR:?}"
: "${FRAMEWORKS_FOLDER_PATH:?}"
dest="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$dest"

# The file list holds the resolved, version-numbered dylibs, which is also the only form
# the build sandbox grants read access to. Each is embedded under its own install name
# (@rpath/libavcodec.62.dylib), which is what the executable's load command asks for.
list="$prefix/embed-inputs.xcfilelist"
[ -f "$list" ] || {
  echo "error: $list missing — run 'make ffmpeg' to rebuild the vendored ffmpeg." >&2
  exit 1
}

while IFS= read -r lib; do
  [ -n "$lib" ] || continue
  soname=$(basename "$(otool -D "$lib" | tail -1)")
  cp -f "$lib" "$dest/$soname"
  chmod u+w "$dest/$soname"
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$dest/$soname"
done <"$list"
