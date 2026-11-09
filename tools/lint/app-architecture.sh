#!/bin/sh
# Ports and adapters for the app layer: adapter modules, narrow hosts of ports and
# values, and small types (docs/decisions/ports-and-adapters.md). A self-check runs
# each rule on a synthetic violation first, which must fail.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"

cd "$(git rev-parse --show-toplevel)"

python3 - "$@" <<'PY'
import collections
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, __import__("os").environ["OPENSKY_TOOLS"] + "/lint")
from module_layers import DATA, FOUNDATION
from swift_source import code_only, line_of

HOST_MEMBERS = 12
TYPE_EXTENSION_FILES = 4
TYPE_LINES = 600
UI_IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+(AppKit|Cocoa|SwiftUI|MetalKit)\b", re.M)
DECLARATION = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|package|open"
    r"|final|nonisolated|indirect)\s+)*(class|struct|enum|actor|protocol|extension|typealias)"
    r"\s+([A-Za-z_]\w*)",
    re.M,
)
VALUE_TYPES = {
    "Bool", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32",
    "UInt64", "Float", "Double", "String", "Character", "Data", "URL", "Date", "UUID",
    "Duration", "Void", "Never", "Set", "Array", "Dictionary", "Optional", "Result",
    "Range", "ClosedRange", "SIMD2", "SIMD3", "SIMD4", "simd_quatf", "float4x4", "float3x3",
    "CGFloat", "CGPoint", "CGSize", "CGRect", "TimeInterval", "Self",
}
TYPE_NAME = re.compile(r"\b[A-Z]\w*")


def braces(code, start):
    """The offset of the brace that closes the first block at or after `start`."""
    opening = code.find("{", start)
    if opening < 0:
        return start
    depth = 0
    for index in range(opening, len(code)):
        depth += {"{": 1, "}": -1}.get(code[index], 0)
        if depth == 0:
            return index
    return len(code)


def module_of(path):
    return path.split("/")[2]


def is_adapter_module(module):
    return module.endswith("Adapters")


def is_interface_module(module):
    return module.endswith("Interface")


def parse(sources):
    """Declarations by type name: [(kind, path, module, first line, last line, body)]."""
    found = collections.defaultdict(list)
    for path, text in sources.items():
        code = code_only(text)
        for match in DECLARATION.finditer(code):
            kind, name = match.group(1), match.group(2)
            end = match.end() if kind == "typealias" else braces(code, match.end())
            found[name].append((
                kind, path, module_of(path), line_of(code, match.start()),
                line_of(code, end), code[match.end():end]
            ))
    return found


def type_kind(name, found):
    """value, port, protocol, or reference for a declared type name. A protocol of an
    interface, foundation, or adapter module is a port, and so is a class of loaded data.
    An adapter module declares a port for the records it reads, so a test can fake them."""
    if name in VALUE_TYPES:
        return "value"
    kinds = [(kind, module) for kind, _, module, _, _, _ in found.get(name, []) if kind != "extension"]
    if not kinds:
        return "unknown"
    kind, module = kinds[0]
    if kind in ("struct", "enum", "typealias"):
        return "value"
    if kind == "protocol":
        known = is_interface_module(module) or is_adapter_module(module) or module in FOUNDATION
        return "port" if known else "protocol"
    return "port" if module in DATA else "reference"


def host_members(name, found, seen=None):
    """[(member line, member text)] of a host protocol and the hosts it inherits."""
    seen = seen or set()
    if name in seen:
        return []
    seen.add(name)
    members = []
    for kind, path, _, first, _, body in found.get(name, []):
        if kind != "protocol":
            continue
        header = body.split("{", 1)[0]
        for parent in re.findall(r"\b(\w+Host)\b", header):
            members += host_members(parent, found, seen)
        inner = body.split("{", 1)[1] if "{" in body else ""
        for member in re.finditer(r"^\s*(?:@\w+\s+)*(?:static\s+)?(var|func|subscript)\b[^\n]*", inner, re.M):
            members.append((f"{path}:{first}", member.group(0).strip()))
    return members


def member_types(member):
    """The type names a host member hands out: a var's type, or a func's result."""
    if member.startswith("var "):
        text = member.split(":", 1)[1] if ":" in member else ""
        text = text.split("{", 1)[0]
    else:
        text = member.split("->", 1)[1] if "->" in member else ""
    text = re.sub(r"\bany\s+|\bsome\s+", "", text)
    return TYPE_NAME.findall(text)


def host_problems(found):
    problems = []
    for name, entries in sorted(found.items()):
        protocols = [e for e in entries if e[0] == "protocol"]
        if not name.endswith("Host") or not protocols:
            continue
        if not (protocols[0][2] == "OpenSky" or is_adapter_module(protocols[0][2])):
            continue
        members = host_members(name, found)
        where = next(f"{path}:{first}" for kind, path, _, first, _, _ in entries if kind == "protocol")
        if len(members) > HOST_MEMBERS:
            problems.append(f"{where}: rule 3: host {name} has {len(members)} members, over {HOST_MEMBERS}")
        for _, member in members:
            for type_name in member_types(member):
                kind = type_kind(type_name, found)
                if kind not in ("value", "port"):
                    problems.append(f"{where}: rule 2: {name} hands out {type_name} ({kind}): {member}")
    return problems


def app_adapter_problems(sources):
    problems = []
    for path, text in sources.items():
        if module_of(path) != "OpenSky" or UI_IMPORT.search(text):
            continue
        for match in re.finditer(r"^(?:final\s+)?class\s+(\w+Adapter)\b", code_only(text), re.M):
            problems.append(f"{path}: rule 1: {match.group(1)} needs no AppKit; move it to an adapter module")
    return problems


def type_size_problems(found):
    problems = []
    for name, entries in sorted(found.items()):
        declared = [e for e in entries if e[0] in ("class", "struct", "enum", "actor")]
        if not declared or not (module_of(declared[0][1]) == "OpenSky" or is_adapter_module(declared[0][2])):
            continue
        home = {path for _, path, *_ in declared}
        extensions = {path for kind, path, *_ in entries if kind == "extension" and path not in home}
        lines = sum(last - first + 1 for kind, _, _, first, last, _ in entries if kind != "protocol")
        where = f"{declared[0][1]}:{declared[0][3]}"
        if len(extensions) > TYPE_EXTENSION_FILES:
            problems.append(f"{where}: rule 4: {name} has {len(extensions)} extension files, over {TYPE_EXTENSION_FILES}")
        if lines > TYPE_LINES:
            problems.append(f"{where}: rule 4: {name} has {lines} lines, over {TYPE_LINES}")
    return problems


def check(sources):
    found = parse(sources)
    return app_adapter_problems(sources) + host_problems(found) + type_size_problems(found)


def self_check():
    many = "\n".join(f"    var v{index}: Int {{ get }}" for index in range(HOST_MEMBERS + 1))
    cases = {
        "rule 1": {"src/Sources/OpenSky/GameView/A.swift": "final class MagicWorldAdapter {}\n"},
        "rule 2": {
            "src/Sources/OpenSky/GameView/B.swift": "protocol BHost: AnyObject {\n    var renderer: Renderer { get }\n}\n",
            "src/Sources/OpenSkyRendering/R.swift": "public final class Renderer {}\n",
        },
        "rule 3": {"src/Sources/OpenSky/GameView/C.swift": f"protocol CHost: AnyObject {{\n{many}\n}}\n"},
        "rule 4": {
            f"src/Sources/OpenSky/GameView/D{index}.swift": "extension DThing {\n}\n"
            for index in range(TYPE_EXTENSION_FILES + 1)
        } | {"src/Sources/OpenSky/GameView/D.swift": "final class DThing {}\n"},
    }
    for rule, sources in cases.items():
        if not any(rule + ":" in problem for problem in check(sources)):
            sys.exit(f"[ERROR] app-architecture self-check: {rule} missed its violation")
    clean = {
        "src/Sources/OpenSkyMagicInterface/P.swift": "public protocol SpellHitApplying {}\n",
        "src/Sources/OpenSky/GameView/E.swift": "import AppKit\nprotocol EHost: AnyObject {\n"
        "    var hits: any SpellHitApplying { get }\n    var count: Int { get }\n}\n"
        "final class ViewAdapter {}\n",
        "src/Sources/OpenSkyMagicAdapters/F.swift": "public protocol FRecordsPort {}\n"
        "protocol FHost: AnyObject {\n    var records: (any FRecordsPort)? { get }\n}\n",
    }
    if check(clean):
        sys.exit(f"[ERROR] app-architecture self-check: a clean tree failed: {check(clean)}")


self_check()
if sys.argv[1:] == ["--self-check"]:
    print("[ OK ] app-architecture self-check")
    sys.exit(0)
tracked = subprocess.run(
    ["git", "ls-files", "src/Sources/*.swift"], capture_output=True, text=True, check=True
).stdout.split()
sources = {
    path: pathlib.Path(path).read_text()
    for path in tracked
    if pathlib.Path(path).exists() and not pathlib.Path(path).name.startswith("._")
}
problems = check(sources)
if problems:
    print("\n".join(problems))
    sys.exit(f"[ERROR] {len(problems)} app-architecture violations (docs/decisions/ports-and-adapters.md)")
print("[ OK ] app architecture: adapters in packages, narrow hosts of ports, small types")
PY
