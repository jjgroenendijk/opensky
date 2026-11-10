#!/bin/sh
# Build the index store, then fail on unused code or an adapter that uses another
# (docs/decisions/code-health-automation.md), or on a port with one conformer and no
# test fake, a member chain through four objects, or a cycle between types in different files.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=tools/lint-index/build-index.sh
. "$root/tools/lint-index/build-index.sh"
tools/lint-index/unused-code.sh tools/lint-index/.periphery.yml "$store"
python3 tools/lint-index/adapter-references.py "$store" .
python3 tools/lint-index/single-conformers.py "$store" . --gate
python3 tools/lint-index/member-chains.py "$store" . --gate
python3 tools/lint-index/type-cycles.py "$store" . --gate
