#!/bin/sh
# Autoformat staged Swift with SwiftFormat, then re-stage (AGENTS.md "Code quality").
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

files="$(staged_matching '\.swift$')"
[ -n "$files" ] || { hook_ok "no Swift changes to format"; exit 0; }

require_tool swiftformat
printf '%s\n' "$files" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  swiftformat --config "$ROOT/tools/format/.swiftformat" "$f"
  git add -- "$f"
done
hook_ok "SwiftFormat applied + re-staged"
