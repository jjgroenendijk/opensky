#!/bin/sh
# Tests run in random order (docs/decisions/test-coverage-rules.md):
#
#   1. Every target of every test plan sets randomExecutionOrdering, so XCTest
#      shuffles its tests on each run.
#   2. No Swift Testing suite carries the `.serialized` trait. Swift Testing runs
#      tests in parallel, so their order changes each run; `.serialized` fixes it.
#
# A self-check first runs each rule on small synthetic violations, which must fail.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import json
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, __import__("os").environ["OPENSKY_TOOLS"] + "/lint")
from swift_source import code_only, line_of

SERIALIZED = re.compile(r"\.serialized\b")


def unordered_targets(name, plan):
    return [
        f"{name}: {entry.get('target', {}).get('name')} does not set randomExecutionOrdering"
        for entry in plan.get("testTargets", [])
        if entry.get("randomExecutionOrdering") is not True
    ]


def serialized_suites(path, text):
    code = code_only(text)
    return [
        f"{path}:{line_of(code, match.start())}: `.serialized` fixes the test order"
        for match in SERIALIZED.finditer(code)
    ]


def self_check():
    cases = [
        (unordered_targets, ("X", {"testTargets": [{"target": {"name": "T"}}]}), 1),
        (unordered_targets, ("X", {"testTargets": [{"randomExecutionOrdering": True}]}), 0),
        (serialized_suites, ("a.swift", "@Suite(.serialized)\nstruct S {}\n"), 1),
        (serialized_suites, ("a.swift", "// the .serialized trait\nstruct S {}\n"), 0),
    ]
    for rule, arguments, expected in cases:
        if len(rule(*arguments)) != expected:
            sys.exit(f"[ERROR] test-order self-check: {rule.__name__} on {arguments!r}")


self_check()
if sys.argv[1:] == ["--self-check"]:
    print("[ OK ] test-order self-check")
    sys.exit(0)
problems = []
for path in sorted(pathlib.Path("src/config/TestPlans").glob("*.xctestplan")):
    problems += unordered_targets(path.stem, json.loads(path.read_text()))
tests = subprocess.run(
    ["git", "ls-files", "src/Tests/*.swift"], capture_output=True, text=True, check=True
).stdout.split()
for path in tests:
    problems += serialized_suites(path, pathlib.Path(path).read_text())

if problems:
    print("[FAIL] test order:", file=sys.stderr)
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    sys.exit(1)
print("[ OK ] test order: every plan shuffles, no suite is serialized")
PY
