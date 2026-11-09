#!/bin/sh
# Error-handling rules (docs/decisions/error-handling.md), over every tracked Swift file:
#
#   1. No swallowed errors in package modules: no `try?` except on the allowed calls,
#      and no catch-all `catch` whose body only leaves (`return`, `continue`, `break`).
#   2. No traps (`fatalError`, `precondition`, `assert`, ...) in the modules that read
#      game files or saves.
#
# A self-check first runs both rules on small synthetic violations, which must fail.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import re
import sys

sys.path.insert(0, __import__("os").environ["OPENSKY_TOOLS"] + "/lint")
from swift_source import code_only, line_of, package_files
# The last name of a call whose failure is expected and harmless. Reasons are on the
# decision page.
ALLOWED_CALLS = {"removeItem", "close"}
TRAP_MODULES = re.compile(r"^(OpenSkyFormats\w*|OpenSkyGameData|OpenSkySave)$")
TRAP = re.compile(r"\b(fatalError|precondition|preconditionFailure|assert|assertionFailure)\s*\(")
TRY_OPTIONAL = re.compile(r"\btry\?\s*(?:await\s+)?(?:unsafe\s+)?([\w.]*)")
SWALLOWING_CATCH = re.compile(r"\bcatch\s*\{\s*(?:return(?:\s+nil)?|continue|break)?\s*\}")


def swallowed(code):
    found = []
    for match in TRY_OPTIONAL.finditer(code):
        name = match.group(1).split(".")[-1]
        if name not in ALLOWED_CALLS:
            found.append((line_of(code, match.start()), f"`try?` on `{match.group(1) or '?'}`"))
    for match in SWALLOWING_CATCH.finditer(code):
        found.append((line_of(code, match.start()), "`catch` that drops the error"))
    return found


def traps(code):
    return [(line_of(code, m.start()), f"`{m.group(1)}`") for m in TRAP.finditer(code)]


def self_check():
    cases = [
        (swallowed, "let x = try? decode(data)", True),
        (swallowed, "let x = (try? reader.readUInt32()) ?? 0", True),
        (swallowed, "do { try f() } catch { return nil }", True),
        (swallowed, "do { try f() } catch {}", True),
        (swallowed, "defer { try? handle.close() }", False),
        (swallowed, "try? FileManager.default.removeItem(at: url)", False),
        (swallowed, "let x = attempt { try decode(data) }", False),
        (swallowed, '// try? in a comment\nlet s = "try? in text"', False),
        (swallowed, "do { try f() } catch { log(error) }", False),
        (traps, 'precondition(count == 4, "four bytes")', True),
        (traps, "fatalError()", True),
        (traps, "assertionFailure()", True),
        (traps, "throw ParseError.truncated", False),
    ]
    for rule, snippet, should_fail in cases:
        if bool(rule(code_only(snippet))) != should_fail:
            verdict = "missed" if should_fail else "rejected"
            sys.exit(f"[ERROR] error-handling self-check: {rule.__name__} {verdict}: {snippet!r}")


self_check()
if sys.argv[1:] == ["--self-check"]:
    print("[ OK ] error-handling self-check")
    sys.exit(0)
failures = []
for module, name, code in package_files():
    for line, what in swallowed(code):
        failures.append(
            f"{name}:{line}: [ERROR] {what} swallows the error; use `attempt {{ try ... }}` or throw"
        )
    if TRAP_MODULES.match(module):
        for line, what in traps(code):
            failures.append(f"{name}:{line}: [ERROR] {what} traps on input; throw a typed error")
if failures:
    print("\n".join(failures))
    sys.exit(f"[ERROR] {len(failures)} error-handling violations (docs/decisions/error-handling.md)")
print("[ OK ] error handling: no swallowed errors, no traps on file input")
PY
