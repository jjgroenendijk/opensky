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

The report goes to `.logs/gaps/<UTC timestamp>/gaps.txt`, with the summary as a Markdown
table in `summary.md` beside it. Both hold names and counts only. A run of every section also
copies `summary.md` into the "Completion progress" table of `README.md`, between the
`gaps:begin` and `gaps:end` markers. Commit that change, so the README shows the progress.

```sh
make gaps                         # every section; updates README.md
make gaps ONLY=papyrus,perks      # some sections; README.md stays as it is
make gaps LIMIT=20                # at most 20 rows per section
```

The asset sections (`meshes`, `textures`, `animations`, `audio`, and the tag part of `swf`)
read every archived file of their kind, one at a time. They take most of the run time.

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
| `events` | A Papyrus event a script handles | The engine sends it (`PapyrusEngineEvents`) | Scripts that handle it |
| `conditions` | A condition function index in a `CTDA` | The whole-game condition registry answers it | Conditions in all active plugins |
| `records` | A record type in the active plugins | It has a decoder that neither throws nor leaves a field unread | Records |
| `settings` | A game setting (`GMST`) a plugin defines | A settings reader asks for it | Plugins that set it |
| `magic` | A magic effect archetype | The active-effect planner applies it | `MGEF` records |
| `perks` | A perk entry point, and an entry-point function | Engine code reads the entry point; the evaluator computes the function | Perk effects |
| `packages` | An AI procedure in a package's resolved tree | An actor can run it | Packages |
| `behavior` | A Havok generator or modifier class in an actor behaviour graph | The sweep reached it and the evaluator noted no gap | Objects of the class |
| `animations` | A Havok class in any `.hkx`, a clip annotation event, a graph variable | A decoder reads the class; engine code reacts to the event or binds the variable | Objects, clips, graphs |
| `meshes` | A NIF block type, a lighting shader type, a shader flag | Engine code names the type; a draw term or draw state uses the shader type or flag | Blocks, shader blocks |
| `textures` | A DDS variant: pixel format, cubemap, or unread kind | `DDSFile` reads it | Textures |
| `audio` | A sound file variant, and lip sync data | The engine opens and decodes it | Files |
| `swf` | An interface movie that talks to the engine, and a SWF tag | A menu bridge drives the movie; a decoder reads the tag | GameDelegate names, tags |

The `records`, `conditions`, `settings`, `magic`, `perks`, and `packages` sections read the
active load order, so mods count too. The other sections read the files inside the archives;
loose files are not read.

Some sections have no total to count against, so they show "-" in the summary: decode
failures, behaviour features ignored, and the AS2 runtime. They list what to check.

## Keeping the "done" lists complete

Each "done" rule reads a list in the module that owns it. A machine check keeps each list
complete, so a new reader cannot be missed:

| List | Check |
| --- | --- |
| `PerkEntryPoint.engineRead` | SwiftLint `perk_entry_point_literal`: no raw entry-point number elsewhere |
| `PapyrusEngineEvents.sent` | SwiftLint `papyrus_event_literal`: no `"On..."` event name elsewhere in the scripting module |
| Game settings | SwiftLint `game_setting_reader`: only the files of known readers call `setting(editorID:)` |
| `NIFShaderFlag.lightingRead`, `effectRead` | SwiftLint `shader_flag_mask`: flags are read through `has(_:)` and a named constant |
| `NIFBlockTypes.handled` | `make gap-registries`: the list holds exactly the NIF type names the code names |

A new settings reader adds its call to `GapsGatherer.settingsRead` and its file to the
`game_setting_reader` rule. A new shader flag reader adds the flag to `lightingRead` or
`effectRead` when a draw term depends on it; decoding a flag alone does not count. A flag
whose behaviour OpenSky has without a read goes in `lightingMatchedByDefault`, with the
reason in [NIF materials](/formats/nif-materials.md), "Flags with no read".

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

The node class section lists "not reached" classes as left, with a `not reached:` prefix, so
they lower the share done. Raising events in a row does not reach every state, so "not
reached" is not "broken". A
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

The SWF tag section counts every tag in every movie, nested sprites included. GFx extension
tags (codes 1000 to 1009) take their names from JPEXS Free Flash Decompiler's GFx tag classes.
The font hinting tags (73, 74, 88) count as done, because OpenSky draws glyphs without hinting.

### Meshes, textures, animations, and sound

- NIF block types count as done when engine code names the type: it decodes it, or skips it on
  purpose, such as water shapes, which have their own pipeline. Shader flag and type names come
  from nif.xml `SkyrimShaderPropertyFlags1/2` and `BSLightingShaderType`.
- Mesh decode failures list each kind once per mesh, with numbers replaced by `#`. A mesh is
  built with `model()`, its particles, collision, and animation sequences.
- Animation events are clip annotations. The payload after `.` or `@` is folded, so
  `SoundPlay.X` counts as `SoundPlay.*`. An event counts as done when combat, archery, or
  ragdoll code observes it, a footstep (`FSTP` `ANAM`) answers it, or it asks for a sound, a
  camera shake, or head tracking ([animation events](/engine/animation-events.md)). The graph itself
  reacts to many events, so these rows need a check before they become an issue. The same
  holds for graph variables: the graph sets many of them itself.
- A voice `.fuz` counts by the audio inside it. Its lip data counts in the lip sync section.

### Rules

- A Papyrus event is an `On...` function that an engine class declares. An engine class is a
  script with native functions, such as `ObjectReference`. A handler is the same name in a
  script without natives.
- A package tree can hold several procedures, but an actor runs one. The others count as left.
- A game setting counts as read when a settings reader asks for it, or when the menus read it
  by prefix (`fStats`, the fast-travel and race menu texts).
