#!/bin/sh
# Shell half of the Makefile's shared xcodebuild invocation (Makefile `xcb`).
# The scripts under tools/ run their own xcodebuild commands; without this they
# each re-derive the build cache path and the products directory, and they have
# drifted apart before. Sourced, never executed:
#
#   . "$root/tools/xcodebuild-lib.sh"
#
# Sets OPENSKY_DERIVED_DATA (the Makefile exports it; this is the fallback for a
# script run directly from a shell) and provides:
#
#   xcodebuild_products_dir CONFIG   built-products directory for a macOS scheme
#   xcodebuild_summary               stdin -> the lines a green run needs
# shellcheck shell=sh

: "${OPENSKY_DERIVED_DATA:=$(cd "$(dirname "$0")/.." && pwd)/DerivedData}"
export OPENSKY_DERIVED_DATA

# xcodebuild puts a macOS scheme's products at a fixed path under the derived
# data root, and reading it back with -showBuildSettings costs several seconds.
xcodebuild_products_dir() {
    printf '%s\n' "$OPENSKY_DERIVED_DATA/Build/Products/$1"
}

# Filter a transcript down to what a green run has to show: diagnostics, the
# tests that did not pass, and the closing counts. Per-file compile lines and
# the one line per passing test are the bulk of the output and say nothing.
# Callers keep the unfiltered transcript in logs/ and print all of it when the
# run fails, so this can never be the only copy of a failure message.
xcodebuild_summary() {
    grep --line-buffered -E \
        -e '(error|warning): ' \
        -e '^\*\*' \
        -e '^(Executed|Testing (failed|cancelled))' \
        -e "^Test (case|suite|Case|Suite) .* (failed|errored)" \
        -e '^✘' \
        || true
}
