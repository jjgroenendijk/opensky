#!/bin/sh
# Run the format and lint scripts as parallel parts, each into its own log, and
# print one line per part. Adding a check means adding a script to tools/lint/ or
# tools/format/; nothing else lists it.
#
# Usage: tools/run-checks.sh MODE
#   format        each tools/format/*.sh rewrites its files
#   format-check  each tools/format/*.sh --check, writing nothing
#   lint          each tools/lint/*.sh, then each with --self-check
#   check         format-check and lint together
set -eu

mode="${1:?usage: tools/run-checks.sh format|format-check|lint|check}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
run_dir="$(tools/run-dir.sh "$mode")"

parts() {
    case "$1" in
        format) for s in tools/format/*.sh; do echo "$s"; done ;;
        format-check) for s in tools/format/*.sh; do echo "$s --check"; done ;;
        lint) for s in tools/lint/*.sh; do echo "$s"; echo "$s --self-check"; done ;;
        check) parts format-check; parts lint ;;
        *) echo "[ERROR] unknown mode $1" >&2; exit 2 ;;
    esac
}

list="$run_dir/parts.txt"
parts "$mode" >"$list"
while read -r script flag; do
    part="$(basename "$script" .sh)${flag:+ $flag}"
    log="$run_dir/$(printf '%s' "$part" | tr ' ' '_').log"
    { sh "$script" ${flag:+"$flag"} >"$log" 2>&1; echo "$? $part" >"$log.status"; } &
done <"$list"
wait

failed=0
for status in "$run_dir"/*.status; do
    read -r code part <"$status"
    log="${status%.status}"
    if [ "$code" -eq 0 ]; then
        echo "[ OK ] $part"
    else
        failed=$((failed + 1))
        echo "[ERROR] $part failed (log: $log)"
        tail -n 30 "$log" | sed 's/^/  /'
    fi
done
if [ "$failed" -gt 0 ]; then
    fix="read each part's [ERROR] lines above"
    [ "$mode" = lint ] || fix="run make fix for formatting, then $fix"
    echo "[ERROR] $failed of $(wc -l <"$list" | tr -d ' ') parts failed: $fix. Run directory: $run_dir"
    exit 1
fi
echo "[ OK ] $mode: $(wc -l <"$list" | tr -d ' ') parts passed. Run directory: $run_dir"
