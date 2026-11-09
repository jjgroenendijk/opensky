#!/bin/sh
# Format the Swift files the branch changed, or every one in CI (tools/checks-lib.sh).
# Usage: tools/format/swift.sh [--check]
set -eu
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=tools/checks-lib.sh
. tools/checks-lib.sh
files="$(checks_swift_files)"
[ -n "$files" ] || { echo "[ OK ] no changed Swift file"; exit 0; }
# shellcheck disable=SC2086 # one word per file
swiftformat ${1:+--lint} --config tools/format/.swiftformat $files
