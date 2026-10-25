#!/bin/sh
# Plans and publishes the nightly preview release (docs/tools/releases.md).
# `plan` prints GitHub step outputs: publish=true|false, tag, sha, and the
# previous preview tag. It takes the newest main commit whose Lint check passed,
# because a later push cancels the run on an older one. It skips when the last
# preview already holds that commit. It needs the checkout's first-parent history.
# `publish DMG` creates the pre-release from those outputs, passed as env.
#
# Usage: tools/ci/preview-release.sh plan
#        TAG=... SHA=... PREVIOUS=... tools/ci/preview-release.sh publish DMG
set -eu
: "${GH_REPO:?GH_REPO is unset: this script runs on a CI runner}"

version=$(awk -F' = ' '/^MARKETING_VERSION/ { print $2 }' config/Build/Base.xcconfig)
[ -n "$version" ] || { echo "[ERROR] no MARKETING_VERSION in config/Build/Base.xcconfig" >&2; exit 1; }

case "${1:-}" in
plan)
    sha=""
    for commit in $(git log --first-parent --format=%H -n 30); do
        lint=$(gh api "repos/$GH_REPO/commits/$commit/check-runs?check_name=Lint" \
            --jq '[.check_runs[].conclusion] | index("success") != null')
        if [ "$lint" = true ]; then sha=$commit; break; fi
    done
    [ -n "$sha" ] || { echo "[ERROR] no main commit with a passing Lint in the last 30" >&2; exit 1; }
    previous=$(gh release list --limit 200 --json tagName --jq '.[].tagName' \
        | grep -E "^v${version}-preview\.[0-9]+$" | sort -t. -k4 -n | tail -n 1 || true)
    number=$(( ${previous##*.} + 0 ))
    publish=true
    if [ -n "$previous" ]; then
        released=$(gh api "repos/$GH_REPO/commits/$previous" --jq .sha)
        if git merge-base --is-ancestor "$sha" "$released" 2>/dev/null; then
            echo "[INFO] $previous ($released) already holds $sha" >&2
            publish=false
        fi
    fi
    echo "publish=$publish"
    echo "sha=$sha"
    echo "tag=v${version}-preview.$((number + 1))"
    echo "previous=$previous"
    ;;
publish)
    dmg="${2:?usage: publish DMG}"
    : "${TAG:?}" "${SHA:?}"
    # The release list cuts long titles, so the title starts with what differs.
    title="Nightly $(date -u +%Y-%m-%d)"
    same_day=$(gh release list --limit 200 --json name --jq '.[].name' | grep -c "^$title" || true)
    [ "$same_day" -eq 0 ] || title="$title ($((same_day + 1)))"
    # A first preview of a version has no previous tag, so GitHub picks the start.
    gh release create "$TAG" --prerelease --target "$SHA" \
        --title "$title" \
        --notes-file .github/preview-release-notes.md --generate-notes \
        ${PREVIOUS:+--notes-start-tag "$PREVIOUS"} \
        "$dmg"
    # Keep the newest 20 previews. Only pre-releases with a preview tag are pruned.
    gh release list --limit 200 --json tagName,isPrerelease,createdAt --jq \
        '[.[] | select(.isPrerelease and (.tagName | test("-preview\\.[0-9]+$")))]
         | sort_by(.createdAt) | reverse | .[20:] | .[].tagName' \
        | while read -r old; do
            echo "[INFO] deleting $old: not among the newest 20 previews" >&2
            gh release delete "$old" --cleanup-tag --yes
        done
    ;;
*)
    echo "[ERROR] usage: tools/ci/preview-release.sh plan|publish DMG" >&2
    exit 2
    ;;
esac
