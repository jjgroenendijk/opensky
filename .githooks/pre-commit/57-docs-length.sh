#!/bin/sh
# Staged docs/ change -> check every page is within the length limit.
# Shares its rules with `make docs-length` so the hook and CI agree.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

touched="$(git diff --cached --name-only | grep -E '^(docs/|Makefile)' || true)"
[ -n "$touched" ] || exit 0

if ! (cd "$ROOT" && make --no-print-directory docs-length); then
  hook_fail "Docs page length check failed. Split or cut the page, then re-commit."
  exit 1
fi
