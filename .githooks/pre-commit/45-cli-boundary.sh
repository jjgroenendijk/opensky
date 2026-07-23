#!/bin/sh
# App-only (AppKit) sources must be excluded from openskycli (issue #109).
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

# Only relevant when Swift sources under opensky/ or the project file change.
files="$(staged_matching '^(opensky/.*\.swift|opensky\.xcodeproj/project\.pbxproj)$')"
[ -n "$files" ] || exit 0

if ! "$ROOT/tools/lint/cli-boundary.sh"; then
  hook_fail "CLI target boundary broken. Fix membershipExceptions, re-commit."
  exit 1
fi
hook_ok "CLI target boundary clean"
