---
type: Convention
title: Coordinators
description: How game logic moves out of GameViewController into one coordinator per domain -
  where a coordinator lives, what it may import, how it reaches the world, and how the app
  wires it.
tags: [engine, architecture, modules, app]
---

# Coordinators

A coordinator owns the state and the logic of one game domain, such as vendors or guards. It
is a class in that domain's feature module, for example `OpenSkyInventory`. The package tests
and `openskycli` can use it, because it imports no AppKit.

`GameViewController` keeps only the view, the input, the render loop, and the panel wiring.
It holds the coordinators and forwards to them.

The reference example is `VendorCoordinator` in `Sources/OpenSkyInventory/`. Its tests are
`VendorCoordinatorTests` in `Tests/OpenSkyInventoryTests/`. Copy its shape.

## Why

Logic in a `GameViewController+X` file runs only inside the app. A test must build the app
host, and the CLI cannot call it. The view controller also grows with every milestone. A
coordinator in a package module is tested with `make test-fast` in seconds.

## Parts

| Part | Where it lives | Example |
| --- | --- | --- |
| Coordinator | The feature module | `VendorCoordinator` |
| Port: what the coordinator reads from the world | The same file, as a protocol | `VendorWorld` |
| Result and refusal values | The same file, as value types | `BarterCounterparty`, `BarterOpenRefusal` |
| Adapter: the app's answers to the port | The app, beside the wire function | `extension GameViewController: VendorWorld` |
| Wire function: builds the coordinator | The app | `wireVendors(provider:)` |
| Effects: menus, camera, sound | The app | `openBarter(with:vendorFaction:)` |

A port is a protocol that names what the coordinator needs from outside, such as the streamed
references or the game hour. A test passes a fake that returns plain values. The app passes
itself or a small adapter. The coordinator holds the port `weak`, because the app owns the
coordinator.

The coordinator returns values, not text. The app turns a value into a readout line and runs
the menu or camera change. Example: `counterparty(for:vendorFaction:)` returns
`.failure(.chestNotResident(factionName:))`, and the app writes "... merchant chest is not
streamed in."

## Module rules

These follow from [The Modular Architecture](/decisions/modular-architecture.md):

- A coordinator imports its own module, lower package modules, and other features'
  `Interface` modules. It never imports another feature's implementation module.
- A call into another feature goes through a protocol in that feature's `Interface` module,
  or through the coordinator's own port, which the app answers.
- The app is the composition root. It builds every coordinator in its wire function, in the
  order the wire functions already run.
- `make module-graph` checks the imports.

Example: vendors need an actor's faction memberships. `OpenSkyInventory` may not import
`OpenSkyFactions`, so `VendorWorld.factionMemberships(of:)` returns an `ActorFactionState`
from `OpenSkyFactionsInterface`. The app answers it from its faction runtime.

## Moving a domain

1. Pick the logic in the `GameViewController+X` file that decides something. Leave view,
   input, and panel code in the app.
2. Write the coordinator and its port in the feature module. Every read of `streamer`,
   `renderer`, or another bridge state becomes one port member.
3. Write tests with a fake port in the feature's test target.
4. In the app, add the stored property, the wire function, and the port adapter. Point every
   caller at the coordinator, and delete the old functions.
5. Run `make check` and `make test-fast T='<Feature>Tests'`, then `make verify-build`.

Do not add a new `GameViewController+X` file for new logic. A SwiftLint rule will enforce this
once every domain has moved ([code-health automation](/decisions/code-health-automation.md)).
