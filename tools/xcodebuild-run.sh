#!/bin/sh
# Run an xcodebuild command with its full transcript kept in a run directory
# and only the interesting lines on stdout: each diagnostic once, failed tests,
# and the closing status. Per-file compile lines and passing tests stay in the
# transcript. A failing run whose filter caught nothing prints the transcript
# tail instead, so a failure never shows as silence.
#
# xcodebuild's own -quiet cannot do this: it decides what to print before the
# text exists, leaving no full copy anywhere.
#
# A build takes a build slot and its tree's lock first (tools/xcodebuild-lib.sh),
# then removes stale module copies (tools/stale-modules.sh). When a failed build
# leaves new stale copies, it removes them and builds once more; the stale check
# also removes the copies of the modules above, so one pass is enough.
#
# The transcript goes to .logs/<name>/<UTC timestamp>/<name>.log (issue #347);
# a caller that has already opened a run directory passes it in so one run of
# a wrapper script keeps all of its output together. phases.tsv beside it notes
# when each phase of the run started, and the last line printed sums them up.
#
# Usage: tools/xcodebuild-run.sh LOG_NAME xcodebuild [args...]
# Env:   OPENSKY_XCODEBUILD_RAW=1  pass everything through, transcript included
#        OPENSKY_RUN_DIR           write into this run directory, not a new one
#        OPENSKY_MAX_ERRORS        unique errors to print (default 40)
#        OPENSKY_STALE_RETRIES     rebuilds after removing stale copies (default 1)
#        OPENSKY_RETRY_MINUTES     no new rebuild starts after this many minutes (default 15)
#        OPENSKY_MAKE_STARTED      epoch seconds when make started (make exports it)
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
phases="$run_dir/phases.tsv"
# The pipeline below runs xcodebuild in a subshell, so its exit status comes
# back through a file rather than $?. `set -o pipefail` is not in POSIX sh.
status_file="$(mktemp -t opensky-xcodebuild)"
shown_file="$(mktemp -t opensky-xcodebuild-shown)"
trap 'rm -f "$status_file" "$shown_file"; opensky_build_unlock' EXIT INT TERM

mark() {
    printf '%s %s\n' "$(date +%s)" "$1" >>"$phases"
}
[ -z "${OPENSKY_MAKE_STARTED:-}" ] || printf '%s make\n' "$OPENSKY_MAKE_STARTED" >>"$phases"
mark wrapper

# test-without-building compiles nothing, so it cannot meet a stale module.
compiles="yes"
case " $* " in
    *" test-without-building "*) compiles="" ;;
esac

run_once() {
    printf '0\n' >"$status_file"
    if [ "${OPENSKY_XCODEBUILD_RAW:-0}" = "1" ]; then
        { "$@" 2>&1 || printf '%s\n' "$?" >"$status_file"; } | tee "$log" \
            | xcodebuild_phase_marks "$phases"
    else
        { "$@" 2>&1 || printf '%s\n' "$?" >"$status_file"; } | tee "$log" \
            | xcodebuild_phase_marks "$phases" \
            | xcodebuild_summary "$root" | tee "$shown_file"
    fi
    mark end
    status="$(cat "$status_file")"
    printf '[INFO] phases: %s\n' "$(xcodebuild_phases "$phases")"
}

# The value after option $1 in the remaining arguments, or nothing.
arg_value() {
    option="$1"
    shift
    while [ "$#" -gt 1 ]; do
        if [ "$1" = "$option" ]; then
            printf '%s\n' "$2"
            return
        fi
        shift
    done
}

# The build's own tree, so a build into the index tree is checked there too.
derived_data="$(arg_value -derivedDataPath "$@")"

remove_stale() {
    stale="$(OPENSKY_DERIVED_DATA="${derived_data:-$OPENSKY_DERIVED_DATA}" \
        "$root/tools/stale-modules.sh" -d | tr '\n' ' ' | sed 's/ $//')"
    [ -n "$stale" ] || return 1
    printf '[INFO] removed stale module copies: %s\n' "$stale"
}

if [ -n "$compiles" ]; then
    opensky_build_lock
    remove_stale || true
fi
mark lock
started="$(date +%s)"
run_once "$@"
max_retries="${OPENSKY_STALE_RETRIES:-1}"
retry_seconds=$((${OPENSKY_RETRY_MINUTES:-15} * 60))
bundle="$(arg_value -resultBundlePath "$@")"
retry=0
while [ "$status" -ne 0 ] && [ -n "$compiles" ] && [ "$retry" -lt "$max_retries" ] \
    && remove_stale; do
    if [ $(($(date +%s) - started)) -ge "$retry_seconds" ]; then
        printf '[ERROR] stale-module rebuilds passed %s minutes; stopping\n' \
            "${OPENSKY_RETRY_MINUTES:-15}"
        break
    fi
    retry=$((retry + 1))
    printf '[INFO] build %s of %s after removing stale modules\n' "$retry" "$max_retries"
    log="$run_dir/$name-retry$retry.log"
    phases="$run_dir/phases-retry$retry.tsv"
    mark wrapper
    mark lock
    # xcodebuild refuses an existing -resultBundlePath, and the failed pass
    # already wrote one there.
    case "$bundle" in
        *.xcresult) rm -rf "$bundle" ;;
    esac
    run_once "$@"
done

if [ "$status" -ne 0 ] && [ "${OPENSKY_XCODEBUILD_RAW:-0}" != "1" ] \
    && ! grep -qE 'error: |failed|errored|^✘' "$shown_file"; then
    printf '[INFO] no diagnostic matched; last 40 transcript lines:\n'
    tail -n 40 "$log"
fi
printf '[INFO] full transcript: %s\n' "$log"
exit "$status"
