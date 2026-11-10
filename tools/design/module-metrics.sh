#!/bin/sh
# Design rule 6, as a report: each package module's abstractness, instability, and distance
# from the main sequence, written to module-metrics.md in the run directory. Fails nothing;
# the weekly workflow runs it (docs/decisions/design-metrics.md).
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
run_dir=$("$root/tools/run-dir.sh" module-metrics)
swift package dump-package --package-path src >"$run_dir/package.json"
python3 tools/design/module-metrics.py "$run_dir/package.json" . "$run_dir/module-metrics.md"
echo "[INFO] run directory: $run_dir"
