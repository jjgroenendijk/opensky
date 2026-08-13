#!/bin/sh
# Build + test before push so main-bound PRs stay green (commit skill).
# OPENSKY_SKIP_BUILD=1 skips this gate; the protected-branch guard always runs.
set -eu
# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/.githooks/lib.sh"

if [ "${OPENSKY_SKIP_BUILD:-0}" = "1" ]; then
  hook_warn "OPENSKY_SKIP_BUILD=1 -> skipping build/test gate"
  exit 0
fi
[ -d "$ROOT/opensky.xcodeproj" ] || { hook_warn "no Xcode project -> skipping build/test"; exit 0; }

require_tool xcodebuild

# Skip the gate when this exact tree content already passed it (issue #417):
# `make test` and `make cli` stamp their green runs with the tested tree hash,
# and the common flow — run both, commit, push — would otherwise pay the whole
# gate a second time for an identical tree. Dirty tree, missing stamp, or any
# content change falls through to the full gate.
if sh "$ROOT/tools/green-stamp.sh" check test cli realdata-build 2>/dev/null; then
  hook_ok "gate already green for this exact tree -> skipping build/test"
  exit 0
fi

hook_info "build + test before push (set OPENSKY_SKIP_BUILD=1 to skip)"
make -C "$ROOT" test
# Build the CLI too: app-only source files silently entering the openskycli
# target (Xcode filesystem-synced groups default new files into every target)
# have broken `make cli` on main more than once, caught only by the next
# milestone's session. CI is suspended, so this hook is the only gate.
hook_info "build openskycli (catches app/CLI target-membership regressions)"
make -C "$ROOT" cli
# Compile the real-data suites too, without running them (issue #457). The
# UnitTests plan does not carry openskyRealDataTests, so a compile break there
# used to land on main and surface only when someone ran `make realtest`.
# Running those suites needs the user's install and stays off the push gate;
# compiling them does not.
hook_info "compile openskyRealDataTests (the unit plan never builds it)"
make -C "$ROOT" realdata-build
hook_ok "build + test + cli + realdata-build passed"
