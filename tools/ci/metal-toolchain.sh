#!/bin/sh
# Download the Metal Toolchain on a CI runner while other steps run.
# `start` launches the download and returns at once. `wait` blocks until it
# ends, prints its output, and exits with its status. The shaders need the
# toolchain, so `wait` goes before the first build.
#
# Usage: tools/ci/metal-toolchain.sh start|wait
set -eu
dir="${RUNNER_TEMP:?RUNNER_TEMP is unset: this script runs on a CI runner}/metal-toolchain"
case "${1:-}" in
start)
    rm -rf "$dir"
    mkdir -p "$dir"
    # Detached from the step's output, or the runner waits for it to close.
    nohup "$0" download </dev/null >/dev/null 2>&1 &
    echo "[INFO] Metal Toolchain download started"
    ;;
download)
    status=0
    xcodebuild -downloadComponent MetalToolchain >"$dir/log" 2>&1 || status=$?
    echo "$status" >"$dir/status"
    ;;
wait)
    [ -d "$dir" ] || {
        echo "[ERROR] no download was started: run '$0 start' first" >&2
        exit 1
    }
    while [ ! -f "$dir/status" ]; do sleep 1; done
    cat "$dir/log"
    exit "$(cat "$dir/status")"
    ;;
*)
    echo "[ERROR] usage: $0 start|wait" >&2
    exit 2
    ;;
esac
