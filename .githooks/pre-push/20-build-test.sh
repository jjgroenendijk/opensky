#!/bin/sh
# Build + test before push so main-bound PRs stay green (AGENTS.md "Git workflow").
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
hook_info "build + test before push (set OPENSKY_SKIP_BUILD=1 to skip)"
make -C "$ROOT" test
# Build the CLI too: app-only source files silently entering the openskycli
# target (Xcode filesystem-synced groups default new files into every target)
# have broken `make cli` on main more than once, caught only by the next
# milestone's session. CI is suspended, so this hook is the only gate.
hook_info "build openskycli (catches app/CLI target-membership regressions)"
make -C "$ROOT" cli
hook_ok "build + test + cli passed"
