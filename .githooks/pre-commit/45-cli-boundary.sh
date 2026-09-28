#!/bin/sh
# App-only (AppKit) sources must stay under Sources/OpenSky (issues #109, #336).
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

# Only relevant when Swift sources under Sources/ or the project file change.
files="$(staged_matching '^(Sources/.*\.swift|OpenSky\.xcodeproj/project\.pbxproj)$')"
[ -n "$files" ] || exit 0

if ! "$ROOT/tools/lint/cli-boundary.sh"; then
  hook_fail "CLI target boundary broken. Move the file under Sources/OpenSky, re-commit."
  exit 1
fi
hook_ok "CLI target boundary clean"
