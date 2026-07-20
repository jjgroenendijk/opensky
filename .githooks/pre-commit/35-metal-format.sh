#!/bin/sh
# Autoformat staged Metal shaders with clang-format, then re-stage
# (AGENTS.md "Code quality"). Lint = Metal compiler warnings-as-errors at build.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

files="$(staged_matching '\.metal$')"
[ -n "$files" ] || exit 0

require_tool xcrun
printf '%s\n' "$files" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  xcrun clang-format --style="file:$ROOT/tools/format/.clang-format" -i "$f"
  git add -- "$f"
done
hook_ok "clang-format applied + re-staged"
