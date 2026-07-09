#!/bin/sh
# Refuse to commit extracted game content (AGENTS.md "Legal & IP boundary").
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

bad="$(staged_matching "$FORBIDDEN_EXT_RE")"
if [ -n "$bad" ]; then
  hook_fail "Refusing to commit — these look like extracted game assets:"
  printf '  %s\n' "$bad" >&2
  hook_fail "Game content must never be committed. Remove: git rm --cached <file>"
  exit 1
fi
