#!/bin/sh
# Block direct pushes to protected branches (AGENTS.md "Git workflow").
# stdin: <local ref> <local sha> <remote ref> <remote sha>  (per line)
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

while read -r _localref _localsha remoteref _remotesha; do
  case "$remoteref" in
    refs/heads/main | refs/heads/master)
      hook_fail "Direct push to '${remoteref#refs/heads/}' is blocked. Open a PR instead."
      exit 1
      ;;
  esac
done
