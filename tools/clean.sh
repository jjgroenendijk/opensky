#!/bin/sh
# Remove this checkout's build output. The shared compilation cache stays: it is
# keyed on the full command and inputs, so it cannot go stale. --deep removes it
# too, for timing a cold build; every worktree then starts cold.
#
# Usage: tools/clean.sh [--deep]
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"
rm -rf "$OPENSKY_DERIVED_DATA" "$OPENSKY_DERIVED_DATA-optimized" "$OPENSKY_DERIVED_DATA-index" \
    "$root/src/.build"
[ "${1:-}" != --deep ] || rm -rf "$OPENSKY_COMPILATION_CACHE" "$OPENSKY_SDK_MODULES"
# What an Xcode GUI build left in Xcode's default place.
find "$HOME/Library/Developer/Xcode/DerivedData" -mindepth 1 -maxdepth 1 -type d \
    -name 'OpenSky-*' -exec rm -rf {} + 2>/dev/null || true
echo "[ OK ] removed the build output of $root"
