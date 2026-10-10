#!/bin/sh
# Shell half of the Makefile's shared xcodebuild invocation (Makefile `xcb`).
# The scripts under tools/ run their own xcodebuild commands; without this they
# each re-derive the build cache path and the products directory, and they have
# drifted apart before. Sourced, never executed:
#
#   . "$root/tools/xcodebuild-lib.sh"
#
# Sets OPENSKY_CACHE_ROOT, OPENSKY_DERIVED_DATA, and XCODE_XCCONFIG_FILE (the
# Makefile exports them; this is the fallback for a script run directly from a
# shell) and provides:
#
#   xcodebuild_products_dir CONFIG   built-products directory for a macOS scheme
#   xcodebuild_summary ROOT          stdin -> each diagnostic once, errors capped
#   opensky_build_lock               wait for a build slot and this build tree
#   opensky_build_unlock             release both
#   xcodebuild_phase_marks FILE      stdin -> stdout, noting when each phase starts in FILE
#   xcodebuild_phases FILE           print one line with the length of each phase
# shellcheck shell=sh

: "${OPENSKY_CACHE_ROOT:=$HOME/Library/Caches/OpenSky}"
export OPENSKY_CACHE_ROOT
: "${OPENSKY_DERIVED_DATA:=$OPENSKY_CACHE_ROOT/$(basename "$(cd "$(dirname "$0")/.." && pwd)")}"
export OPENSKY_DERIVED_DATA
: "${XCODE_XCCONFIG_FILE:=$(cd "$(dirname "$0")/.." && pwd)/Config/Build/Overrides.xcconfig}"
export XCODE_XCCONFIG_FILE

# xcodebuild puts a macOS scheme's products at a fixed path under the derived
# data root, and reading it back with -showBuildSettings costs several seconds.
xcodebuild_products_dir() {
    printf '%s\n' "$OPENSKY_DERIVED_DATA/Build/Products/$1"
}

# Filter a transcript down to what a run has to show: diagnostics, the tests
# that did not pass, and the closing counts. xcodebuild repeats each diagnostic
# with colour codes, absolute paths, and an "(in target ...)" suffix, so the
# filter strips those, prints each line once, and caps errors, failed tests,
# and warnings. The full transcript stays in .logs/. $1 is the checkout root.
xcodebuild_summary() {
    awk -v root="$1/" -v max="${OPENSKY_MAX_ERRORS:-40}" '
        { gsub(/\033\[[0-9;]*m/, "") }
        # Every app-extension build step logs this; it is never the problem.
        /appintentsmetadataprocessor.*Metadata extraction skipped/ { next }
        /(error|warning): |^\*\*|^(Executed|Testing (failed|cancelled))|^Test ([Cc]ase|[Ss]uite) .* (failed|errored)|^✘/ {
            line = $0
            while (length(root) > 1 && (i = index(line, root)) > 0)
                line = substr(line, 1, i - 1) substr(line, i + length(root))
            gsub(/\/\^src\//, "", line)
            sub(/ \(in target .* from project .*\)$/, "", line)
            sub(/ on \047[^\047]*\047 \([0-9.]+ seconds\)$/, "", line)
            if (seen[line]++) next
            if (line ~ /error: |failed|errored|^✘/ && ++problems > max) { hidden++; next }
            if (line ~ /warning: / && ++warnings > 10) { quiet++; next }
            print line
            fflush()
        }
        END {
            if (hidden) printf "[INFO] %d more errors or failed tests not shown\n", hidden
            if (quiet) printf "[INFO] %d more warnings not shown\n", quiet
        }
    '
}

# A few builds at a time on this machine. Sessions in several worktrees each
# start their own build, and eleven at once were seen on eight cores and 16 GB:
# every one of them then swaps. OPENSKY_BUILD_SLOTS (default 2) sets how many
# run. A build also locks its own tree, because two builds into one derived data
# tree collide in xcodebuild's build database.
opensky_try_lock() {
    if mkdir "$1" 2>/dev/null; then
        printf '%s\n' "$$" >"$1/pid"
        return 0
    fi
    owner="$(cat "$1/pid" 2>/dev/null || true)"
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$1"
    fi
    return 1
}

# A lock is a directory, because mkdir is atomic. It holds the owner's pid; a
# lock whose owner is gone is taken over.
opensky_build_lock() {
    mkdir -p "$OPENSKY_CACHE_ROOT"
    slots="${OPENSKY_BUILD_SLOTS:-2}"
    tree_lock="$OPENSKY_DERIVED_DATA.build.lock"
    OPENSKY_BUILD_LOCK=""
    waited=0
    while :; do
        if opensky_try_lock "$tree_lock"; then
            slot=1
            while [ "$slot" -le "$slots" ]; do
                if opensky_try_lock "$OPENSKY_CACHE_ROOT/build.lock.$slot"; then
                    OPENSKY_BUILD_LOCK="$tree_lock $OPENSKY_CACHE_ROOT/build.lock.$slot"
                    return 0
                fi
                slot=$((slot + 1))
            done
            rm -rf "$tree_lock"
        fi
        if [ "$((waited % 30))" -eq 0 ]; then
            printf '[INFO] waiting for one of %s build slots or for this tree, held by:\n' \
                "$slots"
            for held in "$tree_lock" "$OPENSKY_CACHE_ROOT"/build.lock.*; do
                owner="$(cat "$held/pid" 2>/dev/null || true)"
                [ -n "$owner" ] || continue
                printf '[INFO]   pid %s (%s)\n' \
                    "$owner" "$(ps -o command= -p "$owner" 2>/dev/null | cut -c1-80)"
            done
        fi
        sleep 2
        waited=$((waited + 2))
    done
}

opensky_build_unlock() {
    [ -n "${OPENSKY_BUILD_LOCK:-}" ] || return 0
    for held in $OPENSKY_BUILD_LOCK; do
        rm -rf "$held"
    done
    OPENSKY_BUILD_LOCK=""
}

# A run spends most of its time before the first compile, and the transcript
# has no clock. This stage passes the transcript through and appends
# "<epoch> <phase>" to $1 at the line that starts each phase: resolve (package
# graph), plan (build description), build (first task). The test runner's own
# output is buffered until the end, so the test phase comes from xcodebuild's
# "elapsed -- Testing started" line, which carries the test time in seconds.
xcodebuild_phase_marks() {
    awk -v out="$1" '
        function mark(phase, extra,    cmd, now) {
            cmd = "date +%s"
            cmd | getline now
            close(cmd)
            printf "%s %s%s\n", now, phase, extra >> out
            close(out)
        }
        /^Command line invocation:/ { mark("xcodebuild") }
        /^Resolve Package Graph/ { mark("resolve") }
        /^Resolved source packages:/ { mark("plan") }
        /^Build description path:/ { mark("build") }
        match($0, /[0-9.]+ elapsed -- Testing started/) {
            mark("tested", " " substr($0, RSTART, RLENGTH - 27))
        }
        { print; fflush() }
    '
}

# One line from the marks file: how long make, the lock wait, xcodebuild
# start-up, package resolution, planning, the build, and the tests each took.
# A phase whose start was never seen is left out.
xcodebuild_phases() {
    sort -n "$1" | awk '
        { if (!($2 in t)) t[$2] = $1; if ($2 == "tested") tested += $3 }
        function span(from, to) { return (from in t && to in t) ? t[to] - t[from] : -1 }
        function show(name, seconds) {
            if (seconds < 0) return
            line = line sprintf("%s%s %ds", sep, name, seconds)
            sep = ", "
        }
        END {
            show("make", span("make", "wrapper"))
            show("lock", span("wrapper", "lock"))
            show("start", span("lock", "resolve"))
            show("resolve", span("resolve", "plan"))
            show("plan", span("plan", "build"))
            if ("build" in t && "end" in t) show("build", t["end"] - t["build"] - tested)
            if (tested) show("test", tested)
            if ("wrapper" in t && "end" in t) printf "%s (total %ds)\n", line, t["end"] - t["wrapper"]
        }
    '
}
