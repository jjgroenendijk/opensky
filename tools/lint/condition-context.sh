#!/bin/sh
# A condition context carries the function registry it runs on (`ConditionContext.functions`).
# So no function or initialiser in a package module takes a `ConditionContext` and a
# `ConditionFunctionRegistry` as two parameters: a caller could pair them wrongly.
#
# A self-check first runs the rule on small synthetic cases.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import re
import sys

sys.path.insert(0, __import__("os").environ["OPENSKY_TOOLS"] + "/lint")
from swift_source import code_only, line_of, package_files

DECLARATION = re.compile(r"\b(?:func\s+[^\s(<]+|init[?!]?)\s*(?:<[^>{]*>)?\s*\(")
CONTEXT = re.compile(r":\s*(?:inout\s+)?ConditionContext\b")
REGISTRY = re.compile(r":\s*(?:inout\s+)?ConditionFunctionRegistry\b")


def parameter_list(code, start):
    """The text between the parenthesis at `start` and its match."""
    depth = 0
    for index in range(start, len(code)):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
            if depth == 0:
                return code[start + 1 : index]
    return code[start + 1 :]


def paired(code):
    found = []
    for match in DECLARATION.finditer(code):
        parameters = parameter_list(code, match.end() - 1)
        if CONTEXT.search(parameters) and REGISTRY.search(parameters):
            found.append(line_of(code, match.start()))
    return found


def self_check():
    cases = [
        ("func run(context: ConditionContext, registry: ConditionFunctionRegistry) {}", True),
        ("init(\n    context: ConditionContext,\n    functions: ConditionFunctionRegistry\n) {}", True),
        ("static func check<T>(in context: ConditionContext, _ r: ConditionFunctionRegistry)", True),
        ("func run(context: ConditionContext) {}", False),
        ("init(functions: ConditionFunctionRegistry) {}", False),
        ("func run(context: ConditionContext) {}\nfunc name(r: ConditionFunctionRegistry) {}", False),
        ("// func run(context: ConditionContext, registry: ConditionFunctionRegistry)", False),
    ]
    for snippet, should_fail in cases:
        if bool(paired(code_only(snippet))) != should_fail:
            verdict = "missed" if should_fail else "rejected"
            sys.exit(f"[ERROR] condition-context self-check {verdict}: {snippet!r}")


self_check()
if sys.argv[1:] == ["--self-check"]:
    print("[ OK ] condition-context self-check")
    sys.exit(0)
failures = [
    f"{name}:{line}: [ERROR] takes a ConditionContext and a ConditionFunctionRegistry; "
    "set `context.functions` instead"
    for _, name, code in package_files()
    for line in paired(code)
]
if failures:
    print("\n".join(failures))
    sys.exit(f"[ERROR] {len(failures)} functions take a context and a registry apart")
print("[ OK ] condition context: no function takes a context and a registry apart")
PY
