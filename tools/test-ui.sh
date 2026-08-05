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
# Env:   OPENSKY_RESULT_BUNDLE  optional -resultBundlePath target, overriding
#                               the run directory under build/test-results
set -eu

project="$1"
scheme="$2"
destination="$3"
shift 3

# Same build cache the Makefile uses (Makefile DERIVED_DATA).
root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"
derived_data="$OPENSKY_DERIVED_DATA"

# One run, one directory (issue #347): the transcript below and the runner's
# own output land in it, and `logs/test-ui/latest` points at this run.
run_dir="$("$root/tools/run-dir.sh" test-ui)"
OPENSKY_RUN_DIR="$run_dir"
export OPENSKY_RUN_DIR
printf '[INFO] run directory: %s\n' "$run_dir"

# The result bundle is a separate tree because xcresult bundles are large and
# `make test-report` looks for the newest one; it follows the same shape.
bundle="${OPENSKY_RESULT_BUNDLE:-}"
if [ -z "$bundle" ]; then
    bundle="$("$root/tools/run-dir.sh" -b build/test-results test-ui)/ui.xcresult"
else
    rm -rf "$bundle"
    mkdir -p "$(dirname "$bundle")"
fi
bundle_flag="-resultBundlePath $bundle"

# Through the shared runner (Makefile XCB_RUN), so the transcript lands in the
# run directory and stdout stays readable; the runner prints the whole log
# when the run fails, which is also where the grep below reads from.
log="$run_dir/test-ui.log"
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
