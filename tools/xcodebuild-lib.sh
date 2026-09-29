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
#   xcodebuild_xctestrun PLAN        newest .xctestrun for a test plan, or nothing
#   xcodebuild_xctestrun_stale FILE ROOT   exit 0 when FILE must be regenerated
#   xcodebuild_xctestrun_products_missing FILE   exit 0 when a named product is gone
#   xcodebuild_result_counts BUNDLE  "total passed skipped failed" from a bundle
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

# `xcodebuild build-for-testing` writes one .xctestrun per test plan under
# Build/Products, embedding the platform and SDK version in the name
# (OpenSky_<Plan>_macosx<version>-arm64.xctestrun). The version segment moves
# with the SDK, so callers resolve by glob and take the newest match. Prints
# nothing when no build-for-testing has run for the plan yet.
xcodebuild_xctestrun() {
    newest=""
    for candidate in "$OPENSKY_DERIVED_DATA/Build/Products/OpenSky_$1_"*.xctestrun; do
        [ -f "$candidate" ] || continue
        if [ -z "$newest" ] || [ "$candidate" -nt "$newest" ]; then
            newest="$candidate"
        fi
    done
    [ -z "$newest" ] || printf '%s\n' "$newest"
}

# A cached .xctestrun is reusable only while nothing that feeds the build has
# changed since it was written. Sources, xcconfig and test plans under Config/,
# the project file, Package.swift, and the vendored ffmpeg cover every input; the sweep costs
# around a tenth of a second where a "null" build-for-testing costs tens of
# seconds. Missing file, a missing test bundle or host it names, or any newer
# input -> stale (exit 0). Biased toward rebuilding: a false "stale" wastes one
# incremental build, a false "fresh" would test old code.
xcodebuild_xctestrun_stale() {
    xctestrun="$1"
    root="$2"
    [ -f "$xctestrun" ] || return 0
    xcodebuild_xctestrun_products_missing "$xctestrun" && return 0
    [ -n "$(find -H "$root/Sources" "$root/Tests" \
        "$root/Config" "$root/OpenSky.xcodeproj/project.pbxproj" "$root/Package.swift" \
        "$root/.vendor/ffmpeg" \
        -newer "$xctestrun" -print 2>/dev/null | head -n 1)" ]
}

# Exit 0 when a TestBundlePath or TestHostPath in the .xctestrun is missing.
# `make test-ui` rebuilds OpenSky.app without Contents/PlugIns, which removes
# OpenSkyTests.xctest while the .xctestrun stays newer than every source.
# Paths under __PLATFORMS__ belong to Xcode and are not checked.
xcodebuild_xctestrun_products_missing() {
    plutil -convert json -o - "$1" 2>/dev/null | python3 -c '
import json, os, sys
root = os.path.dirname(sys.argv[1])
try:
    configs = json.load(sys.stdin)["TestConfigurations"]
except (ValueError, KeyError):
    sys.exit(0)
for config in configs:
    for target in config.get("TestTargets", []):
        host = target.get("TestHostPath", "").replace("__TESTROOT__", root)
        bundle = target.get("TestBundlePath", "")
        bundle = bundle.replace("__TESTROOT__", root).replace("__TESTHOST__", host)
        for path in (host, bundle):
            if path and "__PLATFORMS__" not in path and not os.path.exists(path):
                print("[INFO] missing test product: " + path, file=sys.stderr)
                sys.exit(0)
sys.exit(1)
' "$1"
}

# The four counts a caller asserts on, straight from the result bundle. Trust
# this over xcodebuild's exit status: a run that executed zero tests (for
# example a misspelled -only-testing selector against Swift Testing) still
# exits 0.
xcodebuild_result_counts() {
    xcrun xcresulttool get test-results summary \
        --path "$1" --format json | python3 -c '
import json, sys
summary = json.load(sys.stdin)
keys = ("totalTestCount", "passedTests", "skippedTests", "failedTests")
print(" ".join(str(summary.get(key, -1)) for key in keys))
'
}
