#!/bin/sh
# Format the Python tools with ruff, which tools/wiki-mirror/uv.lock pins.
# Usage: tools/format/python.sh [--check]
set -eu
cd "$(git rev-parse --show-toplevel)"
UV_LINK_MODE=copy uv run --locked --quiet --project tools/wiki-mirror \
    ruff format ${1:+--check} tools/wiki-mirror
