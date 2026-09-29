#!/bin/sh
# Staged shell script or hook -> shellcheck every script.
# Shares its rules with `make sh-lint` so the hook and CI agree.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

touched="$(git diff --cached --name-only | grep -E '\.sh$|^\.githooks/hooks/' || true)"
[ -n "$touched" ] || exit 0

require_tool shellcheck
if ! (cd "$ROOT" && make --no-print-directory sh-lint); then
  hook_fail "shellcheck findings. Fix them, then re-commit."
  exit 1
fi
hook_ok "Shell scripts clean"
