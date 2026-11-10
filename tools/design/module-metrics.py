"""Design rule 6: each module's abstractness, instability, and distance from the main sequence.

Instability is I = Ce / (Ca + Ce): Ce counts the package modules this module depends on, Ca
the package modules that depend on it. Test targets, and the support modules under
src/Tests, count for neither. Abstractness is
A = protocols / types declared in the module's Swift files. Distance is D = |A + I - 1|.
A report that guides a review, not a gate: an interface module here holds value types as
well as protocols, so a large distance is a question, not a failure.
Usage: module-metrics.py <package.json from swift package dump-package> <repo> <output.md>.
See docs/decisions/design-metrics.md.
"""

import json
import pathlib
import re
import sys

DECLARATION = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|internal|fileprivate"
                         r"|private|open|final|indirect|nonisolated|distributed)\s+)*"
                         r"(protocol|struct|class|enum|actor)\s+\w", re.MULTILINE)


def dependencies(target):
    """The names of the targets and products one target depends on."""
    names = []
    for entry in target.get("dependencies", []):
        for kind in ("byName", "target", "product"):
            if kind in entry:
                names.append(entry[kind][0])
    return names


def metrics(targets, declarations):
    """targets: name -> dependency names, for the non-test targets. declarations: name ->
    (protocols, types). Returns name -> (Ca, Ce, I, A, D)."""
    efferent = {name: {dep for dep in deps if dep in targets and dep != name}
                for name, deps in targets.items()}
    afferent = {name: 0 for name in targets}
    for deps in efferent.values():
        for dep in deps:
            afferent[dep] += 1
    rows = {}
    for name in targets:
        ca, ce = afferent[name], len(efferent[name])
        instability = ce / (ca + ce) if ca + ce else 0.0
        protocols, types = declarations.get(name, (0, 0))
        abstractness = protocols / types if types else 0.0
        rows[name] = (ca, ce, instability, abstractness, abs(abstractness + instability - 1))
    return rows


def count(folder):
    """(protocols, types) declared in the Swift files under `folder`."""
    protocols = types = 0
    for path in sorted(folder.rglob("*.swift")):
        for match in DECLARATION.finditer(path.read_text(errors="ignore")):
            types += 1
            protocols += match.group(1) == "protocol"
    return protocols, types


def table(rows):
    lines = ["| Module | Ca | Ce | I | A | D |", "| --- | --- | --- | --- | --- | --- |"]
    for name, (ca, ce, instability, abstractness, distance) in sorted(
            rows.items(), key=lambda item: (-item[1][4], item[0])):
        lines.append(f"| {name} | {ca} | {ce} | {instability:.2f} | {abstractness:.2f} | "
                     f"{distance:.2f} |")
    return "\n".join(lines) + "\n"


def self_check():
    """A module only others use, holding only protocols, sits on the main sequence: I = 0,
    A = 1. A module that uses one other and holds no protocols does too: I = 1, A = 0. A
    concrete module that others use is the farthest away: D = 1."""
    targets = {"Port": [], "Feature": ["Port", "Swift"], "Core": [], "App": ["Core", "Port"]}
    declarations = {"Port": (2, 2), "Feature": (0, 3), "Core": (0, 4), "App": (0, 1)}
    rows = metrics(targets, declarations)
    sample = "public protocol A {}\n@MainActor final class B {}\nlet structure = 1\n"
    found = len(DECLARATION.findall(sample)) == 2
    return (found and rows["Port"][4] == 0 and rows["Feature"][4] == 0
            and rows["Core"][4] == 1 and rows["App"][2] == 1)


def main():
    if not self_check():
        print("[FAIL] module-metrics self-check: a known distance came out wrong", file=sys.stderr)
        return 1

    package = json.loads(pathlib.Path(sys.argv[1]).read_text())
    repo, output = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    targets, declarations = {}, {}
    for target in package["targets"]:
        if target["type"] == "test" or (target.get("path") or "").startswith("Tests/"):
            continue
        name = target["name"]
        targets[name] = dependencies(target)
        folder = repo / "src" / (target.get("path") or f"Sources/{name}")
        declarations[name] = count(folder)
    report = ("# Module metrics\n\nAbstractness (A), instability (I), and distance from the "
              "main sequence (D), largest distance first. See "
              "docs/decisions/design-metrics.md, rule 6.\n\n" + table(metrics(targets,
                                                                             declarations)))
    output.write_text(report)
    print(report, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
