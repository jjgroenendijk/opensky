#!/bin/sh
# Packs a built OpenSky.app into a disk image for a GitHub release. The image
# holds the app and an Applications shortcut, so the user drags one onto the
# other. Only our own build goes in: the game install is never read here.
#
# Usage: tools/package-dmg.sh APP NAME
#   APP   the Release OpenSky.app (make dmg passes it)
#   NAME  the image name without .dmg, such as OpenSky-0.1.0-preview.1
#
# Writes .logs/dmg/<UTC timestamp>/NAME.dmg and prints its path last.
set -eu

if [ "$#" -ne 2 ]; then
    echo "[ERROR] usage: tools/package-dmg.sh APP NAME" >&2
    exit 2
fi
app="$1"
name="$2"
[ -d "$app" ] || { echo "[ERROR] no app at $app" >&2; exit 2; }
codesign --verify --deep --strict "$app" || { echo "[ERROR] $app fails codesign --verify" >&2; exit 1; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" dmg)
stage="$run_dir/stage"
mkdir -p "$stage"
ditto "$app" "$stage/OpenSky.app"
ln -s /Applications "$stage/Applications"

image="$run_dir/$name.dmg"
hdiutil create -volname OpenSky -srcfolder "$stage" -fs HFS+ -format ULFO -ov "$image" >/dev/null
rm -rf "$stage"
hdiutil verify "$image" >/dev/null
echo "[ OK ] $image"
echo "$image"
