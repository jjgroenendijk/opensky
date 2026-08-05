#!/bin/sh
# make prune — delete the build cache and run output nothing needs any more
# (issue #347). Four kinds of garbage, all of them gitignored:
#
#   1. DerivedData (and build/) inside a linked checkout whose worktree is gone.
#      Each one runs to tens of gigabytes and outlives the branch it was built
#      for, which is what fills the data volume mid-session.
#   2. build/install, the separate Release tree older checkouts installed from.
#   3. Result bundles and log run directories past the retention age, keeping
#      the newest run of each script so `latest` always resolves.
#   4. Loose pre-convention files left directly under logs/.
#
# Sources are never touched: the plan is built from a fixed set of cache and
# output path shapes, every entry is checked to live inside this checkout or a
# sibling worktree, and the whole plan is printed before anything is deleted.
#
# Usage: tools/prune.sh [--days N] [--dry-run]
set -eu

days=14
dry_run=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --days)
            [ "$#" -ge 2 ] || { echo "[ERROR] --days needs a number" >&2; exit 2; }
            days="$2"
            shift 2
            ;;
        --dry-run | -n)
            dry_run=1
            shift
            ;;
        *)
            echo "[ERROR] usage: tools/prune.sh [--days N] [--dry-run]" >&2
            exit 2
            ;;
    esac
done
case "$days" in
    '' | *[!0-9]*)
        echo "[ERROR] --days takes a whole number of days, got: $days" >&2
        exit 2
        ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
# In the main checkout this is the checkout itself; in a linked worktree it is
# the main checkout, which is where .claude/worktrees/ lives.
main="$(cd "$(dirname "$(git -C "$root" rev-parse --git-common-dir)")" && pwd)"
worktree_home="$main/.claude/worktrees"
cutoff="$(date -u -v-"${days}"d +%Y%m%dT%H%M%SZ)"

plan="$(mktemp -t opensky-prune)"
live="$(mktemp -t opensky-prune-live)"
scratch="$(mktemp -t opensky-prune-scratch)"
trap 'rm -f "$plan" "$live" "$scratch"' EXIT INT TERM

# One plan entry: a reason for the report and the path to delete. The path has
# to exist, must not be the checkout itself, and must sit inside this checkout
# or the worktree home — anything else is a bug in a rule below, not something
# to delete anyway.
add() {
    [ -e "$2" ] || return 0
    if [ "$2" = "$root" ] || [ "$2" = "$main" ] || [ "$2" = "$worktree_home" ]; then
        printf '[ERROR] refusing to prune a checkout root: %s\n' "$2" >&2
        exit 1
    fi
    case "$2" in
        "$root"/* | "$worktree_home"/*) ;;
        *)
            printf '[ERROR] refusing to prune outside the checkout: %s\n' "$2" >&2
            exit 1
            ;;
    esac
    printf '%s\t%s\n' "$1" "$2" >>"$plan"
}

# True when STAMP is strictly older than the retention cutoff. Both are UTC
# timestamps from tools/run-dir.sh, so string order is time order.
older_than_cutoff() {
    [ "$1" != "$cutoff" ] || return 1
    [ "$(printf '%s\n%s\n' "$1" "$cutoff" | sort | head -1)" = "$1" ]
}

# A run directory is named by tools/run-dir.sh and nothing else. `latest` and
# anything a pre-convention run left at this level (the innards of a loose
# .xcresult, say) fail this and are never considered for deletion here.
is_run_stamp() {
    case "$1" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) return 0 ;;
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Age out the run directories under BASE/<name>/<stamp>, keeping the newest run
# of every name so the `latest` symlink still resolves after a prune.
prune_run_dirs() {
    base="$1"
    reason="$2"
    [ -d "$base" ] || return 0
    for name_dir in "$base"/*; do
        [ -d "$name_dir" ] || continue
        newest=""
        for run in "$name_dir"/*; do
            stamp="$(basename "$run")"
            is_run_stamp "$stamp" || continue
            [ -d "$run" ] || continue
            newest="$stamp"
        done
        for run in "$name_dir"/*; do
            stamp="$(basename "$run")"
            is_run_stamp "$stamp" || continue
            [ "$stamp" != "$newest" ] || continue
            [ -d "$run" ] || continue
            older_than_cutoff "$stamp" || continue
            add "$reason" "$run"
        done
    done
}

# 1. Caches belonging to worktrees git no longer knows about. A removed
#    worktree often leaves its directory behind precisely because DerivedData
#    is untracked, so the multi-gigabyte part is what git's own prune skips.
git -C "$root" worktree list --porcelain \
    | sed -n 's/^worktree //p' >"$live"
if [ -d "$worktree_home" ]; then
    for checkout in "$worktree_home"/*; do
        [ -d "$checkout" ] || continue
        if grep -qxF "$checkout" "$live"; then continue; fi
        add "stale worktree cache" "$checkout/DerivedData"
        add "stale worktree output" "$checkout/build"
        add "stale worktree output" "$checkout/logs"
    done
fi

# 2. The private Release tree `make install` used before it started sharing the
#    main derived-data cache.
add "obsolete install tree" "$root/build/install"

# 3. Result bundles and log runs past the retention age.
prune_run_dirs "$root/build/test-results" "aged-out result bundle"
prune_run_dirs "$root/logs" "aged-out run output"
# Bundles written straight into build/test-results predate the run-directory
# convention; nothing points at them and every one is a full test result.
for bundle in "$root"/build/test-results/*.xcresult; do
    [ -e "$bundle" ] || continue
    add "pre-convention result bundle" "$bundle"
done

# 4. Loose files directly under logs/, from before the convention. Aged the
#    same way, by modification time since they carry no timestamp in the name.
if [ -d "$root/logs" ]; then
    find "$root/logs" -mindepth 1 -maxdepth 1 -type f -mtime "+$days" \
        >"$scratch" 2>/dev/null || : >"$scratch"
    while IFS= read -r loose; do
        [ -n "$loose" ] || continue
        add "pre-convention log file" "$loose"
    done <"$scratch"
fi

if [ ! -s "$plan" ]; then
    printf '[ OK ] nothing to prune (retention %s days)\n' "$days"
    exit 0
fi

printf '[INFO] prune plan (retention %s days, cutoff %s):\n' "$days" "$cutoff"
total_kb=0
tab="$(printf '\t')"
while IFS="$tab" read -r reason path; do
    size="$(du -sh "$path" 2>/dev/null | awk '{print $1}')"
    kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    total_kb=$((total_kb + ${kb:-0}))
    printf '  %8s  %s (%s)\n' "${size:-?}" "$path" "$reason"
done <"$plan"

human="$(awk -v kb="$total_kb" 'BEGIN {
    if (kb >= 1048576) printf "%.1f GB", kb / 1048576
    else if (kb >= 1024) printf "%.1f MB", kb / 1024
    else printf "%d KB", kb
}')"

if [ "$dry_run" -eq 1 ]; then
    printf '[INFO] --dry-run: nothing deleted (%s would be freed)\n' "$human"
    exit 0
fi

while IFS="$tab" read -r reason path; do
    rm -rf "$path"
done <"$plan"

# A pruned run can leave `latest` pointing at nothing; drop those symlinks so a
# dangling link never reads as "the newest run is missing".
for base in "$root/logs" "$root/build/test-results"; do
    [ -d "$base" ] || continue
    for name_dir in "$base"/*; do
        link="$name_dir/latest"
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            rm -f "$link"
        fi
    done
done

printf '[ OK ] pruned, freed %s\n' "$human"
