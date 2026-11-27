---
type: Tool
title: Gap report
description: How `make rank-gaps` finds what the game data uses and the engine does not do yet, what
  each section counts, and what it cannot see.
tags: [tool, cli, coverage, roadmap]
---

# Gap report

`make rank-gaps` runs `openskycli gaps` on your install. It lists what the game data asks for that
the engine does not implement yet. Each item is ranked by how often the data uses it, so the
top rows are the gaps a player meets first.

The report goes to `.logs/gaps/<UTC timestamp>/gaps.txt`, with the summary as a Markdown
table in `summary.md` beside it. Both hold names and counts only. A run of every section also
copies `summary.md` into the "Completion progress" table of `README.md`, between the
`gaps:begin` and `gaps:end` markers. Commit that change, so the README shows the progress.

```sh
make rank-gaps                         # every section; updates README.md
make rank-gaps ARGS='--only papyrus',perks      # some sections; README.md stays as it is
make rank-gaps ARGS='--limit 20'                # at most 20 rows per section
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
| `fields` | A stored field of a decoded record type that some record fills | Engine code reads it after decoding | Records that fill it |
| `flags` | A bit of a decoded flags field that some record sets | Engine code reads the bit's named constant | Records that set it |
| `enums` | A case of a decoded enum field that some record uses | Engine code names the case | Records that use it |
| `shallow` | A Papyrus native, condition function, or perk entry-point function that has a handler | The handler does work, or does nothing on purpose | Call sites, conditions, perk effects |
| `settings` | A game setting (`GMST`) a plugin defines | A settings reader asks for it | Plugins that set it |
| `magic` | A magic effect archetype | The active-effect planner applies it | `MGEF` records |
| `perks` | A perk entry point, and an entry-point function | Engine code reads the entry point; the evaluator computes the function | Perk effects |
| `packages` | An AI procedure in a package's resolved tree | An actor can run it | Packages |
| `behavior` | A Havok generator or modifier class in an actor behaviour graph | The sweep reached it and the evaluator noted no gap | Objects of the class |
| `animations` | A Havok class in any `.hkx`, a clip annotation event, a graph variable | A decoder reads the class; engine code or a script reacts to the event, or engine code binds the variable | Objects, clips, graphs |
| `meshes` | A NIF block type, a lighting shader type, a shader flag | Engine code names the type; a draw term or draw state uses the shader type or flag | Blocks, shader blocks |
| `textures` | A DDS variant: pixel format, cubemap, volume, or unread kind | `DDSFile` reads it | Textures |
| `audio` | A sound file variant, and lip sync data | The engine opens and decodes it | Files |
| `swf` | An interface movie that talks to the engine, and a SWF tag | A menu bridge drives the movie; a decoder reads the tag | GameDelegate names, tags |

The `records`, `fields`, `flags`, `enums`, `conditions`, `settings`, `magic`, `perks`, and
`packages` sections read the active load order, so mods count too. The other sections read
the files inside the archives; loose files are not read.

Some sections have no total to count against, so they show "-" in the summary: decode
failures, behaviour features ignored, and the AS2 runtime. They list what to check.

## Keeping the "done" lists complete

Each "done" rule reads a list in the module that owns it. A machine check keeps each list
complete, so a new reader cannot be missed:

| List | Check |
| --- | --- |
| `PerkEntryPoint.engineRead` | `syntax-rules.sh` `perk_entry_point_literal`: no raw entry-point number elsewhere |
| `PapyrusEngineEvents.sent` | `syntax-rules.sh` `papyrus_event_literal`: no `"On..."` event name elsewhere in the scripting module |
| Game settings | `syntax-rules.sh` `game_setting_reader`: only the files of known readers call `setting(editorID:)` or declare `resolve(store:)` |
| `NIFShaderFlag.lightingRead`, `effectRead` | `syntax-rules.sh` `shader_flag_mask`: flags are read through `has(_:)` and a named constant |
| `NIFBlockTypes.handled` | `tools/lint/gap-registries.sh`: the list holds exactly the NIF type names the code names |

A new settings reader adds its call to `GapsGatherer.settingsRead` and its file to the
`game_setting_reader` rule. A new shader flag reader adds the flag to `lightingRead` or
`effectRead` when a draw term depends on it; decoding a flag alone does not count. A flag
whose behaviour OpenSky has without a read goes in `lightingMatchedByDefault` or
`effectMatchedByDefault`, with the reason in [NIF materials](/formats/nif-materials.md),
"Flags with no read".

### Perk entry points

Engine code reads an entry point only through a constant in
`src/Sources/OpenSkyProgressionInterface/PerkEntryPoint+Engine.swift`. A SwiftLint rule rejects a
raw entry-point number anywhere else, so the list in that file stays complete. A new reader
adds its entry point there and to `engineRead`.

### Behaviour

The sweep steps every graph in a `behaviors...` folder under `meshes\actors\`. Each graph
uses the skeleton in the `character assets...` folder beside its `behaviors...` folder, matched
by suffix: `canine\behaviors wolf` uses `canine\character assets wolf\skeleton.hkx`. A
behaviour reference loads its file from the install, as in the game. The sweep
runs 30 idle updates, then raises each event the graph declares and runs 3 more updates per
event. Then it raises each event once more from a fresh start: the graph's starting variables
and 30 idle updates. So a state that an earlier event left, or that a variable set by an
earlier event hides, is reached too, such as the turn from standing. No event sets
`i1stPerson`, so a graph that declares it also runs 30 idle updates with the value flipped. A
class is in one of three groups:

- done: an update reached it and the evaluator noted no gap,
- left: the evaluator skipped it, ran it only in part, passed it through, or could not decode it,
- not reached: no update reached it, so the sweep knows nothing about it.

The node class section lists "not reached" classes as left, with a `not reached:` prefix, so
they lower the share done. Raising events in a row does not reach every state, so "not
reached" is not "broken". A
folder with no skeleton is skipped and named in the notes. The "features ignored" section
lists the `BehaviorTally` feature gaps, bindings not applied, and clips not found. A clip
whose file name no archive holds is a note, not a row: the game cannot play it either. Some
vanilla kill moves and scene walks name such clips. A condition that does not parse, or names
a variable the graph lacks, is a note too, because the game blocks the transition the same way
([behaviour state machines](/engine/behavior-state-machines.md)).

### Menus and the AS2 runtime

Every interface movie starts with no bridge and runs 10 ticks. A movie directly in
`interface\` that registers or calls a GameDelegate name is a menu that talks to the engine.
A movie in a subfolder, such as `inventory components\`, is a part another menu loads. A menu
counts as done when `MenuMovieBridges.moviePaths` lists it. A new bridge adds its movie there.

The AS2 section lists the Flash names the runtime did not provide, the opcodes it did not run,
and its faults, over all movies. A movie's own GameDelegate names are not in it, because a
bridge answers them. A movie that needs its bridge before it does anything shows few gaps here.
A name Flash does not define and the movie never set, such as a class name its prologue reads
first, is not a row: Flash answers it with `undefined` too. A note counts these reads
([AS2 runtime](/engine/as2-runtime.md#the-tally)).

The SWF tag section counts every tag in every movie, nested sprites included. GFx extension
tags (codes 1000 to 1009) take their names from JPEXS Free Flash Decompiler's GFx tag classes.
The font hinting tags (73, 74, 88) count as done, because OpenSky draws glyphs without hinting.

### Meshes, textures, animations, and sound

- NIF block types count as done when engine code names the type: it decodes it, or skips it on
  purpose, such as water shapes, which have their own pipeline. Shader flag and type names come
  from nif.xml `SkyrimShaderPropertyFlags1/2` and `BSLightingShaderType`.
- Mesh decode failures list each kind once per mesh, with numbers replaced by `#`. A mesh is
  built with `model()`, its particles, collision, animation sequences, and add-on nodes. Each
  block with a whole-block decoder is also decoded alone, and a block whose bytes the decoder
  does not use up exactly is a failure (`X leaves N bytes unread`).
- Animation events are clip annotations. The payload after `.` or `@` is folded, so
  `SoundPlay.X` counts as `SoundPlay.*`. An event counts as done when combat, archery, or
  ragdoll code observes it, a footstep (`FSTP` `ANAM`) answers it, or it asks for a sound, a
  camera shake, head tracking, or an animation object
  ([animation events](/engine/animation-events.md)). An `ANIO` unload event (`BNAM`) counts
  too. So does an event a graph of the clip's own folder waits for: a transition, an
  event-driven modifier, or another node that switches on it. So does an event the graph of an
  `ARTO` or `ARMA` model waits for, because an actor's events reach the graphs of the effects
  and armour addons on it ([effect graphs](/engine/effect-graphs.md)). So does an event an archived
  script passes as a string to `RegisterForAnimationEvent`, because the engine sends every
  graph event to the `OnAnimationEvent` of the scripts that registered for it. `Func.X` counts
  as done, because it sends `X` to the scripts. The folder is the one above
  `animations` or `behaviors`, so `canine\animations` meets `canine\behaviors wolf`. A
  footstep name that no tag can match, such as `FootFornt` or a tag with a line break after it,
  counts as done, because it plays nothing. So does an event the reference game was seen to
  ignore ([events the game ignores](/engine/animation-events.md#events-the-game-ignores)).
- A graph variable counts as done when engine code sets or reads it, when a script sets it with
  `SetAnimationVariableBool`, `SetAnimationVariableInt`, or `SetAnimationVariableFloat`, or when
  its role is not "engine input". The census gives each variable one role, checked in this order:
  1. Engine input: a graph binds it to a member that takes a world position, such as
     `BSLookAtModifier.targetLocation`.
  2. Left at the graph's value by the game: the reference game was seen not to write it
     ([variables left unwritten](/engine/actor-state-graph.md#variables-left-unwritten)).
  3. Computed by graph nodes: an expression assignment or a modifier output writes it.
  4. Read by nothing: no node, condition, or expression reads it, and no script reads it.
  5. Authored constant: a graph file gives it a non-zero start value.
  6. Engine input: it is on the Creation Kit list of animation variables
     (<https://ck.uesp.net/wiki/List_of_Animation_Variables>), or a script reads it with
     `GetAnimationVariableBool`, `GetAnimationVariableInt`, or `GetAnimationVariableFloat`.
  7. Authored constant: everything else.
  A variable a perk sets through Set Boolean Graph Variable counts as set, because the combat
  runtime writes it. So does an `iState_*` constant the engine reads, and a variable a state
  machine publishes through `isActive`, `currentStateId`, or its sync variable
  ([actor state graph variables](/engine/actor-state-graph.md)).
- A voice `.fuz` counts by the audio inside it. Its lip data counts in the lip sync section.

### Record fields

`records` asks whether a decoder reads each field. `fields` asks whether anything reads the
decoded value afterwards. A field the decoder stores and no game rule reads is data the
engine throws away: `ARMO` `RNAM`, the race a piece fits, is decoded but changes nothing.

The section has two halves:

- `make rank-gaps` builds the index store (`tools/lint-index/build-index.sh`, the same build
  `make lint-index` uses). `tools/lint-index/record-field-reads.py` then lists each property
  of the record module as `read` or `unread` in `field-reads.tsv`, and passes it to
  `openskycli gaps --field-reads`. The first run in a checkout is a full build.
- The CLI decodes every record and walks each value through reflection. A field counts when
  at least one record fills it: a present optional, a non-empty list or text, a non-zero
  number, a true flag, or any enum case. A row names the field as `Type.Nested.field`, then
  up to three record types that fill it, because one Swift type can decode several types,
  such as `DOOR` and `ACTI`.

A field the game does not use counts as done, such as a list count or a Creation Kit note
([record data the game does not use](/formats/unused-record-data.md)).

A field is read when code in another engine module reads it, or when a declaration of the
record module reads it and that declaration is read, such as a computed property another
module calls. A write does not count, and neither does a read in the type's own
initializer, a test, or `openskycli`. A protocol witness is read when its requirement is.

What the rule cannot see:

- A read is not a correct use. A field copied into an engine model counts as read, even when
  nothing reads the model's copy.
- A field reached only through reflection, `Codable`, or a synthesised `==` counts as unread.
- A filled field the list does not name is a note, not a row: the index is older than the
  code. Run `make rank-gaps` again.

### Record flag bits and enum values

A field that engine code reads can still be read only in part. `flags` asks which bits of a
flags field the data sets and which of them engine code tests. `enums` asks which values of
an enum field the data uses and which of them engine code handles. A weapon flag set on
hundreds of weapons that no rule tests is a behaviour the engine ignores.

Both use the same two halves as `fields`. The reflection walk also notes, for each field,
every set bit of an `OptionSet` value and the case of each enum value. The index script
writes `value-reads.tsv` beside `field-reads.tsv`, and `openskycli gaps --value-reads` reads
it.

- A bit is tested when engine code reads the bit's named constant, such as
  `Weapon.Flags.nonPlayable`, by the same rule as a field read. A constant read in the type's
  own decoder counts too, because the decoder turns the bit into another field, which the
  `fields` area checks. A set bit with no named constant is a row named `unnamed`.
- A case is handled when engine code names it, as a `switch` arm or a `==` comparison does.
  A `default` branch names no case, so a value that only a default branch reaches is left.
  The enum's own initializers, `rawValue`, and `description` do not count, because they decode
  or print the value. A value outside the decoder's known set is kept as an `unknown` case
  with its raw number, such as `.unknown 7`, and is always left.

What the check cannot see:

- A branch that names a case and then does nothing counts as handled.
- A flags field stored as a plain integer, not an `OptionSet`, has no bit names. A note lists
  each such field, with the records that set any bit in it.
- Reflection cannot name a case of an enum that prints its own `description`, such as
  `ActorAggression`. A note lists these types.
- A raw enum value stored as a plain integer, such as a type byte, is not an enum field.

### Shallow handlers

`papyrus`, `conditions`, and `perks` count an item as done when a handler exists. `shallow`
asks whether the handler does any work. A handler that only answers a constant counts as
left, ranked by how often the data uses it. `Game.UsingGamepad` answering `false` every time
is an example.

- Natives and condition functions: `tools/shallow-handlers` reads `src/Sources` with
  SwiftSyntax and writes `shallow-handlers.tsv`, which `openskycli gaps --shallow-handlers`
  reads. It finds each registration by its names: `("Sound", "Play")`,
  `(scriptName:functionName:)`, a helper that names only the function, such as
  `reference("GetDistance")`, or `ConditionFunction(index:name:)`. A body is shallow when,
  apart from log lines, it is one constant: a literal, a member such as `.none`, or a call
  such as `.returned(.boolean(true))` whose arguments are constants. A row of a stub table,
  such as the trap stubs that answer `.deviated(_, .stubbed)`, is shallow too.
- Perk entry-point functions are pure, so the CLI runs each one the evaluator computes with
  two values and six payloads. It is shallow when every result is the same.

A handler is shallow on purpose when the game does nothing there either. The comment on its
registration then starts with `Matches the game:` and gives the reason, such as the
`IsHorseStolen` condition, which the CK wiki calls a no-op. It counts as done, and a note
lists it with its reason.

What the check cannot see:

- A body that does work and still answers wrong, such as a guard that always fails.
- A registration built in a loop from names that are not literals, other than a stub table.
- A helper that names only the function is matched to the scripts' calls by that name alone,
  so its uses add up the same function name on every script.

### Rules

- A Papyrus event is an `On...` function that an engine class declares. An engine class is a
  script with native functions, such as `ObjectReference`. A handler is the same name in a
  script without natives.
- A package tree can hold several procedures, but an actor runs one. The others count as left.
- A game setting counts as read when a settings reader asks for it, or when the menus read it
  by prefix (`fStats`, the fast-travel and race menu texts). A setting the game never uses,
  such as a Fallout leftover, counts as done too
  ([settings the game never uses](/formats/gmst.md#settings-the-game-never-uses)).
