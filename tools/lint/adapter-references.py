"""Ports-and-adapters rule 8: no adapter uses another adapter's type.

Reads the index store that a build writes, through Xcode's libIndexStore, so the check
sees real symbol references, not text. Usage: adapter-references.py <DataStore> <repo>.
See docs/decisions/ports-and-adapters.md.
"""

import ctypes
import pathlib
import re
import sys

LIBRARY = ("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
           "/usr/lib/libIndexStore.dylib")
# indexstore.h: symbol roles and kinds this check reads.
ROLE_DEFINITION = 1 << 1
ROLE_REFERENCE = 1 << 2
REL_CONTAINED_BY = 1 << 16
TYPE_KINDS = {5, 6, 7, 8}  # enum, struct, class, protocol
INSTANCE_PROPERTY = 19
ADAPTER_FOLDER = re.compile(r"^Sources/(OpenSky\w*Adapters|OpenSky/GameView)/")
# The build cache maps the checkout to this prefix (docs/tools/build-system.md).
CACHE_PREFIX = "/^src/"


class StringRef(ctypes.Structure):
    _fields_ = [("data", ctypes.c_char_p), ("length", ctypes.c_size_t)]

    def text(self):
        return (self.data or b"")[: self.length].decode()


VOIDP = ctypes.c_void_p
UNIT_CALLBACK = ctypes.CFUNCTYPE(ctypes.c_bool, VOIDP, StringRef)
DEPENDENCY_CALLBACK = ctypes.CFUNCTYPE(ctypes.c_bool, VOIDP, VOIDP)
OCCURRENCE_CALLBACK = ctypes.CFUNCTYPE(ctypes.c_bool, VOIDP, VOIDP)
RELATION_CALLBACK = ctypes.CFUNCTYPE(ctypes.c_bool, VOIDP, VOIDP)


def load(path):
    lib = ctypes.CDLL(path)
    signatures = {
        "indexstore_store_create": (VOIDP, [ctypes.c_char_p, ctypes.POINTER(VOIDP)]),
        "indexstore_store_units_apply_f": (ctypes.c_bool, [VOIDP, ctypes.c_uint, VOIDP,
                                                          UNIT_CALLBACK]),
        "indexstore_unit_reader_create": (VOIDP, [VOIDP, ctypes.c_char_p,
                                                  ctypes.POINTER(VOIDP)]),
        "indexstore_unit_reader_dispose": (None, [VOIDP]),
        "indexstore_unit_reader_get_modification_time": (None, [
            VOIDP, ctypes.POINTER(ctypes.c_int64), ctypes.POINTER(ctypes.c_int64)]),
        "indexstore_unit_reader_dependencies_apply_f": (ctypes.c_bool, [VOIDP, VOIDP,
                                                                       DEPENDENCY_CALLBACK]),
        "indexstore_unit_dependency_get_kind": (ctypes.c_int, [VOIDP]),
        "indexstore_unit_dependency_get_name": (StringRef, [VOIDP]),
        "indexstore_unit_dependency_get_filepath": (StringRef, [VOIDP]),
        "indexstore_record_reader_create": (VOIDP, [VOIDP, ctypes.c_char_p,
                                                    ctypes.POINTER(VOIDP)]),
        "indexstore_record_reader_dispose": (None, [VOIDP]),
        "indexstore_record_reader_occurrences_apply_f": (ctypes.c_bool, [VOIDP, VOIDP,
                                                                        OCCURRENCE_CALLBACK]),
        "indexstore_occurrence_get_symbol": (VOIDP, [VOIDP]),
        "indexstore_occurrence_get_roles": (ctypes.c_uint64, [VOIDP]),
        "indexstore_occurrence_relations_apply_f": (ctypes.c_bool, [VOIDP, VOIDP,
                                                                   RELATION_CALLBACK]),
        "indexstore_symbol_relation_get_roles": (ctypes.c_uint64, [VOIDP]),
        "indexstore_symbol_relation_get_symbol": (VOIDP, [VOIDP]),
        "indexstore_symbol_get_kind": (ctypes.c_int, [VOIDP]),
        "indexstore_symbol_get_usr": (StringRef, [VOIDP]),
        "indexstore_symbol_get_name": (StringRef, [VOIDP]),
    }
    for name, (result, arguments) in signatures.items():
        function = getattr(lib, name)
        function.restype = result
        function.argtypes = arguments
    return lib


def record_files(lib, store):
    """Maps each source file to its record from the newest unit, so old builds drop out."""
    units = []
    lib.indexstore_store_units_apply_f(store, 0, None,
                                       UNIT_CALLBACK(lambda _, name: units.append(name.text())
                                                     or True))
    newest = {}
    for unit in units:
        reader = lib.indexstore_unit_reader_create(store, unit.encode(), None)
        if not reader:
            continue
        seconds, nanoseconds = ctypes.c_int64(), ctypes.c_int64()
        lib.indexstore_unit_reader_get_modification_time(reader, ctypes.byref(seconds),
                                                         ctypes.byref(nanoseconds))
        stamp = (seconds.value, nanoseconds.value)

        def dependency(_, dep):
            if lib.indexstore_unit_dependency_get_kind(dep) == 2:  # record
                path = lib.indexstore_unit_dependency_get_filepath(dep).text()
                if path not in newest or newest[path][0] < stamp:
                    newest[path] = (stamp, lib.indexstore_unit_dependency_get_name(dep).text())
            return True

        lib.indexstore_unit_reader_dependencies_apply_f(reader, None,
                                                        DEPENDENCY_CALLBACK(dependency))
        lib.indexstore_unit_reader_dispose(reader)
    return {path: record for path, (_, record) in newest.items()}


def occurrences(lib, store, record):
    """Yields (roles, symbol kind, usr, name, container usrs) for one record."""
    reader = lib.indexstore_record_reader_create(store, record.encode(), None)
    if not reader:
        return []
    found = []

    def occurrence(_, item):
        symbol = lib.indexstore_occurrence_get_symbol(item)
        containers = []

        def relation(_, rel):
            if lib.indexstore_symbol_relation_get_roles(rel) & REL_CONTAINED_BY:
                other = lib.indexstore_symbol_relation_get_symbol(rel)
                containers.append(lib.indexstore_symbol_get_usr(other).text())
            return True

        lib.indexstore_occurrence_relations_apply_f(item, None, RELATION_CALLBACK(relation))
        found.append((lib.indexstore_occurrence_get_roles(item),
                      lib.indexstore_symbol_get_kind(symbol),
                      lib.indexstore_symbol_get_usr(symbol).text(),
                      lib.indexstore_symbol_get_name(symbol).text(), containers))
        return True

    lib.indexstore_record_reader_occurrences_apply_f(reader, None,
                                                     OCCURRENCE_CALLBACK(occurrence))
    lib.indexstore_record_reader_dispose(reader)
    return found


def families(definitions, owner_properties, references):
    """Maps each part of a split adapter to its owner: the adapter its `owner` names."""
    parent = {}
    for _, containers, usr in references:
        if usr not in definitions:
            continue
        for container in containers:
            if container in owner_properties:
                part = next((d for d in definitions if container.startswith(d)), None)
                if part and part != usr:
                    parent[part] = usr
    return parent


def violations(definitions, owner_properties, references):
    """definitions: adapter usr -> name. references: (file, container usrs, usr) uses.

    A use breaks the rule when code inside one adapter names another adapter outside its
    family. A family is an owner and the parts it was split into."""
    parent = families(definitions, owner_properties, references)

    def root(usr):
        return parent.get(usr, usr)

    found = set()
    for path, containers, usr in references:
        if usr not in definitions:
            continue
        users = {d for d in definitions for c in containers if c.startswith(d)}
        for user in users:
            if root(user) != root(usr):
                found.add(f"rule 8: {path}: {definitions[user]} uses the adapter "
                          f"{definitions[usr]}")
    return sorted(found)


def self_check():
    """A part may use its owner; an adapter may not use an unrelated one."""
    definitions = {"s:A9MagicAdapterC": "MagicAdapter", "s:A10CombatAdapterC": "CombatAdapter",
                   "s:A8WardPartV": "WardPart"}
    owner = "s:A8WardPartV5ownerAA9MagicAdapterCvp"
    references = [("probe.swift", [owner], "s:A9MagicAdapterC"),
                  ("probe.swift", ["s:A9MagicAdapterC4tickyyF"], "s:A8WardPartV"),
                  ("probe.swift", ["s:A9MagicAdapterC4tickyyF"], "s:A10CombatAdapterC")]
    return len(violations(definitions, {owner}, references)) == 1


def main():
    if not self_check():
        print("[FAIL] rule 8 self-check: an adapter using another adapter passed", file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    lib = load(LIBRARY)
    error = VOIDP()
    store = lib.indexstore_store_create(store_path.encode(), ctypes.byref(error))
    if not store:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    definitions, owner_properties, references = {}, set(), []
    for path, record in record_files(lib, store).items():
        relative = next((path[len(root):] for root in (repo + "/", CACHE_PREFIX)
                         if path.startswith(root)), None)
        if relative is None or not ADAPTER_FOLDER.search(relative) \
                or not (pathlib.Path(repo) / relative).exists():
            continue
        for roles, kind, usr, name, containers in occurrences(lib, store, record):
            if roles & ROLE_DEFINITION and kind in TYPE_KINDS and name.endswith("Adapter"):
                definitions[usr] = name
            elif roles & ROLE_DEFINITION and kind == INSTANCE_PROPERTY and name == "owner":
                owner_properties.add(usr)
            elif roles & ROLE_REFERENCE:
                references.append((relative, containers, usr))
    found = violations(definitions, owner_properties, references)
    if found:
        print("[FAIL] an adapter uses another adapter:", file=sys.stderr)
        for line in found:
            print(f"  {line}", file=sys.stderr)
        return 1
    print(f"[ OK ] no adapter uses another adapter ({len(definitions)} adapters)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
