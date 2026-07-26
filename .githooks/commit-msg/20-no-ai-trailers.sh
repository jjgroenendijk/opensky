#!/bin/sh
# Reject AI attribution trailers (commit skill, "Forbidden trailers"). Arg 1 =
# commit message file. Enforced rather than documented because the harness's
# own default is to append one, and the rule applies at a moment when the
# commit skill may never have been loaded.
#
# Parses the real trailer block with `git interpret-trailers` rather than
# grepping every line, so a body that discusses the rule by naming the
# forbidden keys is not itself rejected.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

msg_file="$1"
forbidden_re='^(co-authored-by|generated-by|ai-generated-by|assisted-by|model)[[:space:]]*:'

found="$(git interpret-trailers --parse "$msg_file" | grep -Ei "$forbidden_re" || true)"
if [ -n "$found" ]; then
  hook_fail "Commit message carries a forbidden attribution trailer:"
  printf '%s\n' "$found" | while IFS= read -r line; do printf '  %s\n' "$line" >&2; done
  printf 'Remove it. OpenSky commits carry no AI or co-author attribution.\n' >&2
  exit 1
fi
