#!/bin/sh
# Enforce Conventional Commits (AGENTS.md "Git commits"). Arg 1 = commit message file.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

msg_file="$1"
subject="$(grep -vE '^[[:space:]]*#' "$msg_file" | sed '/^[[:space:]]*$/d' | head -n1)"

# Let merge/revert/fixup/squash subjects through untouched.
case "$subject" in
  Merge* | Revert* | fixup!* | squash!*) exit 0 ;;
esac

types='feat|fix|docs|refactor|perf|test|build|ci|chore|style|revert'
if ! printf '%s' "$subject" | grep -Eq "^(${types})(\([a-z0-9._-]+\))?!?: .{1,72}$"; then
  hook_fail "Commit subject is not a valid Conventional Commit."
  printf '  got:      %s\n' "${subject:-<empty>}" >&2
  printf '  expected: <type>(<scope>)?: <subject up to 72 chars>\n' >&2
  printf '  types:    %s\n' "$types" >&2
  printf '  example:  feat(formats): parse BSA archive header\n' >&2
  exit 1
fi
