#!/bin/sh
# Rerun the last built test plan through its .xctestrun, without the build system:
# seconds instead of minutes. It runs the products as built, so an edit since then
# needs `make test` again.
#
# Usage: tools/test-rerun.sh PLAN
# Env:   T  comma list of Target[/Suite[/test()]] selectors, as for tools/test.sh
set -eu

plan="${1:-Quick}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=tools/build-env.sh
. "$root/tools/build-env.sh"
xctestrun="$(find "$OPENSKY_DERIVED_DATA/Build/Products" -maxdepth 1 -name "OpenSky_${plan}_*.xctestrun" | sort | tail -n 1)"
if [ -z "$xctestrun" ]; then
    echo "[ERROR] no built $plan plan under $OPENSKY_DERIVED_DATA: run make test PLAN=$plan first" >&2
    exit 2
fi
newer="$(find src/Sources src/Tests src/config src/Package.swift -type f -newer "$xctestrun" | head -n 1)"
[ -z "$newer" ] || echo "[WARNING] $newer changed after the last build of $plan; run make test PLAN=$plan to rebuild"

set -- -xctestrun "$xctestrun" -derivedDataPath "$OPENSKY_DERIVED_DATA" \
    -destination 'platform=macOS,arch=arm64'
for selector in $(printf '%s' "${T:-}" | tr ',' ' '); do
    case "$selector" in OpenSky*Tests | OpenSky*Tests/*) ;; *) selector="OpenSkyTests/$selector" ;; esac
    set -- "$@" "-only-testing:$selector"
done
exec tools/xcodebuild.sh "rerun-$plan" "$@" test-without-building
