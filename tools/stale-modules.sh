#!/bin/sh
# Find package modules whose copy in Build/Products differs from the module the
# compiler last emitted under Build/Intermediates.noindex. A build that stops at
# the first error can cancel the copy, and every module above then fails with
# "cannot find in scope" or "has no member" (docs/tools/build-system.md). A
# healthy build leaves the two files identical, so any difference is stale.
#
# A copy that reads a stale copy counts as stale too, so one more build
# rebuilds every layer together.
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
stale_file="$(mktemp -t opensky-stale)"
modules_file="$(mktemp -t opensky-modules)"
trap 'rm -f "$stale_file" "$modules_file"' EXIT INT TERM

# One line "<config> <module> <emitted module>" per module with a Products
# copy. A module that was never copied there is not a product.
modules() {
    for emitted in "$build"/Intermediates.noindex/OpenSky.build/*/*-t.build/Objects-normal/arm64/*.swiftmodule; do
        [ -f "$emitted" ] || continue
        module="$(basename "$emitted" .swiftmodule)"
        config="${emitted#"$build"/Intermediates.noindex/OpenSky.build/}"
        config="${config%%/*}"
        [ -d "$(xcodebuild_products_dir "$config")/$module.swiftmodule" ] || continue
        printf '%s %s %s\n' "$config" "$module" "$emitted"
    done
}
modules >"$modules_file"

while read -r config module emitted; do
    copy="$(xcodebuild_products_dir "$config")/$module.swiftmodule"
    if ! cmp -s "$emitted" "$copy/arm64-apple-macos.swiftmodule"; then
        printf '%s %s\n' "$config" "$module" >>"$stale_file"
    fi
done <"$modules_file"

# A failed pass stops at one module layer, so a module above a stale copy only
# shows its own stale copy after the next pass. Its emit-module dependency file
# lists every module copy it read, so mark those dependents stale now as well.
while :; do
    added=""
    while read -r config module emitted; do
        grep -qx "$config $module" "$stale_file" && continue
        deps="${emitted%.swiftmodule}-primary-emit-module.d"
        [ -f "$deps" ] || continue
        while read -r stale_config stale_module; do
            [ "$stale_config" = "$config" ] || continue
            if grep -qF "/Products/$config/$stale_module.swiftmodule/" "$deps"; then
                printf '%s %s\n' "$config" "$module" >>"$stale_file"
                added="yes"
                break
            fi
        done <"$stale_file"
    done <"$modules_file"
    [ -n "$added" ] || break
done

while read -r config module; do
    printf '%s\n' "$module"
    if [ -n "$delete" ]; then
        rm -rf "$(xcodebuild_products_dir "$config")/$module.swiftmodule"
    fi
done <"$stale_file"
