#!/bin/sh
# Runs shellcheck over every shell script in tools/ and reference/.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/tools"
    printf '#!/bin/sh\necho %s1\n' '$' >"$tree/tools/a.sh"
    expect_failure "$0" "$tree" "SC2086"
fi
cd "$(git rev-parse --show-toplevel)"
git ls-files -z -- 'tools/*.sh' 'reference/*.sh' | xargs -0 shellcheck -x -s sh
echo "[ OK ] shell scripts clean"
