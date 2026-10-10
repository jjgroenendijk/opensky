#!/bin/sh
# Find test bundles inside a built OpenSky.app whose signature does not verify.
# A build that stops before a test bundle is linked leaves it unsigned in the
# app's PlugIns folder. A later plan that does not build that bundle then fails
# the app's own CodeSign step with "code object is not signed at all".
#
# Usage: tools/unsigned-plugins.sh [-d]
#   Prints one bundle path per unsigned bundle. -d also deletes it, so the next
#   build that needs it builds it again.
set -eu

delete=""
if [ "${1:-}" = "-d" ]; then
    delete="yes"
elif [ "$#" -ne 0 ]; then
    echo "[ERROR] usage: tools/unsigned-plugins.sh [-d]" >&2
    exit 2
fi

for bundle in "$OPENSKY_DERIVED_DATA"/Build/Products/*/OpenSky.app/Contents/PlugIns/*.xctest; do
    [ -d "$bundle" ] || continue
    codesign --verify "$bundle" 2>/dev/null && continue
    printf '%s\n' "$bundle"
    if [ -n "$delete" ]; then
        rm -rf "$bundle"
    fi
done
