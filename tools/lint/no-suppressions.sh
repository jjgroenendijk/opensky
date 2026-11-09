#!/bin/sh
# No Swift file disables a SwiftLint rule; fix the finding instead
# (docs/decisions/code-health-automation.md).
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX"
    printf '// swiftlint:%s:next force_unwrapping\n' disable >"$tree/src/Sources/OpenSkyX/A.swift"
    expect_failure "$0" "$tree" "SwiftLint suppressions"
fi
cd "$(git rev-parse --show-toplevel)"
offenders="$(git ls-files -- 'src/*.swift' | xargs grep -n 'swiftlint:disable' || true)"
if [ -n "$offenders" ]; then
    printf '[FAIL] SwiftLint suppressions:\n%s\n' "$offenders" >&2
    echo 'Fix: change the code so the rule passes, then drop the comment.' >&2
    exit 1
fi
echo "[ OK ] no SwiftLint suppressions"
