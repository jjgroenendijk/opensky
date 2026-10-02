#!/bin/sh
# Check the rules every test plan under Config/TestPlans/ follows.
#
# docs/tools/test-runs.md explains each rule. In short: every plan is in the
# scheme, sets test timeouts, never repeats or retries tests, and selects by
# target or tag, never by test name. The Perf plan selects the `perf` tag, and
# each tag plan is the unit plan narrowed to one tag.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import json
import pathlib
import re
import sys

ROOT = pathlib.Path.cwd()
PLANS = ROOT / "Config/TestPlans"
SCHEME = ROOT / "OpenSky.xcodeproj/xcshareddata/xcschemes/OpenSky.xcscheme"
TAGS = ROOT / "Tests/TagsTesting/Tags.swift"
TIMEOUT_KEYS = (
    "defaultTestExecutionTimeAllowance",
    "maximumTestExecutionTimeAllowance",
)
# Repetition hides a flaky test, so only `make test-unit N=...` asks for it.
REPEAT_KEYS = ("testRepetitionMode", "maximumTestRepetitions")
TAG_PLANS = {"Parser": "parser", "GPU": "gpu"}
problems = []


def load(path):
    with path.open("rb") as stream:
        return json.load(stream)


plans = {path.stem: load(path) for path in sorted(PLANS.glob("*.xctestplan"))}
declared_tags = set(re.findall(r"@Tag public static var (\w+)", TAGS.read_text()))

in_scheme = set(re.findall(r"container:Config/TestPlans/(\w+)\.xctestplan", SCHEME.read_text()))
for name in sorted(set(plans) ^ in_scheme):
    where = "the scheme" if name in plans else "Config/TestPlans/"
    problems.append(f"{name}.xctestplan is missing from {where}")

for name, plan in plans.items():
    defaults = plan.get("defaultOptions", {})
    if defaults.get("testTimeoutsEnabled") is not True:
        problems.append(f"{name}: defaultOptions does not set testTimeoutsEnabled to true")
    allowances = [defaults.get(key) for key in TIMEOUT_KEYS]
    if not all(isinstance(value, int) and value >= 60 for value in allowances):
        problems.append(f"{name}: set both {' and '.join(TIMEOUT_KEYS)} to 60 s or more")
    elif allowances[0] > allowances[1]:
        problems.append(f"{name}: the default allowance is above the maximum")
    for options in [defaults] + [config.get("options", {}) for config in plan["configurations"]]:
        for key in REPEAT_KEYS:
            if key in options:
                problems.append(f"{name}: sets {key}; repeat with `make test-unit N=...` instead")
    for entry in plan.get("testTargets", []):
        target = entry.get("target", {}).get("name")
        for key in ("selectedTests", "skippedTests"):
            if entry.get(key):
                problems.append(
                    f"{name}: {target} carries {key}, which matches no Swift Testing test"
                )
        for key in ("selectedTags", "skippedTags"):
            unknown = set(entry.get(key, {}).get("tags", [])) - declared_tags
            if unknown:
                problems.append(f"{name}: {target} {key} names unknown tags {sorted(unknown)}")


perf = plans.get("Perf", {})
perf_targets = perf.get("testTargets", [])
if [entry.get("target", {}).get("name") for entry in perf_targets] != ["OpenSkyRealDataTests"]:
    problems.append("Perf: must select exactly OpenSkyRealDataTests")
elif perf_targets[0].get("selectedTags", {}).get("tags") != ["perf"]:
    problems.append("Perf: must select the `perf` tag and nothing else")


def data_root(plan):
    entries = plan.get("defaultOptions", {}).get("environmentVariableEntries", [])
    return [entry.get("value") for entry in entries if entry.get("key") == "OPENSKY_DATA_ROOT"]


if data_root(perf) != data_root(plans.get("RealData", {})):
    problems.append("Perf: OPENSKY_DATA_ROOT must match the RealData plan")

unit = [entry["target"]["name"] for entry in plans.get("UnitTests", {}).get("testTargets", [])]
sanitized = [entry["target"]["name"] for entry in plans.get("Sanitizers", {}).get("testTargets", [])]
if unit != sanitized:
    problems.append("Sanitizers: must list the same test targets as UnitTests, in the same order")
unit_env = plans.get("UnitTests", {}).get("defaultOptions", {}).get("environmentVariableEntries")
sanitized_env = plans.get("Sanitizers", {}).get("defaultOptions", {}).get("environmentVariableEntries")
if unit_env != sanitized_env:
    problems.append("Sanitizers: must set the same environment as UnitTests")

# A tag plan is the unit plan narrowed to one tag, so `make test-<tag>` sees every target.
for name, tag in TAG_PLANS.items():
    plan = plans.get(name, {})
    entries = plan.get("testTargets", [])
    if [entry["target"]["name"] for entry in entries] != unit:
        problems.append(f"{name}: must list the same test targets as UnitTests, in the same order")
    if any(entry.get("selectedTags", {}).get("tags") != [tag] for entry in entries):
        problems.append(f"{name}: every target must select only the `{tag}` tag")
    if plan.get("defaultOptions", {}).get("environmentVariableEntries") != unit_env:
        problems.append(f"{name}: must set the same environment as UnitTests")

if problems:
    print("[FAIL] test plans:", file=sys.stderr)
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    sys.exit(1)
PY
