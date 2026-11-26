"""Lists each stored field of the record types and whether engine code reads it, for the
"Record fields" area of `make rank-gaps` (docs/tools/gaps.md).

Reads the index store that a build writes, through Xcode's libIndexStore. A field is a
property defined in the record module. It is read when code in another engine module reads
it, or when a declaration of the record module reads it and that declaration is read in
turn, such as a computed property another module calls. The decoder's writes do not count,
and neither do reads in the type's own initializers, tests, or the developer CLI. A protocol
witness is read when its requirement is read.
Usage: record-field-reads.py <DataStore> <repo> <out>. Writes one line per field to <out>:
`read` or `unread`, a tab, and the field as `Type.Nested.field`.
"""

import collections
import pathlib
import sys

from index_store import (EXTENSION, INSTANCE_PROPERTY, REL_ACCESSOR_OF, REL_CHILD_OF,
                         REL_CONTAINED_BY, REL_OVERRIDE_OF, ROLE_DEFINITION, ROLE_REFERENCE,
                         TYPE_KINDS, occurrences, open_store, repository_records)

RECORD_MODULE = "src/Sources/OpenSkyFormatsESM/"
# Modules whose reads are tools, not engine rules.
TOOL_MODULES = {"OpenSkyCLI", "OpenSkyCLIArguments"}
ROLE_READ = 1 << 3
ROLE_WRITE = 1 << 4
ROLE_IMPLICIT = 1 << 8
REL_EXTENDED_BY = 1 << 14
CONSTRUCTOR = 22


def module(path):
    """The module of a file under src/Sources, or None for tests and other files."""
    parts = path.split("/")
    return parts[2] if len(parts) > 3 and parts[1] == "Sources" else None


def is_read(roles):
    """A reference that reads the value. `x.f += 1` reads and writes; `x.f = 1` only writes."""
    return bool(roles & ROLE_READ) or not roles & ROLE_WRITE


class Index:
    """What the record module declares, and every reference to it."""

    def __init__(self):
        self.types = {}  # usr -> (name, parent usr or None)
        self.extended = {}  # extension usr -> extended type usr
        self.fields = {}  # property usr -> parent type usr
        self.initializers = {}  # constructor usr -> parent type usr
        self.accessors = {}  # accessor usr -> property usr
        self.witnesses = collections.defaultdict(set)  # requirement usr -> witness usrs
        self.outside = set()  # usrs an engine module outside the record module reads
        self.inside = collections.defaultdict(set)  # container usr -> usrs it reads

    def definition(self, kind, usr, name, relations):
        parent = next((other for roles, _, other in relations if roles & REL_CHILD_OF), None)
        if kind in TYPE_KINDS:
            self.types[usr] = (name, parent)
        elif kind == INSTANCE_PROPERTY and parent:
            self.fields[usr] = parent
        elif kind == CONSTRUCTOR and parent:
            self.initializers[usr] = parent
        for roles, _, other in relations:
            if roles & REL_ACCESSOR_OF:
                self.accessors[usr] = other
            if roles & REL_OVERRIDE_OF:
                self.witnesses[other].add(usr)

    def reference(self, home, roles, usr, relations):
        """`home` is the module of the referring file."""
        for rel_roles, _, other in relations:
            if rel_roles & REL_EXTENDED_BY:
                self.extended[other] = usr
        if (home in TOOL_MODULES or not roles & ROLE_REFERENCE or roles & ROLE_IMPLICIT
                or not is_read(roles)):
            return
        if home != "OpenSkyFormatsESM":
            self.outside.add(usr)
            return
        for rel_roles, _, container in relations:
            if rel_roles & REL_CONTAINED_BY:
                self.inside[container].add(usr)

    def owner(self, usr):
        return self.accessors.get(usr, usr)

    def read_fields(self):
        """The field usrs that engine code reads, directly or through a read declaration."""
        edges = collections.defaultdict(set)
        for container, targets in self.inside.items():
            for target in targets:
                field = self.owner(target)
                # The type's own initializers decode the field; that is no use of it.
                if container in self.initializers and \
                        self.initializers[container] == self.fields.get(field):
                    continue
                edges[self.owner(container)].add(field)
        for requirement, witnesses in self.witnesses.items():
            edges[self.owner(requirement)].update(self.owner(w) for w in witnesses)
        pending = [self.owner(usr) for usr in self.outside]
        seen = set(pending)
        while pending:
            for target in edges.get(pending.pop(), ()):
                if target not in seen:
                    seen.add(target)
                    pending.append(target)
        return seen & set(self.fields)

    def qualified(self, usr):
        """`Outer.Inner` for a type, through enclosing types and extensions."""
        names = []
        while usr in self.types or usr in self.extended:
            if usr in self.extended:
                usr = self.extended[usr]
                continue
            name, parent = self.types[usr]
            names.append(name)
            usr = parent
        return ".".join(reversed(names))

    def lines(self, names):
        read = self.read_fields()
        rows = set()
        for usr, parent in self.fields.items():
            if parent in self.types or parent in self.extended:
                state = "read" if usr in read else "unread"
                rows.add(f"{state}\t{self.qualified(parent)}.{names[usr]}")
        return sorted(rows, key=lambda row: row.split("\t")[1])


def self_check():
    """A field another module reads is read. A field only the decoder writes, or only its own
    initializer reads, is not. A field that a read computed property reads is read, through
    its getter, and so is a witness of a read requirement. A nested type takes its outer name,
    also through an extension."""
    armor, details, extension = "s:A5ArmorV", "s:A5ArmorV7DetailsV", "s:e:A5ArmorV"
    rating, icon, sound, total = armor + "6ratingvp", details + "4iconvp", details + "5soundvp", \
        armor + "5totalvp"
    initializer, getter, requirement = armor + "4initfc", armor + "5totalvg", "s:B4Item4namevp"
    name = armor + "4namevp"
    index = Index()
    index.definition(6, armor, "Armor", [])
    index.definition(6, details, "Details", [(REL_CHILD_OF, EXTENSION, extension)])
    index.reference("OpenSkyFormatsESM", ROLE_REFERENCE, armor, [(REL_EXTENDED_BY, 9, extension)])
    for usr, parent in ((rating, armor), (icon, details), (sound, details), (total, armor)):
        index.definition(INSTANCE_PROPERTY, usr, "", [(REL_CHILD_OF, 6, parent)])
    index.definition(CONSTRUCTOR, initializer, "init", [(REL_CHILD_OF, 6, armor)])
    index.definition(16, getter, "getter", [(REL_ACCESSOR_OF, 19, total)])
    index.definition(INSTANCE_PROPERTY, name, "name", [(REL_CHILD_OF, 6, armor),
                                                       (REL_OVERRIDE_OF, 19, requirement)])
    index.reference("OpenSkyInventory", ROLE_REFERENCE | ROLE_READ, rating, [])
    index.reference("OpenSkyFormatsESM", ROLE_REFERENCE | ROLE_WRITE, icon,
                    [(REL_CONTAINED_BY, CONSTRUCTOR, initializer)])
    index.reference("OpenSkyFormatsESM", ROLE_REFERENCE | ROLE_READ, rating,
                    [(REL_CONTAINED_BY, CONSTRUCTOR, initializer)])
    index.reference("OpenSkyFormatsESM", ROLE_REFERENCE | ROLE_READ, sound,
                    [(REL_CONTAINED_BY, 16, getter)])
    index.reference("OpenSkyCLI", ROLE_REFERENCE | ROLE_READ, icon, [])
    index.reference("OpenSkyCombat", ROLE_REFERENCE | ROLE_READ, total, [])
    index.reference("OpenSkyMenus", ROLE_REFERENCE | ROLE_READ, requirement, [])
    return (index.read_fields() == {rating, sound, total, name}
            and index.qualified(details) == "Armor.Details")


def main():
    if not self_check():
        print("[FAIL] record field reads self-check: a field was judged wrong", file=sys.stderr)
        return 1
    store_path, repo, out = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve()), sys.argv[3]
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    lib, store = opened
    index, names = Index(), {}
    for relative, record in repository_records(lib, store, repo):
        home = module(relative)
        if home is None:
            continue
        in_records = relative.startswith(RECORD_MODULE)
        for roles, kind, usr, name, relations in occurrences(lib, store, record):
            if roles & ROLE_DEFINITION:
                if in_records:
                    index.definition(kind, usr, name, relations)
                    names[usr] = name
            else:
                index.reference(home, roles, usr, relations)
    rows = index.lines(names)
    pathlib.Path(out).write_text("".join(row + "\n" for row in rows))
    read = sum(row.startswith("read\t") for row in rows)
    print(f"[INFO] record fields: {read} of {len(rows)} read by engine code; list in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
