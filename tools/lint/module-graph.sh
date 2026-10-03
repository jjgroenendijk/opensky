#!/bin/sh
# Module-graph check for The Modular Architecture (issue #636,
# docs/decisions/modular-architecture.md). Reads the package graph from
# `swift package dump-package`, so it needs no build. Every rule is a gate.
set -eu

cd "$(git rev-parse --show-toplevel)"

# A file, not an environment variable: Linux caps one variable at 128 KiB, and
# the graph is larger.
MODULE_GRAPH="$(mktemp)"
trap 'rm -f "$MODULE_GRAPH"' EXIT
swift package dump-package >"$MODULE_GRAPH"
export MODULE_GRAPH

python3 - <<'PY'
import json
import os
import pathlib
import re
import sys

# Rule 1. The lower modules, lowest layer first. A lower module depends only on
# a module in a lower layer.
LAYERS = [
    ["OpenSkyShaderTypes", "CFFmpeg"],
    ["OpenSkyFormatsCore"],
    ["OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsAnimation",
     "OpenSkyFormatsAudio", "OpenSkyFormatsPEX", "OpenSkyFormatsSWF"],
    ["OpenSkyGameData"],
    ["OpenSkyBehavior", "OpenSkyLaunch"],
    ["OpenSkyPhysics", "OpenSkyDiagnostics", "OpenSkyAgentControl"],
    ["OpenSkyRendering", "OpenSkyAudio", "OpenSkyWorldState"],
    ["OpenSkyConditions"],
]
# Rule 8. Shared by the app and OpenSkyCLI; may depend on anything.
COMPOSITION = {"OpenSkyPreview"}
# Rule 6. A feature without one of its targets, and why.
MISSING = {
    ("OpenSkyMenus", "Interface"): "nothing depends on menus",
    ("OpenSkyMenus", "Testing"): "no other tests need menu fakes",
    ("OpenSkySave", "Interface"): "nothing depends on saves",
    ("OpenSkyCombat", "Testing"): "its fakes fake seams the implementation declares",
    ("OpenSkySave", "Testing"): "nothing depends on saves",
    ("OpenSkyScripting", "Testing"): "its fixtures run the Papyrus implementation",
}

layer = {name: index for index, names in enumerate(LAYERS) for name in names}
targets = json.loads(pathlib.Path(os.environ["MODULE_GRAPH"]).read_text())["targets"]
names = {target["name"] for target in targets}
deps = {
    target["name"]: [dep.get("target", dep.get("byName", [None]))[0]
                     for dep in target["dependencies"]]
    for target in targets
}
tests = {t["name"] for t in targets if t["type"] == "test"}
test_side = {t["name"] for t in targets
             if t["type"] == "regular" and (t.get("path") or "").startswith("Tests/")}
testing = {n for n in test_side if n.endswith("Testing")}
fixtures = {n for n in test_side if n.endswith("Fixtures")}
interfaces = {n for n in names if n.endswith("Interface") and n not in tests}
features = names - set(layer) - COMPOSITION - tests - test_side - interfaces
failures = []
for name in sorted(test_side - testing - fixtures):
    failures.append(f"library {name} under Tests/ is named neither ...Testing nor ...Fixtures")
for name in sorted(fixtures):
    if name[:-len("Fixtures")] not in features:
        failures.append(f"fixtures library {name} names no feature")


def kind(name):
    if name in layer:
        return "lower"
    if name in interfaces:
        return "interface"
    if name in testing:
        return "testing"
    if name in fixtures:
        return "fixtures"
    return "feature"


for name in sorted(n for n in names if n not in layer and n.endswith("Interface")):
    if name[:-len("Interface")] not in features:
        failures.append(f"interface {name} has no feature implementation")

for name in sorted(names):
    for dep in deps[name]:
        if name in layer:
            if dep not in layer or layer[dep] >= layer[name]:
                failures.append(f"rule 1: lower module {name} depends on {dep}")
        elif name in features:
            if kind(dep) not in ("lower", "interface"):
                failures.append(
                    f"rule 2: feature {name} depends on {dep}; use {dep}Interface")
        elif name in interfaces:
            if kind(dep) not in ("lower", "interface"):
                failures.append(f"rule 3: interface {name} depends on {dep}")
        elif name in testing:
            if kind(dep) in ("feature", "fixtures") or dep in COMPOSITION:
                failures.append(f"rule 4: testing library {name} depends on {dep}")
        elif name in fixtures:
            own = name[:-len("Fixtures")]
            if kind(dep) in ("feature", "fixtures") and dep != own or dep in COMPOSITION:
                failures.append(f"rule 4: fixtures library {name} depends on {dep}")
        elif name in tests:
            own = name[:-len("Tests")]
            if (dep in features or dep in COMPOSITION) and dep != own:
                failures.append(f"rule 5: {name} depends on the implementation {dep}")
            if dep in fixtures and dep != own + "Fixtures":
                failures.append(f"rule 5: {name} depends on {dep}, another feature's fixtures")

for feature in sorted(features):
    for part in ("Interface", "Testing", "Tests"):
        present = feature + part in names
        excused = (feature, part) in MISSING
        if not present and not excused:
            failures.append(f"rule 6: feature {feature} has no {feature}{part}")
        if present and excused:
            failures.append(
                f"rule 6: {feature}{part} exists; drop its exception from this check")
for (feature, part) in MISSING:
    if feature not in features:
        failures.append(f"rule 6: exception names {feature}, which is not a feature")

IMPORT = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|private|fileprivate)\s+)?"
    r"import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)",
    re.M,
)
imports = 0
for target in targets:
    name = target["name"]
    root = "Tests" if name in tests else "Sources"
    folder = pathlib.Path(target.get("path") or f"{root}/{name}")
    allowed = set(deps[name]) | {name}
    for path in sorted(folder.rglob("*.swift")):
        for module in IMPORT.findall(path.read_text()):
            imports += module in names
            if module in names and module not in allowed:
                failures.append(
                    f"rule 7: {path} imports {module}, which {name} does not declare")

if failures:
    print("[FAIL] module graph breaks The Modular Architecture:", file=sys.stderr)
    for line in failures:
        print(f"  {line}", file=sys.stderr)
    print("See docs/decisions/modular-architecture.md.", file=sys.stderr)
    raise SystemExit(1)
print(f"[ OK ] module graph follows TMA ({len(names)} targets, {imports} imports)")
PY
