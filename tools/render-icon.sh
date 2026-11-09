#!/bin/sh
# Render the AppIcon PNGs from the SVG logo (needs librsvg: brew install librsvg).
#
# Usage: tools/render-icon.sh SVG ICON_DIR
set -eu

command -v rsvg-convert >/dev/null || { echo "[ERROR] rsvg-convert not found: brew install librsvg" >&2; exit 1; }
for size in 16 32 64 128 256 512 1024; do
    rsvg-convert -w "$size" -h "$size" "$1" -o "$2/icon_$size.png"
done
echo "[ OK ] $2"
