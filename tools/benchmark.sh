#!/bin/sh
# Runs the shared performance benchmark (openskycli benchmark) on the real
# install and keeps its output (docs/tools/benchmark.md).
#
# Usage: tools/benchmark.sh CLI
#   CLI   the Release openskycli (make benchmark builds and passes it)
#
# Writes .logs/benchmark/<UTC timestamp>/: benchmark.log, result.json, and
# view.png, the measured view. The PNG embeds game assets, so it stays in .logs/.
set -eu

if [ "$#" -ne 1 ]; then
    echo "[ERROR] usage: tools/benchmark.sh CLI" >&2
    exit 2
fi
cli="$1"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" benchmark)
echo "[INFO] run directory: $run_dir"

status=0
"$cli" benchmark --out "$run_dir/result.json" --frame "$run_dir/view.png" >"$run_dir/benchmark.log" 2>&1 || status=$?
grep -E '^\[ ?(INFO|OK|WARNING|ERROR)' "$run_dir/benchmark.log" || true
exit "$status"
