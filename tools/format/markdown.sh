#!/bin/sh
# Lint Markdown strictly, or fix what markdownlint can fix.
# Usage: tools/format/markdown.sh [--check]
set -eu
cd "$(git rev-parse --show-toplevel)"
if [ -n "${1:-}" ]; then
    markdownlint-cli2 --config tools/markdown/.markdownlint-cli2.yaml '**/*.md'
else
    markdownlint-cli2 --fix --config tools/markdown/.markdownlint-cli2.yaml '**/*.md' || true
fi
