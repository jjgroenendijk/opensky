#!/bin/sh
# Coverage floors (docs/decisions/test-coverage-rules.md), from the last
# `make test-unit COVERAGE=1` run. Each test run rewrites the profile, so a
# filtered run reads too low.
#
#   1. Every OpenSkyFormats* module keeps FORMAT_FLOOR percent line coverage.
#   2. Every game-rule module (feature, interface, world domain) keeps RULE_FLOOR.
#   3. Every pure core file (`*Core.swift`) keeps CORE_FLOOR.
#
# Usage: tools/lint/coverage-floor.sh FORMAT_FLOOR RULE_FLOOR CORE_FLOOR DERIVED_DATA
#        tools/lint/coverage-floor.sh --self-check
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import sys

sys.path.insert(0, "tools/lint")
from coverage_profile import lcov, parse_lcov
from swift_source import rule_modules


def percent(covered, total):
    return 100.0 if total == 0 else 100.0 * covered / total


def units(files, rules):
    """(label, floor key, covered, total) for each module and core file under a floor."""
    modules = {}
    found = []
    for path, data in files.items():
        lines = data["lines"]
        covered = sum(1 for count in lines.values() if count > 0)
        module = path.split("/")[2]
        totals = modules.setdefault(module, [0, 0])
        totals[0] += covered
        totals[1] += len(lines)
        if path.endswith("Core.swift"):
            found.append((path, "core", covered, len(lines)))
    for module, (covered, total) in sorted(modules.items()):
        if module.startswith("OpenSkyFormats"):
            found.append((module, "format", covered, total))
        elif module in rules:
            found.append((module, "rule", covered, total))
    return found


def below(found, floors):
    return [
        (label, kind, percent(covered, total))
        for label, kind, covered, total in found
        if percent(covered, total) < floors[kind]
    ]


def self_check():
    files = {
        "src/Sources/OpenSkyFormatsX/A.swift": {"lines": {1: 1, 2: 0}},
        "src/Sources/OpenSkyMagic/MagicCore.swift": {"lines": {1: 1, 2: 1, 3: 0, 4: 0}},
        "src/Sources/OpenSkyRendering/R.swift": {"lines": {1: 0}},
    }
    floors = {"format": 80, "rule": 60, "core": 75}
    labels = sorted(label for label, _, _ in below(units(files, {"OpenSkyMagic"}), floors))
    expected = ["OpenSkyFormatsX", "OpenSkyMagic", "src/Sources/OpenSkyMagic/MagicCore.swift"]
    if labels != expected:
        sys.exit(f"[ERROR] coverage-floor self-check: found {labels}, expected {expected}")


self_check()
if sys.argv[1:] == ["--self-check"]:
    print("[ OK ] coverage-floor self-check")
    sys.exit(0)
if len(sys.argv) != 5:
    sys.exit("[ERROR] usage: coverage-floor.sh FORMAT_FLOOR RULE_FLOOR CORE_FLOOR DERIVED_DATA")
floors = dict(zip(("format", "rule", "core"), map(float, sys.argv[1:4])))
found = units(parse_lcov(lcov(sys.argv[4])), rule_modules())
failures = below(found, floors)
for label, kind, value in failures:
    print(f"[FAIL] {label:48} {value:6.2f}%  (floor {floors[kind]:.0f}% for {kind})")
if failures:
    sys.exit(f"[FAIL] {len(failures)} under their coverage floor. Add tests for the untested lines.")
counts = {kind: sum(1 for _, k, _, _ in found if k == kind) for kind in floors}
print(
    f"[ OK ] coverage floors: {counts['format']} format modules >= {floors['format']:.0f}%, "
    f"{counts['rule']} rule modules >= {floors['rule']:.0f}%, "
    f"{counts['core']} core files >= {floors['core']:.0f}%"
)
PY
