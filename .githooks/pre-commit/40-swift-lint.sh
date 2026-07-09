#!/bin/sh
# Strict lint of staged Swift; any violation blocks the commit (AGENTS.md "Code quality").
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

files="$(staged_matching '\.swift$')"
[ -n "$files" ] || exit 0

require_tool swiftlint
if ! printf '%s\n' "$files" \
  | xargs swiftlint lint --strict --quiet --config "$ROOT/tools/lint/.swiftlint.yml"; then
  hook_fail "SwiftLint violations (strict: warnings count). Fix, then re-commit."
  exit 1
fi
hook_ok "SwiftLint clean"
