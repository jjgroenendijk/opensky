#!/bin/sh
# Rule 5 of docs/decisions/ports-and-adapters.md over every adapter module: no magic
# numbers and a complexity of at most 6. A self-check lints a synthetic violation first.
set -eu

cd "$(git rev-parse --show-toplevel)"
config=tools/lint/adapters.swiftlint.yml
swiftlint=${SWIFTLINT:-swiftlint}

probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
cat >"$probe/Probe.swift" <<'SWIFT'
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
found=$("$swiftlint" lint --quiet --config "$config" "$probe/Probe.swift" 2>/dev/null || true)
for rule in no_magic_numbers cyclomatic_complexity; do
  case $found in
    *"($rule)"*) ;;
    *) echo "[ERROR] adapter-rules self-check: $rule missed its violation" >&2; exit 1 ;;
  esac
done

modules=$(git ls-files 'Sources/*Adapters/*.swift' | cut -d/ -f1-2 | sort -u)
[ -n "$modules" ] || { echo "[ OK ] no adapter module to lint"; exit 0; }
if ! printf '%s\n' "$modules" | xargs "$swiftlint" lint --strict --quiet --config "$config"; then
  echo "[ERROR] an adapter holds a magic number or a complex function (docs/decisions/ports-and-adapters.md, rule 5)" >&2
  exit 1
fi
echo "[ OK ] adapter rules: no magic numbers, complexity at most 6"
