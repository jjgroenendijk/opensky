#!/bin/sh
# Sourced by the index-store checks: builds the index store and sets `store` to its path.
# The index tree is built uncached, because a task replayed from the compilation cache writes
# no index data, so its first run in a checkout is a full build; later runs are incremental.
# The unit and real-data plans together cover the app, the CLI, and every test bundle.
# The caller sets `root` to the repository root.
: "${root:?}"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"
index="$OPENSKY_DERIVED_DATA-index"
for plan in UnitTests RealData; do
    tools/xcodebuild.sh "index-$plan" -scheme OpenSky -configuration Debug \
        -destination 'platform=macOS,arch=arm64' -derivedDataPath "$index" \
        COMPILATION_CACHE_ENABLE_CACHING=NO -testPlan "$plan" build-for-testing
done
store="$index/Index.noindex/DataStore"
export store
