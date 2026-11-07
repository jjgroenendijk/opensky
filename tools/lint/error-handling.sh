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

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import pathlib
import re
import subprocess
import sys

# Package modules. The app and the CLI are Xcode-only targets.
XCODE_ONLY = {"OpenSky", "OpenSkyCLI"}
# The last name of a call whose failure is expected and harmless. Reasons are on the
# decision page.
ALLOWED_CALLS = {"removeItem", "close"}
TRAP_MODULES = re.compile(r"^(OpenSkyFormats\w*|OpenSkyGameData|OpenSkySave)$")
TRAP = re.compile(r"\b(fatalError|precondition|preconditionFailure|assert|assertionFailure)\s*\(")
TRY_OPTIONAL = re.compile(r"\btry\?\s*(?:await\s+)?(?:unsafe\s+)?([\w.]*)")
SWALLOWING_CATCH = re.compile(r"\bcatch\s*\{\s*(?:return(?:\s+nil)?|continue|break)?\s*\}")


def code_only(text):
    """The text with comments and string literals blanked, so lines keep their numbers."""
    out, index, length = [], 0, len(text)
    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            out.append(" " * (end - index))
            index = end
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = length if end < 0 else end + 2
            out.append(re.sub(r"[^\n]", " ", text[index:end]))
            index = end
        elif text[index] == '"':
            quote = '"""' if text.startswith('"""', index) else '"'
            end = index + len(quote)
            while end < length and not text.startswith(quote, end):
                end += 2 if text[end] == "\\" else 1
            end = min(end + len(quote), length)
            out.append('"' + re.sub(r"[^\n]", " ", text[index + 1:end - 1]) + '"')
            index = end
        else:
            out.append(text[index])
            index += 1
    return "".join(out)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


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
tracked = subprocess.run(
    ["git", "ls-files", "Sources/*.swift"], capture_output=True, text=True, check=True
).stdout.split()
failures = []
for name in tracked:
    path = pathlib.Path(name)
    if not path.exists() or path.name.startswith("._"):
        continue
    module = path.parts[1]
    if module in XCODE_ONLY:
        continue
    code = code_only(path.read_text())
    for line, what in swallowed(code):
        failures.append(f"{name}:{line}: [ERROR] {what} swallows the error; use `attempt {{ try ... }}` or throw")
    if TRAP_MODULES.match(module):
        for line, what in traps(code):
            failures.append(f"{name}:{line}: [ERROR] {what} traps on input; throw a typed error")
if failures:
    print("\n".join(failures))
    sys.exit(f"[ERROR] {len(failures)} error-handling violations (docs/decisions/error-handling.md)")
print("[ OK ] error handling: no swallowed errors, no traps on file input")
PY
