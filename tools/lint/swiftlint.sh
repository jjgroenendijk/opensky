#!/bin/sh
# SwiftLint, strict, over the Swift files the branch changed, or every one in CI.
# src/Package.swift stays out: one manifest cannot split to the file-length cap.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX"
    printf 'let value = optional!\n' >"$tree/src/Sources/OpenSkyX/A.swift"
    printf 'func cast(a: Int, b: Int, c: Int, d: Int, e: Int) {}\n' >"$tree/src/Sources/OpenSkyX/B.swift"
    expect_failure "$0" "$tree" "force_unwrapping" "function_parameter_count"
fi
config="$OPENSKY_TOOLS/lint/.swiftlint.yml"
cd "$(git rev-parse --show-toplevel)"
files="$(checks_swift_files | grep -v '^src/Package.swift$' || true)"
[ -n "$files" ] || { echo "[ OK ] no changed Swift file to lint"; exit 0; }
# shellcheck disable=SC2086 # one word per file
"${SWIFTLINT:-swiftlint}" lint --strict --quiet --config "$config" $files
