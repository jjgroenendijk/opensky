---
type: Decision
title: Design metrics
description: The limits that keep types small, loosely coupled, acyclic, and minimally public,
  why each value was chosen, and how each rule lands from a report to a gate.
tags: [decision, architecture, lint, code-quality]
---

# Design metrics

These checks keep each type small and keep its links to other types few and visible. The
principles behind them give no fixed numbers, so each limit below is our own choice. This page
records each value and its reason.

## How a rule lands

Each rule starts at zero, as every check here does
([code-health automation](/decisions/code-health-automation.md)):

1. The rule lands as a report, such as `make design-index-report` for the rules that read the
   index store. The report prints each finding and the count per module, and it fails nothing.
2. The findings are fixed per module, one module or a group of modules per pull request.
3. The limit moves into the lint config, and the rule becomes a gate, when the count on `main`
   is zero. There is no exception list.

## Rule 1: size limits

SwiftLint checks the size of a function's parameter list, a tuple, and nested types. All three
limits are gates in `tools/lint/.swiftlint.yml`: nesting since 2026-11-09, parameters and tuples
since 2026-11-10.

| Limit | Value | Before | Findings when set (2026-11-09) | Reason |
| --- | --- | --- | --- | --- |
| Parameters of a function, defaults not counted | 4 | 5 | 283 | A long list usually means a missing value type. A limit of 3 gives 1056 findings, so 4 comes first and 3 is tried when this count is zero |
| Members of a tuple | 2 | 2 | 0 | Already the lint value. A wider result gets a named struct |
| Levels of nested types | 1 | 2 | 17 | A type nested two levels deep is hard to find and to name from outside. Most findings are record layouts in `OpenSkyFormatsESM` |

Example: `func cast(spell: FormID, from caster: ReferenceKey, at target: ReferenceKey,
hand: SpellHand, cost: Float)` takes 5 parameters. A `SpellCast` value that holds them makes
the call read as one idea and gives the next field a home.

## Rule 2: fan-out per type

A type that uses many other types does many jobs, and a change in any of them can break it.
This is coupling between objects, after Chidamber and Kemerer. `make lint-index` counts for
each type the other types it uses, and fails on each type over the limit
(`tools/lint-index/fan-out.py --gate`). The `Index checks` CI job runs it.

- A type uses another when code inside it names that type or one of its members.
- Only types declared under `src/Sources/` count. The standard library and Apple's
  frameworks do not, because every type uses them.
- A type's nested types, and the type it is nested in, do not count.
- The composition root and the session scope are left out by name: `GameViewController`,
  `GameSessionScope`, `GameSessionScopeBuild`, `GameSessionScopeCellReset`,
  `GameSessionScopeFactories`, and `SessionPorts`. Building the object graph is their job.
  `GameSessionScopeBuild` is the second stage of the session scope: it builds every adapter
  and coordinator over the started session. `GameSessionScopeCellReset` builds the cell
  reset over the load-order stores in the same way.

| Limit | Value | Findings when set (2026-11-10) | Reason |
| --- | --- | --- | --- |
| Other types one type uses | 40 | 103 of 4322 types | The count spreads widely: 733 types use more than 10, 329 more than 20, and the largest, `CellSceneBuilder`, uses 327. A limit of 40 comes first, so the fixes start with the worst types. The limit tightens in later pull requests, as rule 1 did |

The limit is a gate since 2026-11-13, when the count on `main` reached zero.

Example: a coordinator that reads records, runs the game rules, and starts effects uses the
types of all three jobs. When each job moves into its own type behind a port, each part uses
only the types of its job, and the coordinator uses the parts.

## Rule 3: minimal public surface

A `public` declaration that no other module uses widens what other modules can come to depend
on. This is information hiding, after David Parnas. Periphery's redundant-public report finds
nothing on this package layout (measured 2026-11-08), so `make lint-index` runs its own check
on the index store and fails on each finding (`tools/lint-index/public-surface.py --gate`). The
`Index checks` CI job runs it.

- The index store holds no access levels. The check reads the source line at each definition,
  and finds `public` or `open` before the name, or a `public extension` around it.
- Another module uses a declaration when its code names it. A test file that imports the module
  with `@testable` sees internal declarations, so its use does not count.
- A declaration also stays public when another module uses one of its members, or when a
  public declaration that is needed names it, such as a type in the signature of a used
  function. A name on the line of a declaration counts as part of its signature. An enum case
  or a protocol requirement is public with its type, so the names on its line count for that
  type.
- A protocol witness and an override stay public, because their requirement needs it.

| Limit | Value | Findings when set (2026-11-10) | Reason |
| --- | --- | --- | --- |
| Public declarations no other module uses | 0 | 7151 of 39799 | The rule has no tolerance: a declaration is needed outside its module or it is not. Most findings are record fields and coordinator members that only the module and its `@testable` tests read |

Example: a parser module marks a record's raw `unknownNAM5` field `public`, but only the parser
and its tests read it. Without the keyword, the field is internal, and a later change to it
cannot break another module.

## Rule 4: no cycles between types across files

When type A uses type B and B uses A, neither can change or be tested alone. A cycle that
spans files usually means one type or one module is really two. This is the Acyclic
Dependencies Principle, after Robert C. Martin, applied to types. `make lint-index` fails on
each cycle (`tools/lint-index/type-cycles.py --gate`), and the `Index checks` CI job runs it.

- Type A uses type B when code inside A names B or one of its members, and both are declared
  in the same module under `src/Sources/`.
- Code in an extension counts for the type it extends, and the type sits in the file that
  declares it.
- A cycle is a group of types where each one reaches every other through such uses. A cycle
  whose types all sit in one file is allowed, such as a tree node and its parent, a recursive
  enum, or an owner and its delegate.

| Limit | Value | Findings when set (2026-11-10) | Reason |
| --- | --- | --- | --- |
| Cycles whose types sit in more than one file | 0 | 49 cycles, 241 types | The rule has no tolerance. The largest cycles are the save decoders in `OpenSkySave` (32 types), the record types in `OpenSkyFormatsESM` (30), and the NIF decoders in `OpenSkyFormatsMesh` (23) |

Example: a save decoder calls each part decoder, and each part decoder calls back into the
main decoder to validate what it read. When the validation moves into its own type, both
sides use that type, and the cycle is gone.

## Rule 5: Law of Demeter

A long chain through objects ties the caller to the inner structure of objects it does not
own. This is the Law of Demeter, after Lieberherr. `make lint-index` fails on each deep chain
(`tools/lint-index/member-chains.py --gate`), and the `Index checks` CI job runs it.

- A chain is a run of member accesses on one line, such as `game.combat.archery?.projectiles.live`.
- A step counts when the index store names the member it reaches, and that member belongs to a
  class, an actor, or a protocol limited to classes declared under `src/Sources/`.
- Steps through structs and enums do not count, so reading the fields of a parsed record is
  allowed.

| Limit | Value | Findings when set (2026-11-10) | Reason |
| --- | --- | --- | --- |
| Steps through reference types in one chain | 3 | 18 chains | The issue's value. All findings are in the adapters, where an adapter reaches through its host into a feature's runtime |

Example: `game.combat.archery?.projectiles.live` reaches through four objects. A `liveProjectiles`
member on the combat port gives the adapter the list, and the adapter no longer depends on how
archery stores it.

## Rule 6: abstractness and instability per module

A module that many others use should be abstract, so it can change without breaking them. A
module that uses many others and that no other uses can stay concrete. This is the distance
from the main sequence, after Robert C. Martin. `make module-metrics` writes the report to
`module-metrics.md` in its run directory, and the weekly workflow runs it and keeps the file.

- Instability is `I = Ce / (Ca + Ce)`. `Ce` counts the package modules a module depends on,
  and `Ca` counts the package modules that depend on it. Test targets, and the support modules
  under `src/Tests/`, count for neither.
- Abstractness is `A = protocols / types` declared in the module's Swift files.
- Distance is `D = |A + I - 1|`. A module on the main sequence has `D = 0`.

This rule is a report, not a gate. An interface module here holds value types as well as
protocols, so a large distance is a question for a review, not a failure. On 2026-11-10, 30 of
84 modules have a distance of 0.7 or more. Most are the format and interface modules, which
many modules use and which hold mostly value types.

## Rule 7: one job per module

The fan-out rule looks at one type at a time. It cannot see a module that holds several jobs,
where each type is small but the module mixes unrelated work. Such a module rebuilds, and can
break, for changes that have nothing to do with most of its types. `make design-groups` builds
the index store and writes the report to `design-groups.txt` in its run directory
(`tools/design/design-groups.py`). The weekly workflow runs it and keeps the file.

- Each type is a node, and a link joins two types when code inside one names the other or one
  of its members, as in rule 2.
- The Louvain method (Blondel and others, 2008) finds groups of types with many links inside
  and few between. The report runs it with a fixed seed, so two runs give the same groups.
- Modularity (Newman) scores a grouping from 0 to about 1. The report prints it for the module
  partition and for the Louvain groups.
- For each module with 15 or more types, the report prints its number of natural groups and the
  share of its types in the largest one. A low share means the module holds several jobs.
- For each type over the rule 2 limit, it groups the members that call each other or that use
  mostly the same outside types (Jaccard similarity of 0.3 or more). Each group is a candidate
  for its own type.

The Louvain method is written out in the script, about 60 lines, so the tooling needs no graph
library. This rule is a report, not a gate: some modules span groups by design, and the table
below gives the reason for each. For each module under 50 %, the report also lists its groups
with a few type names, which shows the jobs the module mixes.

The modularity of the module partition is 0.44 on 2026-11-13, after the fan-out splits of rule
2 (`main` at the gate of rule 2). The Louvain groups reach 0.72. No module was split for this
rule, so the first run and the last run are the same run. A group that serves one feature
only is a candidate to move into that feature, tracked as open work.

Each module below has less than half of its types in its largest group. The share is from the
run on 2026-11-13.

| Module | Share | Reason it spans groups |
| --- | --- | --- |
| `OpenSkyCLI` | 15 % | A driver: one group per command family, such as the SWF, audio, and animation commands. Each family follows the feature it drives |
| `OpenSkyCLIArguments` | 28 % | The argument types of the same command families, for the same reason |
| `OpenSky` | 41 % | The app: the launcher pages, the session scope, and one group per menu controller. It drives every feature |
| `OpenSkyWorldInterface` | 16 % | An interface module: value types that many features share, one group per feature that reads them, such as dragon flight and the benchmark. The groups that serve one feature only are candidates to move |
| `OpenSkySessionInterface` | 33 % | The ports of the session, one group per feature that uses them. A port belongs next to the other ports, so the adapters find them in one place |
| `OpenSkyActorsInterface` | 37 % | Actor values, actor conditions, and combat state: three faces of one actor, read by different features |
| `OpenSkyMenusInterface` | 42 % | The menu snapshots and input routing that each menu shares with the app |
| `OpenSkyShaderTypes` | 22 % | Structs and indexes shared with the Metal shaders. Each shader family has its own group, and they share no code by design |
| `OpenSkyRenderCore` | 22 % | The Metal-free render math, one group per pass: decals, sky, grass, particles, shadows. Passes share little by design |
| `OpenSkyRendering` | 26 % | The renderer and its passes. The passes meet only in the frame encoder, which holds them together |
| `OpenSkyFormatsCore` | 45 % | Shared readers and small value types, such as the binary reader, the logger, and the control map. Each format module uses a few of them |
| `OpenSkyFormatsAudio` | 43 % | Two audio containers, FUZ and Bink, which share only the WAV output |
| `OpenSkyGameData` | 44 % | The record stores, the load order, and the actor value data that every feature reads. The asset load queue is a candidate to move |
| `OpenSkySessionAdapters` | 26 % | Adapters that answer ports from the session: runtime state, save export, and audio. Each group is one port family |
| `OpenSkyMenuAdapters` | 40 % | One group per menu port: the map, the loading screen, and the menu screens |
| `OpenSkyStoryAdapters` | 47 % | One group per story port: ambient talk, crime, and dialogue |
| `OpenSkyActorAdapters` | 48 % | One group per actor port: animation events, actor values, mounts, and actor graphs |
| `OpenSkyPlayer` | 37 % | The player's body: the state graph, interaction rays, mounts, and cameras. The mounts are a candidate to move |
| `OpenSkyActorPresentation` | 40 % | Actor animation, assembly, dragon flight, lip sync, and vehicles. Dragon flight and vehicles are candidates to move |
| `OpenSkyQuests` | 45 % | Quest aliases, the journal, and social events: the three parts of the quest runtime |
| `OpenSkyObjectAnimation` | 48 % | Animated cell objects, effect graphs, and trap contacts: everything that moves without being an actor |
