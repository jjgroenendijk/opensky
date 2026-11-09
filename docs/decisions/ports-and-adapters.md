---
type: Decision
title: Ports and adapters
description: How the world adapters connect the session to each feature - adapter modules,
  narrow host protocols of ports and values, the size limits and their reasons, and the lint
  that checks them.
tags: [decision, architecture, adapters, lint]
---

# Ports and adapters

A feature coordinator reads the world through a protocol, its port. Example: `MagicCoordinator`
reads `MagicWorld`. A world adapter answers that port from the running session. Example:
`MagicWorldAdapter` answers `MagicWorld` with the actors, the cells, and the scripts.

The adapter needs parts of the session. It does not get the whole session. It gets a host: a
protocol that lists only the parts it reads. `SessionPorts` in the app answers every host, and
the session scope builds each adapter with it (`/decisions/session-scope.md`).

`tools/lint/module-graph.sh` checks rule 7 as its rule 13 (`/decisions/modular-architecture.md`).
`tools/lint-index/adapter-references.py` checks rule 8 in `make lint-index` and the `Index checks` CI job
on each pull request, because it reads the index store that a build writes.
`tools/lint/app-architecture.sh` checks rules 1 to 4, and `tools/lint/adapter-rules.sh` checks
rule 5 with SwiftLint (`tools/lint/adapters.swiftlint.yml`). `make lint`, `make check`, and CI
run both. Each reads every adapter or app file, so `OPENSKY_CHECK_ALL=1` changes nothing for them. Each first
runs its rules on a small synthetic violation, which must fail.

## The rules

| Rule | What must be true | Why |
| --- | --- | --- |
| 1 | An adapter that needs no AppKit or SwiftUI lives in an adapter package module | The app keeps only the shell and the composition root; the module size limit holds |
| 2 | A host member is a port or a value type | A port can be faked in a test; a concrete class, a view, or another adapter cannot |
| 3 | A host has at most 12 members, its inherited hosts included | A wide host hides what the adapter depends on |
| 4 | An app or adapter type has at most 4 extension files and 600 lines | Matches the file length warning, so one type stays readable in one sitting |
| 5 | An adapter has no magic number and no function over complexity 6 | A game rule in an adapter has no unit test; in its feature module it has one |
| 6 | The late-setter, late-attached-world, and pure-core lints cover the app and the adapters | A dependency set after the initializer can be missing when the object is first used |
| 7 | A module depends only on a module at least as stable, or on an interface | A change in an unstable module then cannot force changes in the stable modules below it |
| 8 | No adapter uses the type of an adapter outside its own family | Two adapters that know each other change together, and neither can be built in a test alone |

A port is a protocol from an interface module or a foundation module, or a class from a data
layer, such as `WorldDataStores`. A value type is a struct, an enum, a type alias, or a type of
the standard library, Foundation, or `simd`.

Rule 8 reads real symbols, not text: a use is a reference in the index store, and the code
that holds it belongs to the adapter whose symbol contains it. An adapter is a type whose name
ends in `Adapter` in an adapter module or the app's `GameView/`. A family is an owner and the
parts it was split into ([Splitting a large adapter](#splitting-a-large-adapter)): a part is an
adapter that another adapter of the same module stores in a property. Inside one family, every
use is allowed. A helper that answers no port, such as `SkyrimSaveImport`, is not named `Adapter`.

Rule 3 counts members of inherited hosts, because the adapter can reach them all. Example:
`MenuRouterHost` refines `MenuSoundHost`, so its 5 members and the 3 of `MenuSoundHost` count
as 8.

Rule 5 counts a `switch` as one branch, because a switch that maps one enum to another is
not a game rule. A number moves with its rule into the feature module, with a unit test, such
as `WardArc.halfArc` in `OpenSkyMagic`. A technical number, such as a distance below which two
points are the same, gets a named constant in the adapter. A value without a source also gets a
row in `/engine/unverified-values.md`.

## Splitting a large adapter

An adapter whose host passes 12 members is split into smaller adapters. Each smaller adapter
is a struct with its own host. It holds an `unowned` reference to the owner only when it calls
back into it. Example:
`CombatWorldAdapter` keeps its frame wiring and owns `CombatGearAdapter`,
`CombatOutcomesAdapter`, and `CombatReportsAdapter`.

The owner still conforms to the feature's port, so the coordinator holds one object.
`<Adapter>+Witnesses.swift` forwards each port requirement to the part that answers it.
A part that a coordinator holds weakly is a `final class` that the owner stores, because a
struct has no identity to hold.

## Adapter modules

The adapters live in eleven modules, one per feature group, such as `OpenSkyMagicAdapters` and
`OpenSkyStoryAdapters`. `src/Package.swift` declares them with the `composition` helper:

- They may import feature implementations, because an adapter connects them.
- No other package module may import them. Only the app and `openskycli` link them.
- `module-graph.sh` treats every module whose name ends in `Adapters` as composition.

## Connecting a started session

The session starts after its adapters are built, so an adapter is connected to it later. The
connection is a step, not a method: a `<Name>Wiring` struct whose initializer does the work, such
as `CombatMeleeWiring(combatWorld, gameSession: gameSession)`. The composition root builds the
steps in order. An adapter, a coordinator, and the app keep no `wire...` or `install...` method,
and no `attach(world:)`-style setter, so the `late_setter_method` and `late_attached_world`
SwiftLint rules hold everywhere, the app included.

## The game view

The view is AppKit, so no adapter holds it. An adapter gets what it needs as values or ports:

- `drawableSize` and `viewBounds` are host members of value type.
- The menu cursor and the key bindings: the session scope applies them to `GameMetalView`. The
  adapter returns the value or calls a closure that the scope sets.
- A benchmark tour gets `BenchmarkViewPort`. The shell's `BenchmarkViewSurface` answers it with
  the overlay, the window mode, and the uncapped frame loop.
- Quitting the app: the scope sets the adapter's `terminateApp` closure.

## Alternatives that lost

- One host per adapter, as before. The widest host had 73 members, so a test fake had to answer
  all of them.
- An exception list for the large adapters. It would keep the wide hosts and grow over time.
- One module for all adapters. It is over the module size warning, and a module per feature
  shows which features an adapter connects.
