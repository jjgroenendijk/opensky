"""Design rule 4: cycles between types declared in different files.

Reads the index store that a build writes, through Xcode's libIndexStore. Type A uses type B
when code inside A names B or one of its members, and both are declared in the same module
under src/Sources. A cycle is a group of types where each one reaches every other through
such uses. A cycle whose types sit in one file is allowed, such as a tree node and its
parent, or an owner and its delegate. A type's nested types, and the type it is nested in,
do not count as uses. With --gate it fails on any cycle; without, it reports and passes.
Usage: type-cycles.py <DataStore> <repo> [--gate]. See docs/decisions/design-metrics.md.
"""

import collections
import functools
import pathlib
import sys

from index_store import (REL_CONTAINED_BY, ROLE_DEFINITION, ROLE_REFERENCE, TYPE_KINDS,
                         occurrences, open_store, repository_records)


def uses(definitions, references):
    """definitions: type usr -> (name, file). references: (container usrs, used usr).

    Maps each type usr to the types of its own module it uses. A member usr starts with the
    usr of its type, so the longest declared prefix names the type."""
    declared = set(definitions)

    @functools.lru_cache(maxsize=None)
    def owner(usr):
        best = None
        for end in range(1, len(usr) + 1):
            if usr[:end] in declared:
                best = usr[:end]
        return best

    def module(usr):
        return definitions[usr][1].split("/")[2]

    graph = collections.defaultdict(set)
    for containers, usr in references:
        target = owner(usr)
        if target is None:
            continue
        for container in containers:
            user = owner(container)
            if (user is None or user.startswith(target) or target.startswith(user)
                    or module(user) != module(target)):
                continue
            graph[user].add(target)
    return graph


def components(graph):
    """The strongly connected groups of more than one type, by Tarjan's algorithm, without
    recursion so a deep graph does not reach Python's stack limit."""
    index, low, on_stack, stack, groups = {}, {}, set(), [], []
    for start in list(graph):
        if start in index:
            continue
        work = [(start, iter(sorted(graph.get(start, ()))))]
        index[start] = low[start] = len(index)
        stack.append(start)
        on_stack.add(start)
        while work:
            node, children = work[-1]
            child = next(children, None)
            if child is not None:
                if child not in index:
                    index[child] = low[child] = len(index)
                    stack.append(child)
                    on_stack.add(child)
                    work.append((child, iter(sorted(graph.get(child, ())))))
                elif child in on_stack:
                    low[node] = min(low[node], index[child])
                continue
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[node])
            if low[node] == index[node]:
                group = []
                while True:
                    member = stack.pop()
                    on_stack.discard(member)
                    group.append(member)
                    if member == node:
                        break
                if len(group) > 1:
                    groups.append(group)
    return groups


def findings(definitions, graph):
    """(module, files, names) for each cycle whose types sit in more than one file, the
    largest first."""
    rows = []
    for group in components(graph):
        files = sorted({definitions[usr][1] for usr in group})
        if len(files) > 1:
            names = sorted(definitions[usr][0] for usr in group)
            rows.append((files[0].split("/")[2], files, names))
    return sorted(rows, key=lambda row: (-len(row[2]), row[0], row[2]))


def self_check():
    """Two types in two files that use each other form a cycle. A node and its parent in one
    file do not, and neither does a use in one direction only."""
    a, b, c = "s:3App1AC", "s:3App1BC", "s:3App1CV"
    node, parent = "s:3App4NodeC", "s:3App6ParentC"
    definitions = {a: ("A", "src/Sources/App/A.swift"), b: ("B", "src/Sources/App/B.swift"),
                   c: ("C", "src/Sources/App/C.swift"),
                   node: ("Node", "src/Sources/App/Tree.swift"),
                   parent: ("Parent", "src/Sources/App/Tree.swift")}
    references = [([a + "3runyyF"], b + "4stepyyF"), ([b + "4stepyyF"], a),
                  ([b + "4stepyyF"], c), ([node + "2upyyF"], parent), ([parent], node)]
    rows = findings(definitions, uses(definitions, references))
    return [row[2] for row in rows] == [["A", "B"]]


def report(rows, gate):
    failed = gate and bool(rows)
    tag = "[FAIL]" if failed else "[INFO]" if rows else "[ OK ]"
    types = sum(len(names) for _, _, names in rows)
    print(f"{tag} design rule 4, cycles across files: {len(rows)} cycles, {types} types")
    for module, files, names in rows:
        shown = ", ".join(names[:8]) + (", ..." if len(names) > 8 else "")
        print(f"  {module}: {len(names)} types in {len(files)} files: {shown}",
              file=sys.stderr if failed else sys.stdout)
    for module, count in collections.Counter(row[0] for row in rows).most_common():
        print(f"    {module}: {count}")


def main():
    if not self_check():
        print("[FAIL] type-cycles self-check: a cycle across files was not found",
              file=sys.stderr)
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
    rows = findings(definitions, uses(definitions, references))
    gate = "--gate" in sys.argv[3:]
    report(rows, gate)
    return 1 if gate and rows else 0


if __name__ == "__main__":
    sys.exit(main())
