#!/bin/sh
# Drop build products that still carry the lowercase target names from before the
# rename to PascalCase (opensky -> OpenSky, openskyTests -> OpenSkyTests).
#
# The checkout sits on a case-insensitive volume. A build after the rename writes
# OpenSky.swiftmodule into the existing opensky.swiftmodule directory, which keeps
# its old spelling, and the Swift module scanner then fails with "Unable to resolve
# module dependency: 'OpenSky'". The index store under Index.noindex keeps records
# under the old module names too, which `make dead-code` would read as extra
# declarations. Deleting Build/ and Index.noindex/ once fixes both; the compilation
# cache is outside them, so the next build is still served from the cache.
#
# Usage: tools/drop-stale-products.sh DERIVED_DATA_DIR...
# Run by every xcodebuild-driving make target (`make stale-products`); silent when
# there is nothing to do.
set -eu

for derived in "$@"; do
    stale=""
    # A glob returns names with their stored case, so a case-sensitive `case`
    # tells the old spelling apart from the new one. A -e test on this volume
    # cannot: it finds opensky.app when asked for OpenSky.app.
    for path in "$derived"/Build/Products/*/*; do
        case "${path##*/}" in
            opensky.swiftmodule | opensky.app | openskyTests.* | openskyRealDataTests.* | openskyUITests*)
                stale=1 ;;
        esac
    done
    [ -n "$stale" ] || continue
    rm -rf "${derived:?}/Build" "${derived:?}/Index.noindex"
    echo "[INFO] removed Build/ and Index.noindex/ in $derived: named before the PascalCase rename"
done
