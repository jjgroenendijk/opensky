#!/bin/sh
# Add the shared tags a test suite needs (tools/lint/test-tags.sh); the lint checks them.
# Usage: tools/format/test-tags.sh [--check]
set -eu
[ -z "${1:-}" ] || { echo "[ OK ] tags are checked by the test-tags lint"; exit 0; }
sh "$(dirname "$0")/../lint/test-tags.sh" --fix
