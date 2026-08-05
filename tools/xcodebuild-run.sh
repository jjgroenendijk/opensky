#!/bin/sh
# Run an xcodebuild command with its full transcript kept in a run directory
# and only the interesting lines on stdout. Per-file compile lines and the one
# line per passing test are the dominant output cost of `make build` and `make
# test` and carry nothing a green run needs, but they are exactly what you want
# when something breaks -- so a failing run prints the whole transcript.
#
# xcodebuild's own -quiet cannot do this: it decides what to print before the
# text exists, leaving no full copy anywhere.
#
# The transcript goes to logs/<name>/<UTC timestamp>/<name>.log (issue #347);
# a caller that has already opened a run directory passes it in so one run of
# a wrapper script keeps all of its output together.
#
# Usage: tools/xcodebuild-run.sh LOG_NAME xcodebuild [args...]
# Env:   OPENSKY_XCODEBUILD_RAW=1  pass everything through, transcript included
#        OPENSKY_RUN_DIR           write into this run directory, not a new one
set -eu

if [ "$#" -lt 2 ]; then
    echo "[ERROR] usage: tools/xcodebuild-run.sh LOG_NAME xcodebuild [args...]" >&2
    exit 2
fi

name="$1"
shift
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"

if [ -n "${OPENSKY_RUN_DIR:-}" ]; then
    run_dir="$OPENSKY_RUN_DIR"
    mkdir -p "$run_dir"
else
    run_dir="$("$root/tools/run-dir.sh" "$name")"
fi
log="$run_dir/$name.log"
# The pipeline below runs xcodebuild in a subshell, so its exit status comes
# back through a file rather than $?. `set -o pipefail` is not in POSIX sh.
status_file="$(mktemp -t opensky-xcodebuild)"
trap 'rm -f "$status_file"' EXIT INT TERM
printf '0\n' >"$status_file"

if [ "${OPENSKY_XCODEBUILD_RAW:-0}" = "1" ]; then
    { "$@" 2>&1 || printf '%s\n' "$?" >"$status_file"; } | tee "$log"
else
    { "$@" 2>&1 || printf '%s\n' "$?" >"$status_file"; } | tee "$log" \
        | xcodebuild_summary
fi

status="$(cat "$status_file")"
if [ "$status" -ne 0 ] && [ "${OPENSKY_XCODEBUILD_RAW:-0}" != "1" ]; then
    cat "$log"
fi
printf '[INFO] full transcript: %s\n' "$log"
exit "$status"
