#!/bin/sh
# Swift language rules (docs/decisions/language-rules.md). Two checks:
#
#   1. The package and the Xcode build turn on the same language features.
#      src/Package.swift lists them in `languageSettings`; src/config/Build/Base.xcconfig
#      sets the matching build settings. Every required feature is in both.
#   2. Self-check: each rule rejects a small violation. The script compiles one
#      snippet per rule with the flags it read from src/Package.swift. A snippet that
#      compiles means the rule no longer holds, so the check fails.
set -eu

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PY'
import pathlib
import re
import subprocess
import sys
import tempfile

PACKAGE = pathlib.Path("src/Package.swift")
XCCONFIG = pathlib.Path("src/config/Build/Base.xcconfig")

# Package setting -> the Xcode build setting that turns on the same feature.
UPCOMING = {
    "ExistentialAny": "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY",
    "InternalImportsByDefault": "SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT",
    "MemberImportVisibility": "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY",
    # SWIFT_APPROACHABLE_CONCURRENCY turns on both of these.
    "NonisolatedNonsendingByDefault": "SWIFT_APPROACHABLE_CONCURRENCY",
    "InferIsolatedConformances": "SWIFT_APPROACHABLE_CONCURRENCY",
}
STRICT_MEMORY_SAFETY = "SWIFT_STRICT_MEMORY_SAFETY"
REQUIRED = {"ExistentialAny", "InternalImportsByDefault", "StrictMemorySafety"}

# One violation per rule. Each must fail to compile with the package's flags.
VIOLATIONS = {
    "ExistentialAny": "protocol Shape {}\nfunc draw(_ shape: Shape) {}\n",
    "InternalImportsByDefault": "import Foundation\npublic func home() -> URL? { nil }\n",
    "StrictMemorySafety": (
        "func first(_ pointer: UnsafePointer<Int>) -> Int { pointer.pointee }\n"
    ),
}
CLEAN = (
    "public import Foundation\nprotocol Shape {}\nfunc draw(_ shape: any Shape) {}\n"
    "public func home() -> URL? { nil }\n"
    "func first(_ pointer: UnsafePointer<Int>) -> Int { unsafe pointer.pointee }\n"
)


def package_features():
    text = PACKAGE.read_text()
    block = re.search(r"let languageSettings: \[SwiftSetting\] = \[(.*?)\n\]", text, re.S)
    if not block:
        raise SystemExit(f"[FAIL] {PACKAGE} has no languageSettings list")
    body = block.group(1)
    found = set(re.findall(r'\.enableUpcomingFeature\("(\w+)"\)', body))
    if ".strictMemorySafety()" in body:
        found.add("StrictMemorySafety")
    return found


def xcconfig_settings():
    settings = {}
    for line in XCCONFIG.read_text().splitlines():
        match = re.match(r"\s*([A-Z_]+)\s*=\s*(\S+)", line)
        if match:
            settings[match.group(1)] = match.group(2)
    return settings


def flags(features):
    result = ["-swift-version", "6", "-warnings-as-errors"]
    for feature in sorted(features - {"StrictMemorySafety"}):
        result += ["-enable-upcoming-feature", feature]
    if "StrictMemorySafety" in features:
        result.append("-strict-memory-safety")
    return result


def compiles(source, features):
    with tempfile.TemporaryDirectory() as folder:
        path = pathlib.Path(folder, "Snippet.swift")
        path.write_text(source)
        run = subprocess.run(
            ["xcrun", "swiftc", "-typecheck", "-parse-as-library", *flags(features), str(path)],
            capture_output=True, text=True, check=False)
        return run.returncode == 0, run.stderr


failures = []
features = package_features()
settings = xcconfig_settings()
for feature in sorted(REQUIRED - features):
    failures.append(f"{PACKAGE} languageSettings does not turn on {feature}")
for feature in sorted(features):
    setting = STRICT_MEMORY_SAFETY if feature == "StrictMemorySafety" else UPCOMING.get(feature)
    if setting is None:
        failures.append(f"{feature} has no known Xcode build setting; add it to this check")
    elif settings.get(setting) != "YES":
        failures.append(f"{PACKAGE} turns on {feature}, but {XCCONFIG} lacks {setting} = YES")
for setting, value in sorted(settings.items()):
    known = set(UPCOMING.values()) | {STRICT_MEMORY_SAFETY}
    wanted = {f for f, s in UPCOMING.items() if s == setting}
    if setting == STRICT_MEMORY_SAFETY:
        wanted = {"StrictMemorySafety"}
    if setting in known and value == "YES" and not wanted & features:
        failures.append(f"{XCCONFIG} sets {setting}, but {PACKAGE} does not turn it on")

ok, errors = compiles(CLEAN, features)
if not ok:
    failures.append("self-check: the clean snippet does not compile:\n" + errors)
for rule, source in VIOLATIONS.items():
    ok, _ = compiles(source, features)
    if ok:
        failures.append(f"self-check: a {rule} violation compiles; the rule is off")

if failures:
    print("[FAIL] Swift language rules:", file=sys.stderr)
    for line in failures:
        print(f"  {line}", file=sys.stderr)
    print("See docs/decisions/language-rules.md.", file=sys.stderr)
    raise SystemExit(1)
print(f"[ OK ] language rules: {len(features)} features match, "
      f"{len(VIOLATIONS)} violations rejected")
PY
