#!/bin/sh
# Format the reference bridge plugin's C++, in the shaders' clang-format style.
# Usage: tools/format/cpp.sh [--check]
set -eu
cd "$(git rev-parse --show-toplevel)"
mode="-i"
[ -z "${1:-}" ] || mode="--dry-run --Werror"
# shellcheck disable=SC2046,SC2086 # one word per file and per flag
xcrun clang-format --style=file:tools/format/.clang-format $mode \
    $(git ls-files -- 'reference/bridge/src/*.cpp' 'reference/bridge/src/*.h')
