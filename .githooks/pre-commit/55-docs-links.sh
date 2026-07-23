#!/bin/sh
# Staged docs/ change -> verify intra-wiki links resolve (issue #102).
# Any staged docs path triggers a full-tree check: a deletion or rename can
# dangle links in files that are not themselves staged.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

touched="$(git diff --cached --name-only | grep -E '^docs/' || true)"
[ -n "$touched" ] || exit 0

if ! "$ROOT/tools/check-docs-links.sh"; then
  hook_fail "Dangling docs/ links. Fix the link or target, then re-commit."
  exit 1
fi
