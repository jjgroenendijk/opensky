#!/bin/sh
# Block direct commits to protected branches (AGENTS.md "Git workflow").
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo DETACHED)"
case "$branch" in
  main | master)
    hook_fail "Direct commits to '$branch' are blocked. Branch, then open a PR."
    exit 1
    ;;
esac
