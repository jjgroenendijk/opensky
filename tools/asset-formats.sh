#!/bin/sh
# Runs the asset format comparison (openskycli asset-formats) on the real install and
# keeps its output (docs/tools/asset-format-comparison.md).
#
# Usage: tools/asset-formats.sh CLI [KIND]
#   CLI    the Release openskycli (make asset-formats builds and passes it)
#   KIND   optional: texture, mesh, collision, animation, or audio
#
# Writes logs/asset-formats/<UTC timestamp>/: asset-formats.log and result.json. The
# cache files it measures are game content; they live in scratch/ during the run and
# are deleted at the end.
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "[ERROR] usage: tools/asset-formats.sh CLI [KIND]" >&2
    exit 2
fi
cli="$1"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" asset-formats)
echo "[INFO] run directory: $run_dir"
scratch="$run_dir/scratch"
trap 'rm -rf "$scratch"' EXIT INT TERM

status=0
if [ "$#" -eq 2 ]; then
    "$cli" asset-formats --scratch "$scratch" --out "$run_dir/result.json" --kind "$2" \
        >"$run_dir/asset-formats.log" 2>&1 || status=$?
else
    "$cli" asset-formats --scratch "$scratch" --out "$run_dir/result.json" \
        >"$run_dir/asset-formats.log" 2>&1 || status=$?
fi
grep -E '^\[ ?(OK|WARNING|ERROR)' "$run_dir/asset-formats.log" || true
exit "$status"
