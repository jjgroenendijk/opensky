#!/bin/sh
# Check that every Makefile target that runs tests is named test-<kind>.
#
# One target per kind of test keeps the list short to learn: options such as
# T= and N= choose what runs, not extra targets. A recipe runs tests when it
# calls the xcodebuild test action.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import re
import sys

# The xcodebuild `test` action ends a recipe line; `guarded` adds it for a target.
RUNNER = re.compile(r"\stest(-without-building)?\s*$|\$\(call guarded,")
RULE = re.compile(r"^([A-Za-z0-9_.-]+):(?!=)")

problems = []
target = None
with open("Makefile", encoding="utf-8") as makefile:
    for line in makefile:
        rule = RULE.match(line)
        if rule:
            target = rule.group(1)
            continue
        if not line.startswith("\t") or target is None:
            if line.strip() and not line.startswith("#"):
                target = None
            continue
        if RUNNER.search(line) and not target.startswith("test-"):
            problems.append(f"{target}: runs tests, so its name must start with test-")
            target = None

if problems:
    print("[FAIL] Makefile test targets:", file=sys.stderr)
    for problem in sorted(set(problems)):
        print(f"  {problem}", file=sys.stderr)
    sys.exit(1)
PY
