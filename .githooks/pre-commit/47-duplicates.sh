#!/bin/sh
# No new copy-pasted Swift blocks (docs/decisions/code-smell-scans.md). The scan
# covers the whole tree against the baseline, because a clone spans two files and
# only one of them need be staged; it takes well under a second.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

files="$(staged_matching '\.swift$')"
[ -n "$files" ] || exit 0

require_tool jscpd
if ! make -s -C "$ROOT" dup-check; then
  hook_fail "New duplicated Swift. Extract the shared code, then re-commit."
  exit 1
fi
