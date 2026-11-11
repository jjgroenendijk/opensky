"""Design rule 2, as a report: how many other types each type uses.

Reads the index store that a build writes, through Xcode's libIndexStore, so the count sees
real symbols, not text. A type uses another when code inside it names that type or one of
its members. Only types this repository declares under src/Sources count: the standard
library and Apple's frameworks do not. A type's own nested types, and the type it is
nested in, do not count either. The composition root and the session scope build the object
graph, so they are left out by name. Fails nothing.
Usage: fan-out.py <DataStore> <repo>. See docs/decisions/design-metrics.md.
"""

import collections
import functools
import pathlib
import sys

from index_store import (REL_CONTAINED_BY, ROLE_DEFINITION, ROLE_REFERENCE, TYPE_KINDS,
                         occurrences, open_store, repository_records)

LIMIT = 40
# Building the object graph is their job (design rule 2).
WIRING = {
    "GameViewController",
    "GameSessionScope",
    "GameSessionScopeBuild",
    "GameSessionScopeFactories",
    "SessionPorts",
}
SHOWN_LIMITS = (10, 20, 30, 40)


def fan_out(definitions, references):
    """definitions: type usr -> (name, file). references: (container usrs, used usr).

    Maps each type usr to the set of other type usrs it uses. A member usr starts with the
    usr of its type, so the longest declared prefix names the type."""
    declared = set(definitions)

    @functools.lru_cache(maxsize=None)
    def owner(usr):
        best = None
        for end in range(1, len(usr) + 1):
            if usr[:end] in declared:
                best = usr[:end]
        return best

    used = collections.defaultdict(set)
    for containers, usr in references:
        target = owner(usr)
        if target is None:
            continue
        for container in containers:
            user = owner(container)
            if user is None or user.startswith(target) or target.startswith(user):
                continue
            used[user].add(target)
    return {user: targets for user, targets in used.items()
            if definitions[user][0] not in WIRING}


def findings(definitions, used, limit):
    """(count, name, file) for each type over `limit`, the largest first."""
    rows = [(len(targets), *definitions[user]) for user, targets in used.items()
            if len(targets) > limit]
    return sorted(rows, key=lambda row: (-row[0], row[1]))


def self_check():
    """A type that names three others is over a limit of 2. Its nested type, its own members,
    and a library type do not count."""
    hub, nested = "s:3App3HubC", "s:3App3HubC4PartV"
    parts = [f"s:3App1{letter}V" for letter in "ABC"]
    definitions = {hub: ("Hub", "src/Sources/App/Hub.swift"),
                   nested: ("Part", "src/Sources/App/Hub.swift")}
    definitions.update({usr: (usr[-2], "src/Sources/App/Parts.swift") for usr in parts})
    method = hub + "4tickyyF"
    references = [([method], usr + "5valueSivp") for usr in parts]
    references += [([method], nested), ([method], hub + "5countSivp"), ([method], "s:SiV")]
    used = fan_out(definitions, references)
    return [row[0] for row in findings(definitions, used, 2)] == [3]


def report(definitions, used):
    rows = findings(definitions, used, LIMIT)
    print(f"[INFO] design rule 2, fan-out per type: {len(rows)} types use more than "
          f"{LIMIT} others ({len(used)} types counted)")
    for count, name, path in rows:
        print(f"  {path}: {name} uses {count} types")
    modules = collections.Counter(path.split("/")[2] for _, _, path in rows)
    for module, count in modules.most_common():
        print(f"    {module}: {count}")
    for limit in SHOWN_LIMITS:
        print(f"[INFO] over {limit}: {len(findings(definitions, used, limit))}")


def main():
    if not self_check():
        print("[FAIL] fan-out self-check: a type over the limit was not found", file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    lib, store = opened
    definitions, references = {}, []
    for relative, record in repository_records(lib, store, repo):
        if not relative.startswith("src/Sources/"):
            continue
        for roles, kind, usr, name, relations in occurrences(lib, store, record):
            if roles & ROLE_DEFINITION and kind in TYPE_KINDS:
                definitions[usr] = (name, relative)
            elif roles & ROLE_REFERENCE:
                containers = [other for rel_roles, _, other in relations
                              if rel_roles & REL_CONTAINED_BY]
                references.append((containers, usr))
    report(definitions, fan_out(definitions, references))
    return 0


if __name__ == "__main__":
    sys.exit(main())
