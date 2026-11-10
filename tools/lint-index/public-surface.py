"""Design rule 3, as a report: public declarations that no other module uses.

Reads the index store that a build writes, through Xcode's libIndexStore. The store holds
no access levels, so the check reads the source line at each definition and finds `public`
or `open` before the name, or a `public extension` around it. A declaration is used by
another module when code in another module names it. A test file that imports the module
with `@testable` sees internal declarations, so its use does not count. A declaration stays
needed when another module uses one of its members or names it as a protocol witness, or when a needed declaration of its own
module names it, such as a type in the signature of a used function. Protocol witnesses and
overrides take the access their requirement needs, so they are left out. Fails nothing.
Usage: public-surface.py <DataStore> <repo>. See docs/decisions/design-metrics.md.
"""

import collections
import functools
import pathlib
import re
import sys

from index_store import (EXTENSION, PROTOCOL, REL_ACCESSOR_OF, REL_CHILD_OF, REL_CONTAINED_BY,
                         REL_OVERRIDE_OF, ROLE_DEFINITION, occurrences,
                         open_store, repository_records)

KEYWORD = re.compile(r"(^|[\s)])(public|open)\s")
SETTER = re.compile(r"\b(?:private|fileprivate|internal)\(set\)")
NARROWER = re.compile(r"(^|\s)(private|fileprivate|internal)[\s(]")
EXTENSION_KEYWORD = re.compile(r"(^|\s)public\s+extension\s")
TESTABLE = re.compile(r"^@testable\s+import\s+(\w+)", re.MULTILINE)
PARAMETER = 25
ENUM_CASE = 15
ROLE_IMPLICIT = 1 << 8


def module(path):
    """The module or test target of a file under src/Sources or src/Tests."""
    parts = path.split("/")
    return parts[2] if len(parts) > 3 and parts[1] in ("Sources", "Tests") else None


def is_public(line, column, extension_lines):
    """`line` is the source line of the definition, `column` its 1-based byte column.
    `extension_lines` are the lines of the extensions the definition sits in."""
    before = line.encode()[: max(column - 1, 0)].decode(errors="ignore")
    if NARROWER.search(SETTER.sub("", before)):
        return False
    return bool(KEYWORD.search(before)) or any(EXTENSION_KEYWORD.search(text)
                                               for text in extension_lines)


def unused(public, references, witnesses):
    """public: usr -> (name, module). references: (module, testable modules, containers, usr).
    witnesses: usrs that a protocol requirement or an override needs public.

    Returns the public usrs no other module needs, after the needs spread from members to
    their types and from needed declarations to the declarations they name."""
    declared = set(public)

    @functools.lru_cache(maxsize=None)
    def owners(usr):
        return [usr[:end] for end in range(1, len(usr) + 1) if usr[:end] in declared]

    needed, inside = set(witnesses) & declared, collections.defaultdict(set)
    for user_module, testable, containers, usr in references:
        targets = owners(usr)
        if not targets:
            continue
        home = public[targets[-1]][1]
        if user_module != home and home not in testable:
            needed.update(targets)
        elif user_module == home:
            for container in containers:
                if container in declared:
                    inside[container].update(targets)
    pending = list(needed)
    while pending:
        for target in inside.pop(pending.pop(), ()):
            if target not in needed:
                needed.add(target)
                pending.append(target)
    return declared - needed


def self_check():
    """A public helper that only its own module calls, from an internal function, is reported. A public function that
    another module calls is not, nor the public type in its signature, nor a type whose
    member another module reads, nor a witness and the type in its signature."""
    used, helper = "s:3App4mainyyF", "s:3App6helperyyF"
    result, holder = "s:3App6ResultV", "s:3App6HolderV"
    public = {used: ("main", "App"), helper: ("helper", "App"), result: ("Result", "App"),
              holder: ("Holder", "App")}
    references = [("Tool", set(), [], used), ("App", set(), [used], result),
                  ("App", set(), ["s:3App5setupyyF"], helper), ("Tool", set(), [], holder + "4sizeSivp"),
                  ("AppTests", {"App"}, [], helper)]
    lines = ["    public func helper() {", "    func helper() {"]
    keyword = [is_public(text, text.index("helper") + 1, []) for text in lines]
    in_extension = is_public("    func size() {", 10, ["public extension Holder {"])
    setter = "    public internal(set) var count = 0"
    keyword.append(is_public(setter, setter.index("count") + 1, []))
    witness = "s:3App4playyyF"
    public[witness] = ("play", "App")
    references.append(("App", set(), [witness], "s:3App5SoundV"))
    public["s:3App5SoundV"] = ("Sound", "App")
    return unused(public, references, {witness}) == {helper} and keyword == [True, False, True] and in_extension


def report(public, names):
    rows = sorted((names[usr][1], names[usr][2], names[usr][3], names[usr][0])
                  for usr in public)
    print(f"[INFO] design rule 3, minimal public surface: {len(rows)} public declarations "
          f"no other module uses ({len(names)} public declarations counted)")
    for _, path, line, name in rows:
        print(f"  {path}:{line}: {name}")
    for name, count in collections.Counter(row[0] for row in rows).most_common():
        print(f"    {name}: {count}")


def read_store(lib, store, repo):
    """Public definitions under src/Sources as usr -> (name, module, file, line), every
    reference as (module, testable modules, containers, usr), and the witnesses."""
    definitions, extensions, raw, witnesses = [], {}, [], set()
    on_line, kinds = collections.defaultdict(list), {}
    for relative, record in repository_records(lib, store, repo):
        home = module(relative)
        if home is None:
            continue
        text = (pathlib.Path(repo) / relative).read_text(errors="ignore")
        testable = set(TESTABLE.findall(text))
        lines = text.split("\n")
        for roles, kind, usr, name, relations, (line, column) in occurrences(
                lib, store, record, located=True):
            if any(rel_roles & REL_OVERRIDE_OF for rel_roles, _, _ in relations):
                witnesses.add(usr)
            if not roles & ROLE_DEFINITION:
                containers = [other for rel_roles, _, other in relations
                              if rel_roles & REL_CONTAINED_BY]
                raw.append((home, testable, containers, usr, (relative, line)))
            if (not roles & ROLE_DEFINITION or roles & ROLE_IMPLICIT
                    or not relative.startswith("src/Sources/")):
                continue
            kinds[usr] = kind
            source = lines[line - 1] if 0 < line <= len(lines) else ""
            if kind == EXTENSION:
                extensions[usr] = source
            elif kind != PARAMETER and not any(rel_roles & REL_ACCESSOR_OF
                                               for rel_roles, _, _ in relations):
                parents = [other for rel_roles, _, other in relations
                           if rel_roles & REL_CHILD_OF]
                definitions.append((usr, name, home, relative, line, column, source, parents))
                on_line[(relative, line)].append((usr, kind, parents))
    names = {}
    for usr, name, home, relative, line, column, source, parents in definitions:
        around = [extensions[parent] for parent in parents if parent in extensions]
        if is_public(source, column, around):
            names[usr] = (name, home, relative, line)
    references = [(home, testable, containers + signature_owners(on_line.get(place, ()),
                                                                 names, kinds), usr)
                  for home, testable, containers, usr, place in raw]
    return names, references, witnesses


def signature_owners(declared, names, kinds):
    """The declarations whose signature holds a reference on their own line: a public
    declaration, or the type of an enum case or a protocol requirement, which are public
    without the keyword when their type is."""
    owners = []
    for usr, kind, parents in declared:
        if usr in names:
            owners.append(usr)
        elif kind == ENUM_CASE or any(kinds.get(parent) == PROTOCOL for parent in parents):
            owners.extend(parents)
    return owners


def main():
    if not self_check():
        print("[FAIL] public-surface self-check: an unused public declaration was not found",
              file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    names, references, witnesses = read_store(*opened, repo)
    public = {usr: (name, home) for usr, (name, home, _, _) in names.items()}
    report(unused(public, references, witnesses), names)
    return 0


if __name__ == "__main__":
    sys.exit(main())
