#!/bin/sh
# Build one product through tools/xcodebuild.sh (docs/tools/build-system.md).
#
# Usage: tools/build.sh app|cli|tests|install
# Env:   CONFIG  Debug (default) or Release, for app and cli
#        PLAN    the plan whose bundles `tests` compiles (default UnitTests)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"
xcb="$root/tools/xcodebuild.sh"
destination="platform=macOS,arch=arm64"

# A Debug build is a test build of the smallest plan, so it shares one build context
# with every test run and compiles nothing twice. Release has no test context.
test_build() {
    "$xcb" "$1" -scheme OpenSky -configuration Debug -destination "$destination" \
        -testPlan "$2" build-for-testing
}
release() { "$xcb" "$1" -scheme "$2" -configuration Release build; }

case "${1:-}:${CONFIG:-Debug}" in
    app:Debug | cli:Debug) test_build "build-$1" AgentControl ;;
    app:Release) release build-app OpenSky ;;
    cli:Release) release build-cli OpenSkyCLI ;;
    tests:*) test_build build-tests "${PLAN:-UnitTests}" ;;
    install:*)
        # The CLI goes inside the app, so a session drives the installed app with no build.
        release install OpenSky && release install-cli OpenSkyCLI
        products="$OPENSKY_DERIVED_DATA/Build/Products/Release"
        "$root/tools/install-app.sh" "$products/OpenSky.app" "$products/openskycli" /Applications/OpenSky.app
        ;;
    *)
        echo "[ERROR] usage: tools/build.sh app|cli|tests|install, with CONFIG=Debug or Release" >&2
        exit 2
        ;;
esac
