#!/bin/sh
# No new unused code (docs/decisions/code-smell-scans.md). Periphery reads the
# compiler's index store, so `make dead-code` first runs `make verify-build`:
# incremental builds of the app, openskycli, and both unit bundles. No test runs
# here; what to test is the author's call (testing-and-verifying skill).
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

[ -d "$ROOT/opensky.xcodeproj" ] || { hook_warn "no Xcode project -> skipping dead-code scan"; exit 0; }

require_tool xcodebuild
require_tool periphery
hook_info "build the index, then scan for new unused code (Periphery, against the baseline)"
make -s -C "$ROOT" dead-code
