#!/bin/sh
# Run one xcodebuild command with the shared command line: the workspace, this
# checkout's build tree, the shared compilation cache, and XCODEBUILD_FLAGS. The
# transcript and the result bundle go into a run directory, and stdout gets only
# what the bundle holds: errors, warnings, test totals, and failed tests.
#
# Two checks Xcode does not do stay here (docs/tools/build-system.md):
# - after a failed compile, drop the driver records of the failed targets, or the
#   next build links objects with an old field layout (tools/failed-build-records.sh);
# - fail a run whose -only-testing selector matched no test (tools/test-selectors.sh).
#
# Usage: tools/xcodebuild.sh NAME [xcodebuild args...]
# Env:   OPENSKY_RUN_DIR  write into this run directory, not a new one
set -eu

if [ "$#" -lt 2 ]; then
    echo "[ERROR] usage: tools/xcodebuild.sh NAME [xcodebuild args...]" >&2
    exit 2
fi
name="$1"
shift
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"
run_dir="${OPENSKY_RUN_DIR:-$("$root/tools/run-dir.sh" "$name")}"
mkdir -p "$run_dir"
log="$run_dir/$name.log"
bundle="$run_dir/$name.xcresult"

derived_data="$OPENSKY_DERIVED_DATA" config="" selectors="" previous=""
for arg in "$@"; do
    case "$previous" in
        -derivedDataPath) derived_data="$arg" ;;
        -configuration) config="$arg" ;;
    esac
    case "$arg" in -only-testing:*) selectors="$selectors${arg#-only-testing:} " ;; esac
    previous="$arg"
done
compiles="yes"
case " $* " in
    *" -xctestrun "*) compiles="" ;;
    *" -derivedDataPath "*) ;;
    *) set -- -derivedDataPath "$derived_data" "$@" ;;
esac
if [ -n "$compiles" ]; then
    # A build keeps going after an error: one that stops at the first error cancels the
    # Products copy of a module whose emit finished, and every module above then fails.
    # Debug compiles with coverage like a test build, so the two share intermediates.
    # Release is arm64 only: Float16 does not exist on x86_64.
    case "$config" in
        Debug) set -- "$@" CLANG_COVERAGE_MAPPING=YES ;;
        Release) set -- "$@" ARCHS=arm64 ;;
    esac
    set -- -workspace "$root/src/OpenSky.xcworkspace" "$@" \
        COMPILATION_CACHE_CAS_PATH="$OPENSKY_COMPILATION_CACHE" \
        SDK_EXPLICIT_MODULES_OUTPUT_PATH="$OPENSKY_SDK_MODULES" \
        -IDEBuildingContinueBuildingAfterErrors=YES
    "$root/tools/drop-signing-temp.sh" "$derived_data/Build/Products"
fi
echo "[INFO] transcript: $log"

status=0
# shellcheck disable=SC2086 # XCODEBUILD_FLAGS holds several words
xcodebuild "$@" ${XCODEBUILD_FLAGS:-} -resultBundlePath "$bundle" >"$log" 2>&1 || status=$?
python3 "$root/tools/xcresult_summary.py" "$bundle" || [ "$status" -ne 0 ] || status=1

if [ "$status" -ne 0 ] && [ -n "$compiles" ]; then
    "$root/tools/failed-build-records.sh" -d "$log" "$derived_data/Build"
fi
if [ "$status" -eq 0 ] && [ -n "$selectors" ] \
    && ! printf '%s' "$selectors" | xargs "$root/tools/test-selectors.sh" "$bundle"; then
    status=1
fi
[ "$status" -eq 0 ] || [ -e "$bundle/Info.plist" ] || tail -n 40 "$log"
exit "$status"
