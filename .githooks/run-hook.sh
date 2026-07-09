#!/bin/sh
# Generic hook runner. Executes every numbered script in .githooks/<hook>/ in sorted
# order, forwards args + stdin, stops on first failure. Called by the tiny wrappers in
# .githooks/hooks/. See AGENTS.md "Git workflow".
set -eu

hook="${1:?usage: run-hook.sh <hook-name> [args...]}"
shift

root="$(git rev-parse --show-toplevel)"
dir="$root/.githooks/$hook"
[ -d "$dir" ] || exit 0

for script in "$dir"/[0-9]*.sh; do
  [ -e "$script" ] || continue          # no matches -> literal glob, skip
  if [ ! -x "$script" ]; then
    printf '[FAIL] hook script not executable: %s\n' "$script" >&2
    exit 1
  fi
  "$script" "$@"                          # set -e -> first failure aborts the hook
done
