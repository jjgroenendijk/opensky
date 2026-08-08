#!/bin/sh
# Run the UI test target, turning a missing Accessibility grant into an
# actionable message instead of an opaque multi-minute hang.
#
# The plan selection is load-bearing (issue #380). `openskyTests` and
# `openskyRealDataTests` are both app-hosted: their test host *is* opensky.app.
# Put either in the same test session as the UI
# runner and xcodebuild stands the app up as a test host, injecting
# libXCTestBundleInject.dylib, so the app sits in
# -[XCTestDriver _prepareTestConfigurationAndIDESession] waiting for an IDE
# session that belongs to the runner while the runner waits for the app to enter
# automation mode. Neither moves and XCTest gives up after 60s with "Timed out
# while enabling automation mode" — which reads like a permission failure but is
# a deadlock, and is why `make test-ui` never once reached a test case.
# `-only-testing:` does not avoid it: it filters which tests run, not which
# targets the session stands up. The UITests plan, which lists openskyUITests
# alone, does.
#
# With that fixed the runner really does request kTCCServiceAccessibility, and a
# missing grant produces the same error string for a genuine reason. That case
# points at `make test-perms`.
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
    $bundle_flag "$@" -testPlan UITests test || status=$?

if [ "$status" -ne 0 ] && grep -q "enabling automation mode" "$log"; then
    cat >&2 <<'MSG'

[WARNING] UI tests failed at harness init: "enabling automation mode" timed out.
          The runner asked macOS for Accessibility and did not get an answer.
          Fix once:   make test-perms
          Then grant: System Settings > Privacy & Security > Accessibility >
                      openskyUITests-Runner.app
          The grant is keyed to the runner's code signature, so it is one click
          per signature, not per run. Meanwhile, verify render behavior via
          Renderer.renderOffscreen unit tests or `make run-cli ARGS="render ..."`
          (see docs/testing.md).
MSG
    exit 3
fi
exit "$status"
