#!/bin/sh
# Every `make <target>` in the docs, skills, agent files, scripts, and code names a target the
# Makefile has, so a renamed or deleted target leaves no stale instruction behind.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    printf 'help:\n\t@true\n' >"$tree/Makefile"
    printf '%s\n' "Run \`make help\`, then \`make test-unit\`." >"$tree/README.md"
    expect_failure "$0" "$tree" "README.md:1: make test-unit"
fi
cd "$(git rev-parse --show-toplevel)"
targets="$(sed -n 's/^\([a-z][a-z0-9-]*\):.*/\1/p' Makefile | sort -u)"
report="$(git ls-files -z -- ':!Makefile' ':!tools/lint/make-targets.sh' | xargs -0 grep -HnoE '`make [a-z][a-z0-9-]*' 2>/dev/null \
    | sed 's/:`make /: make /' | while IFS= read -r hit; do
        name="${hit##*make }"
        [ "${name%-}" = "$name" ] || continue
        printf "%s\n" "$targets" | grep -qx "$name" || printf "%s\n" "$hit"
    done)"
if [ -n "$report" ]; then
    printf '[FAIL] these name a make target the Makefile does not have:\n%s\n' "$report" >&2
    echo 'Fix: name a target from make help.' >&2
    exit 1
fi
echo "[ OK ] every make target named in the tree exists"
