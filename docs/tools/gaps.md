---
type: Tool
title: Gap report
description: How `make gaps` finds what the game data uses and the engine does not do yet, what
  each section counts, and what it cannot see.
tags: [tool, cli, coverage, roadmap]
---

# Gap report

`make gaps` runs `openskycli gaps` on your install. It lists what the game data asks for that
the engine does not implement yet. Each item is ranked by how often the data uses it, so the
top rows are the gaps a player meets first.

The report goes to `.logs/gaps/<UTC timestamp>/gaps.txt` and holds names and counts only.

```sh
make gaps                         # every section, under a minute
make gaps ONLY=papyrus,perks      # some sections
make gaps LIMIT=20                # at most 20 rows per section
```

## Reading the report

The report opens with a summary table. It has one row per area, with how many distinct items
are done, how many are left, and the share done. Then each section lists the items that are
left, one per line: the number of uses, then the name.

"Done" means a program could check it. It does not mean the item behaves exactly like the
game. A bound Papyrus native can still return a wrong value. Wrong behaviour, such as a
texture drawn in the wrong colour, needs a render check or a play test, not this report.

## Sections

| Section | What one item is | Done when | Uses |
| --- | --- | --- | --- |
| `papyrus` | A native function the archived scripts call | `PapyrusNativeRegistry.standard` binds it | Call sites |
| `conditions` | A condition function index in a `CTDA` | The whole-game condition registry answers it | Conditions in all active plugins |
| `records` | A record type in the active plugins | It has a decoder that neither throws nor leaves a field unread | Records |
| `magic` | A magic effect archetype | The active-effect planner applies it | `MGEF` records |
| `perks` | A perk entry point, and an entry-point function | Engine code reads the entry point; the evaluator computes the function | Perk effects |
| `behavior` | A Havok generator or modifier class in an actor behaviour graph | The sweep reached it and the evaluator noted no gap | Objects of the class |
| `swf` | An interface movie that talks to the engine | A menu bridge drives it | GameDelegate names it uses |

The `records`, `conditions`, `magic`, and `perks` sections read the active load order, so
mods count too. `papyrus` reads the scripts inside the archives; loose script files are not
read.

### Perk entry points

Engine code reads an entry point only through a constant in
`Sources/OpenSkyProgressionInterface/PerkEntryPoint+Engine.swift`. A SwiftLint rule rejects a
raw entry-point number anywhere else, so the list in that file stays complete. A new reader
adds its entry point there and to `engineRead`.

### Behaviour

The sweep steps every graph in a `behaviors...` folder under `meshes\actors\`. Each graph
uses the skeleton in the `character assets...` folder beside its `behaviors...` folder, matched
by suffix: `canine\behaviors wolf` uses `canine\character assets wolf\skeleton.hkx`. It
runs 30 idle updates, then raises each event the graph declares and runs 3 more updates per
event. A class is in one of three groups:

- done: an update reached it and the evaluator noted no gap,
- left: the evaluator skipped it, ran it only in part, passed it through, or could not decode it,
- not reached: no update reached it, so the sweep knows nothing about it.

Raising events in a row does not reach every state, so "not reached" is not "broken". A
folder with no skeleton is skipped and named in the notes. The "features ignored" section
lists the `BehaviorTally` feature gaps, bindings not applied, and clips not found.

### Menus and the AS2 runtime

Every interface movie starts with no bridge and runs 10 ticks. A movie directly in
`interface\` that registers or calls a GameDelegate name is a menu that talks to the engine.
A movie in a subfolder, such as `inventory components\`, is a part another menu loads. A menu
counts as done when `MenuMovieBridges.moviePaths` lists it. A new bridge adds its movie there.

The AS2 section lists the names the runtime did not provide, the opcodes it did not run, and
its faults, over all movies. GameDelegate calls are not in it, because a bridge answers them.
A movie that needs its bridge before it does anything shows few gaps here. A name a movie reads
before it sets it, such as a CLIK component's `_listeners`, counts too, so the top rows need a
check before they become an issue.
