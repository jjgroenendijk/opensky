#!/bin/sh
# Rule 5 of docs/decisions/ports-and-adapters.md over every adapter module: no magic
# numbers and a complexity of at most 6. syntax-rules.sh checks rule 9.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyXAdapters"
    cat >"$tree/src/Sources/OpenSkyXAdapters/Probe.swift" <<'SWIFT'
struct Probe {
    func branches(_ a: Bool, _ b: Bool, _ c: Bool) throws -> Int {
        guard a else { return 0 }
        guard b else { return 0 }
        guard c else { return 0 }
        if a { return 1 } else { return 2 }
        do { try check() } catch { return 3 }
        if b { return 4 }
        guard case .some = Optional(1) else { return 5 }
        return 1
    }

    func check() throws {}
}
SWIFT
    expect_failure "$0" "$tree" "(no_magic_numbers)" "(cyclomatic_complexity)"
fi
config="$OPENSKY_TOOLS/lint/adapters.swiftlint.yml"

cd "$(git rev-parse --show-toplevel)"
swiftlint=${SWIFTLINT:-swiftlint}

modules=$(git ls-files 'src/Sources/*Adapters/*.swift' | cut -d/ -f1-3 | sort -u)
[ -n "$modules" ] || { echo "[ OK ] no adapter module to lint"; exit 0; }
if ! printf '%s\n' "$modules" | xargs "$swiftlint" lint --strict --quiet --config "$config"; then
  echo "[ERROR] an adapter holds a magic number or a complex function (docs/decisions/ports-and-adapters.md, rule 5)" >&2
  exit 1
fi
echo "[ OK ] adapter rules: no magic numbers, complexity at most 6"
