#!/bin/sh
# Run the UI test target, but turn the machine's known TCC failure mode into an
# actionable message instead of an opaque multi-minute hang.
#
# On this machine `make test-ui` reliably dies at harness init with "Timed out
# while enabling automation mode" (a TCC/automation-permission gap, not a code
# fault — see docs/testing.md). Sessions burned minutes rediscovering that each
# time. This wrapper runs the tests, and if that specific failure appears it
# prints the one-time remedy (`make test-perms`) and the offscreen-render
# alternative rather than leaving a bare non-zero exit.
#
# Usage: tools/test-ui.sh PROJECT SCHEME DESTINATION [extra xcodebuild args...]
# Env:   OPENSKY_RESULT_BUNDLE  optional -resultBundlePath target
set -eu

project="$1"
scheme="$2"
destination="$3"
shift 3

bundle_flag=""
if [ -n "${OPENSKY_RESULT_BUNDLE:-}" ]; then
    rm -rf "$OPENSKY_RESULT_BUNDLE"
    mkdir -p "$(dirname "$OPENSKY_RESULT_BUNDLE")"
    bundle_flag="-resultBundlePath $OPENSKY_RESULT_BUNDLE"
fi

# Same build cache the Makefile uses (Makefile DERIVED_DATA).
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"
derived_data="$OPENSKY_DERIVED_DATA"

# Through the shared runner (Makefile XCB_RUN), so the transcript lands in
# logs/test-ui.log and stdout stays readable; the runner prints the whole log
# when the run fails, which is also where the grep below reads from.
log="$root/logs/test-ui.log"
status=0
# shellcheck disable=SC2086  # bundle_flag + passthrough flags are word-split on purpose
"$root/tools/xcodebuild-run.sh" test-ui \
    xcodebuild -project "$project" -scheme "$scheme" -destination "$destination" \
    -derivedDataPath "$derived_data" \
    $bundle_flag "$@" -only-testing:openskyUITests test || status=$?

if [ "$status" -ne 0 ] && grep -q "enabling automation mode" "$log"; then
    cat >&2 <<'MSG'

[WARNING] UI tests failed at harness init: "enabling automation mode" timed out.
          This is the known TCC/automation gap on this machine, not a test fault.
          Fix once:   make test-perms   (grants Automation + Full Disk Access)
          Meanwhile:  verify render behavior via Renderer.renderOffscreen unit
                      tests or `make run-cli ARGS="render ..."` (see docs/testing.md).
MSG
    exit 3
fi
exit "$status"
