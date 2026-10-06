#!/bin/sh
# Measures the asset cache on the real install with the shared benchmark
# (docs/engine/asset-cache.md, "Measurements").
#
# Usage: tools/asset-cache-bench.sh CLI CACHE_ROOT [EXTERNAL_ROOT]
#   CLI            the Release openskycli (make asset-cache-bench passes it)
#   CACHE_ROOT     a folder outside the repo for the benchmark block's caches
#   EXTERNAL_ROOT  optional folder on another disk: repeats the Highest quality
#                  run there, and builds the whole install for every preset
#
# Writes .logs/asset-cache-bench/<UTC timestamp>/. The caches, loose copies,
# and frame PNGs are game content, so they stay in CACHE_ROOT and .logs/.
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "[ERROR] usage: tools/asset-cache-bench.sh CLI CACHE_ROOT [EXTERNAL_ROOT]" >&2
    exit 2
fi
cli="$1"
cache_root="$2"
external_root="${3:-}"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" asset-cache-bench)
echo "[INFO] run directory: $run_dir"
paths="$run_dir/paths.txt"
presets="highest balanced best"

# Runs one step under /usr/bin/time -l, so the log ends with the peak memory.
step() {
    name="$1"
    shift
    echo "[INFO] $name"
    /usr/bin/time -l "$cli" "$@" >"$run_dir/$name.log" 2>&1 \
        || { echo "[ERROR] $name failed, see $run_dir/$name.log" >&2; exit 1; }
}

summary() {
    log="$run_dir/$1.log"
    grep -E 'cold load:|warm load:|GPU memory|asset cache (texture|mesh)|frame time over' "$log" || true
    awk '/maximum resident set size/ { printf "[INFO] peak memory: %d MiB\n", $1 / 1048576 }' "$log"
}

step baseline benchmark --evict --frame "$run_dir/view-baseline.png"
step record benchmark --asset-cache --preset highest --folder "$cache_root/record" \
    --record-paths "$paths"
rm -rf "$cache_root/record"
echo "[INFO] $(wc -l <"$paths" | tr -d ' ') asset paths in the benchmark block"

for preset in $presets; do
    step "build-$preset" asset-cache build --preset "$preset" --folder "$cache_root/$preset" --paths "$paths"
    step "bench-$preset" benchmark --asset-cache --evict --preset "$preset" \
        --folder "$cache_root/$preset" --frame "$run_dir/view-$preset.png"
    "$cli" asset-cache compare "$run_dir/view-baseline.png" "$run_dir/view-$preset.png" \
        >"$run_dir/compare-$preset.log" 2>&1
    echo "[INFO] $preset cache: $(du -sk "$cache_root/$preset" | cut -f1) KiB on disk"
done

step extract asset-cache extract --paths "$paths" --out "$cache_root/loose"
step bench-loose benchmark --evict --loose "$cache_root/loose"
step io-bench asset-cache io-bench --preset highest --folder "$cache_root/highest" --paths "$paths"
step bench-highest-fast benchmark --asset-cache --fast-load --evict --preset highest \
    --folder "$cache_root/highest"

if [ -n "$external_root" ]; then
    step build-external asset-cache build --preset highest --folder "$external_root/highest" --paths "$paths"
    step bench-external benchmark --asset-cache --evict --preset highest --folder "$external_root/highest"
    step io-bench-external asset-cache io-bench --preset highest --folder "$external_root/highest" \
        --paths "$paths"
    for preset in $presets; do
        step "full-build-$preset" asset-cache build --preset "$preset" --folder "$external_root/full-$preset"
        echo "[INFO] full $preset cache: $(du -sk "$external_root/full-$preset" | cut -f1) KiB on disk"
    done
fi

for name in baseline bench-loose bench-highest bench-highest-fast bench-balanced bench-best \
    ${external_root:+bench-external}; do
    echo "--- $name"
    summary "$name"
done
for preset in $presets; do
    echo "--- $preset: $(cat "$run_dir/compare-$preset.log")"
    grep -E '^[0-9]+/[0-9]+ files' "$run_dir/build-$preset.log" || true
done
echo "--- io-bench"
grep -E '^(\[INFO\]|method|archive|cacheCPU|fastLoad)' "$run_dir/io-bench.log" || true
