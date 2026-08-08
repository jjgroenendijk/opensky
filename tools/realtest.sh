#!/bin/sh
# Run the env-gated real-data tests under the physical-footprint watchdog:
# either the whole RealData test plan, or exactly one test from it.
#
# `Config/RealData.xctestplan` does two jobs. It names the suites, so the
# real-data set is one diffable list instead of one selector per test, and it
# carries OPENSKY_DATA_ROOT as a plan environment entry -- which xcodebuild
# *does* forward into the unit-test host (measured, issue #381). That replaces
# the build-for-testing / rewrite the .xctestrun / test-without-building dance
# issue #82 needed: an ordinary `xcodebuild test -testPlan RealData` is enough.
#
# Two measured limits of test plans shape the rest (Xcode 26.5, see
# docs/tools/environment.md):
#
#   * Plan environment values are copied through verbatim, with no `$(SETTING)`
#     expansion, so the plan holds a literal path. A caller whose install lives
#     somewhere else edits the plan; this script refuses to run against a
#     conflicting OPENSKY_DATA_ROOT rather than silently testing an install the
#     plan does not point at.
#   * A plan's own `selectedTests` does not match Swift Testing tests: the
#     identifiers reach the runner as `OnlyTestIdentifiers` and select nothing,
#     so running the plan straight through executes zero tests. `-only-testing`
#     on the command line does work, and replaces the plan's selection, so this
#     script reads the plan's list and passes it that way. The plan stays the
#     one place the set is written down; tools/lint/realdata-plan.sh keeps it
#     matching the suites in openskyTests, which is also what stops a misspelled
#     entry from silently selecting nothing.
#
# tools/memguard.sh runs alongside either mode, because a heavy real-data test
# once reached ~30 GB and locked the machine. See docs/engine/cell-streaming.md
# (memory budget) and docs/testing.md (real-data suites).
#
# Usage: tools/realtest.sh [-t SELECTOR] [-c CAP_MB] [-s GUARD_SECONDS] [-O]
#   -t  -only-testing selector; must resolve to exactly one test. Omit to run
#       the whole plan.
#   -c  watchdog kill threshold in MB (default 4096 for one test, 6144 for the
#       set: one host process runs every suite in turn and keeps their caches).
#   -s  watchdog lifetime in seconds (default 900 for one test, 7200 for the
#       set).
#   -O  build the suites optimized, for a perf gate that measures the engine
#       rather than the compiler (issue #392). The Debug configuration is kept
#       because `@testable import` needs ENABLE_TESTABILITY, which Release turns
#       off; only the optimization level and one compilation condition change,
#       and a run announces itself to the tests through OPENSKY_OPTIMIZED. The
#       products go in their own derived-data tree, because otherwise every
#       alternation between `make test` and this would rebuild the whole engine.
set -eu

selector=""
cap_mb=""
guard_seconds=""
optimized=""
while getopts "t:c:s:O" opt; do
    case "$opt" in
        t) selector="$OPTARG" ;;
        c) cap_mb="$OPTARG" ;;
        s) guard_seconds="$OPTARG" ;;
        O) optimized="yes" ;;
        *)
            echo "[ERROR] usage: tools/realtest.sh [-t SELECTOR] [-c MB] [-s SECONDS] [-O]" >&2
            exit 2
            ;;
    esac
done
shift $((OPTIND - 1))
if [ "$#" -ne 0 ]; then
    echo "[ERROR] unexpected argument: $1" >&2
    exit 2
fi

if [ -n "$selector" ]; then
    cap_mb="${cap_mb:-4096}"
    guard_seconds="${guard_seconds:-900}"
else
    cap_mb="${cap_mb:-6144}"
    guard_seconds="${guard_seconds:-7200}"
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"
plan="$root/Config/RealData.xctestplan"

guard_pid=""
cleanup() {
    kill "${guard_pid:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Everything this script needs to know comes out of the plan: `root` prints the
# data root, `suites` prints one fully-qualified suite selector per line. The
# script used to carry its own copy of the data root and the two could drift.
plan_query() {
    python3 - "$plan" "$1" <<'PY'
import json, sys

with open(sys.argv[1], "rb") as stream:
    plan = json.load(stream)

if sys.argv[2] == "root":
    entries = plan.get("defaultOptions", {}).get("environmentVariableEntries", [])
    values = [e.get("value") for e in entries if e.get("key") == "OPENSKY_DATA_ROOT"]
    if len(values) != 1 or not values[0]:
        print("[ERROR] plan has no single OPENSKY_DATA_ROOT entry", file=sys.stderr)
        raise SystemExit(1)
    print(values[0])
else:
    target = plan["testTargets"][0]
    selected = target.get("selectedTests", [])
    if not selected:
        print("[ERROR] plan selects no tests", file=sys.stderr)
        raise SystemExit(1)
    for name in selected:
        print(f"{target['target']['name']}/{name}")
PY
}

data_root="$(plan_query root)"

if [ -n "${OPENSKY_DATA_ROOT:-}" ] && [ "$OPENSKY_DATA_ROOT" != "$data_root" ]; then
    {
        echo "[ERROR] OPENSKY_DATA_ROOT does not match the test plan:"
        echo "          environment: $OPENSKY_DATA_ROOT"
        echo "          plan:        $data_root"
        echo "        The plan carries the root into the test host and xcodebuild"
        echo "        does not expand build settings in a plan environment value,"
        echo "        so the environment cannot override it. Point the suite at a"
        echo "        different install by editing Config/RealData.xctestplan."
    } >&2
    exit 2
fi

if [ ! -e "$data_root/Data/Skyrim.esm" ] && [ ! -e "$data_root/Skyrim.esm" ]; then
    echo "[ERROR] no Skyrim install at $data_root (edit Config/RealData.xctestplan)" >&2
    exit 1
fi

# One run, one directory (issue #347): both xcodebuild transcripts and the
# selector enumeration land here, and `logs/realtest/latest` points at it.
run_dir="$("$root/tools/run-dir.sh" realtest)"
OPENSKY_RUN_DIR="$run_dir"
export OPENSKY_RUN_DIR
printf '[INFO] run directory: %s\n' "$run_dir"
result_bundle="$("$root/tools/run-dir.sh" -b build/test-results realtest)/realtest.xcresult"

# Parallel testing off keeps xcodebuild to one test host, which is what makes
# the watchdog's per-process cap meaningful; Swift Testing still runs its own
# tests concurrently inside that host.
derived_data="$OPENSKY_DERIVED_DATA"
if [ -n "$optimized" ]; then
    derived_data="$OPENSKY_DERIVED_DATA-optimized"
    printf '[INFO] optimized build, derived data: %s\n' "$derived_data"
fi
set -- xcodebuild -project "$root/opensky.xcodeproj" -scheme opensky \
    -configuration Debug -derivedDataPath "$derived_data" \
    -destination 'platform=macOS' -testPlan RealData \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
if [ -n "$optimized" ]; then
    set -- "$@" SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s \
        SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG OPENSKY_OPTIMIZED"
fi
if [ -n "$selector" ]; then
    set -- "$@" -only-testing:"$selector"
else
    # The plan's own selection selects nothing (see the header), so the set is
    # requested the way that works. Suite names never contain whitespace, so
    # the default field splitting over the plan's list is safe here.
    for suite in $(plan_query suites); do
        set -- "$@" -only-testing:"$suite"
    done
fi

echo "[INFO] starting watchdog (cap ${cap_mb} MB, ${guard_seconds}s)"
sh "$root/tools/memguard.sh" "$cap_mb" "$guard_seconds" &
guard_pid=$!

if [ -n "$selector" ]; then
    printf '[INFO] test -testPlan RealData: %s\n' "$selector"
else
    echo "[INFO] test -testPlan RealData: the whole real-data set"
fi
status=0
# Through the shared runner (Makefile XCB_RUN): full transcript into the run
# directory, stdout filtered on a green run, whole log printed when it fails.
"$root/tools/xcodebuild-run.sh" realtest "$@" \
    -resultBundlePath "$result_bundle" test || status=$?

kill "$guard_pid" 2>/dev/null || true
guard_pid=""
if [ "$status" -ne 0 ]; then
    exit "$status"
fi

# Trust the result bundle, not xcodebuild's status: a run that executed nothing
# also exits 0. A single test must be the one that ran and passed; the set must
# have executed at least one test with nothing failing. Skips stay legal for
# the set because some of these suites also gate on a Metal 4 device.
summary=$(xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --format json | python3 -c '
import json, sys
summary = json.load(sys.stdin)
keys = ("totalTestCount", "passedTests", "skippedTests", "failedTests")
print(" ".join(str(summary.get(key, -1)) for key in keys))
')
# shellcheck disable=SC2086 # the four counts are deliberately word-split
printf '[INFO] total %s, passed %s, skipped %s, failed %s\n' $summary

if [ -n "$selector" ]; then
    if [ "$summary" != "1 1 0 0" ]; then
        echo "[ERROR] exact test did not pass once ($summary): $selector" >&2
        # A misspelled Swift Testing selector runs zero tests and exits 0, so
        # this assertion is the guard (issue #417 dropped the enumeration
        # pre-pass that used to cost a whole extra xcodebuild run per test).
        total="$(echo "$summary" | awk '{print $1}')"
        if [ "$total" = "0" ]; then
            xctestrun="$(xcodebuild_xctestrun RealData)"
            [ -z "$xctestrun" ] || \
                "$root/tools/test-fast-suggest.sh" "$xctestrun" "$selector" >&2 || true
        fi
        exit 1
    fi
    echo "[INFO] selector executed exactly one test"
    exit 0
fi

total="$(echo "$summary" | awk '{print $1}')"
failed="$(echo "$summary" | awk '{print $4}')"
if [ "$total" -lt 1 ]; then
    echo "[ERROR] the RealData plan executed no tests" >&2
    exit 1
fi
if [ "$failed" != "0" ]; then
    echo "[ERROR] $failed real-data test(s) failed; see make test-report" >&2
    exit 1
fi
echo "[ OK ] the real-data set is green"
