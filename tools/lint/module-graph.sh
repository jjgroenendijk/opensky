#!/bin/sh
# Module-graph check for The Modular Architecture (issue #636,
# docs/decisions/modular-architecture.md). Reads the package graph from
# `swift package dump-package`, so it needs no build. Every rule is a gate.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX" "$tree/src/Sources/OpenSkyY"
    printf '%s\n' '// swift-tools-version: 6.0' 'import PackageDescription' \
        'let package = Package(name: "probe", targets: [' \
        '    .target(name: "OpenSkyX"), .target(name: "OpenSkyY"),' '])' >"$tree/src/Package.swift"
    echo 'import OpenSkyY' >"$tree/src/Sources/OpenSkyX/A.swift"
    echo 'public let y = 1' >"$tree/src/Sources/OpenSkyY/B.swift"
    expect_failure "$0" "$tree" "rule 7: src/Sources/OpenSkyX/A.swift imports OpenSkyY"
fi

cd "$(git rev-parse --show-toplevel)"

# A file, not an environment variable: Linux caps one variable at 128 KiB, and
# the graph is larger.
MODULE_GRAPH="$(mktemp)"
trap 'rm -f "$MODULE_GRAPH"' EXIT
swift package --package-path src dump-package >"$MODULE_GRAPH"
export MODULE_GRAPH

python3 - <<'PY'
import json
import os
import pathlib
import re
import sys

# Rule 1. The lower modules, lowest layer first (module_layers.py). A lower module
# depends only on a module in a lower layer.
sys.path.insert(0, __import__("os").environ["OPENSKY_TOOLS"] + "/lint")
from module_layers import DOMAINS, LAYERS

DOMAIN_OWNER = "OpenSkyWorld"
# Rule 10. The renderer draws from one RenderFrameInput per frame and holds no game
# state, so it depends only on these: formats, loaded data, assets, and draw helpers.
RENDERER = "OpenSkyRendering"
RENDERER_DEPS = {
    "OpenSkyFormatsCore", "OpenSkyFormatsESM", "OpenSkyFormatsMesh", "OpenSkyFormatsSWF",
    "OpenSkyGameData", "OpenSkyShaderTypes", "OpenSkyShaders",
    "OpenSkyAssetCache", "CASTCEncoder", "OpenSkyImageKernels", "OpenSkyRenderCore",
    "OpenSkyRenderResources",
}
# Products of external packages. They sit below every layer.
EXTERNAL = {"HeapModule", "DequeModule", "ArgumentParser"}
# Rule 8. Shared by the app and OpenSkyCLI; may depend on anything.
COMPOSITION = {"OpenSkyPreview", "OpenSkySession"}
# Rule 14. An adapter module depends on lower modules, interfaces, the world feature and its
# domains, and the implementations of its own feature group, never on another feature's
# implementation. ADAPTER_OWNER names that group for each adapter module.
ADAPTER_OWNER = {"OpenSkyAgentAdapters": {"OpenSkyAgentControl"},
                 "OpenSkyActorAdapters": {"OpenSkyActors", "OpenSkyFactions"},
                 "OpenSkyAIAdapters": {"OpenSkyPerception"},
                 "OpenSkyCombatAdapters": {"OpenSkyCombat"},
                 "OpenSkyInventoryAdapters": {"OpenSkyInventory"},
                 "OpenSkyMagicAdapters": {"OpenSkyMagic"},
                 "OpenSkyMenuAdapters": {"OpenSkyMenus"},
                 "OpenSkyProgressionAdapters": {"OpenSkyProgression"},
                 "OpenSkyScriptAdapters": {"OpenSkyScripting"},
                 "OpenSkySessionAdapters": {"OpenSkySave"},
                 "OpenSkyStoryAdapters": {"OpenSkyCrime", "OpenSkyDialogue", "OpenSkyQuests"}}
# Rule 6. A feature without one of its targets, and why.
MISSING = {
}

layer = {name: index for index, names in enumerate(LAYERS) for name in names}
layer.update({name: -1 for name in EXTERNAL})
targets = json.loads(pathlib.Path(os.environ["MODULE_GRAPH"]).read_text())["targets"]
names = {target["name"] for target in targets}
deps = {
    target["name"]: [(dep.get("target") or dep.get("byName") or dep.get("product") or [None])[0]
                     for dep in target["dependencies"]]
    for target in targets
}
tests = {t["name"] for t in targets if t["type"] == "test"}
test_side = {t["name"] for t in targets
             if t["type"] == "regular" and (t.get("path") or "").startswith("Tests/")}
testing = {n for n in test_side if n.endswith("Testing")}
fixtures = {n for n in test_side if n.endswith("Fixtures")}
interfaces = {n for n in names if n.endswith("Interface") and n not in tests}
domain = {name: index for index, name in enumerate(DOMAINS)}
COMPOSITION |= {n for n in names if n.endswith("Adapters")}
features = names - set(layer) - set(domain) - COMPOSITION - tests - test_side - interfaces
failures = []
for name in sorted(test_side - testing - fixtures):
    failures.append(f"library {name} under src/Tests/ is named neither ...Testing nor ...Fixtures")
for name in sorted(fixtures):
    if name[:-len("Fixtures")] not in features | set(domain):
        failures.append(f"fixtures library {name} names no feature or domain")


def kind(name):
    if name in layer:
        return "lower"
    if name in domain:
        return "domain"
    if name in interfaces:
        return "interface"
    if name in testing:
        return "testing"
    if name in fixtures:
        return "fixtures"
    return "feature"


for name in sorted(n for n in names if n not in layer and n.endswith("Interface")):
    if name[:-len("Interface")] not in features | COMPOSITION:
        failures.append(f"interface {name} has no feature implementation")

for name in sorted(names):
    for dep in deps[name]:
        if name in layer:
            if dep not in layer or layer[dep] >= layer[name]:
                failures.append(f"rule 1: lower module {name} depends on {dep}")
        elif name in domain:
            if kind(dep) not in ("lower", "interface", "domain") or domain.get(dep, -1) >= domain[name]:
                failures.append(f"rule 9: domain {name} depends on {dep}")
        elif name in features:
            if kind(dep) == "domain" and name != DOMAIN_OWNER:
                failures.append(f"rule 9: feature {name} depends on the domain {dep}")
            elif kind(dep) not in ("lower", "interface", "domain"):
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
            # An adapter's API names the types of the feature it serves, so its tests may too.
            served = ADAPTER_OWNER.get(own, set())
            if (dep in features or dep in COMPOSITION) and dep != own and dep not in served:
                failures.append(f"rule 5: {name} depends on the implementation {dep}")
            if dep in fixtures and dep != own + "Fixtures":
                failures.append(f"rule 5: {name} depends on {dep}, another feature's fixtures")


def adapter_failures(name, found, kinds):
    """Rule 14 for one adapter module: found are its dependencies, kinds maps each to its kind."""
    own = ADAPTER_OWNER.get(name, set()) | {DOMAIN_OWNER}
    return [f"rule 14: adapter module {name} depends on the implementation {dep}; "
            f"use {dep}Interface" for dep in found
            if dep not in own and kinds(dep) == "feature"]


probe_kinds = {"OpenSkyProgression": "feature", "OpenSkyCombat": "feature",
               DOMAIN_OWNER: "feature", "OpenSkyCells": "domain",
               "OpenSkyCombatInterface": "interface"}
if len(adapter_failures("OpenSkyProgressionAdapters", list(probe_kinds), probe_kinds.get)) != 1:
    failures.append("rule 14 self-check: an adapter module depending on another feature passed")
for name in sorted(n for n in names if n.endswith("Adapters")):
    if name not in ADAPTER_OWNER:
        failures.append(f"rule 14: adapter module {name} names no own feature in ADAPTER_OWNER")
    else:
        failures += adapter_failures(name, deps[name], kind)

for dep in sorted(set(deps.get(RENDERER, [])) - RENDERER_DEPS):
    failures.append(f"rule 10: the renderer depends on {dep}; pass its state in RenderFrameInput")

for feature in sorted(features):
    for part in ("Interface", "Tests"):
        present = feature + part in names
        excused = (feature, part) in MISSING
        if not present and not excused:
            failures.append(f"rule 6: feature {feature} has no {feature}{part}")
        if present and excused:
            failures.append(
                f"rule 6: {feature}{part} exists; drop its exception from this check")
for name in DOMAINS:
    if name not in names:
        failures.append(f"rule 9: domain {name} is not a target")
    elif name + "Tests" not in names:
        failures.append(f"rule 9: domain {name} has no {name}Tests")
for (feature, part) in MISSING:
    if feature not in features:
        failures.append(f"rule 6: exception names {feature}, which is not a feature")

IMPORT = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|private|fileprivate)\s+)?"
    r"import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)",
    re.M,
)
PUBLIC_IMPORT = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*public\s+import\s+(?:\w+\s+)?(\w+)", re.M)
EXPORTED = re.compile(r"^\s*@_exported\s+import\b", re.M)


def public_import_failures(name, path, text):
    """Rule 11: an interface re-exports only lower modules and interfaces."""
    found = []
    if EXPORTED.search(text):
        found.append(f"rule 11: {path} uses @_exported import; write public import")
    if name in interfaces:
        for module in PUBLIC_IMPORT.findall(text):
            if module in names and kind(module) not in ("lower", "interface"):
                found.append(f"rule 11: interface {path} publicly imports {module}")
    return found


# Self-check: rule 11 rejects a small violation, so it cannot switch off unnoticed.
probe_interface = next(iter(sorted(interfaces)), None)
probe_feature = next(iter(sorted(features)), None)
if probe_interface and probe_feature:
    probe = f"public import {probe_feature}\n@_exported import Foundation\n"
    if len(public_import_failures(probe_interface, "self-check", probe)) != 2:
        failures.append("rule 11 self-check: a public import of a feature passed")

imports = 0
for target in targets:
    name = target["name"]
    root = "Tests" if name in tests else "Sources"
    folder = pathlib.Path("src", target.get("path") or f"{root}/{name}")
    allowed = set(deps[name]) | {name}
    used = set()
    for path in sorted(folder.rglob("*.swift")):
        text = path.read_text()
        failures += public_import_failures(name, path, text)
        for module in IMPORT.findall(text):
            imports += module in names
            used.add(module)
            if module in names and module not in allowed:
                failures.append(
                    f"rule 7: {path} imports {module}, which {name} does not declare")
    # Rule 12. A declared edge no file imports would distort the stability metric.
    for module in sorted(set(deps[name]) - used):
        failures.append(f"rule 12: {name} declares {module}, which no file of it imports")


# Rule 13. A module depends only on a module at least as stable. Instability is
# out / (in + out), counted over every target, tests included. An interface may be
# depended on at any instability, because it holds only ports.
def instability(graph):
    edges = {name: set(found) & graph.keys() for name, found in graph.items()}
    fan_in = dict.fromkeys(graph, 0)
    for found in edges.values():
        for dep in found:
            fan_in[dep] += 1
    return {name: len(edges[name]) / max(len(edges[name]) + fan_in[name], 1) for name in graph}


def stability_failures(graph, checked):
    value = instability(graph)
    return [
        f"rule 13: {name} (instability {value[name]:.3f}) depends on the less stable "
        f"{dep} ({value[dep]:.3f})"
        for name in sorted(checked) for dep in sorted(set(graph[name]) & graph.keys())
        if not dep.endswith("Interface") and value[dep] > value[name]
    ]


probe_graph = {"Stable": ["Loose"], "Loose": ["Low", "Base"], "Low": [], "Base": [],
               "UserA": ["Stable"], "UserB": ["Stable"]}
if len(stability_failures(probe_graph, probe_graph.keys())) != 1:
    failures.append("rule 13 self-check: a dependency on a less stable module passed")
failures += stability_failures(deps, names - tests - test_side)

if failures:
    print("[FAIL] module graph breaks The Modular Architecture:", file=sys.stderr)
    for line in failures:
        print(f"  {line}", file=sys.stderr)
    print("See docs/decisions/modular-architecture.md.", file=sys.stderr)
    raise SystemExit(1)
print(f"[ OK ] module graph follows TMA ({len(names)} targets, {imports} imports)")
PY
