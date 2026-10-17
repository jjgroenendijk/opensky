#!/bin/sh
# Print where the newest unit test run spent its build time, as Markdown for a
# CI run summary: compilation cache hits, time per task kind, slowest tasks.
# `xcodebuild test` ignores -showBuildTimingSummary, so this reads the build
# log inside the result bundle instead. The log is kept in .logs/build-timing/,
# which the CI job uploads, for a closer look at one run.
#
# Usage: tools/ci/build-timing.sh [PLAN]   (default UnitTests)
set -eu
plan="${1:-UnitTests}"
dd="${OPENSKY_DERIVED_DATA:-DerivedData}"
bundle="$dd/TestResults/unit-$plan/latest/unit-$plan.xcresult"
transcript=.logs/test-unit/latest/test-unit.log
if [ ! -d "$bundle" ]; then
    echo "[INFO] no result bundle at $bundle"
    exit 0
fi
log="$(tools/run-dir.sh build-timing)/build-log.json"
xcrun xcresulttool get log --type build --path "$bundle" --compact >"$log"

echo '### Build timing'
echo
build="$(jq '.duration | floor' "$log")"
action="$(xcrun xcresulttool get test-results summary --path "$bundle" | jq '.finishTime - .startTime | floor')"
echo "Build: $build s, $(jq '.subsections | length' "$log") tasks. Tests: $((action - build)) s."
if [ -f "$transcript" ]; then
    grep -A1 '^CompilationCacheMetrics' "$transcript" | sed -n 's/^note: /Compilation cache: /p'
fi
echo
echo '| Task kind | Tasks | Summed time (s) |'
echo '| --- | --- | --- |'
jq -r '.subsections | group_by(.title | split(" ")[0])
    | map({kind: (.[0].title | split(" ")[0]), count: length, time: (map(.duration) | add)})
    | sort_by(-.time)[:12][] | "| \(.kind) | \(.count) | \(.time | floor) |"' "$log"
echo
echo '| Slowest task | Time (s) |'
echo '| --- | --- |'
jq -r '.subsections | sort_by(-.duration)[:12][] | "| \(.title | gsub("\\|"; "/")) | \(.duration | floor) |"' "$log"
