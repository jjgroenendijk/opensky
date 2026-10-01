#!/bin/sh
# The build-once/run-many test loop (issue #417). `xcodebuild test` pays the
# whole build-system spin-up on every invocation, which is why a warm
# `make test` costs ~80 s when the tests inside it run in seconds. This script
# splits the two halves: `build-for-testing` writes an .xctestrun plus the
# built products once, and every following run goes through
# `test-without-building`, which skips the build system entirely.
#
# The .xctestrun is regenerated only when an input changed or a test product
# it names is missing (xcodebuild_xctestrun_stale in tools/xcodebuild-lib.sh).
# -B forces the rebuild.
#
# The RealData plan works here without any environment injection because the
# plan's OPENSKY_DATA_ROOT entry is baked into the generated .xctestrun as an
# EnvironmentVariables value (measured, issue #417) — the same forwarding that
# issue #381 measured for `xcodebuild test -testPlan RealData`. This script
# reads the root back out of the .xctestrun, so it checks exactly the value
# the test host will see.
#
# `-only-testing` accepts a misspelled Swift Testing selector and exits 0
# after running zero tests, under test-without-building just as under test.
# The result-bundle count assertion below is therefore the correctness gate,
# with near-match suggestions from a cached flat enumeration on failure.
#
# Usage: tools/test-fast.sh [-p UnitTests|RealData] [-t SELECTOR] [-g TAG] [-C CONFIG]
#                           [-r COUNT] [-B] [-c CAP_MB] [-s GUARD_SECONDS]
#   -p  test plan (default UnitTests). RealData runs under tools/memguard.sh
#       with parallel testing off, like tools/realtest.sh.
#   -t  -only-testing selector, fully qualified — OpenSkyTests/Suite/test()
#       under the unit plan, OpenSkyRealDataTests/Suite/test() under RealData.
#   -g  run only the tests with this Swift Testing tag, in every target. Written
#       into a copy of the .xctestrun as OnlyTestingTags, the key a plan's
#       selectedTags becomes; xcodebuild has no flag for it.
#   -C  plan configuration to run (UnitTests: Unit by default, or Locale).
#   -r  rerun until the first failure, at most COUNT times (`make test-repeat`).
#   -B  force build-for-testing even when nothing looks stale.
#   -c  watchdog kill threshold in MB (RealData only, default 4096).
#   -s  watchdog lifetime in seconds (RealData only, default 900).
set -eu

plan="UnitTests"
selector=""
tag=""
configuration=""
repeat_count=""
force_build=""
cap_mb=""
guard_seconds=""
while getopts "p:t:g:C:r:Bc:s:" opt; do
    case "$opt" in
        p) plan="$OPTARG" ;;
        t) selector="$OPTARG" ;;
        g) tag="$OPTARG" ;;
        C) configuration="$OPTARG" ;;
        r) repeat_count="$OPTARG" ;;
        B) force_build="yes" ;;
        c) cap_mb="$OPTARG" ;;
        s) guard_seconds="$OPTARG" ;;
        *)
            echo "[ERROR] usage: tools/test-fast.sh [-p PLAN] [-t SELECTOR] [-g TAG] [-C CONFIG] [-r COUNT] [-B] [-c MB] [-s SECONDS]" >&2
            exit 2
            ;;
    esac
done
shift $((OPTIND - 1))
if [ "$#" -ne 0 ]; then
    echo "[ERROR] unexpected argument: $1" >&2
    exit 2
fi

case "$plan" in
    UnitTests) configuration="${configuration:-Unit}" ;;
    RealData) ;;
    *)
        echo "[ERROR] -p must be UnitTests or RealData, got: $plan" >&2
        exit 2
        ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"

run_dir="$("$root/tools/run-dir.sh" test-fast)"
OPENSKY_RUN_DIR="$run_dir"
export OPENSKY_RUN_DIR
printf '[INFO] run directory: %s\n' "$run_dir"
result_bundle="$("$root/tools/run-dir.sh" -b "$OPENSKY_DERIVED_DATA/TestResults" fast)/fast.xcresult"

# Build (or reuse) the products and the .xctestrun for the plan.
xctestrun="$(xcodebuild_xctestrun "$plan")"
if [ -n "$force_build" ] || xcodebuild_xctestrun_stale "${xctestrun:-missing}" "$root"; then
    printf '[INFO] build-for-testing (%s): products or .xctestrun stale\n' "$plan"
    "$root/tools/xcodebuild-run.sh" test-fast-build \
        xcodebuild -workspace "$root/OpenSky.xcworkspace" -scheme OpenSky \
        -configuration Debug -derivedDataPath "$OPENSKY_DERIVED_DATA" \
        -destination 'platform=macOS' -testPlan "$plan" build-for-testing
    xctestrun="$(xcodebuild_xctestrun "$plan")"
    if [ -z "$xctestrun" ]; then
        echo "[ERROR] build-for-testing wrote no .xctestrun for plan $plan" >&2
        exit 1
    fi
else
    printf '[INFO] reusing %s\n' "$xctestrun"
fi

guard_pid=""
cleanup() {
    kill "${guard_pid:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# -derivedDataPath matters even without a build: test-without-building still
# writes its session logs under a derived-data root, and omitting the flag
# starts a second cache on the boot volume (AGENTS.md gotcha).
set -- xcodebuild test-without-building -xctestrun "$xctestrun" \
    -derivedDataPath "$OPENSKY_DERIVED_DATA" \
    -destination 'platform=macOS' -resultBundlePath "$result_bundle"
if [ -n "$selector" ]; then
    set -- "$@" -only-testing:"$selector"
fi
if [ -n "$configuration" ]; then
    set -- "$@" -only-test-configuration "$configuration"
fi
if [ -n "$repeat_count" ]; then
    set -- "$@" -run-tests-until-failure -test-iterations "$repeat_count"
fi
if [ -n "$tag" ]; then
    if ! grep -q "@Tag public static var $tag:" "$root/Tests/TagsTesting/Tags.swift"; then
        echo "[ERROR] unknown tag: $tag (see Tests/TagsTesting/Tags.swift)" >&2
        exit 2
    fi
    tagged="$run_dir/tagged.xctestrun"
    python3 - "$xctestrun" "$tagged" "$tag" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    run = plistlib.load(stream)
for configuration in run["TestConfigurations"]:
    for target in configuration["TestTargets"]:
        target["OnlyTestingTags"] = {"Tags": [sys.argv[3]]}
with open(sys.argv[2], "wb") as stream:
    plistlib.dump(run, stream)
PY
    # Swap the -xctestrun argument for the tagged copy, which sits in the run
    # directory. Its __TESTROOT__ paths resolve against the copy's folder, so
    # point them back at the products folder.
    sed -i '' "s|__TESTROOT__|$(dirname "$xctestrun")|g" "$tagged"
    shift 4
    set -- xcodebuild test-without-building -xctestrun "$tagged" "$@"
    printf '[INFO] tag filter: %s\n' "$tag"
fi

if [ "$plan" = "RealData" ]; then
    # The root the host will actually see is the one baked into the .xctestrun.
    data_root="$(plutil -extract \
        'TestConfigurations.0.TestTargets.0.EnvironmentVariables.OPENSKY_DATA_ROOT' \
        raw -o - "$xctestrun" 2>/dev/null || true)"
    if [ -z "$data_root" ]; then
        echo "[ERROR] $xctestrun carries no OPENSKY_DATA_ROOT (rebuild with -B?)" >&2
        exit 1
    fi
    if [ -n "${OPENSKY_DATA_ROOT:-}" ] && [ "$OPENSKY_DATA_ROOT" != "$data_root" ]; then
        {
            echo "[ERROR] OPENSKY_DATA_ROOT does not match the built .xctestrun:"
            echo "          environment: $OPENSKY_DATA_ROOT"
            echo "          .xctestrun:  $data_root"
            echo "        Edit Config/TestPlans/RealData.xctestplan and rerun with -B."
        } >&2
        exit 2
    fi
    if [ ! -e "$data_root/Data/Skyrim.esm" ] && [ ! -e "$data_root/Skyrim.esm" ]; then
        echo "[ERROR] no Skyrim install at $data_root (edit Config/TestPlans/RealData.xctestplan)" >&2
        exit 1
    fi
    cap_mb="${cap_mb:-4096}"
    guard_seconds="${guard_seconds:-900}"
    # One test host, so the watchdog's per-process cap means something; Swift
    # Testing still runs concurrently inside the host (see tools/realtest.sh).
    set -- "$@" -parallel-testing-enabled NO -maximum-parallel-testing-workers 1
    echo "[INFO] starting watchdog (cap ${cap_mb} MB, ${guard_seconds}s)"
    sh "$root/tools/memguard.sh" "$cap_mb" "$guard_seconds" &
    guard_pid=$!
fi

printf '[INFO] test-without-building (%s)%s\n' "$plan" \
    "${selector:+: $selector}"
status=0
"$root/tools/xcodebuild-run.sh" test-fast "$@" || status=$?

kill "${guard_pid:-}" 2>/dev/null || true
guard_pid=""
if [ "$status" -ne 0 ]; then
    exit "$status"
fi

counts="$(xcodebuild_result_counts "$result_bundle")"
# shellcheck disable=SC2086 # the four counts are deliberately word-split
printf '[INFO] total %s, passed %s, skipped %s, failed %s\n' $counts
total="$(echo "$counts" | awk '{print $1}')"
failed="$(echo "$counts" | awk '{print $4}')"

if [ "$total" -lt 1 ]; then
    if [ -n "$selector" ]; then
        echo "[ERROR] selector matched no test: $selector" >&2
        "$root/tools/test-fast-suggest.sh" "$xctestrun" "$selector" >&2 || true
    else
        echo "[ERROR] the $plan plan executed no tests" >&2
    fi
    exit 1
fi
if [ "$failed" != "0" ]; then
    echo "[ERROR] $failed test(s) failed; see make test-report" >&2
    exit 1
fi
if [ -n "$selector" ] && [ "$plan" = "RealData" ] && [ "$counts" != "1 1 0 0" ]; then
    echo "[ERROR] exact test did not pass once ($counts): $selector" >&2
    exit 1
fi
echo "[ OK ] $plan green ($counts)"
