#!/bin/sh
# Compares the quick benchmark tour on the real install with and without the
# optimised asset files, each after a page cache eviction
# (docs/engine/asset-cache.md, "Measurements"). The tours read the optimised
# files from the folder in the app's settings; build them first on the
# launcher's Asset Optimisation page.
#
# Usage: tools/asset-cache-bench.sh PRODUCTS
#   PRODUCTS  the Release products folder (make asset-cache-bench builds and passes it)
#
# Writes .logs/asset-cache-bench/<UTC timestamp>/<variant>/ with each tour's result.
set -eu

if [ "$#" -ne 1 ]; then
    echo "[ERROR] usage: tools/asset-cache-bench.sh PRODUCTS" >&2
    exit 2
fi
products="$1"
cli="$products/openskycli"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }
[ -d "$products/OpenSky.app" ] || { echo "[ERROR] no OpenSky.app in $products" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" asset-cache-bench)
echo "[INFO] run directory: $run_dir"

tour() {
    name="$1"
    shift
    echo "[INFO] $name"
    "$cli" benchmark --app "$products/OpenSky.app" --preset quick --no-overlay --evict \
        --out "$run_dir/$name" "$@" >"$run_dir/$name.log" 2>&1 \
        || { echo "[ERROR] $name failed, see $run_dir/$name.log" >&2; exit 1; }
}

tour originals --set assetOptimisation.enabled=off
tour optimised --set assetOptimisation.enabled=on,assetOptimisation.directLoad=off
tour direct --set assetOptimisation.enabled=on,assetOptimisation.directLoad=on,assetOptimisation.directLoad.textures=on,assetOptimisation.directLoad.meshes=on

for name in originals optimised direct; do
    echo "--- $name"
    cat "$run_dir/$name/summary.txt"
done
