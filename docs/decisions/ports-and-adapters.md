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

`tools/lint/app-architecture.sh` checks the rules below. `make lint`, `make check`, and CI run
it. It reads every tracked Swift file, so `ALL=1` changes nothing for it. It first runs each
rule on a small synthetic violation, which must fail.

## The rules

| Rule | What must be true | Why |
| --- | --- | --- |
| 1 | An adapter that needs no AppKit or SwiftUI lives in an adapter package module | The app keeps only the shell and the composition root; the module size limit holds |
| 2 | A host member is a port or a value type | A port can be faked in a test; a concrete class, a view, or another adapter cannot |
| 3 | A host has at most 12 members, its inherited hosts included | A wide host hides what the adapter depends on |
| 4 | An app or adapter type has at most 4 extension files and 600 lines | Matches the file length warning, so one type stays readable in one sitting |

A port is a protocol from an interface module or a foundation module, or a class from a data
layer, such as `WorldDataStores`. A value type is a struct, an enum, a type alias, or a type of
the standard library, Foundation, or `simd`.

Rule 3 counts members of inherited hosts, because the adapter can reach them all. Example:
`MenuRouterHost` refines `MenuSoundHost`, so its 5 members and the 3 of `MenuSoundHost` count
as 8.

## Splitting a large adapter

An adapter whose host passes 12 members is split into smaller adapters. Each smaller adapter
is a struct with its own host and an `unowned` reference to the owner. Example:
`CombatWorldAdapter` keeps its frame wiring and owns `CombatGearAdapter`,
`CombatOutcomesAdapter`, and `CombatReportsAdapter`.

The owner still conforms to the feature's port, so the coordinator holds one object.
`<Adapter>+Witnesses.swift` forwards each port requirement to the part that answers it.
A part that a coordinator holds weakly is a `final class` that the owner stores, because a
struct has no identity to hold.

## Adapter modules

The adapters live in eleven modules, one per feature group, such as `OpenSkyMagicAdapters` and
`OpenSkyStoryAdapters`. `Package.swift` declares them with the `composition` helper:

- They may import feature implementations, because an adapter connects them.
- No other package module may import them. Only the app and `openskycli` link them.
- `module-graph.sh` treats every module whose name ends in `Adapters` as composition.

An adapter module is part of the composition root. So the `late_setter_method` SwiftLint rule
does not apply to it: an adapter's `wire...(gameSession:)` method connects it to a session that
starts after the adapter is built. Coordinators in feature modules still take every dependency
in their initializer.

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
