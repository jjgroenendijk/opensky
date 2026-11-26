#!/bin/sh
# Runs `openskycli gaps` on the real install and keeps the report
# (docs/tools/gaps.md): what the data uses that the engine does not do yet.
#
# Usage: tools/gaps.sh [--no-build] [GAPS_OPTION...]
#   --no-build   use the Release openskycli already built
#   GAPS_OPTION  more gaps options, such as --only papyrus,perks or --limit 20
#
# Writes .logs/gaps/<UTC timestamp>/gaps.txt and summary.md, and prints the summary
# table. The fields section first builds the index store (tools/lint-index/build-index.sh)
# and lists the record fields engine code reads in field-reads.tsv beside them. A run of every section (no --only) also puts summary.md into README.md,
# between the gaps markers. The report holds names and counts only, no game content.
set -eu

# shellcheck source=tools/release-products.sh
. "$(dirname "$0")/release-products.sh"
cli="$products/openskycli"
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
run_dir=$("$root/tools/run-dir.sh" gaps)
echo "[INFO] run directory: $run_dir"

every_section=1
needs_fields=1
previous=
for arg in "$@"; do
    [ "$arg" = "--only" ] && every_section=0
    if [ "$previous" = "--only" ]; then
        case ",$arg," in *,fields,*) ;; *) needs_fields=0 ;; esac
    fi
    previous=$arg
done

if [ "$needs_fields" -eq 1 ]; then
    (
        cd "$root"
        # shellcheck source=tools/lint-index/build-index.sh
        . "$root/tools/lint-index/build-index.sh"
        python3 tools/lint-index/record-field-reads.py "$store" . "$run_dir/field-reads.tsv"
    )
    set -- "$@" --field-reads "$run_dir/field-reads.tsv"
fi

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
            print "Measured on " day " by `make rank-gaps`."
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
