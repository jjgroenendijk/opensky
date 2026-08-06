#!/bin/sh
# Run openskyTests under the runtime sanitizers (issue #383).
#
# `Config/Sanitizers.xctestplan` carries two configurations, because Thread and
# Address Sanitizer cannot be enabled in the same build:
#
#   Thread    SWIFT_THREAD_SANITIZER / ENABLE_THREAD_SANITIZER
#   Address   ENABLE_ADDRESS_SANITIZER plus ENABLE_UNDEFINED_BEHAVIOR_SANITIZER
#
# Why a separate plan rather than two more configurations on UnitTests:
# xcodebuild runs *every* configuration in a plan, so the pre-push `make test`
# would pay for the sanitized builds on every commit. This is a periodic and
# pre-milestone check, the same category as `make realtest-all`.
#
# The sanitized products are their own object files, so the first run of each
# configuration recompiles the world and takes far longer than `make test`.
#
# tools/memguard.sh runs alongside, because sanitizer shadow memory multiplies
# resident size -- ASan maps one shadow byte per eight bytes of address space
# and TSan's is larger still -- and this repo already lost a machine to a test
# host that ran away (docs/testing.md, RSS watchdog). The default cap is
# therefore well above the real-data one.
#
# Usage: tools/test-sanitize.sh [-o CONFIGURATION] [-c CAP_MB] [-s GUARD_SECONDS]
#   -o  run one plan configuration (Thread or Address). Omit to run both.
#   -c  watchdog kill threshold in MB (default 12288).
#   -s  watchdog lifetime in seconds (default 10800).
set -eu

configuration=""
cap_mb=12288
guard_seconds=10800
while getopts "o:c:s:" opt; do
    case "$opt" in
        o) configuration="$OPTARG" ;;
        c) cap_mb="$OPTARG" ;;
        s) guard_seconds="$OPTARG" ;;
        *)
            echo "[ERROR] usage: tools/test-sanitize.sh [-o CONFIGURATION]" \
                "[-c MB] [-s SECONDS]" >&2
            exit 2
            ;;
    esac
done
shift $((OPTIND - 1))
if [ "$#" -ne 0 ]; then
    echo "[ERROR] unexpected argument: $1" >&2
    exit 2
fi

case "$configuration" in
    "" | Thread | Address) ;;
    *)
        echo "[ERROR] unknown configuration: $configuration" \
            "(Config/Sanitizers.xctestplan has Thread and Address)" >&2
        exit 2
        ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"

guard_pid=""
cleanup() {
    kill "${guard_pid:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# One run, one directory (issue #347): the xcodebuild transcript lands here and
# logs/test-sanitize/latest points at it.
run_dir="$("$root/tools/run-dir.sh" test-sanitize)"
OPENSKY_RUN_DIR="$run_dir"
export OPENSKY_RUN_DIR
printf '[INFO] run directory: %s\n' "$run_dir"
result_bundle="$("$root/tools/run-dir.sh" -b build/test-results \
    sanitize)/sanitize.xcresult"

# Parallel testing off keeps xcodebuild to one test host, which is what makes
# the watchdog's per-process cap meaningful; several sanitized hosts at once is
# the runaway shape the cap exists to catch. Swift Testing still runs its own
# tests concurrently inside that host, which is also what gives TSan something
# to observe.
set -- xcodebuild -project "$root/opensky.xcodeproj" -scheme opensky \
    -configuration Debug -derivedDataPath "$OPENSKY_DERIVED_DATA" \
    -destination 'platform=macOS' -testPlan Sanitizers \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
if [ -n "$configuration" ]; then
    set -- "$@" -only-test-configuration "$configuration"
fi

echo "[INFO] starting watchdog (cap ${cap_mb} MB, ${guard_seconds}s)"
sh "$root/tools/memguard.sh" "$cap_mb" "$guard_seconds" &
guard_pid=$!

if [ -n "$configuration" ]; then
    printf '[INFO] test -testPlan Sanitizers: %s configuration only\n' \
        "$configuration"
else
    echo "[INFO] test -testPlan Sanitizers: Thread, then Address with UBSan"
fi
status=0
"$root/tools/xcodebuild-run.sh" test-sanitize "$@" \
    -resultBundlePath "$result_bundle" test || status=$?

kill "$guard_pid" 2>/dev/null || true
guard_pid=""

# Trust the result bundle, not xcodebuild's status: a run that executed nothing
# also exits 0. A sanitizer report surfaces as a failing test, so the counts are
# also how a finding is noticed.
summary=$(xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --format json | python3 -c '
import json, sys
summary = json.load(sys.stdin)
keys = ("totalTestCount", "passedTests", "skippedTests", "failedTests")
print(" ".join(str(summary.get(key, -1)) for key in keys))
')
# shellcheck disable=SC2086 # the four counts are deliberately word-split
printf '[INFO] total %s, passed %s, skipped %s, failed %s\n' $summary
printf '[INFO] result bundle: %s\n' "$result_bundle"

if [ "$status" -ne 0 ]; then
    exit "$status"
fi

total="$(echo "$summary" | awk '{print $1}')"
failed="$(echo "$summary" | awk '{print $4}')"
if [ "$total" -lt 1 ]; then
    echo "[ERROR] the Sanitizers plan executed no tests" >&2
    exit 1
fi
if [ "$failed" != "0" ]; then
    echo "[ERROR] $failed sanitized test(s) failed; see make test-report" >&2
    exit 1
fi
echo "[ OK ] openskyTests is clean under the sanitizers"
