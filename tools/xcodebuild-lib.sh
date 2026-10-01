#!/bin/sh
# Shell half of the Makefile's shared xcodebuild invocation (Makefile `xcb`).
# The scripts under tools/ run their own xcodebuild commands; without this they
# each re-derive the build cache path and the products directory, and they have
# drifted apart before. Sourced, never executed:
#
#   . "$root/tools/xcodebuild-lib.sh"
#
# Sets OPENSKY_DERIVED_DATA and XCODE_XCCONFIG_FILE (the Makefile exports both;
# this is the fallback for a script run directly from a shell) and provides:
#
#   xcodebuild_products_dir CONFIG   built-products directory for a macOS scheme
#   xcodebuild_summary ROOT          stdin -> each diagnostic once, errors capped
#   xcodebuild_xctestrun PLAN        newest .xctestrun for a test plan, or nothing
#   xcodebuild_xctestrun_stale FILE ROOT   exit 0 when FILE must be regenerated
#   xcodebuild_xctestrun_products_missing FILE   exit 0 when a named product is gone
#   xcodebuild_result_counts BUNDLE  "total passed skipped failed" from a bundle
# shellcheck shell=sh

: "${OPENSKY_DERIVED_DATA:=$(cd "$(dirname "$0")/.." && pwd)/DerivedData}"
export OPENSKY_DERIVED_DATA
: "${XCODE_XCCONFIG_FILE:=$(cd "$(dirname "$0")/.." && pwd)/Config/Build/Overrides.xcconfig}"
export XCODE_XCCONFIG_FILE

# xcodebuild puts a macOS scheme's products at a fixed path under the derived
# data root, and reading it back with -showBuildSettings costs several seconds.
xcodebuild_products_dir() {
    printf '%s\n' "$OPENSKY_DERIVED_DATA/Build/Products/$1"
}

# Filter a transcript down to what a run has to show: diagnostics, the tests
# that did not pass, and the closing counts. xcodebuild repeats each diagnostic
# with colour codes, absolute paths, and an "(in target ...)" suffix, so the
# filter strips those, prints each line once, and caps errors, failed tests,
# and warnings. The full transcript stays in logs/. $1 is the checkout root.
xcodebuild_summary() {
    awk -v root="$1/" -v max="${OPENSKY_MAX_ERRORS:-40}" '
        { gsub(/\033\[[0-9;]*m/, "") }
        # Every app-extension build step logs this; it is never the problem.
        /appintentsmetadataprocessor.*Metadata extraction skipped/ { next }
        /(error|warning): |^\*\*|^(Executed|Testing (failed|cancelled))|^Test ([Cc]ase|[Ss]uite) .* (failed|errored)|^✘/ {
            line = $0
            while (length(root) > 1 && (i = index(line, root)) > 0)
                line = substr(line, 1, i - 1) substr(line, i + length(root))
            gsub(/\/\^src\//, "", line)
            sub(/ \(in target .* from project .*\)$/, "", line)
            sub(/ on \047[^\047]*\047 \([0-9.]+ seconds\)$/, "", line)
            if (seen[line]++) next
            if (line ~ /error: |failed|errored|^✘/ && ++problems > max) { hidden++; next }
            if (line ~ /warning: / && ++warnings > 10) { quiet++; next }
            print line
            fflush()
        }
        END {
            if (hidden) printf "[INFO] %d more errors or failed tests not shown\n", hidden
            if (quiet) printf "[INFO] %d more warnings not shown\n", quiet
        }
    '
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
