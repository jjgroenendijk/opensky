#!/bin/sh
# Claude Code PreToolUse hook for Bash: refuse a command that polls with sleep.
# Sessions ran `sleep N && tail log` hundreds of times in three weeks. Each one
# is a turn that re-reads the whole context and still waits. The right loop is
# a background command and the completion notification. Exit 2 blocks the call
# and shows the message to the agent.
set -eu

command="$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))' 2>/dev/null || true)"
case " $command " in
    *" sleep "* | *"(sleep "*)
        cat >&2 <<'MSG'
[BLOCKED] Do not poll with sleep. Start the long command with run_in_background
and wait for its completion notification; `gh pr checks <n> --watch` waits for CI.
MSG
        exit 2
        ;;
esac
exit 0
