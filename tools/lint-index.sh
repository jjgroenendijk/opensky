#!/bin/sh
# Build the index store, then fail on unused code or an adapter that uses another
# (docs/decisions/code-health-automation.md), or on a port with one conformer and no
# test fake. The index tree is built uncached,
# because a task replayed from the compilation cache writes no index data, so its
# first run in a checkout is a full build; later runs are incremental. The unit and
# real-data plans together cover the app, the CLI, and every test bundle.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"
index="$OPENSKY_DERIVED_DATA-index"
for plan in UnitTests RealData; do
    tools/xcodebuild.sh "index-$plan" -scheme OpenSky -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath "$index" \
        COMPILATION_CACHE_ENABLE_CACHING=NO -testPlan "$plan" build-for-testing
done
store="$index/Index.noindex/DataStore"
tools/lint-index/unused-code.sh tools/lint-index/.periphery.yml "$store"
python3 tools/lint-index/adapter-references.py "$store" .
python3 tools/lint-index/single-conformers.py "$store" . --gate
