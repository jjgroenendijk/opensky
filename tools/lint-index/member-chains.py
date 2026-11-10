"""Design rule 5, as a report: member chains that reach through more than 3 reference types.

Reads the index store that a build writes, through Xcode's libIndexStore, and the source
line of each chain. A chain is a run of member accesses on one line, such as
`game.world.cells.loaded.first`. A step counts when the index store names the member it
reaches and that member belongs to a class, an actor, or a protocol limited to classes
declared under src/Sources. Steps through structs and enums, such as fields of a parsed
record, do not count. Fails nothing.
Usage: member-chains.py <DataStore> <repo>. See docs/decisions/design-metrics.md.
"""

import collections
import functools
import pathlib
import re
import sys

from index_store import (ROLE_DEFINITION, TYPE_KINDS, occurrences, open_store,
                         repository_records)

LIMIT = 3
CLASS = 7
PROTOCOL = 8
# A run of `.member` steps, each after a name, a call, a subscript, or an optional mark.
CHAIN = re.compile(r"[A-Za-z_]\w*(?:[?!]?(?:\([^()]*\)|\[[^\[\]]*\])*[?!]?\.[A-Za-z_]\w*)+")
MEMBER = re.compile(r"\.([A-Za-z_]\w*)")
CLASS_BOUND = re.compile(r"\b(AnyObject|class|actor|Actor)\b")


def reference_types(definitions):
    """definitions: type usr -> (kind, declaration line). The usrs of the classes, actors,
    and protocols limited to classes."""
    found = set()
    for usr, (kind, line) in definitions.items():
        head = line.split("{")[0]
        if kind == CLASS or (kind == PROTOCOL and CLASS_BOUND.search(head.split(":", 1)[-1]
                                                                     if ":" in head else "")):
            found.add(usr)
        elif re.search(r"\bactor\s", head):
            found.add(usr)
    return found


def chain_steps(line, members, owner, references):
    """Yields (column, steps) for each chain on `line`. `members` maps a 1-based byte column
    to the usr the index store names there; `owner` maps a usr to its type usr."""
    encoded = line.encode()
    for match in CHAIN.finditer(line):
        steps = 0
        for member in MEMBER.finditer(match.group(0)):
            start = match.start() + member.start(1)
            column = len(line[:start].encode()) + 1
            usr = members.get(column)
            if usr is not None and owner(usr) in references:
                steps += 1
        if steps > LIMIT:
            yield len(encoded[: len(line[: match.start()].encode())]) + 1, steps


def findings(definitions, files):
    """files: path -> (lines, {(line, column): usr}). (path, line, steps, text) for each
    chain with more than LIMIT reference steps."""
    declared = set(definitions)
    references = reference_types(definitions)

    @functools.lru_cache(maxsize=None)
    def owner(usr):
        best = None
        for end in range(1, len(usr)):
            if usr[:end] in declared:
                best = usr[:end]
        return best

    rows = []
    for path, (lines, located) in sorted(files.items()):
        by_line = collections.defaultdict(dict)
        for (line, column), usr in located.items():
            by_line[line][column] = usr
        for number, members in sorted(by_line.items()):
            text = lines[number - 1] if 0 < number <= len(lines) else ""
            for _, steps in chain_steps(text, members, owner, references):
                rows.append((path, number, steps, text.strip()))
    return rows


def self_check():
    """`game.world.cells.loaded.count` reaches through four classes and is reported. The
    same depth through a struct, or three classes, is not."""
    game, world, cells, record = "s:3App4GameC", "s:3App5WorldC", "s:3App5CellsC", "s:3App1RV"
    definitions = {game: (CLASS, "final class Game {"), world: (CLASS, "class World {"),
                   cells: (CLASS, "class Cells {"), record: (6, "struct R {"),
                   "s:3App4PortP": (PROTOCOL, "protocol Port: AnyObject {")}
    deep = "        let n = game.world.cells.loaded.count"
    shallow = "        let n = game.world.cells.count"
    value = "        let n = game.record.name.value.count"

    def located(text, usrs):
        columns = [match.start(1) + 1 for match in MEMBER.finditer(text)]
        return dict(zip(((1, column) for column in columns), usrs))

    files = {"Deep.swift": ([deep], located(deep, [game + "5worldvp", world + "5cellsvp",
                                                   cells + "6loadedvp", cells + "5countvp"])),
             "Shallow.swift": ([shallow], located(shallow, [game + "5worldvp",
                                                            world + "5cellsvp",
                                                            cells + "5countvp"])),
             "Value.swift": ([value], located(value, [game + "6recordvp", record + "4namevp",
                                                      record + "5valuevp",
                                                      record + "5countvp"]))}
    rows = findings(definitions, files)
    bound = reference_types(definitions)
    return [(row[0], row[2]) for row in rows] == [("Deep.swift", 4)] and "s:3App4PortP" in bound


def report(rows):
    print(f"[INFO] design rule 5, Law of Demeter: {len(rows)} chains reach through more than "
          f"{LIMIT} reference types")
    for path, line, steps, text in rows:
        print(f"  {path}:{line}: {steps} steps: {text[:100]}")
    for module, count in collections.Counter(row[0].split("/")[2] for row in rows).most_common():
        print(f"    {module}: {count}")


def main():
    if not self_check():
        print("[FAIL] member-chains self-check: a deep chain was not found", file=sys.stderr)
        return 1
    store_path, repo = sys.argv[1], str(pathlib.Path(sys.argv[2]).resolve())
    opened = open_store(store_path)
    if not opened:
        print(f"[FAIL] cannot open the index store at {store_path}", file=sys.stderr)
        return 1
    lib, store = opened
    definitions, files = {}, {}
    for relative, record in repository_records(lib, store, repo):
        if not relative.startswith("src/Sources/"):
            continue
        lines = (pathlib.Path(repo) / relative).read_text(errors="ignore").split("\n")
        located = {}
        for roles, kind, usr, _, _, (line, column) in occurrences(lib, store, record,
                                                                  located=True):
            if roles & ROLE_DEFINITION:
                if kind in TYPE_KINDS and 0 < line <= len(lines):
                    definitions[usr] = (kind, lines[line - 1])
            else:
                located[(line, column)] = usr
        files[relative] = (lines, located)
    report(findings(definitions, files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
