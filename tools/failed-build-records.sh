#!/bin/sh
# Find the Swift driver records of targets that had a failed compile in a build
# transcript. After a failed job the driver skips the files that depend on a
# changed declaration, but its record still says they are current. So the next
# build reuses objects with an old field layout (docs/tools/build-system.md).
# Without its record, the driver compiles the whole target again.
#
# A target is the folder of a failed file, below Sources/ or Tests/.
#
# Usage: tools/failed-build-records.sh [-d] TRANSCRIPT BUILD_DIR
#   BUILD_DIR holds Intermediates.noindex: $OPENSKY_DERIVED_DATA/Build for
#   xcodebuild, .build/out for swift build. Prints one target per record. -d
#   also deletes the record.
set -eu

delete=""
if [ "${1:-}" = "-d" ]; then
    delete="yes"
    shift
fi
if [ "$#" -ne 2 ]; then
    echo "[ERROR] usage: tools/failed-build-records.sh [-d] TRANSCRIPT BUILD_DIR" >&2
    exit 2
fi
log="$1"
intermediates="$2/Intermediates.noindex"
[ -f "$log" ] && [ -d "$intermediates" ] || exit 0

# xcodebuild lists failed commands indented by a tab under "The following build
# commands failed:"; swift build prints "error: SwiftCompile ... failed with a
# nonzero exit code".
grep -E '^	SwiftCompile normal |^error: SwiftCompile normal .* failed with a nonzero exit code' "$log" |
    grep -oE '/(Sources|Tests)/[^/ ]+/' | sed -E 's#^/(Sources|Tests)/##; s#/$##' | sort -u |
    while read -r target; do
        records="$(find "$intermediates" -maxdepth 6 -name "$target-primary.priors")"
        [ -n "$records" ] || continue
        printf '%s\n' "$target"
        if [ -n "$delete" ]; then
            printf '%s\n' "$records" | while read -r record; do rm -f "$record"; done
        fi
    done
