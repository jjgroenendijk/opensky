#!/bin/sh
# Keeps one issue in step with the weekly checks (docs/tools/ci.md#weekly).
# A failed run opens the issue, or comments on the open one. A green run closes it.
#
# Usage: tools/ci/weekly-issue.sh RESULT RUN_URL
# RESULT is the `needs.<job>.result` of the checks: success, failure, or cancelled.
# Needs GH_TOKEN with issues: write, and GH_REPO.
set -eu

[ "$#" -eq 2 ] || { echo "[ERROR] usage: weekly-issue.sh RESULT RUN_URL" >&2; exit 2; }
result="$1"
run_url="$2"
title="Weekly checks fail on main"

open_issue="$(gh issue list --state open --label bug --label code-health \
  --search "\"$title\" in:title" --json number,title \
  --jq "map(select(.title == \"$title\")) | first | .number // empty")"

case "$result" in
  success)
    if [ -n "$open_issue" ]; then
      gh issue close "$open_issue" --comment "The weekly checks passed again: $run_url"
      echo "[INFO] closed #$open_issue"
    else
      echo "[INFO] weekly checks passed; no open issue"
    fi
    ;;
  failure)
    body="The weekly checks failed: $run_url

The run page names the failed job, and the artifact of each job holds its \`.logs/\` output."
    if [ -n "$open_issue" ]; then
      gh issue comment "$open_issue" --body "$body"
      echo "[INFO] commented on #$open_issue"
    else
      gh issue create --title "$title" --label bug --label code-health --body "$body"
    fi
    ;;
  *)
    echo "[INFO] weekly checks ended as $result; issue unchanged"
    ;;
esac
