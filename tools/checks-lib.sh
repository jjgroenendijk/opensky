# shellcheck shell=sh
# Shared by the scripts in tools/lint/ and tools/format/. Sourced, never run.
#
#   OPENSKY_TOOLS                 absolute path of tools/, from the real checkout
#   checks_swift_files           the Swift files to check: every one under src/ in
#                                CI or with OPENSKY_CHECK_ALL=1, else the branch's
#   self_check_tree              a new temp git repo for a self-check; prints its path
#   expect_failure SCRIPT TREE TEXT...
#                                run SCRIPT in TREE, which holds a violation; it must
#                                fail and print each TEXT, so a crash does not count
#
# A lint's self-check writes a small violation into a temp tree and runs the
# lint there, so a lint that silently stopped working fails `make check`.

OPENSKY_TOOLS="$(cd "$(dirname "$0")/.." && pwd)"
export OPENSKY_TOOLS

checks_swift_files() {
    if [ -n "${CI:-}" ] || [ -n "${OPENSKY_CHECK_ALL:-}" ]; then
        git ls-files -co --exclude-standard -- 'src/*.swift'
        return
    fi
    base="$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
    { git diff --name-only --diff-filter=AMR "$base" -- 'src/*.swift'
      git ls-files --others --exclude-standard -- 'src/*.swift'; } | sort -u \
        | while read -r file; do [ ! -f "$file" ] || printf '%s\n' "$file"; done
}

self_check_tree() {
    tree="$(mktemp -d -t opensky-self-check)"
    git -C "$tree" init -q
    printf '%s\n' "$tree"
}

expect_failure() {
    name="$(basename "$1" .sh)"
    script="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    git -C "$2" add -A
    if (cd "$2" && OPENSKY_CHECK_ALL=1 sh "$script") >"$2.out" 2>&1; then
        echo "[ERROR] $name self-check: the lint passed a planted violation" >&2
        sed 's/^/  /' "$2.out" >&2
        rm -rf "$2" "$2.out"
        exit 1
    fi
    tree="$2"
    shift 2
    for text in "$@"; do
        grep -qF -- "$text" "$tree.out" && continue
        echo "[ERROR] $name self-check: the lint failed without reporting: $text" >&2
        sed 's/^/  /' "$tree.out" >&2
        rm -rf "$tree" "$tree.out"
        exit 1
    done
    rm -rf "$tree" "$tree.out"
    echo "[ OK ] $name self-check"
    exit 0
}
