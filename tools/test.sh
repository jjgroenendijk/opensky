#!/bin/sh
# Run one test plan (docs/tools/test-runs.md). Each plan is one xcodebuild call,
# so Xcode decides what runs; this script adds only what a plan needs around it.
#
# Usage: tools/test.sh PLAN
# Env:   T         comma list of Target[/Suite[/test()]] selectors
#        N         rerun until the first failure, at most N times
#        COVERAGE  1 gathers coverage, then checks the floors and the changed lines
#        SAN       thread or address, for the Sanitizers plan
#        CAP       memory cap in MB for a guarded plan
#        DIFF_BASE the commit the changed-lines check diffs against
set -eu

plan="${1:?usage: tools/test.sh PLAN}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"

# One -only-testing per entry of T. An entry that names no OpenSky*Tests target
# resolves under the plan's own bundle.
selectors() {
    printf '%s\n' "${T:-}" | tr ',' '\n' | while read -r selector; do
        [ -n "$selector" ] || continue
        case "$selector" in OpenSky*Tests | OpenSky*Tests/*) ;; *) selector="$1/$selector" ;; esac
        printf -- '-only-testing:%s\n' "$selector"
    done
}

# A real-data host once reached 30 GB and locked the machine.
guard() {
    sh tools/memguard.sh "$1" "${CAP:-$2}" 10800 &
    guard_pid=$!
    trap 'kill "$guard_pid" 2>/dev/null' EXIT INT TERM
}

coverage="NO"
[ -z "${COVERAGE:-}" ] || coverage="YES"
set -- -scheme OpenSky -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -enableCodeCoverage "$coverage"
case "$plan" in
    Quick | UnitTests | GPU | AgentControl)
        bundle=OpenSkyTests
        set -- "$@" -testPlan "$plan"
        [ -z "${N:-}" ] || set -- "$@" -run-tests-until-failure -test-iterations "$N"
        set -- "$@" build-for-testing test-without-building
        ;;
    UITests) bundle=OpenSkyUITests; set -- "$@" -testPlan UITests test ;;
    RealData | RealDataAll | Perf)
        bundle=OpenSkyRealDataTests
        export TEST_RUNNER_OPENSKY_CHECKOUT="$root"
        export TEST_RUNNER_OPENSKY_SKYRIM_SAVES="${OPENSKY_SKYRIM_SAVES:-}"
        tree="$OPENSKY_DERIVED_DATA"
        if [ "$plan" = Perf ]; then
            # The perf gates measure optimized code, in their own tree.
            tree="$OPENSKY_DERIVED_DATA-optimized"
            set -- "$@" -derivedDataPath "$tree" SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s \
                SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG OPENSKY_OPTIMIZED"
        fi
        guard "$tree" 6144
        set -- "$@" -testPlan "$plan" -parallel-testing-enabled NO test
        ;;
    Sanitizers)
        case "${SAN:-}" in
            thread) configuration=Thread ;;
            address) configuration=Address ;;
            *) echo "[ERROR] the Sanitizers plan needs SAN=thread or SAN=address" >&2; exit 2 ;;
        esac
        bundle=OpenSkyTests
        guard "$OPENSKY_DERIVED_DATA" 12288
        set -- "$@" -testPlan Sanitizers -only-test-configuration "$configuration" \
            -parallel-testing-enabled NO test
        ;;
    *)
        echo "[ERROR] PLAN must be one of: Quick UnitTests GPU AgentControl UITests RealData RealDataAll Perf Sanitizers" >&2
        exit 2
        ;;
esac
for selector in $(selectors "$bundle"); do set -- "$@" "$selector"; done

status=0
TEST_RUNNER_OPENSKY_DATA_ROOT="${OPENSKY_DATA_ROOT:-}" tools/xcodebuild.sh "test-$plan" "$@" || status=$?
[ "$status" -eq 0 ] && [ -n "${COVERAGE:-}" ] || exit "$status"
# Each run overwrites Xcode's one profile; a copy per plan lets the checks merge plans.
profiles="$OPENSKY_DERIVED_DATA/Build/ProfileData"
newest="$(find "$profiles" -name Coverage.profdata -exec stat -f '%m %N' {} + | sort -rn | head -n 1 | cut -d' ' -f2-)"
[ -z "$newest" ] || cp "$newest" "$profiles/$plan.profdata"
# Only the whole plan runs every module's tests, so only it can check the floors.
[ "$plan" != UnitTests ] || tools/coverage/floor.sh "$OPENSKY_DERIVED_DATA"
base="${DIFF_BASE:-$(git merge-base HEAD origin/main 2>/dev/null || true)}"
[ -n "$base" ] || { echo "[INFO] no origin/main to diff against: changed lines not checked"; exit 0; }
tools/coverage/changed-lines.sh "$base" "$OPENSKY_DERIVED_DATA"
