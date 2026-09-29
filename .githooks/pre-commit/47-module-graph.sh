#!/bin/sh
# Package.swift or an import line changed -> check the module graph (TMA, issue #636).
# Shares its rules with `make module-graph` so the hook and CI agree.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

manifest="$(git diff --cached --name-only | grep -E '^(Package\.swift|tools/lint/module-graph\.sh)$' || true)"
imports="$(git diff --cached -U0 -- '*.swift' \
  | grep -E '^[+-][[:space:]]*(@[[:alnum:]_]+[[:space:]]+)*([a-z]+[[:space:]]+)?import[[:space:]]' || true)"
[ -n "$manifest$imports" ] || exit 0

if ! "$ROOT/tools/lint/module-graph.sh"; then
  hook_fail "Module graph breaks TMA. Fix the dependency or the import, then re-commit."
  exit 1
fi
