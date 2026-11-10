#!/bin/sh
# Give every tracked file one fixed modification time, so a build tree restored from
# another checkout sees the unchanged files as unchanged. A fresh checkout writes each
# file now, which would make the build compile everything again. With BASE, the
# commit the restored tree was built from, the files that differ from it get the
# current time, so the build compiles exactly those.
# Usage: tools/ci/source-times.sh [BASE]
set -eu
cd "$(git rev-parse --show-toplevel)"
base="${1:-}"
git ls-files -z | xargs -0 touch -h -t 200001010000
echo "[INFO] tracked files set to 2000-01-01"
[ -n "$base" ] || exit 0
if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    git fetch --quiet --depth=1 origin "$base" || {
        echo "[WARNING] cannot fetch $base; the build compiles everything" >&2
        git ls-files -z | xargs -0 touch -h
        exit 0
    }
fi
changed="$(git diff --name-only --no-renames "$base" HEAD -- | while read -r path; do
    [ -e "$path" ] && touch -h "$path" && echo "$path"
done | wc -l | tr -d ' ')"
echo "[INFO] $changed files changed since $base"
