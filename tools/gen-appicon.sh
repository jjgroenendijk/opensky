#!/bin/sh
# Regenerate AppIcon PNGs from the SVG logo source (opensky/Branding/opensky-logo.svg).
# Run via `make icon`. Requires librsvg (`brew install librsvg`).
set -eu

cd "$(dirname "$0")/.."

SRC="opensky/Branding/opensky-logo.svg"
OUT="opensky/Assets.xcassets/AppIcon.appiconset"

command -v rsvg-convert >/dev/null 2>&1 || {
    echo "[ERROR] rsvg-convert not found — install with: brew install librsvg" >&2
    exit 1
}
[ -f "$SRC" ] || { echo "[ERROR] missing $SRC" >&2; exit 1; }

for size in 16 32 64 128 256 512 1024; do
    rsvg-convert -w "$size" -h "$size" "$SRC" -o "$OUT/icon_${size}.png"
    echo "[ OK ] $OUT/icon_${size}.png"
done
