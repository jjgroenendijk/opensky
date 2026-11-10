#!/bin/sh
# The design rules that read the index store, as reports: builds the index store as
# `make lint-index` does, then prints each rule's findings and count. Fails nothing; a rule
# becomes a gate in `make lint-index` when its count is zero (docs/decisions/design-metrics.md).
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
# shellcheck source=tools/lint-index/build-index.sh
. "$root/tools/lint-index/build-index.sh"
python3 tools/lint-index/fan-out.py "$store" .
