#!/bin/sh
# Format the Metal shaders and their headers with Xcode's clang-format.
# Usage: tools/format/metal.sh [--check]
set -eu
cd "$(git rev-parse --show-toplevel)"
mode="-i"
[ -z "${1:-}" ] || mode="--dry-run --Werror"
# shellcheck disable=SC2046,SC2086 # one word per file and per flag
xcrun clang-format --style=file:tools/format/.clang-format $mode \
    $(git ls-files -- 'src/Sources/*.metal' 'src/Sources/Shaders/*.h')
