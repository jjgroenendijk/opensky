#!/bin/sh
# Autoformat staged Swift with SwiftFormat, then re-stage (AGENTS.md "Code quality").
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

files="$(staged_matching '\.swift$')"
[ -n "$files" ] || { hook_ok "no Swift changes to format"; exit 0; }

require_tool swiftformat
# One swiftformat and one `git add` for the whole staged set, not one pair per
# file: each swiftformat start-up re-reads the config and costs more than the
# formatting itself on a multi-file commit. NUL separators so paths with spaces
# survive xargs.
printf '%s\n' "$files" | tr '\n' '\0' \
  | xargs -0 swiftformat --config "$ROOT/tools/format/.swiftformat"
printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 git add --
hook_ok "SwiftFormat applied + re-staged"
