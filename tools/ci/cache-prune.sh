#!/bin/sh
# Delete one ref's GitHub Actions caches, so old entries do not push new ones
# out of the 10 GB limit. PREFIX limits it to keys starting with it; KEEP is a
# key to leave, normally the entry this run just saved.
# Usage: tools/ci/cache-prune.sh REF [PREFIX [KEEP]]
# Env:   GH_TOKEN with actions:write, GH_REPO as owner/name
set -eu
if [ "$#" -lt 1 ]; then
    echo "[ERROR] usage: tools/ci/cache-prune.sh REF [PREFIX [KEEP]]" >&2
    exit 2
fi
ref="$1"
prefix="${2:-}"
keep="${3:-}"
gh cache list --ref "$ref" ${prefix:+--key "$prefix"} --limit 100 --json id,key \
    --jq ".[] | select(.key != \"$keep\") | \"\(.id) \(.key)\"" |
    while read -r id key; do
        # A fork's pull request gets a read-only token, so a failed delete only warns.
        if gh cache delete "$id" >/dev/null; then
            echo "[INFO] deleted cache $key"
        else
            echo "[WARNING] could not delete cache $key"
        fi
    done
