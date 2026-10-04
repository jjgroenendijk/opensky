#!/bin/sh
# Samples the main thread of the app through its first minute of play: from the
# launch, through the world load and the session start, into steady frames.
# The app shows the user's game, so everything stays in logs/.
#
# Usage: tools/launch-sample.sh CLI APP [SECONDS]
#   CLI      an openskycli from the same build as APP
#   APP      the OpenSky.app to launch (make launch-sample uses the Release app)
#   SECONDS  how long to sample after the launch starts (default 60)
#
# Writes logs/launch-sample/<UTC timestamp>/: launch.log, frames.txt (one
# `game state frame` reply per line, with seconds since launch), and one
# `sample` report per tick, s_<seconds>.txt.
set -eu

if [ "$#" -lt 2 ]; then
    echo "[ERROR] usage: tools/launch-sample.sh CLI APP [SECONDS]" >&2
    exit 2
fi
cli="$1"
app="$2"
duration="${3:-60}"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }
[ -d "$app" ] || { echo "[ERROR] no app at $app" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" launch-sample)
echo "[INFO] run directory: $run_dir"
binary="$app/Contents/MacOS/OpenSky"

started=$(date +%s)
elapsed() {
    echo $(($(date +%s) - started))
}

{
    "$cli" game launch --app "$app" --wait "$duration" || true
    printf 'launch returned at t=%ss\n' "$(elapsed)"
} >"$run_dir/launch.log" 2>&1 &
launch_pid=$!

pid=""
while [ "$(elapsed)" -lt "$duration" ]; do
    if [ -z "$pid" ]; then
        pid=$(pgrep -f "^$binary" | head -1 || true)
    fi
    if [ -n "$pid" ]; then
        tick=$(elapsed)
        # Frame stats first: `sample` pauses the app, which would slow the frames it averages.
        reply=$("$cli" game state frame --reply-timeout 5 2>&1 || true)
        printf 't=%ss %s\n' "$tick" "$reply" >>"$run_dir/frames.txt"
        # One second of samples at 1 ms; the main thread is the first thread listed.
        sample "$pid" 1 1 -file "$run_dir/s_$(printf '%03d' "$tick").txt" >/dev/null 2>&1 || true
    fi
    sleep 3
done

wait "$launch_pid" 2>/dev/null || true
"$cli" game quit >/dev/null 2>&1 || true
[ -s "$run_dir/frames.txt" ] || {
    echo "[ERROR] the app never started; see $run_dir/launch.log" >&2
    exit 1
}
tail -1 "$run_dir/launch.log"
tail -3 "$run_dir/frames.txt"
echo "[INFO] samples: $run_dir"
