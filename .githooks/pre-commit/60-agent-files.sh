#!/bin/sh
# Staged agent instruction file or skill -> check the agent-file rules.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

touched="$(git diff --cached --name-only | grep -E '(^|/)(AGENTS|CLAUDE)\.md$|^\.AGENTS/' || true)"
[ -n "$touched" ] || exit 0

if ! "$ROOT/tools/lint/agent-files.sh"; then
  hook_fail "Agent files out of line. Fix them, then re-commit."
  exit 1
fi
