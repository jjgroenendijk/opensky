#!/bin/sh
# Delete the temporary files that a stopped codesign left in a products folder.
# codesign writes the signed binary to NAME.cstemp beside the binary, then
# renames it. A build that stops on an error kills the codesign tasks still
# running, and the half-written .cstemp stays in the bundle. The next codesign
# reads it as a broken part of the bundle and fails with "invalid or unsupported
# format for signature". A finished codesign leaves no .cstemp, so each one
# found before a build starts is left over.
#
# Usage: tools/drop-signing-temp.sh PRODUCTS_DIR
set -eu

if [ "$#" -ne 1 ]; then
    echo "[ERROR] usage: tools/drop-signing-temp.sh PRODUCTS_DIR" >&2
    exit 2
fi
[ -d "$1" ] || exit 0
find "$1" -name '*.cstemp' -print -delete | sed 's/^/[INFO] deleted a stopped codesign file: /'
