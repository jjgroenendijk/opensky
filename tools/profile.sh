#!/bin/sh
# Records a Time Profiler trace of one openskycli bench on the real install.
# xctrace attaches to a running process, because a process it launches here
# never starts.
#
# Usage: tools/profile.sh CLI walk|fly [BENCH_OPTION...]
#   CLI   the Release openskycli (make profile builds and passes it)
#   walk  bench --walk-path; fly runs bench --fly-path
#   BENCH_OPTION  passed on to bench, e.g. --footprint-cap-mb 2048
#
# Writes .logs/profile/<UTC timestamp>/: bench.log, bench.trace, and
# samples.xml, the time-profile table for agents without Instruments.
set -eu

if [ "$#" -lt 2 ]; then
    echo "[ERROR] usage: tools/profile.sh CLI walk|fly [BENCH_OPTION...]" >&2
    exit 2
fi
cli="$1"
case "$2" in
    walk) bench_flag=--walk-path ;;
    fly) bench_flag=--fly-path ;;
    *)
        echo "[ERROR] unknown mode '$2': use walk or fly" >&2
        exit 2
        ;;
esac
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }
shift 2

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" profile)
echo "[INFO] run directory: $run_dir"

"$cli" bench "$bench_flag" "$@" >"$run_dir/bench.log" 2>&1 &
bench_pid=$!
xcrun xctrace record --template 'Time Profiler' --output "$run_dir/bench.trace" \
    --attach "$bench_pid" >"$run_dir/xctrace.log" 2>&1 || true
bench_status=0
wait "$bench_pid" || bench_status=$?
grep -E '^\[ ?(INFO|OK|WARNING|ERROR|FAIL)' "$run_dir/bench.log" | tail -6 || true

if [ ! -d "$run_dir/bench.trace" ]; then
    echo "[ERROR] no trace recorded; see $run_dir/xctrace.log" >&2
    exit 1
fi
xcrun xctrace export --input "$run_dir/bench.trace" \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
    --output "$run_dir/samples.xml" >/dev/null
echo "[INFO] trace: $run_dir/bench.trace"
exit "$bench_status"
