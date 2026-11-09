#!/bin/sh
# ruff over the Python tools, with the version tools/wiki-mirror/uv.lock pins.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/tools/wiki-mirror"
    printf 'import os\n' >"$tree/tools/wiki-mirror/a.py"
    expect_failure "$0" "$tree" "F401"
fi
project="$OPENSKY_TOOLS/wiki-mirror"
cd "$(git rev-parse --show-toplevel)"
UV_LINK_MODE=copy uv run --locked --quiet --project "$project" \
    ruff check --config "$project/pyproject.toml" tools/wiki-mirror
echo "[ OK ] Python tools clean"
