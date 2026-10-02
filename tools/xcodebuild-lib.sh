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
