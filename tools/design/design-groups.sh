#!/bin/sh
# Module cohesion, as a report: builds the index store as `make lint-index` does, then writes
# the Louvain groups of the type graph against the modules to design-groups.txt in the run
# directory. Fails nothing; the weekly workflow runs it (docs/decisions/design-metrics.md).
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
# shellcheck source=tools/lint-index/build-index.sh
. "$root/tools/lint-index/build-index.sh"
run_dir=$("$root/tools/run-dir.sh" design-groups)
python3 tools/design/design-groups.py "$store" . | tee "$run_dir/design-groups.txt"
echo "[INFO] run directory: $run_dir"
