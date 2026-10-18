#!/bin/sh
# Flies the benchmark tour in the Release app on the real install and keeps its
# output (docs/tools/benchmark.md).
#
# Usage: tools/benchmark.sh PRODUCTS [BENCHMARK_OPTION...]
#   PRODUCTS          the Release products folder (make benchmark builds and passes it)
#   BENCHMARK_OPTION  passed on, such as --preset quick or --set rendering.gpuCulling=off
#
# Writes .logs/benchmark/<UTC timestamp>/: benchmark.log, result.json, and summary.txt.
set -eu

if [ "$#" -lt 1 ]; then
    echo "[ERROR] usage: tools/benchmark.sh PRODUCTS [BENCHMARK_OPTION...]" >&2
    exit 2
fi
products="$1"
shift
cli="$products/openskycli"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }
[ -d "$products/OpenSky.app" ] || { echo "[ERROR] no OpenSky.app in $products" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" benchmark)
echo "[INFO] run directory: $run_dir"

status=0
"$cli" benchmark --app "$products/OpenSky.app" --out "$run_dir" "$@" >"$run_dir/benchmark.log" 2>&1 || status=$?
cat "$run_dir/benchmark.log"
exit "$status"
