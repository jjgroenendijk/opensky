#!/bin/sh
# Diff coverage (docs/decisions/test-coverage-rules.md), from the last
# `make test COVERAGE=1` run, over the Swift lines of package modules that
# the branch adds or changes since BASE:
#
#   1. At least 80 percent of the changed executable lines ran in a test.
#   2. Every function the branch adds ran in a test. Closures count under rule 1.
#
# A block git sees as moved unchanged is not new: rename detection for lines.
#
# Usage: tools/coverage/changed-lines.sh BASE DERIVED_DATA
#        tools/coverage/changed-lines.sh --self-check
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import re
import subprocess
import sys

sys.path[:0] = ["tools/coverage", "tools/lint"]
from coverage_profile import current_profiles, demangled, is_closure, lcov, parse_lcov
from swift_source import XCODE_ONLY, wiring_modules

HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
# The colours `git diff --color-moved` gets, so a moved added line is told apart.
NEW, MOVED = "\x1b[32m", "\x1b[34m"
COLOURS = ["-c", "color.diff.new=green", "-c", "color.diff.newMoved=blue",
           "-c", "color.diff.newMovedAlternative=blue"]


def changed_lines(diff):
    """{path: {line}} for the lines a coloured `git diff -U0` adds, without moved ones."""
    changed, lines, number = {}, None, 0
    skipped = XCODE_ONLY | wiring_modules()
    for raw in diff.splitlines():
        text = ANSI.sub("", raw)
        if text.startswith("+++ "):
            path = text[6:] if text.startswith("+++ b/") else ""
            usable = (path.startswith("src/Sources/") and path.endswith(".swift")
                      and path.split("/")[2] not in skipped)
            lines = changed.setdefault(path, set()) if usable else None
        elif (hunk := HUNK.match(text)):
            number = int(hunk.group(1))
        elif text.startswith("+") and lines is not None:
            if not raw.startswith(MOVED):
                lines.add(number)
            number += 1
    return changed


def check(changed, files, readable_names):
    """(covered, executable, [untested new functions], {path: [lines no test ran]})."""
    covered = executable = 0
    untested = []
    missed = {}
    for path, lines in sorted(changed.items()):
        data = files.get(path, {"lines": {}, "functions": []})
        for line in lines:
            if line in data["lines"]:
                executable += 1
                covered += data["lines"][line] > 0
                if data["lines"][line] == 0:
                    missed.setdefault(path, []).append(line)
        for line, name, count in data["functions"]:
            readable = readable_names.get(name, name)
            if line in lines and count == 0 and not is_closure(readable):
                untested.append(f"{path}:{line}: {readable}")
    return covered, executable, untested, missed


def ranges(lines):
    """`3-5, 9` for [3, 4, 5, 9]."""
    spans = []
    for line in sorted(lines):
        if spans and line == spans[-1][1] + 1:
            spans[-1][1] = line
        else:
            spans.append([line, line])
    return ", ".join(str(a) if a == b else f"{a}-{b}" for a, b in spans)


def self_check():
    diff = (
        "diff --git a/src/Sources/OpenSkyMagic/A.swift b/src/Sources/OpenSkyMagic/A.swift\n"
        "+++ b/src/Sources/OpenSkyMagic/A.swift\n@@ -0,0 +1,4 @@\n"
        f"{NEW}+a\n{NEW}+b\n{NEW}+c\n{MOVED}+moved\n"
        "diff --git a/src/Sources/OpenSky/B.swift b/src/Sources/OpenSky/B.swift\n"
        "+++ b/src/Sources/OpenSky/B.swift\n@@ -0,0 +1,1 @@\n+b\n"
        "diff --git a/src/Sources/OpenSkyMagicAdapters/C.swift b/src/Sources/OpenSkyMagicAdapters/C.swift\n"
        "+++ b/src/Sources/OpenSkyMagicAdapters/C.swift\n@@ -0,0 +1,1 @@\n+c\n"
    )
    changed = changed_lines(diff)
    if changed != {"src/Sources/OpenSkyMagic/A.swift": {1, 2, 3}}:
        sys.exit(f"[ERROR] diff-coverage self-check: changed lines {changed}")
    files = {
        "src/Sources/OpenSkyMagic/A.swift": {
            "lines": {1: 1, 2: 0, 3: 0, 9: 0},
            "functions": [(1, "f", 1), (2, "g", 0), (3, "c", 0), (9, "old", 0)],
        }
    }
    names = {"c": "closure #1 in f()"}
    result = check(changed, files, names)
    expected = (1, 3, ["src/Sources/OpenSkyMagic/A.swift:2: g"], {"src/Sources/OpenSkyMagic/A.swift": [2, 3]})
    if result != expected or ranges([3, 4, 5, 9]) != "3-5, 9":
        sys.exit(f"[ERROR] diff-coverage self-check: {result}")
    # A Quick run kept after the last source change merges in; an older GPU run does not.
    if current_profiles("newest", [("Quick", 5), ("GPU", 1)], 3) != ["newest", "Quick"]:
        sys.exit("[ERROR] diff-coverage self-check: kept profiles chosen wrongly")


self_check()
if sys.argv[1:] == ["--self-check"]:
    print("[ OK ] diff-coverage self-check")
    sys.exit(0)
if len(sys.argv) != 3:
    sys.exit("[ERROR] usage: changed-lines.sh BASE DERIVED_DATA")
floor, base, derived_data = 80.0, sys.argv[1], sys.argv[2]
diff = subprocess.run(
    ["git", *COLOURS, "diff", "--color=always", "--color-moved=zebra",
     "--color-moved-ws=allow-indentation-change", "-U0", "-M", "--diff-filter=AMR", base],
    capture_output=True, text=True, check=True,
).stdout
changed = changed_lines(diff)
if not changed:
    print("[ OK ] diff coverage: no package module lines changed")
    sys.exit(0)
files = parse_lcov(lcov(derived_data))
mangled = sorted({name for path in changed for _, name, _ in files.get(path, {}).get("functions", [])})
readable_names = dict(zip(mangled, demangled(mangled)))
covered, executable, untested, missed = check(changed, files, readable_names)
value = 100.0 if executable == 0 else 100.0 * covered / executable
for entry in untested:
    print(f"[FAIL] {entry} never ran in a test")
if value < floor:
    for path, lines in sorted(missed.items()):
        print(f"[INFO] no test ran {path}: lines {ranges(lines)}")
    print(f"[FAIL] {covered} of {executable} changed lines ran in a test: {value:.1f}%, floor {floor:.0f}%")
if untested or value < floor:
    sys.exit("[FAIL] diff coverage: add tests for the new code")
print(f"[ OK ] diff coverage: {covered} of {executable} changed lines ran ({value:.1f}%), every new function ran")
PY
