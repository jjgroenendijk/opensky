#!/bin/sh
# Replay the recorded tour in the Release app already built, hidden and muted, and keep
# its state reads (docs/tools/acceptance-record.md, Tour check).
#
# Usage: tools/tour/tour.sh record|check
#   record  the run becomes the reference, in the main checkout's .logs/tour-record/
#   check   the run is diffed against that reference; any difference fails
set -eu
mode="${1:?usage: tools/tour/tour.sh record|check}"
case "$mode" in record | check) ;; *) echo "[ERROR] usage: tools/tour/tour.sh record|check" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
set -- --no-build
# shellcheck source=tools/release-products.sh
. "$root/tools/release-products.sh"
cli="$products/openskycli"
app="$products/OpenSky.app"
[ -x "$cli" ] && [ -d "$app" ] || {
    echo "[ERROR] no Release build in $products; run make build-app build-cli CONFIG=Release" >&2
    exit 2
}
main="$(cd "$(git -C "$root" rev-parse --git-common-dir)/.." && pwd)"
reference="$main/.logs/tour-record/latest/reads.json"
if [ "$mode" = check ] && [ ! -f "$reference" ]; then
    echo "[ERROR] no reference run at $reference; run make tour-record on the base first" >&2
    exit 2
fi
# The reference lives in the main checkout, so every worktree checks against the same one.
if [ "$mode" = record ]; then run_dir="$("$root/tools/run-dir.sh" -b "$main/.logs" tour-record)"
else run_dir="$("$root/tools/run-dir.sh" tour-check)"; fi
# A locked screen stops the display link, so the app draws no frame and the world never loads.
if ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'; then
    echo "[ERROR] the screen is locked, so the app draws no frames; unlock it and run again" >&2
    exit 2
fi
socket="/tmp/opensky-tour-$$.sock"
started="$(date +%s)"

# Quit the app however the run ends, a failed launch included.
trap '"$cli" game quit --socket "$socket" >/dev/null 2>&1 || true; rm -f "$socket"' EXIT INT TERM
"$cli" game launch --hidden --app "$app" --socket "$socket" --wait 240 >"$run_dir/launch.json"
status=0
"$cli" game run "$here/tour.jsonl" --socket "$socket" >"$run_dir/replies.jsonl" 2>&1 || status=$?
[ "$status" -eq 0 ] || { tail -n 5 "$run_dir/replies.jsonl" >&2; echo "[ERROR] the tour stopped; read $run_dir/replies.jsonl" >&2; exit 1; }
git -C "$root" rev-parse HEAD >"$run_dir/commit.txt"
python3 "$here/tour_diff.py" "$here/tour.jsonl" "$run_dir/replies.jsonl" "$run_dir/reads.json"
echo "[INFO] tour took $(($(date +%s) - started)) s; run directory: $run_dir"
[ "$mode" = record ] || python3 "$here/tour_diff.py" diff "$reference" "$run_dir/reads.json"
