"""Lists each stored field of the record types and whether engine code reads it, for the
"Record fields" area of `make rank-gaps` (docs/tools/gaps.md).

Reads the index store that a build writes, through Xcode's libIndexStore. A field is a
property defined in the record module. It is read when code in another engine module reads
it, or when a declaration of the record module reads it and that declaration is read in
turn, such as a computed property another module calls. The decoder's writes do not count,
and neither do reads in the type's own initializers, tests, or the developer CLI. A protocol
witness is read when its requirement is read.
Usage: record-field-reads.py <DataStore> <repo> <out> [<values out>]. Writes one line per
field to <out>: `read` or `unread`, a tab, and the field as `Type.Nested.field`.

With <values out>, it also lists the named single bits of each `OptionSet` type of the
record module and each enum case, read or not, for the "Record flag bits" and "Record enum
values" areas. A bit is tested when its constant is read as above. A case is handled when
code names it, as a `switch` arm or a comparison does, but not when the enum's own
initializers, `rawValue`, or `description` name it: those decode or print the value.
"""

import collections
import pathlib
import re
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
ENUM_CASE = 15
STATIC_PROPERTY = 21
REL_BASE_OF = 1 << 10
OPTION_SET = "s:s9OptionSetP"
# Members that decode or print a value; naming a case there does not handle it.
CODING_MEMBERS = {"rawValue", "description", "debugDescription"}
RAW_VALUE = re.compile(r"rawValue:\s*([^)]*)\)")
NUMBER = re.compile(r"^(0[xX][0-9a-fA-F]+|0[bB][01]+|[0-9]+)(?:<<([0-9]+))?$")


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
        self.cases = {}  # enum case usr -> enum usr
        self.constants = {}  # static property usr -> (parent usr, source line)
        self.option_sets = set()  # usrs of the types that conform to OptionSet
        self.names = {}  # usr -> name, for each definition of the record module

    def definition(self, kind, usr, name, relations, line=""):
        """`line` is the definition's source line, which holds a flag constant's value."""
        parent = next((other for roles, _, other in relations if roles & REL_CHILD_OF), None)
        self.names[usr] = name
        if kind == ENUM_CASE and parent:
            self.cases[usr] = parent
        elif kind == STATIC_PROPERTY and parent:
            self.constants[usr] = (parent, line)
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
            if usr == OPTION_SET and rel_roles & REL_BASE_OF and home == "OpenSkyFormatsESM":
                self.option_sets.add(other)
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

    def decodes(self, container, target):
        """Whether `container` only decodes or prints `target`, so it does not use it."""
        # The type's own initializers decode its fields.
        if container in self.initializers and \
                self.initializers[container] == self.fields.get(target):
            return True
        if target not in self.cases:
            return False
        return container in self.initializers or \
            self.names.get(self.owner(container)) in CODING_MEMBERS

    def reached(self):
        """Every usr that engine code reads, directly or through a read declaration."""
        edges = collections.defaultdict(set)
        for container, targets in self.inside.items():
            for target in targets:
                field = self.owner(target)
                if not self.decodes(container, field):
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
        return seen

    def read_fields(self):
        """The field usrs that engine code reads, directly or through a read declaration."""
        return self.reached() & set(self.fields)

    def value_lines(self):
        """The `flags`, `bit`, and `case` rows of the values list."""
        reached = self.reached()
        rows = {f"flags\t{self.qualified(usr)}" for usr in self.option_sets}
        for usr, (parent, line) in self.constants.items():
            bit = single_bit(line) if parent in self.option_sets else None
            if bit:
                state = "read" if usr in reached else "unread"
                rows.add(f"{state}\tbit\t{self.qualified(parent)}\t{bit:#x}\t{self.names[usr]}")
        for usr, parent in self.cases.items():
            state = "read" if usr in reached else "unread"
            rows.add(f"{state}\tcase\t{self.qualified(parent)}.{self.names[usr]}")
        return sorted(rows)

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


def single_bit(line):
    """The value of `static let x = Flags(rawValue: 0x8)` when it is one bit, else None."""
    found = RAW_VALUE.search(line)
    number = NUMBER.match(found.group(1).replace("_", "").replace(" ", "")) if found else None
    if not number:
        return None
    text, shift = number.group(1), number.group(2)
    base = 16 if text[:2] in ("0x", "0X") else 2 if text[:2] in ("0b", "0B") else 10
    value = int(text[2:] if base != 10 else text, base) << int(shift or 0)
    return value if value and value & (value - 1) == 0 else None


def values_self_check():
    """A flag constant another module reads is tested; one only the type's own code reads
    is not. A case a `switch` outside names is handled; one only the enum's initializer and
    `rawValue` name is not. A constant of more than one bit is no row."""
    flags, kind = "s:A5ArmorV5FlagsV", "s:A5ArmorV4KindO"
    worn, heavy, both = flags + "4wornvpZ", flags + "5heavyvpZ", flags + "4bothvpZ"
    light, plate = kind + "5lightyA2CmF", kind + "5plateyA2CmF"
    init, raw = kind + "4initfc", kind + "8rawValuevp"
    index = Index()
    index.definition(6, "s:A5ArmorV", "Armor", [])
    index.definition(6, flags, "Flags", [(REL_CHILD_OF, 6, "s:A5ArmorV")])
    index.definition(5, kind, "Kind", [(REL_CHILD_OF, 6, "s:A5ArmorV")])
    index.reference("OpenSkyFormatsESM", ROLE_REFERENCE, OPTION_SET,
                    [(REL_BASE_OF, 6, flags)])
    for usr, name, line in ((worn, "worn", "static let worn = Flags(rawValue: 0x0008)"),
                            (heavy, "heavy", "static let heavy = Flags(rawValue: 1 << 4)"),
                            (both, "both", "static let both = Flags(rawValue: 0x18)")):
        index.definition(STATIC_PROPERTY, usr, name, [(REL_CHILD_OF, 6, flags)], line)
    for usr, name in ((light, "light"), (plate, "plate")):
        index.definition(ENUM_CASE, usr, name, [(REL_CHILD_OF, 5, kind)])
    index.definition(CONSTRUCTOR, init, "init(rawValue:)", [(REL_CHILD_OF, 5, kind)])
    index.definition(INSTANCE_PROPERTY, raw, "rawValue", [(REL_CHILD_OF, 5, kind)])
    index.reference("OpenSkyInventory", ROLE_REFERENCE | ROLE_READ, worn, [])
    index.reference("OpenSkyInventory", ROLE_REFERENCE | ROLE_READ, light, [])
    index.reference("OpenSkyInventory", ROLE_REFERENCE | ROLE_READ, init, [])
    index.reference("OpenSkyInventory", ROLE_REFERENCE | ROLE_READ, raw, [])
    for container in (init, raw):
        index.reference("OpenSkyFormatsESM", ROLE_REFERENCE | ROLE_READ, plate,
                        [(REL_CONTAINED_BY, 22, container)])
    return index.value_lines() == [
        "flags\tArmor.Flags", "read\tbit\tArmor.Flags\t0x8\tworn",
        "read\tcase\tArmor.Kind.light", "unread\tbit\tArmor.Flags\t0x10\theavy",
        "unread\tcase\tArmor.Kind.plate"
    ]


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
    if not self_check() or not values_self_check():
        print("[FAIL] record field reads self-check: a field or value was judged wrong",
              file=sys.stderr)
        return 1
    store_path, repo, out = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve()), sys.argv[3]
    values_out = sys.argv[4] if len(sys.argv) > 4 else None
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    lib, store = opened
    index = Index()
    for relative, record in repository_records(lib, store, repo):
        home = module(relative)
        if home is None:
            continue
        in_records = relative.startswith(RECORD_MODULE)
        source = (pathlib.Path(repo) / relative).read_text().split("\n") if in_records else []
        for roles, kind, usr, name, relations, (line, _) in occurrences(lib, store, record,
                                                                        located=True):
            if roles & ROLE_DEFINITION:
                if in_records:
                    text = source[line - 1] if kind == STATIC_PROPERTY else ""
                    index.definition(kind, usr, name, relations, text)
            else:
                index.reference(home, roles, usr, relations)
    rows = index.lines(index.names)
    pathlib.Path(out).write_text("".join(row + "\n" for row in rows))
    read = sum(row.startswith("read\t") for row in rows)
    print(f"[INFO] record fields: {read} of {len(rows)} read by engine code; list in {out}")
    if values_out:
        values = index.value_lines()
        pathlib.Path(values_out).write_text("".join(row + "\n" for row in values))
        print(f"[INFO] record values: {len(values)} rows in {values_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
