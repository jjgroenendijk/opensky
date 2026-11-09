"""Shared helpers for the lint scripts that read Swift source as text."""

import pathlib
import re
import subprocess

# The app and the CLI are Xcode-only targets; every other src/Sources/ folder is a package module.
XCODE_ONLY = {"OpenSky", "OpenSkyCLI"}


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
            out.append('"' + re.sub(r"[^\n]", " ", text[index + 1 : end - 1]) + '"')
            index = end
        else:
            out.append(text[index])
            index += 1
    return "".join(out)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def package_files():
    """(module, path, code) for every tracked Swift file of a package module."""
    tracked = subprocess.run(
        ["git", "ls-files", "src/Sources/*.swift"], capture_output=True, text=True, check=True
    ).stdout.split()
    for name in tracked:
        path = pathlib.Path(name)
        if not path.exists() or path.name.startswith("._") or path.parts[2] in XCODE_ONLY:
            continue
        yield path.parts[2], name, code_only(path.read_text())


def wiring_modules():
    """Each module declared with composition(), and its interface: ports and wiring, no rule."""
    text = pathlib.Path("src/Package.swift").read_text()
    composed = set(re.findall(r'\bcomposition\(\s*"(\w+)"', text))
    return composed | {name + "Interface" for name in composed}


def tested_wiring_modules():
    """The adapter modules that have a test target over the generated port fakes. Both
    coverage rules hold for them; the other wiring modules stay outside."""
    return {
        name for name in wiring_modules()
        if name.endswith("Adapters") and pathlib.Path(f"src/Tests/{name}Tests").is_dir()
    }


def rule_modules():
    """The game-rule modules: each feature, interface, and world-domain module, and each tested
    adapter module, without the other wiring modules."""
    text = pathlib.Path("src/Package.swift").read_text()
    names = set(re.findall(r'\b(?:feature|domain|interface)\(\s*"(\w+)"', text))
    modules = {module for name in names for module in (name, name + "Interface")}
    return (modules - wiring_modules()) | tested_wiring_modules()
