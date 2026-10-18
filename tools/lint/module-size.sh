#!/bin/sh
# Module size check (docs/tools/modules.md#module-size). Counts the Swift source lines
# of each folder under Sources/, without blank lines and comments, and prints them
# sorted. Over WARN lines it warns; over LIMIT lines it fails, unless the module is on
# module-size-exceptions.txt with an open issue that splits it.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import pathlib
import subprocess
import sys

WARN = 20_000
LIMIT = 30_000
APP = "OpenSky"
EXCEPTIONS = pathlib.Path("tools/lint/module-size-exceptions.txt")


def code_lines(text):
    """Lines that hold code once comments are gone. Strings keep their lines."""
    kept, i, depth, quote = [], 0, 0, None
    while i < len(text):
        if depth:
            if text.startswith("/*", i):
                depth, i = depth + 1, i + 2
            elif text.startswith("*/", i):
                depth, i = depth - 1, i + 2
            else:
                kept.append("\n" if text[i] == "\n" else "")
                i += 1
        elif quote:
            if text.startswith(quote, i):
                kept.append(quote)
                i, quote = i + len(quote), None
            elif text[i] == "\\":
                kept.append("x")
                i += 2
            else:
                kept.append(text[i] if text[i] == "\n" else "x")
                if text[i] == "\n" and quote == '"':
                    quote = None
                i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        elif text.startswith("/*", i):
            depth, i = 1, i + 2
        elif text.startswith('"""', i) or text[i] == '"':
            quote = '"""' if text.startswith('"""', i) else '"'
            kept.append(quote)
            i += len(quote)
        else:
            kept.append(text[i])
            i += 1
    return sum(1 for line in "".join(kept).split("\n") if line.strip())


sizes = {}
for folder in sorted(pathlib.Path("Sources").iterdir()):
    if folder.is_dir():
        lines = sum(code_lines(path.read_text()) for path in folder.rglob("*.swift"))
        if lines:
            sizes[folder.name] = lines

exceptions = {}
for number, line in enumerate(EXCEPTIONS.read_text().splitlines(), 1):
    if line.strip() and not line.startswith("#"):
        module, issue, reason = (line.split(maxsplit=2) + ["", ""])[:3]
        exceptions[module] = (issue.lstrip("#"), reason, number)

failures, warnings = [], []
width = max(len(name) for name in sizes) + len(" (app)")
for name, lines in sorted(sizes.items(), key=lambda item: (-item[1], item[0])):
    label = f"{name} (app)" if name == APP else name
    print(f"  {label:<{width}} {lines:>7,}")
    if lines > LIMIT and name not in exceptions:
        failures.append(f"{name} has {lines:,} lines, over {LIMIT:,}; split it along its domains")
    elif lines > WARN and name not in exceptions:
        warnings.append(f"{name} has {lines:,} lines, over {WARN:,}; plan its split")


def issue_state(issue):
    result = subprocess.run(
        ["gh", "issue", "view", issue, "--json", "state", "--jq", ".state"],
        capture_output=True, text=True, check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


for module, (issue, reason, number) in sorted(exceptions.items()):
    where = f"{EXCEPTIONS}:{number}"
    if not reason or not issue.isdigit():
        failures.append(f"{where}: an entry is '<module> #<issue> <reason>'")
    elif sizes.get(module, 0) <= LIMIT:
        failures.append(f"{where}: {module} is not over {LIMIT:,} lines; drop its entry")
    else:
        state = issue_state(issue)
        if state != "OPEN":
            failures.append(f"{where}: issue #{issue} for {module} is {state or 'unreadable'}"
                            "; an entry needs an open split issue")

for line in warnings:
    print(f"[WARNING] {line}")
if failures:
    print("[FAIL] module size:", file=sys.stderr)
    for line in failures:
        print(f"  {line}", file=sys.stderr)
    raise SystemExit(1)
print(f"[ OK ] module sizes ({len(sizes)} modules, {len(exceptions)} on the exception list)")
PY
