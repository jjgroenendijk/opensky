"""A protocol exists only where a second conformer or a test fake passes through it.

Reports every protocol in an interface module that has one conformer in the sources and
none in the tests. Usage: single-conformers.py <DataStore> <repo> [--gate]. Without
--gate it reports and passes. See docs/decisions/ports-and-adapters.md.
"""

import pathlib
import re
import sys

from index_store import (PROTOCOL, REL_BASE_OF, ROLE_DEFINITION, ROLE_REFERENCE, occurrences,
                         open_store, repository_records)

INTERFACE_FILE = re.compile(r"^src/Sources/OpenSky\w*Interface/")


def descendants(protocol, children):
    """The protocols that refine `protocol`, directly or through others."""
    found, stack = set(), [protocol]
    while stack:
        for child in children.get(stack.pop(), ()):
            if child not in found:
                found.add(child)
                stack.append(child)
    return found


def single_conformers(protocols, conformances, refinements=()):
    """protocols: usr -> (name, file). conformances: (file, protocol usr, conformer usr).
    refinements: (protocol usr, refining protocol usr).

    A conformer in src/Tests is a fake; one in src/Sources is a real type. A type that
    conforms to a refining protocol conforms to the refined one too."""
    children = {}
    for parent, child in refinements:
        children.setdefault(parent, set()).add(child)
    direct_real, direct_fakes = {}, {}
    for path, protocol, conformer in conformances:
        side = direct_fakes if path.startswith("src/Tests/") else direct_real
        side.setdefault(protocol, set()).add(conformer)
    real, fakes = {}, {}
    for usr in protocols:
        family = {usr} | descendants(usr, children)
        real[usr] = set().union(*(direct_real.get(p, set()) for p in family))
        fakes[usr] = set().union(*(direct_fakes.get(p, set()) for p in family))
    return sorted(f"{file}: {name}" for usr, (name, file) in protocols.items()
                  if len(real.get(usr, ())) == 1 and not fakes.get(usr))


def self_check():
    """A port with one real conformer fails; one with a fake, a second conformer, or a
    refining port that has a fake passes."""
    protocols = {"s:4Lone": ("LonePort", "src/Sources/OpenSkyXInterface/LonePort.swift"),
                 "s:4Fake": ("FakedPort", "src/Sources/OpenSkyXInterface/FakedPort.swift"),
                 "s:4Pair": ("PairPort", "src/Sources/OpenSkyXInterface/PairPort.swift"),
                 "s:4Base": ("BasePort", "src/Sources/OpenSkyXInterface/BasePort.swift")}
    conformances = [("src/Sources/OpenSkyX/A.swift", "s:4Lone", "s:1A"),
                    ("src/Sources/OpenSkyX/A.swift", "s:4Fake", "s:1A"),
                    ("src/Tests/OpenSkyXTests/F.swift", "s:4Fake", "s:1F"),
                    ("src/Sources/OpenSkyX/A.swift", "s:4Pair", "s:1A"),
                    ("src/Sources/OpenSkyX/B.swift", "s:4Pair", "s:1B"),
                    ("src/Sources/OpenSkyX/A.swift", "s:4Base", "s:1A")]
    refinements = [("s:4Base", "s:4Fake")]
    return single_conformers(protocols, conformances, refinements) == [
        "src/Sources/OpenSkyXInterface/LonePort.swift: LonePort"]


def main():
    if not self_check():
        print("[FAIL] single-conformer self-check: a lone port passed", file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    gate = "--gate" in sys.argv[3:]
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    lib, store = opened
    protocols, conformances, refinements = {}, set(), set()
    for relative, record in repository_records(lib, store, repo):
        if not relative.startswith(("src/Sources/", "src/Tests/")):
            continue
        for roles, kind, usr, name, relations in occurrences(lib, store, record):
            if roles & ROLE_DEFINITION and kind == PROTOCOL and INTERFACE_FILE.search(relative):
                protocols[usr] = (name, relative)
            elif roles & ROLE_REFERENCE and kind == PROTOCOL:
                for rel_roles, other_kind, other in relations:
                    if not rel_roles & REL_BASE_OF:
                        continue
                    if other_kind == PROTOCOL:
                        refinements.add((usr, other))
                    else:
                        conformances.add((relative, usr, other))
    found = single_conformers(protocols, conformances, refinements)
    tag = "[FAIL]" if gate and found else "[INFO]"
    for line in found:
        print(f"{tag} one conformer and no test fake: {line}",
              file=sys.stderr if gate else sys.stdout)
    print(f"{'[FAIL]' if gate and found else '[ OK ]'} {len(found)} of {len(protocols)} "
          "interface protocols have one conformer and no test fake")
    return 1 if gate and found else 0


if __name__ == "__main__":
    sys.exit(main())
