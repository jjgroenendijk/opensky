"""Module cohesion, as a report: the natural groups of the type graph against the modules.

Reads the index store, as the fan-out check does. Each type is a node; type A links to type B
when code inside A names B or one of its members. The Louvain method (Blondel and others,
2008) finds groups with many links inside and few between. Modularity (Newman) scores a
grouping from 0 to about 1. The report prints the modularity of the module partition and of
the Louvain groups, and for each module its number of groups and the share of its types in
its largest group. For each type over the fan-out limit it also prints member groups, each a
candidate for its own type. Fails nothing.
Usage: design-groups.py <DataStore> <repo>. See docs/decisions/design-metrics.md.
"""

import collections
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "lint-index"))
from index_store import (REL_ACCESSOR_OF, REL_CONTAINED_BY, ROLE_DEFINITION,  # noqa: E402
                         ROLE_REFERENCE, TYPE_KINDS, occurrences, open_store,
                         repository_records)

SEED = 1
FAN_OUT_LIMIT = 40
SHOWN_MODULE_SIZE = 15
SIMILARITY = 0.3
# A module with less of its types in one group than this is listed with its groups.
ONE_JOB_SHARE = 0.5
MEMBER_KINDS = {16, 17, 18, 19, 20, 21, 22}


def add_edge(adjacency, a, b, weight):
    adjacency.setdefault(a, {})
    adjacency.setdefault(b, {})
    if a == b:
        adjacency[a][a] = adjacency[a].get(a, 0) + weight
        return
    adjacency[a][b] = adjacency[a].get(b, 0) + weight
    adjacency[b][a] = adjacency[b].get(a, 0) + weight


def degrees(adjacency):
    """A self loop holds the weight inside an aggregated node, so it counts twice."""
    return {n: sum(w for m, w in nbrs.items() if m != n) + 2 * nbrs.get(n, 0)
            for n, nbrs in adjacency.items()}


def one_level(adjacency, rng):
    """Moves each node to the neighbouring group with the best modularity gain, until no
    move helps. Returns node -> group."""
    degree = degrees(adjacency)
    twice_m = sum(degree.values())
    group = {n: n for n in adjacency}
    total = dict(degree)
    order = sorted(adjacency, key=str)
    rng.shuffle(order)
    moved = True
    while moved and twice_m:
        moved = False
        for node in order:
            current, k = group[node], degree[node]
            links = collections.defaultdict(float)
            for other, w in adjacency[node].items():
                if other != node:
                    links[group[other]] += w
            total[current] -= k
            best = current
            best_gain = links.get(current, 0) - total[current] * k / twice_m
            for candidate in sorted(links, key=str):
                gain = links[candidate] - total[candidate] * k / twice_m
                if gain > best_gain + 1e-12:
                    best, best_gain = candidate, gain
            total[best] += k
            if best != current:
                group[node] = best
                moved = True
    return group


def aggregate(adjacency, group):
    merged = {}
    for a, nbrs in adjacency.items():
        merged.setdefault(group[a], {})
        for b, w in nbrs.items():
            if a == b:
                add_edge(merged, group[a], group[a], w)
            elif group[a] == group[b]:
                add_edge(merged, group[a], group[a], w / 2)
            elif str(a) < str(b):
                add_edge(merged, group[a], group[b], w)
    return merged


def louvain(adjacency, seed=SEED):
    """Groups of nodes, the largest first. A fixed seed gives the same groups on each run."""
    rng = random.Random(seed)
    member = {n: n for n in adjacency}
    current = adjacency
    while True:
        group = one_level(current, rng)
        if len(set(group.values())) == len(current):
            break
        member = {n: group[g] for n, g in member.items()}
        current = aggregate(current, group)
    groups = collections.defaultdict(set)
    for n, g in member.items():
        groups[g].add(n)
    return sorted(groups.values(), key=lambda g: (-len(g), sorted(map(str, g))[0]))


def modularity(adjacency, groups):
    degree = degrees(adjacency)
    twice_m = sum(degree.values())
    if not twice_m:
        return 0.0
    score = 0.0
    for members in groups:
        inside = sum(w for a in members for b, w in adjacency.get(a, {}).items()
                     if b in members and b != a)
        inside += sum(2 * adjacency.get(a, {}).get(a, 0) for a in members)
        total = sum(degree.get(a, 0) for a in members)
        score += inside / twice_m - (total / twice_m) ** 2
    return score


def self_check():
    """Two triangles joined by one link form two groups, and the grouping scores above 0.3."""
    adjacency = {}
    for a, b in [(1, 2), (2, 3), (1, 3), (4, 5), (5, 6), (4, 6), (3, 4)]:
        add_edge(adjacency, a, b, 1)
    groups = louvain(adjacency)
    return sorted(map(sorted, groups)) == [[1, 2, 3], [4, 5, 6]] \
        and modularity(adjacency, groups) > 0.3


def load(store_path, repo):
    lib, store = open_store(store_path)
    types, members, accessor_of, references = {}, set(), {}, []
    for relative, record in repository_records(lib, store, repo):
        if not relative.startswith("src/Sources/"):
            continue
        for roles, kind, usr, name, relations in occurrences(lib, store, record):
            if roles & ROLE_DEFINITION:
                if kind in TYPE_KINDS:
                    types[usr] = (name, relative)
                accessors = [u for r, _, u in relations if r & REL_ACCESSOR_OF]
                if accessors:
                    accessor_of[usr] = accessors[0]
                elif kind in MEMBER_KINDS:
                    members.add((usr, name))
            if roles & ROLE_REFERENCE:
                containers = [u for r, _, u in relations if r & REL_CONTAINED_BY]
                references.append((containers, usr))
    return types, members, accessor_of, references


class Graph:
    """The type graph, and for each member the members and outside types it uses."""

    def __init__(self, types, members, accessor_of, references):
        self.types = types
        declared = set(types)
        cache = {}

        def owner(usr):
            if usr not in cache:
                best = None
                for end in range(1, len(usr) + 1):
                    if usr[:end] in declared:
                        best = usr[:end]
                cache[usr] = best
            return cache[usr]

        self.member_name = {}
        self.member_type = {}
        for usr, name in members:
            if owner(usr):
                self.member_name[usr] = name
                self.member_type[usr] = owner(usr)

        def member_of(usr):
            while usr in accessor_of:
                usr = accessor_of[usr]
            return usr if usr in self.member_type else None

        self.adjacency = {t: {} for t in types}
        self.inner = collections.defaultdict(collections.Counter)
        self.outer = collections.defaultdict(set)
        for containers, usr in references:
            target, target_member = owner(usr), member_of(usr)
            for container in containers:
                user, member = owner(container), member_of(container)
                if user and target and not (user.startswith(target) or target.startswith(user)):
                    add_edge(self.adjacency, user, target, 1)
                if not member:
                    continue
                home = self.member_type[member]
                if target_member and self.member_type[target_member] == home \
                        and target_member != member:
                    self.inner[member][target_member] += 1
                elif target and not (target.startswith(home) or home.startswith(target)):
                    self.outer[member].add(target)
        self.by_type = collections.defaultdict(list)
        for usr, home in self.member_type.items():
            self.by_type[home].append(usr)

    def module(self, usr):
        return self.types[usr][1].split("/")[2]

    def member_groups(self, type_usr):
        """Members linked by a call, or by sharing most of the outside types they use."""
        names = sorted(self.by_type[type_usr])
        adjacency = {m: {} for m in names}
        for m in names:
            for other, w in self.inner[m].items():
                if other in adjacency and str(m) < str(other):
                    add_edge(adjacency, m, other, w)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                shared = self.outer[a] & self.outer[b]
                if shared:
                    similarity = len(shared) / len(self.outer[a] | self.outer[b])
                    if similarity >= SIMILARITY:
                        add_edge(adjacency, a, b, similarity)
        return louvain(adjacency)


def module_report(graph):
    groups = louvain(graph.adjacency)
    by_module = collections.defaultdict(set)
    for usr in graph.types:
        by_module[graph.module(usr)].add(usr)
    links = sum(len(n) for n in graph.adjacency.values()) // 2
    print(f"[INFO] module cohesion: {len(graph.types)} types, {links} links")
    print(f"[INFO] modularity of the modules: {modularity(graph.adjacency, by_module.values()):.2f}")
    print(f"[INFO] modularity of the Louvain groups: {modularity(graph.adjacency, groups):.2f}")
    group_of = {u: i for i, g in enumerate(groups) for u in g}
    rows = []
    for module, usrs in by_module.items():
        if len(usrs) < SHOWN_MODULE_SIZE:
            continue
        counts = collections.Counter(group_of[u] for u in usrs)
        rows.append((counts.most_common(1)[0][1] / len(usrs), module, len(usrs), len(counts)))
    print(f"[INFO] modules with {SHOWN_MODULE_SIZE} or more types, lowest share first:")
    print("  module: types, natural groups, share in the largest group")
    for share, module, count, natural in sorted(rows):
        print(f"  {module}: {count}, {natural}, {share:.0%}")
    print(f"[INFO] groups of the modules under {ONE_JOB_SHARE:.0%}, with up to 6 types each:")
    for share, module, _, _ in sorted(rows):
        if share >= ONE_JOB_SHARE:
            break
        print(f"  {module}:")
        in_group = collections.defaultdict(list)
        for usr in by_module[module]:
            in_group[group_of[usr]].append(graph.types[usr][0])
        for names in sorted(in_group.values(), key=len, reverse=True):
            if len(names) >= 2:
                print(f"    {len(names)}: {', '.join(sorted(names)[:6])}")


def member_report(graph):
    over = []
    for type_usr, members in graph.by_type.items():
        uses = {x for m in members for x in graph.outer[m]}
        if len(uses) > FAN_OUT_LIMIT:
            over.append((len(uses), type_usr))
    print(f"[INFO] member groups of the {len(over)} types over {FAN_OUT_LIMIT} outside types:")
    for count, type_usr in sorted(over, reverse=True):
        name, path = graph.types[type_usr]
        print(f"  {path}: {name} uses {count} types")
        for group in graph.member_groups(type_usr):
            if len(group) < 2:
                continue
            used = collections.Counter(x for m in group for x in graph.outer[m])
            members = ", ".join(sorted(graph.member_name[m] for m in group)[:12])
            print(f"    {len(group)} members, {len(used)} types: {members}")


def main():
    if not self_check():
        print("[FAIL] design-groups self-check: two linked triangles were not two groups",
              file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    if not open_store(store_path):
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    graph = Graph(*load(store_path, repo))
    module_report(graph)
    member_report(graph)
    return 0


if __name__ == "__main__":
    sys.exit(main())
