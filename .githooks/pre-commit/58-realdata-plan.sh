#!/bin/sh
# Staged test source or test plan -> check the real-data suites stay in their target.
# Shares its rules with `make realdata-plan` so the hook and CI agree.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

touched="$(git diff --cached --name-only | grep -E '^(Tests/.*\.swift|Config/TestPlans/)' || true)"
[ -n "$touched" ] || exit 0

if ! "$ROOT/tools/lint/realdata-plan.sh"; then
  hook_fail "Real-data suite outside its target or plan. Fix it, then re-commit."
  exit 1
fi
hook_ok "Real-data suites and plan line up"
