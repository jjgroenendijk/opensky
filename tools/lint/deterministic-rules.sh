#!/bin/sh
# Deterministic game rules (docs/decisions/deterministic-rules.md), over every tracked
# Swift file of a package module:
#
#   1. No hidden randomness or clock in game-rule code: the feature, interface, and
#      world-domain modules, and every pure core (`*Core.swift`).
#   2. No global mutable state or singletons, except the installed switches and sinks
#      named in ALLOWED_GLOBALS.
#   3. No game events through the system notification centre.
#
# A self-check first runs each rule on small synthetic violations, which must fail.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import re
import sys

sys.path.insert(0, "tools/lint")
from swift_source import line_of, package_files

# Process-wide switches and sinks that one installer fills. Reasons are on the decision page.
ALLOWED_GLOBALS = {
    "EngineLogTap.lines",
    "LoadOptimisations.current",
    "PlayerSettingsOverrides.values",
    "RecordDecodeScope.openScopes",
    "AssetLoadQueue.shared",
    "AssetLoadQueue.background",
}
HIDDEN_SOURCE = re.compile(
    r"\b(SystemRandomNumberGenerator|arc4random\w*|drand48|UUID\(\)|Date\(\)|Date\.now\b"
    r"|Date\(timeIntervalSinceNow|DispatchTime\.now|DispatchWallTime\.now|ContinuousClock"
    r"|SuspendingClock|CFAbsoluteTimeGetCurrent|CACurrentMediaTime|mach_absolute_time"
    r"|mach_continuous_time|systemUptime|clock_gettime|gettimeofday|globallyUniqueString)"
    r"|\.(randomElement|shuffled|shuffle)\(\)|\b(Bool|Int\w*|UInt\w*|Float|Double|CGFloat)\.random\("
)
MUTABLE_HOLDER = (
    r"(Mutex|Atomic|NSLock|NSRecursiveLock|OSAllocatedUnfairLock|NSCache|NSMutable\w+"
    r"|DispatchQueue|OperationQueue)\b"
)
GLOBALS = [
    (re.compile(r"\bstatic var (\w+)(\s*:[^={\n]*)?(\s*=[^{\n]*)?$", re.M), "a mutable static"),
    (re.compile(r"^(?:\w+(?:\([^)]*\))? )*var (\w+)", re.M), "a mutable global"),
    (re.compile(r"\bnonisolated\(unsafe\)()"), "`nonisolated(unsafe)` state"),
    (re.compile(r"\bstatic let (\w+)\s*(?::[^=\n]*)?=\s*" + MUTABLE_HOLDER), "a shared mutable holder"),
    (re.compile(r"^(?:\w+ )*let (\w+)\s*(?::[^=\n]*)?=\s*" + MUTABLE_HOLDER, re.M), "a shared mutable holder"),
    (re.compile(r"\bstatic let (shared|instance)\b"), "a singleton"),
]
EVENT_BUS = re.compile(
    r"\b(NotificationCenter|DistributedNotificationCenter|NSNotification\.Name|Notification\.Name)\b"
)
TYPE_DECLARATION = re.compile(r"^\s*(?:[\w()]+ )*(?:enum|struct|class|actor|extension) (\w+)", re.M)


def rule_modules():
    text = open("Package.swift").read()
    names = set(re.findall(r'\b(?:feature|domain|interface)\(\s*"(\w+)"', text))
    return names | {name + "Interface" for name in names}


def owner(code, offset):
    """The innermost type or extension whose body holds `offset`."""
    name = ""
    for match in TYPE_DECLARATION.finditer(code, 0, offset):
        start = code.find("{", match.end())
        if start < 0 or start > offset:
            continue
        depth, index = 0, start
        while index < len(code):
            depth += {"{": 1, "}": -1}.get(code[index], 0)
            if depth == 0:
                break
            index += 1
        if index > offset:
            name = match.group(1)
    return name


def hidden_sources(code):
    found = []
    for match in HIDDEN_SOURCE.finditer(code):
        call = match.group(0)
        if call.endswith(".random("):
            rest = code[match.end() : code.find("\n", match.end())]
            if "using:" in rest:
                continue
        found.append((line_of(code, match.start()), f"`{call.rstrip('(')}`"))
    return found


def globals_in(code):
    found = []
    for pattern, what in GLOBALS:
        for match in pattern.finditer(code):
            line_start = code.rfind("\n", 0, match.start()) + 1
            prefix = code[max(0, line_start - 200) : match.start()]
            if "@TaskLocal" in prefix.split("\n")[-1] or "@TaskLocal" in prefix.split("\n")[-2:][0]:
                continue
            name = match.group(1)
            if name and f"{owner(code, match.start())}.{name}" in ALLOWED_GLOBALS:
                continue
            found.append((line_of(code, match.start()), f"{what} `{name or match.group(0)}`"))
    return found


def event_bus(code):
    return [(line_of(code, m.start()), f"`{m.group(1)}`") for m in EVENT_BUS.finditer(code)]


def self_check():
    cases = [
        (hidden_sources, "let roll = Float.random(in: 0 ..< 100)", True),
        (hidden_sources, "let roll = Float.random(in: 0 ..< 100, using: &generator)", False),
        (hidden_sources, "let id = UUID()", True),
        (hidden_sources, "let now = Date()", True),
        (hidden_sources, "let pick = names.randomElement()", True),
        (hidden_sources, "let watch = Stopwatch()", False),
        (globals_in, "enum Store {\n    static var count = 0\n}", True),
        (globals_in, "var counter = 0", True),
        (globals_in, "enum Tap {\n    static let lines = Mutex<[Int]>([])\n}", True),
        (globals_in, "enum EngineLogTap {\n    static let lines = Mutex<[Int]>([])\n}", False),
        (globals_in, "enum EngineLogTap {\n    struct Line {}\n    static let lines = Mutex<[Int]>([])\n}", False),
        (globals_in, "enum Loader {\n    static let shared = Loader()\n}", True),
        (globals_in, "enum Scope {\n    @TaskLocal static var value: Int?\n}", False),
        (globals_in, "enum Area {\n    static var size: Int { 4 }\n}", False),
        (globals_in, "struct Box {\n    var count = 0\n}", False),
        (event_bus, "NotificationCenter.default.post(name: .changed, object: nil)", True),
        (event_bus, "events.publish(.changed)", False),
    ]
    for rule, snippet, should_fail in cases:
        if bool(rule(snippet)) != should_fail:
            verdict = "missed" if should_fail else "rejected"
            sys.exit(f"[ERROR] deterministic-rules self-check: {rule.__name__} {verdict}: {snippet!r}")


self_check()
in_rules = rule_modules()
failures = []
for module, name, code in package_files():
    if module in in_rules or name.endswith("Core.swift"):
        for line, what in hidden_sources(code):
            failures.append(f"{name}:{line}: [ERROR] {what} is a hidden random source or clock; pass it in")
    for line, what in globals_in(code):
        failures.append(f"{name}:{line}: [ERROR] {what}; pass the state through an initializer")
    for line, what in event_bus(code):
        failures.append(f"{name}:{line}: [ERROR] {what} is a hidden event bus; use a typed port")
if failures:
    print("\n".join(failures))
    sys.exit(f"[ERROR] {len(failures)} deterministic-rule violations (docs/decisions/deterministic-rules.md)")
print("[ OK ] deterministic rules: no hidden random source, clock, global state, or event bus")
PY
