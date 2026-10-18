#!/bin/sh
# Records a Time Profiler trace of the Release app while it flies the benchmark
# tour. xctrace attaches to the running app, because a process it launches here
# never starts.
#
# Usage: tools/profile.sh PRODUCTS [BENCHMARK_OPTION...]
#   PRODUCTS          the Release products folder (make profile builds and passes it)
#   BENCHMARK_OPTION  passed on to openskycli benchmark; the default is --preset quick
#
# Writes .logs/profile/<UTC timestamp>/: benchmark.log, result.json, tour.trace,
# and samples.xml, the time-profile table for agents without Instruments.
set -eu

if [ "$#" -lt 1 ]; then
    echo "[ERROR] usage: tools/profile.sh PRODUCTS [BENCHMARK_OPTION...]" >&2
    exit 2
fi
products="$1"
shift
cli="$products/openskycli"
app="$products/OpenSky.app"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }
[ -d "$app" ] || { echo "[ERROR] no OpenSky.app in $products" >&2; exit 2; }
[ "$#" -gt 0 ] || set -- --preset quick

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" profile)
echo "[INFO] run directory: $run_dir"

"$cli" benchmark --app "$app" --out "$run_dir" "$@" >"$run_dir/benchmark.log" 2>&1 &
cli_pid=$!
# The app opens through LaunchServices, so wait up to a minute for its process.
app_pid=""
tries=0
while [ -z "$app_pid" ] && [ "$tries" -lt 60 ]; do
    app_pid=$(pgrep -n -f "$app/Contents/MacOS/" || true)
    tries=$((tries + 1))
    [ -n "$app_pid" ] || sleep 1
done
if [ -z "$app_pid" ]; then
    echo "[ERROR] the app did not start; see $run_dir/benchmark.log" >&2
    wait "$cli_pid" || true
    exit 1
fi
xcrun xctrace record --template 'Time Profiler' --output "$run_dir/tour.trace" \
    --attach "$app_pid" >"$run_dir/xctrace.log" 2>&1 || true
cli_status=0
wait "$cli_pid" || cli_status=$?
tail -12 "$run_dir/benchmark.log" || true

if [ ! -d "$run_dir/tour.trace" ]; then
    echo "[ERROR] no trace recorded; see $run_dir/xctrace.log" >&2
    exit 1
fi
xcrun xctrace export --input "$run_dir/tour.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
    --output "$run_dir/samples.xml" >/dev/null
echo "[INFO] trace: $run_dir/tour.trace"
exit "$cli_status"
