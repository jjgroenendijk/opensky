"""Reads the index store that a build writes, through Xcode's libIndexStore, so a check sees
real symbols and references, not text. Imported by the checks in this folder."""

import ctypes
import pathlib
import subprocess

# The active Xcode's, so CI's DEVELOPER_DIR picks the same one the build used.
DEVELOPER_DIR = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True,
                               check=True).stdout.strip()
LIBRARY = f"{DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib"
# indexstore.h: symbol roles and kinds this check reads.
ROLE_DEFINITION = 1 << 1
ROLE_REFERENCE = 1 << 2
REL_CHILD_OF = 1 << 9
REL_BASE_OF = 1 << 10
REL_OVERRIDE_OF = 1 << 11
REL_ACCESSOR_OF = 1 << 15
REL_CONTAINED_BY = 1 << 16
TYPE_KINDS = {5, 6, 7, 8}  # enum, struct, class, protocol
PROTOCOL = 8
EXTENSION = 9
INSTANCE_PROPERTY = 19
# The build cache maps the package folder, src/, to this prefix (docs/tools/build-system.md).
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
        "indexstore_occurrence_get_line_col": (None, [VOIDP, ctypes.POINTER(ctypes.c_uint),
                                                      ctypes.POINTER(ctypes.c_uint)]),
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


def occurrences(lib, store, record, located=False):
    """Yields (roles, symbol kind, usr, name, relations) for one record. Each relation is
    (roles, kind, usr) of the related symbol. With `located`, each tuple ends with the
    1-based (line, column) of the occurrence, the column in UTF-8 bytes."""
    reader = lib.indexstore_record_reader_create(store, record.encode(), None)
    if not reader:
        return []
    found = []

    def occurrence(_, item):
        symbol = lib.indexstore_occurrence_get_symbol(item)
        relations = []

        def relation(_, rel):
            other = lib.indexstore_symbol_relation_get_symbol(rel)
            relations.append((lib.indexstore_symbol_relation_get_roles(rel),
                              lib.indexstore_symbol_get_kind(other),
                              lib.indexstore_symbol_get_usr(other).text()))
            return True

        lib.indexstore_occurrence_relations_apply_f(item, None, RELATION_CALLBACK(relation))
        row = (lib.indexstore_occurrence_get_roles(item), lib.indexstore_symbol_get_kind(symbol),
               lib.indexstore_symbol_get_usr(symbol).text(),
               lib.indexstore_symbol_get_name(symbol).text(), relations)
        if located:
            line, column = ctypes.c_uint(), ctypes.c_uint()
            lib.indexstore_occurrence_get_line_col(item, ctypes.byref(line), ctypes.byref(column))
            row += ((line.value, column.value),)
        found.append(row)
        return True

    lib.indexstore_record_reader_occurrences_apply_f(reader, None,
                                                     OCCURRENCE_CALLBACK(occurrence))
    lib.indexstore_record_reader_dispose(reader)
    return found


def open_store(store_path):
    """The library and the opened store, or None when the store cannot be opened."""
    lib = load(LIBRARY)
    error = VOIDP()
    store = lib.indexstore_store_create(store_path.encode(), ctypes.byref(error))
    return (lib, store) if store else None


def repository_records(lib, store, repo):
    """Yields (path from the repository root, record) for each file that still exists."""
    prefixes = ((repo + "/", ""), (CACHE_PREFIX, "src/"))
    for path, record in record_files(lib, store).items():
        relative = next((base + path[len(root):] for root, base in prefixes
                         if path.startswith(root)), None)
        if relative is not None and (pathlib.Path(repo) / relative).exists():
            yield relative, record
