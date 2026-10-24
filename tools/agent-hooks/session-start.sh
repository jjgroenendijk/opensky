#!/bin/sh
# Claude Code SessionStart hook: give a new worktree a clone of the newest build
# tree before its first build (tools/seed-build-tree.sh). The clone takes a few
# seconds, so it runs detached and the session starts at once. A build that
# starts meanwhile waits on the tree's lock.
set -eu

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
if [ -x "$root/tools/seed-build-tree.sh" ]; then
    mkdir -p "$root/.logs/seed-build-tree"
    nohup make -C "$root" seed-build-tree \
        >"$root/.logs/seed-build-tree/session-start.log" 2>&1 &
fi
exit 0
