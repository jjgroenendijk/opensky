#!/bin/sh
# Staged workflow change -> lint the workflows with actionlint.
# Shares its rules with `make workflow-lint` so the hook and CI agree.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

touched="$(git diff --cached --name-only | grep -E '^\.github/workflows/' || true)"
[ -n "$touched" ] || exit 0

require_tool actionlint
if ! (cd "$ROOT" && actionlint); then
  hook_fail "Workflow lint failed. Fix the workflow, then re-commit."
  exit 1
fi
hook_ok "Workflows clean"
