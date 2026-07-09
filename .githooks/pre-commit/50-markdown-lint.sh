#!/bin/sh
# Autofix + strict-lint staged Markdown (AGENTS.md "Code quality").
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

files="$(staged_matching '\.md$')"
[ -n "$files" ] || exit 0

require_tool markdownlint-cli2
cfg="$ROOT/tools/markdown/.markdownlint-cli2.yaml"

# Autofix what can be fixed, then re-stage.
printf '%s\n' "$files" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  markdownlint-cli2 --fix --config "$cfg" "$f" >/dev/null 2>&1 || true
  git add -- "$f"
done

# Fail on anything still violating.
if ! printf '%s\n' "$files" | xargs markdownlint-cli2 --config "$cfg"; then
  hook_fail "Markdown violations remain. Fix, then re-commit."
  exit 1
fi
hook_ok "Markdown clean"
