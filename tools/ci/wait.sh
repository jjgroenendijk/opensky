#!/bin/sh
# Wait for the CI run of a pull request's last push, then print each job's result and
# the [FAIL], [ERROR], and compiler error lines of the failed jobs. A session then
# neither writes its own wait loop nor searches the job logs by hand.
# Usage: tools/ci/wait.sh [PR]   the pull request of the current branch by default
set -eu

# shellcheck disable=SC2086 # no argument means the current branch's pull request
pr="$(gh pr view ${1:-} --json number,headRefOid -q '"\(.number) \(.headRefOid)"')"
number="${pr% *}"
sha="${pr#* }"

# The run appears some seconds after the push, and `gh pr checks --watch` ends at once
# when it sees no run yet.
tries=0
until run="$(gh run list --workflow ci.yml --commit "$sha" --event pull_request \
    --json databaseId -q '.[0].databaseId // empty')" && [ -n "$run" ]; do
    tries=$((tries + 1))
    if [ "$tries" -gt 30 ]; then
        echo "[ERROR] no CI run for commit $sha of pull request #$number after 5 minutes" >&2
        exit 2
    fi
    sleep 10
done

until [ "$(gh run view "$run" --json status -q .status)" = completed ]; do
    gh run watch "$run" --interval 20 >/dev/null 2>&1 || sleep 20
done

gh run view "$run" --json jobs -q '.jobs[] | "[\(.conclusion)] \(.name)"'
conclusion="$(gh run view "$run" --json conclusion -q .conclusion)"
if [ "$conclusion" = success ]; then
    echo "[ OK ] CI passed for pull request #$number (run $run)"
    exit 0
fi
if [ "$conclusion" = cancelled ]; then
    echo "[FAIL] CI run $run was cancelled, usually by a newer push: run this again"
    exit 1
fi
# A log line is "job<TAB>step<TAB>timestamp message"; the paths are the runner's checkout.
gh run view "$run" --log-failed 2>/dev/null | cut -f1,3- \
    | sed -E 's/	[0-9TZ:.-]+ /: /; s#/[^ :]*/opensky/opensky/##g' \
    | grep -E '\[FAIL\]|\[ERROR\]|error: ' | awk '!seen[$0]++' | head -n 60 || true
echo "[FAIL] CI $conclusion for pull request #$number. Every line: gh run view $run --log-failed"
exit 1
