#!/bin/sh
# Runs `openskycli gaps` on the real install and keeps the report
# (docs/tools/gaps.md): what the data uses that the engine does not do yet.
#
# Usage: tools/gaps.sh CLI [ARGS...]
#   CLI   the Release openskycli (make gaps builds and passes it)
#   ARGS  more gaps options, such as --only papyrus,perks
#
# Writes .logs/gaps/<UTC timestamp>/gaps.txt and summary.md, and prints the summary
# table. A run of every section (no --only) also puts summary.md into README.md,
# between the gaps markers. The report holds names and counts only, no game content.
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

every_section=1
for arg in "$@"; do
    [ "$arg" = "--only" ] && every_section=0
done

status=0
"$cli" gaps "$@" --summary-out "$run_dir/summary.md" >"$run_dir/gaps.txt" || status=$?
sed -n '1,/^$/p' "$run_dir/gaps.txt"
echo "[INFO] full report: $run_dir/gaps.txt"

readme="$root/README.md"
if [ "$status" -eq 0 ] && [ "$every_section" -eq 1 ]; then
    awk -v table="$run_dir/summary.md" -v day="$(date -u +%Y-%m-%d)" '
        /<!-- gaps:begin -->/ {
            print
            print ""
            print "Measured on " day " by `make gaps`."
            print ""
            while ((getline line < table) > 0) print line
            print ""
            skip = 1
            next
        }
        /<!-- gaps:end -->/ { skip = 0 }
        !skip { print }
    ' "$readme" >"$run_dir/README.md"
    cp "$run_dir/README.md" "$readme"
    echo "[INFO] README.md progress table updated"
fi
exit "$status"
