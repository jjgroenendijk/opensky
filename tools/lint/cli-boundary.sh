#!/bin/sh
# Every src/Sources/ folder but OpenSky/ is built into or linked by openskycli, so an
# app-only import there breaks the CLI build. This catches it without building.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX"
    printf 'import AppKit\n' >"$tree/src/Sources/OpenSkyX/A.swift"
    expect_failure "$0" "$tree" "app-only sources"
fi
cd "$(git rev-parse --show-toplevel)"
offenders="$(git ls-files -- 'src/Sources/*.swift' | grep -v '^src/Sources/OpenSky/' \
    | xargs grep -lE '^[[:space:]]*import (AppKit|Cocoa|SwiftUI)' || true)"
if [ -n "$offenders" ]; then
    printf '[FAIL] app-only sources compiled into openskycli:\n%s\n' "$offenders" >&2
    echo 'Fix: move the file to src/Sources/OpenSky/ with git mv, or drop the import.' >&2
    exit 1
fi
echo "[ OK ] CLI target boundary clean"
