#!/bin/sh
# Check that every Swift Testing suite carries the shared tags its files call for.
#
# The tags live in Tests/TagsTesting/Tags.swift. A suite needs:
#   .acceptance  when it is declared under an Acceptance/ folder,
#   .gpu         when a file of the suite reaches a Metal device,
#   .parser      when it is declared in a format test target.
# A `.disabled` trait must name the issue that tracks it ("flaky: #123").
# Acceptance suite names do not start with a milestone number.
#
# --fix adds the missing tags to each suite's @Suite attribute.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import pathlib
import re
import sys

ROOT = pathlib.Path.cwd()
TESTS = ROOT / "Tests"
# The UI bundle is XCTest, so Swift Testing tags do not apply to it.
SKIPPED_TARGETS = {"OpenSkyUITests"}
DEVICE = re.compile(
    r"MTLCreateSystemDefaultDevice|hasMetal4Device|OffscreenRendererFixture\.device"
    r"|RealDataEnvironment\.(?:device|canRender)|\bSelf\.(?:device|hasDevice)\b"
    r"|ShaderLibraryFixture"
)
DECL = re.compile(
    r"^(?:(?:public|internal|private|fileprivate|final|nonisolated)\s+)*"
    r"(struct|class|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)",
    re.M,
)
SUITE_ATTR = re.compile(r"@Suite\b(\()?")
TAGS_ARG = re.compile(r"\.tags\(([^)]*)\)")
MILESTONE_NAME = re.compile(r"^M\d+")


class Declaration:
    def __init__(self, path, text, kind, name, start, end, attr_start):
        self.path = path
        self.kind = kind
        self.name = name
        self.start = start
        self.attr_start = attr_start
        self.body = text[start:end]
        self.attributes = text[attr_start:start]


def balanced(text, open_index):
    """Index just past the parenthesis that closes the one at open_index."""
    depth = 0
    in_string = False
    index = open_index
    while index < len(text):
        char = text[index]
        if char == '"' and text[index - 1] != "\\":
            in_string = not in_string
        elif not in_string and char == "(":
            depth += 1
        elif not in_string and char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return len(text)


def attribute_start(text, decl_start):
    """Start of the attribute lines right above a column-0 declaration."""
    start = decl_start
    offset = decl_start
    unclosed = 0
    for line in reversed(text[:decl_start].split("\n")[:-1]):
        offset -= len(line) + 1
        if unclosed == 0 and not line.startswith(("@", ")")):
            break
        unclosed += line.count(")") - line.count("(")
        start = offset
    return start


def declarations(path):
    text = path.read_text()
    matches = list(DECL.finditer(text))
    found = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        found.append(Declaration(
            path, text, match.group(1), match.group(2), match.start(), end,
            attribute_start(text, match.start()),
        ))
    return text, found


def test_files():
    for target in sorted(TESTS.iterdir()):
        if not target.is_dir() or not target.name.endswith("Tests"):
            continue
        if target.name in SKIPPED_TARGETS:
            continue
        yield from sorted(target.rglob("*.swift"))


def existing_tags(attributes):
    match = SUITE_ATTR.search(attributes)
    if not match:
        return set()
    args = attributes[match.end() - 1:balanced(attributes, match.end() - 1)] if match.group(1) else ""
    tags = set()
    for group in TAGS_ARG.findall(args):
        tags |= {tag.strip().lstrip(".") for tag in group.split(",") if tag.strip()}
    return tags


def required_tags(primary, files_text):
    rel = primary.path.relative_to(TESTS).as_posix()
    tags = set()
    if "/Acceptance/" in f"/{rel}":
        tags.add("acceptance")
    if rel.startswith("OpenSkyFormats"):
        tags.add("parser")
    if any(DEVICE.search(text) for text in files_text):
        tags.add("gpu")
    return tags


def disabled_without_issue(path, text):
    errors = []
    for match in re.finditer(r"@(?:Test|Suite)\(", text):
        args = text[match.end() - 1:balanced(text, match.end() - 1)]
        for trait in re.finditer(r"\.disabled\b(\()?", args):
            if trait.group(1):
                trait_args = args[trait.end() - 1:balanced(args, trait.end() - 1)]
                if trait_args.lstrip("( \n").startswith("if:"):
                    continue
                if re.search(r"#\d+", trait_args):
                    continue
            line = text[:match.start()].count("\n") + 1
            errors.append(f"{path.relative_to(ROOT)}:{line}: .disabled names no issue (#NNN)")
    return errors


def add_tags(text, primary, missing):
    """Return text with `missing` tags added to the primary declaration's @Suite."""
    tags = ", ".join(f".{tag}" for tag in sorted(missing))
    attributes = primary.attributes
    match = SUITE_ATTR.search(attributes)
    if match and match.group(1):
        close = balanced(attributes, match.end() - 1)
        args = attributes[match.end():close - 1]
        tags_match = TAGS_ARG.search(args)
        if tags_match:
            inner = tags_match.group(1).rstrip()
            new_args = args[:tags_match.start(1)] + f"{inner}, {tags}" + args[tags_match.end(1):]
        elif args.strip():
            new_args = args.rstrip() + f", .tags({tags})"
        else:
            new_args = f".tags({tags})"
        new_attributes = attributes[:match.end()] + new_args + attributes[close - 1:]
    elif match:
        new_attributes = attributes[:match.start()] + f"@Suite(.tags({tags}))" + attributes[match.end():]
    else:
        new_attributes = f"@Suite(.tags({tags}))\n" + attributes
    return text[:primary.attr_start] + new_attributes + text[primary.start:]


def add_import(text):
    if not re.search(r"^import TagsTesting$", text, re.M):
        if re.search(r"^import Testing$", text, re.M):
            text = re.sub(r"^import Testing$", "import TagsTesting\nimport Testing", text, count=1, flags=re.M)
        else:
            imports = list(re.finditer(r"^(?:@testable )?import .*$", text, re.M))
            at = imports[-1].end() if imports else 0
            text = text[:at] + "\nimport TagsTesting\nimport Testing" + text[at:]
    return text


def main():
    fix = sys.argv[1:] == ["--fix"]
    texts = {}
    by_name = {}
    for path in test_files():
        text, found = declarations(path)
        texts[path] = text
        for decl in found:
            by_name.setdefault((path.relative_to(TESTS).parts[0], decl.name), []).append(decl)

    errors = []
    edits = {}
    for (_, name), decls in sorted(by_name.items()):
        primaries = [decl for decl in decls if decl.kind != "extension"]
        if len(primaries) != 1:
            continue
        primary = primaries[0]
        is_suite = "@Suite" in primary.attributes or any("@Test" in decl.body for decl in decls)
        if not is_suite:
            continue
        rel = primary.path.relative_to(ROOT)
        if "/Acceptance/" in f"/{rel.as_posix()}" and MILESTONE_NAME.match(name):
            errors.append(f"{rel}: suite {name} starts with a milestone number")
        files_text = {texts[decl.path] for decl in decls}
        missing = required_tags(primary, files_text) - existing_tags(primary.attributes)
        if missing:
            edits.setdefault(primary.path, []).append((primary, missing))
            listed = ", ".join(f".{tag}" for tag in sorted(missing))
            errors.append(f"{rel}: suite {name} needs {listed}")

    for path, text in texts.items():
        errors += disabled_without_issue(path, text)

    if fix:
        for path, pending in edits.items():
            text = texts[path]
            # Edit from the bottom up so earlier offsets stay valid.
            for primary, missing in sorted(pending, key=lambda item: -item[0].start):
                text = add_tags(text, primary, missing)
            path.write_text(add_import(text))
        print(f"[INFO] tagged {sum(len(p) for p in edits.values())} suites in {len(edits)} files")
        remaining = [error for error in errors if "needs ." not in error]
        for error in remaining:
            print(f"[ERROR] {error}", file=sys.stderr)
        return 1 if remaining else 0

    for error in errors:
        print(f"[ERROR] {error}", file=sys.stderr)
    if errors:
        print("[ERROR] fix: make lint-test-tags FIX=1 (tags only); see Tests/AGENTS.md",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
