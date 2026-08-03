#!/bin/sh
# Toolchain + Swift 6 language-mode baseline (issue #314).
# Shares its rules with `make swift-baseline` so the hook and CI agree.
set -eu

exec "$(git rev-parse --show-toplevel)/tools/lint/swift-baseline.sh"
