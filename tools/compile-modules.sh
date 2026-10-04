#!/bin/sh
# Compile package modules with `swift build`, without Xcode, the app, or the
# test hosts: the quick check while fixing compile errors. The modules are the
# ones named, or else the ones the branch changed, plus every package target
# that depends on them, test targets included, since an interface change
# breaks those first. It builds only the top of that set, since each build
# pulls in what it depends on, and keeps going after a failure so one run shows
# every broken target.
#
# Usage: tools/compile-modules.sh [MODULE...]
# Env:   OPENSKY_COMPILE_MAX  more top targets than this builds the whole
#                             package instead (default 12)
#
# Xcode-only code (the app, the CLI, OpenSkyTests, the real-data and UI tests)
# is not a package target; make build-app, build-cli, or build-tests covers it.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"

run_dir="$("$root/tools/run-dir.sh" compile)"
graph="$run_dir/graph.txt"
# One "target dependency" line per edge, and "target -" for every target.
swift package dump-package | jq -r '
    .targets[] | .name as $t
    | ("\($t) -"),
      (.dependencies[] | (.target // .byName // empty)[0] | "\($t) \(.)")
' >"$graph"

if [ "$#" -gt 0 ]; then
    wanted="$*"
else
    base="$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
    wanted="$(
        { git diff --name-only "$base"; git ls-files --others --exclude-standard; } |
            sed -En 's#^(Sources|Tests)/([^/]+)/.*#\2#p' | sort -u |
            while read -r dir; do
                if grep -q "^$dir -$" "$graph"; then
                    printf '%s ' "$dir"
                else
                    printf '[INFO] %s is Xcode-only; make build-app, build-cli, or build-tests compiles it\n' "$dir" >&2
                fi
            done
    )"
fi
if [ -z "$wanted" ]; then
    echo "[ OK ] no changed package module to compile"
    exit 0
fi
for module in $wanted; do
    if ! grep -q "^$module -$" "$graph"; then
        echo "[ERROR] $module is not a package target" >&2
        exit 2
    fi
done

# The wanted modules plus everything that depends on them, then the top of
# that set: members no other member depends on.
tops="$(awk -v wanted="$wanted" '
    $2 != "-" { users[$2] = users[$2] " " $1; edges[NR] = $0 }
    END {
        n = split(wanted, queue, " ")
        for (i = 1; i <= n; i++) closure[queue[i]] = 1
        for (i = 1; i <= n; i++) {
            m = split(users[queue[i]], next_, " ")
            for (j = 1; j <= m; j++)
                if (!(next_[j] in closure)) { closure[next_[j]] = 1; queue[++n] = next_[j] }
        }
        for (e in edges) {
            split(edges[e], pair, " ")
            if ((pair[1] in closure) && (pair[2] in closure)) used[pair[2]] = 1
        }
        for (t in closure) if (!(t in used)) print t
    }
' "$graph" | sort)"
count="$(printf '%s\n' "$tops" | wc -l | tr -d ' ')"

log="$run_dir/compile.log"
status=0
if [ "$count" -gt "${OPENSKY_COMPILE_MAX:-12}" ]; then
    printf '[INFO] %s top targets depend on %s; building the whole package\n' "$count" "$wanted"
    swift build --build-tests >"$log" 2>&1 || status=$?
else
    for target in $tops; do
        printf '[INFO] swift build --target %s\n' "$target"
        swift build --target "$target" >>"$log" 2>&1 || status=$?
    done
fi
# swift build adds a source excerpt under each error and a long compiler
# command line per failed file; the error lines alone say the same.
xcodebuild_summary "$root" <"$log" |
    grep -vE '^[[:space:]]*\||nonzero exit code|^error: Build failed' || true
printf '[INFO] full transcript: %s\n' "$log"
if [ "$status" -ne 0 ]; then
    echo "[ERROR] compile failed" >&2
    exit "$status"
fi
echo "[ OK ] compiled $wanted and its dependents"
