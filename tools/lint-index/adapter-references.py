"""Ports-and-adapters rule 8: no adapter uses another adapter's type.

Reads the index store that a build writes, through Xcode's libIndexStore, so the check
sees real symbol references, not text. Usage: adapter-references.py <DataStore> <repo>.
See docs/decisions/ports-and-adapters.md.
"""

import pathlib
import re
import sys

from index_store import (INSTANCE_PROPERTY, REL_CONTAINED_BY, ROLE_DEFINITION, ROLE_REFERENCE,
                         TYPE_KINDS, occurrences, open_store, repository_records)

ADAPTER_FOLDER = re.compile(r"^src/Sources/(OpenSky\w*Adapters|OpenSky/GameView)/")


def module_of(path):
    return path.split("/")[2]


def stored(definitions, properties, references):
    """Maps each adapter to the adapters it stores in one of its own properties, in its own
    module. An owner stores its parts, and a part may store a sibling it calls."""
    edges = {}
    for path, containers, usr in references:
        if usr not in definitions:
            continue
        for container in containers:
            holder = next((d for d in definitions if container.startswith(d)), None)
            if container in properties and holder and holder != usr \
                    and module_of(definitions[usr][1]) == module_of(path):
                edges.setdefault(holder, set()).add(usr)
    return edges


def violations(definitions, properties, references):
    """definitions: adapter usr -> (name, file). references: (file, container usrs, usr) uses.

    A use breaks the rule when code inside one adapter names another adapter that it does
    not store itself. A part never names its owner, and no adapter names one of another
    feature."""
    edges = stored(definitions, properties, references)

    found = set()
    for path, containers, usr in references:
        if usr not in definitions:
            continue
        users = {d for d in definitions for c in containers if c.startswith(d)}
        for user in users:
            if user != usr and usr not in edges.get(user, set()):
                found.add(f"rule 8: {path}: {definitions[user][0]} uses the adapter "
                          f"{definitions[usr][0]}")
    return sorted(found)


def self_check():
    """An owner may use the part it stores. A part may not use its owner, and an adapter
    may not use one of another module, even one it stores."""
    magic, ward, combat = "s:A9MagicAdapterC", "s:A8WardPartV", "s:A10CombatAdapterC"
    definitions = {magic: ("MagicAdapter", "src/Sources/Magic/MagicAdapter.swift"),
                   ward: ("WardPart", "src/Sources/Magic/WardPart.swift"),
                   combat: ("CombatAdapter", "src/Sources/Combat/CombatAdapter.swift")}
    ward_property, combat_property = magic + "4wardvp", magic + "6combatvp"
    file = "src/Sources/Magic/MagicAdapter.swift"
    part_file = "src/Sources/Magic/WardPart.swift"
    references = [(file, [ward_property], ward), (file, [magic + "4tickyyF"], ward),
                  (file, [combat_property], combat), (part_file, [ward + "4tickyyF"], magic)]
    return len(violations(definitions, {ward_property, combat_property}, references)) == 2


def main():
    if not self_check():
        print("[FAIL] rule 8 self-check: an adapter using another adapter passed", file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    lib, store = opened
    definitions, properties, references = {}, set(), []
    for relative, record in repository_records(lib, store, repo):
        if not ADAPTER_FOLDER.search(relative):
            continue
        for roles, kind, usr, name, relations in occurrences(lib, store, record):
            containers = [other for rel_roles, _, other in relations
                          if rel_roles & REL_CONTAINED_BY]
            if roles & ROLE_DEFINITION and kind in TYPE_KINDS and name.endswith("Adapter"):
                definitions[usr] = (name, relative)
            elif roles & ROLE_DEFINITION and kind == INSTANCE_PROPERTY:
                properties.add(usr)
            elif roles & ROLE_REFERENCE:
                references.append((relative, containers, usr))
    found = violations(definitions, properties, references)
    if found:
        print("[FAIL] an adapter uses another adapter:", file=sys.stderr)
        for line in found:
            print(f"  {line}", file=sys.stderr)
        return 1
    print(f"[ OK ] no adapter uses another adapter ({len(definitions)} adapters)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
