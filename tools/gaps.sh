#!/bin/sh
# Runs `openskycli gaps` on the real install and keeps the report
# (docs/tools/gaps.md): what the data uses that the engine does not do yet.
#
# Usage: tools/gaps.sh CLI [ARGS...]
#   CLI   the Release openskycli (make gaps builds and passes it)
#   ARGS  more gaps options, such as --only papyrus,perks
#
# Writes .logs/gaps/<UTC timestamp>/gaps.txt and prints its summary table. The
# report holds names and counts only, no game content.
set -eu

if [ "$#" -lt 1 ]; then
    echo "[ERROR] usage: tools/gaps.sh CLI [ARGS...]" >&2
    exit 2
fi
cli="$1"
shift
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" gaps)
echo "[INFO] run directory: $run_dir"

status=0
"$cli" gaps "$@" >"$run_dir/gaps.txt" || status=$?
sed -n '1,/^$/p' "$run_dir/gaps.txt"
echo "[INFO] full report: $run_dir/gaps.txt"
exit "$status"
