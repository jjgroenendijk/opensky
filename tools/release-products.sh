# shellcheck shell=sh
# Sourced by the scripts that run the Release app on the real install. Builds the
# Release app and openskycli, unless the first argument is --no-build, and sets
# `products` to their folder.
# shellcheck source=tools/build-env.sh
. "$(git rev-parse --show-toplevel)/tools/build-env.sh"
if [ "${1:-}" = --no-build ]; then
    shift
else
    make -C "$opensky_root" --no-print-directory build-app build-cli CONFIG=Release
fi
products="$OPENSKY_DERIVED_DATA/Build/Products/Release"
