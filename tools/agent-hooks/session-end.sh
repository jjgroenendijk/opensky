#!/bin/sh
# Claude Code SessionEnd hook: stop this session's language server and prune
# the caches of removed worktrees.
#
# The swift-lsp plugin starts one sourcekit-lsp per session, and each one keeps a
# SourceKitService alive. Seven were found running for sessions that had ended,
# on a machine with 16 GB. The hook runs as a child of the session's process, so
# its parent pid is the session: every sourcekit-lsp with that parent is this
# session's. A sourcekit-lsp whose parent is gone belongs to no session at all.
#
# The prune runs detached, because its size report walks tens of gigabytes on an
# external volume and the hook should return at once.
set -eu

session="$PPID"
ps -axo pid=,ppid=,comm= | awk -v session="$session" '
    $3 ~ /sourcekit-lsp$/ && ($2 == session || $2 == 1) { print $1 }
' | while read -r pid; do
    kill "$pid" 2>/dev/null || true
done

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
if [ -x "$root/tools/prune.sh" ]; then
    mkdir -p "$root/.logs/prune"
    nohup "$root/tools/prune.sh" >"$root/.logs/prune/session-end.log" 2>&1 &
fi
exit 0
