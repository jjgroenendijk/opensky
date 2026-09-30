#!/bin/sh
# Find package modules whose copy in Build/Products differs from the module the
# compiler last emitted under Build/Intermediates.noindex. xcodebuild can skip
# the copy after an interface change, and every module above then fails with
# "cannot find in scope" or "has no member" (docs/tools/environment.md). A
# healthy build leaves the two files identical, so any difference is stale.
#
# Usage: tools/stale-modules.sh [-d]
#   Prints one module name per stale copy. -d also deletes the copy, so the
#   next build writes it again.
set -eu

delete=""
if [ "${1:-}" = "-d" ]; then
    delete="yes"
elif [ "$#" -ne 0 ]; then
    echo "[ERROR] usage: tools/stale-modules.sh [-d]" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"
build="$OPENSKY_DERIVED_DATA/Build"

for emitted in "$build"/Intermediates.noindex/OpenSky.build/*/*-t.build/Objects-normal/arm64/*.swiftmodule; do
    [ -f "$emitted" ] || continue
    module="$(basename "$emitted" .swiftmodule)"
    config="${emitted#"$build"/Intermediates.noindex/OpenSky.build/}"
    config="${config%%/*}"
    copy="$(xcodebuild_products_dir "$config")/$module.swiftmodule"
    # A module that was never copied to Products is not a product; skip it.
    [ -d "$copy" ] || continue
    if ! cmp -s "$emitted" "$copy/arm64-apple-macos.swiftmodule"; then
        printf '%s\n' "$module"
        if [ -n "$delete" ]; then
            rm -rf "$copy"
        fi
    fi
done
