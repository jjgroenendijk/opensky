#!/bin/sh
# RealData test-target lint (issues #381, #418). `make realtest-all` runs whatever
# Config/RealData.xctestplan selects, and since #418 that is one whole target:
# openskyRealDataTests. So the check is no longer "is every suite named in the
# plan" -- a 57-entry list nobody could keep spelled right -- but the two
# structural facts that make target-level selection correct:
#
#   * Every env-gated suite lives in openskyRealDataTests/. One in openskyTests/
#     or openskyTestSupport/ is a suite `make realtest-all` never runs, and it
#     would silently skip inside `make test` instead, because a plain
#     `xcodebuild test` does not forward OPENSKY_DATA_ROOT into the host.
#   * The plan selects that target, with no selectedTests narrowing it -- a
#     plan's own selectedTests does not match Swift Testing tests at all
#     (measured, issue #381), so one would select nothing.
#
# It also re-asserts the issue #380 rule for the new bundle: no plan may list an
# app-hosted unit bundle beside openskyUITests, or the test host and the UI
# runner deadlock.
#
# A suite counts as env-gated when its file declares the real-data root
# (`dataRoot: GameDataRoot?`, the shape openskyRealDataTests/CLAUDE.md
# prescribes) and the type carries at least one @Test.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json
import pathlib
import re
import sys

PLAN = pathlib.Path("Config/RealData.xctestplan")
TARGET = "openskyRealDataTests"
HOME = pathlib.Path(TARGET)
ELSEWHERE = [pathlib.Path("openskyTests"), pathlib.Path("openskyTestSupport")]
# A Swift Testing suite is a plain type declaration -- no @Suite attribute is
# required -- so the declarations are found positionally and each one keeps the
# text up to the next declaration.
DECLARATION = re.compile(
    r"^(?:@MainActor\s*\n)?(?:struct|final class|class|extension) ([A-Za-z0-9_]+)",
    re.M,
)
problems = []


def gated_suites(folder: pathlib.Path) -> list[str]:
    suites = []
    for path in sorted(folder.glob("*.swift")):
        text = path.read_text()
        if "dataRoot: GameDataRoot?" not in text:
            continue
        marks = [(m.start(), m.group(1)) for m in DECLARATION.finditer(text)]
        for index, (start, name) in enumerate(marks):
            end = marks[index + 1][0] if index + 1 < len(marks) else len(text)
            if "@Test" in text[start:end]:
                suites.append(f"{path}: {name}")
    return suites


for folder in ELSEWHERE:
    for suite in gated_suites(folder):
        problems.append(
            f"env-gated suite outside {TARGET}/: {suite}"
            f" (move the file into {TARGET}/, or `make realtest-all` never runs it)"
        )

if not gated_suites(HOME):
    problems.append(f"{HOME}/ declares no env-gated suite at all")

with PLAN.open("rb") as stream:
    plan = json.load(stream)
entries = plan.get("testTargets", [])
names = [entry.get("target", {}).get("name") for entry in entries]
if names != [TARGET]:
    problems.append(f"{PLAN} selects {names}, expected exactly [{TARGET!r}]")
for entry in entries:
    for key in ("selectedTests", "skippedTests"):
        if entry.get(key):
            problems.append(
                f"{PLAN} carries {key} for {entry['target']['name']};"
                " a plan's own test selection does not match Swift Testing"
                " (issue #381), so it would select nothing"
            )

# Issue #380: an app-hosted unit bundle and the UI runner deadlock in one session.
HOSTED = {"openskyTests", TARGET}
for path in sorted(pathlib.Path("Config").glob("*.xctestplan")):
    with path.open("rb") as stream:
        listed = {
            entry.get("target", {}).get("name")
            for entry in json.load(stream).get("testTargets", [])
        }
    if "openskyUITests" in listed and listed & HOSTED:
        problems.append(
            f"{path} lists openskyUITests beside {sorted(listed & HOSTED)};"
            " an app-hosted unit bundle deadlocks the UI runner (issue #380)"
        )

if problems:
    print("[FAIL] real-data test target layout:", file=sys.stderr)
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    raise SystemExit(1)
PY
