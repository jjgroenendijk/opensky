#!/bin/sh
# Rewrite comment blocks in bulk without reading whole files. `dump` prints
# the blocks worth a look, each under a `=== path:first-last` header. Edit the
# text under each header, then `apply` writes it back. An empty body deletes
# the block. A block is a run of lines that start with `//`, as in
# tools/lint/comment-length.sh.
#
# Usage: tools/comment-blocks.sh dump [-n LINES] [-r] [PATH...]
#          -n  only blocks of at least LINES lines (default 7, over the limit)
#          -r  also shorter blocks that cite an issue or a milestone
#          PATH  files or folders (default Sources Tests)
#        tools/comment-blocks.sh apply SPEC
#          A range that is no longer exactly one comment block is refused, and
#          its file is left untouched.
set -eu

usage() {
    sed -n 's/^# Usage: /  /p; s/^#        /  /p' "$0" >&2
    exit 2
}

dump() {
    min=7
    refs=0
    while getopts "n:r" opt; do
        case "$opt" in
            n) min="$OPTARG" ;;
            r) refs=1 ;;
            *) usage ;;
        esac
    done
    shift $((OPTIND - 1))
    [ "$#" -gt 0 ] || set -- Sources Tests
    git ls-files -- "$@" | grep -E '\.(swift|metal|h)$' |
        awk -v min="$min" -v refs="$refs" '
            function flush(   i, cited) {
                cited = 0
                for (i = 1; i <= n; i++)
                    if (text[i] ~ /#[0-9][0-9]|[Ii]ssue [0-9]|(^|[^A-Za-z])M[0-9]+(\.[0-9]+)+/) cited = 1
                if (n >= min || (refs && cited)) {
                    printf "=== %s:%d-%d\n", file, start, start + n - 1
                    for (i = 1; i <= n; i++) print text[i]
                }
                n = 0
            }
            {
                file = $0
                row = 0
                while ((getline line < file) > 0) {
                    row++
                    if (line ~ /^[ \t]*\/\//) {
                        if (n == 0) start = row
                        text[++n] = line
                    } else {
                        flush()
                    }
                }
                close(file)
                flush()
            }
        '
}

apply_file() {
    awk -v target="$1" '
        FNR == NR {
            if ($0 ~ /^=== /) {
                cur = 0
                if (match($0, /:[0-9]+-[0-9]+$/)) {
                    path = substr($0, 5, RSTART - 5)
                    if (path == target) {
                        cur = ++k
                        split(substr($0, RSTART + 1), range, "-")
                        first[k] = range[1] + 0
                        last[k] = range[2] + 0
                        count[k] = 0
                    }
                }
                next
            }
            if (cur) body[cur, ++count[cur]] = $0
            next
        }
        { src[FNR] = $0; total = FNR }
        END {
            comment = "^[ \t]*//"
            for (e = 1; e <= k; e++) {
                while (count[e] > 0 && body[e, count[e]] == "") count[e]--
                bad = first[e] < 1 || last[e] > total || first[e] > last[e]
                for (i = first[e]; !bad && i <= last[e]; i++) bad = src[i] !~ comment
                if (!bad && first[e] > 1) bad = src[first[e] - 1] ~ comment
                if (!bad && last[e] < total) bad = src[last[e] + 1] ~ comment
                if (bad) {
                    printf "[ERROR] %s:%d-%d is no longer that comment block\n", \
                        target, first[e], last[e] > "/dev/stderr"
                    exit 1
                }
                starts[first[e]] = e
            }
            for (i = 1; i <= total; i++) {
                if (i in starts) {
                    e = starts[i]
                    for (j = 1; j <= count[e]; j++) print body[e, j]
                    i = last[e]
                    # A deleted block must not leave two blank lines behind.
                    if (count[e] == 0 && src[i + 1] == "" && i + 1 <= total \
                        && (first[e] == 1 || src[first[e] - 1] == "")) i++
                    continue
                }
                print src[i]
            }
        }
    ' "$2" "$1"
}

apply() {
    [ "$#" -eq 1 ] && [ -f "$1" ] || usage
    spec="$1"
    status=0
    files="$(mktemp)"
    sed -En 's/^=== (.*):[0-9]+-[0-9]+$/\1/p' "$spec" | sort -u >"$files"
    while IFS= read -r file; do
        tmp="$(mktemp)"
        if apply_file "$file" "$spec" >"$tmp"; then
            cat "$tmp" >"$file"
            printf '[ OK ] %s\n' "$file"
        else
            status=1
        fi
        rm -f "$tmp"
    done <"$files"
    rm -f "$files"
    return "$status"
}

cd "$(git rev-parse --show-toplevel)"
[ "$#" -gt 0 ] || usage
command="$1"
shift
case "$command" in
    dump) dump "$@" ;;
    apply) apply "$@" ;;
    *) usage ;;
esac
