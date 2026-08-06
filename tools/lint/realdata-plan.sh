#!/bin/sh
# RealData test-plan lint (issue #381). `make realtest-all` runs whatever
# Config/RealData.xctestplan selects, so a real-data suite that is not listed
# there is a suite nobody ever runs -- and the plan says nothing about the
# omission. This asserts the selection is exactly the set of env-gated suites
# in openskyTests, which makes adding a suite and forgetting the plan a lint
# failure instead of silent coverage loss.
#
# A suite counts as env-gated when its file declares the real-data root
# (`dataRoot: GameDataRoot?`, the shape openskyTests/CLAUDE.md prescribes) and
# the type carries at least one @Test.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json
import pathlib
import re
import sys

PLAN = pathlib.Path("Config/RealData.xctestplan")
TESTS = pathlib.Path("openskyTests")
TARGET = "openskyTests"
# A Swift Testing suite is a plain type declaration -- no @Suite attribute is
# required -- so the declarations are found positionally and each one keeps the
# text up to the next declaration.
DECLARATION = re.compile(
    r"^(?:@MainActor\s*\n)?(?:struct|final class|class|extension) ([A-Za-z0-9_]+)",
    re.M,
)


def gated_suites() -> set[str]:
    suites = set()
    for path in sorted(TESTS.glob("*.swift")):
        text = path.read_text()
        if "dataRoot: GameDataRoot?" not in text:
            continue
        marks = [(m.start(), m.group(1)) for m in DECLARATION.finditer(text)]
        for index, (start, name) in enumerate(marks):
            end = marks[index + 1][0] if index + 1 < len(marks) else len(text)
            if "@Test" in text[start:end]:
                suites.add(name)
    return suites


def selected_suites() -> set[str]:
    with PLAN.open("rb") as stream:
        plan = json.load(stream)
    for entry in plan.get("testTargets", []):
        if entry.get("target", {}).get("name") == TARGET:
            return set(entry.get("selectedTests", []))
    print(f"[FAIL] {PLAN} does not select the {TARGET} target", file=sys.stderr)
    raise SystemExit(1)


expected = gated_suites()
actual = selected_suites()
if expected == actual:
    raise SystemExit(0)

missing = sorted(expected - actual)
extra = sorted(actual - expected)
lines = [f"[FAIL] {PLAN} does not match the env-gated suites in {TESTS}/:"]
for name in missing:
    lines.append(f"  missing: {name} (gated on the data root, never runs)")
for name in extra:
    lines.append(f"  stale:   {name} (selected, but not a data-root suite)")
lines.append("Fix: add or drop the suite in the plan's selectedTests list.")
print("\n".join(lines), file=sys.stderr)
raise SystemExit(1)
PY
