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

The reference example is the vendor domain in `Sources/OpenSkyInventory/`: `VendorCore` and
`VendorCoordinator`. Their tests are `VendorCoreTests` and `VendorCoordinatorTests` in
`Tests/OpenSkyInventoryTests/`. Copy its shape.

## Why

Logic in a `GameViewController+X` file runs only inside the app. A test must build the app
host, and the CLI cannot call it. The view controller also grows with every milestone. A
coordinator in a package module is tested with `make test-fast` in seconds.

## Parts

| Part | Where it lives | Example |
| --- | --- | --- |
| Core: the pure rules | The feature module | `VendorCore` |
| Coordinator: the shell around the core | The feature module | `VendorCoordinator` |
| Port: what the coordinator reads from the world | The same file, as a protocol | `VendorWorld` |
| Result and refusal values | The same file, as value types | `BarterCounterparty`, `BarterOpenRefusal` |
| Adapter: the app's answers to the port | The app, beside the wire function | `InventoryWorldAdapter: VendorWorld` |
| Wire function: builds the coordinator | The app | `InventoryWorldAdapter.wireVendors(provider:)` |
| Effects: menus, camera, sound | The app | `ContainerMenuController.openBarter(with:vendorFaction:)` |

When a domain's last `GameViewController+X` file goes, the adapter and the wire functions move
into a small app class that holds the view controller, such as `CombatWorldAdapter`. The view
controller keeps only the stored coordinator and one-line panel forwards. The combat domain
works this way: `CombatCore`, `CombatCoordinator`, and its port `CombatWorld` live in
`Sources/OpenSkyCombat/`, and the coordinator is also the world of the melee, archery, and
combat-loop runtimes it owns. The magic domain has the same shape: `MagicCore`,
`MagicCoordinator`, and `MagicWorld` in `Sources/OpenSkyMagic/`, answered by
`MagicWorldAdapter`. The coordinator is the cast loop's `CasterWorld`. The inventory domain has
`InventoryCore`, `InventoryCoordinator`, and `InventoryWorld` in `Sources/OpenSkyInventory/`,
answered by `InventoryWorldAdapter`. The coordinator also holds the `VendorCoordinator`.
The faction domain has `FactionCoordinator` and `FactionWorld` in `Sources/OpenSkyFactions/`,
answered by `FactionWorldAdapter`. Its rules are `FactionRuntime` and `HostilityDerivation`.
The crime domain has `CrimeCore`, `CrimeCoordinator`, and `CrimeSessionWorld` in
`Sources/OpenSkyCrime/`, answered by `CrimeWorldAdapter`. The coordinator is the bounty
reporter's `CrimeWorld`. It reaches factions only through its port, because `OpenSkyCrime`
may not import `OpenSkyFactions`.
The audio domain has `AudioLabCore` in `Sources/OpenSkyAudio/`, and `AudioCoordinator` with its
port `AudioWorld` in `Sources/OpenSkyWorld/Session/`, answered by `AudioWorldAdapter`. The
coordinator sits in `OpenSkyWorld`, not `OpenSkyAudio`, because the directors it owns and
`LipSyncPlayback` live there. It is also the panel's `AudioControlProviding`. The view
controller conforms through `AudioControlForwarding`, which forwards every member to it.
The ragdoll domain has `RagdollCoordinator` and `RagdollSessionWorld` in `Sources/OpenSkyCombat/`,
answered by `RagdollWorldAdapter`. It lives beside `RagdollRuntime`, and it is the runtime's
`RagdollWorldSeam`. The player has `PlayerCore`, `PlayerCoordinator`, and `PlayerWorld` in
`Sources/OpenSkyWorld/Player/`, and the Face Morphs panel has `FaceMorphCoordinator` and
`FaceMorphWorld`. `PlayerWorldAdapter` answers both ports.
The dialogue domain has `DialogueCore`, `DialogueCoordinator`, and `DialogueWorld` in
`Sources/OpenSkyDialogue/`, answered by `DialogueWorldAdapter`. The core's speaker focus is a
state machine: it returns hold, face, and release effects, and the coordinator sends them
through the port. The journal has `JournalCore`, `JournalCoordinator`, and `JournalWorld` in
`Sources/OpenSkyQuests/`.
The actor-value domain has `ActorValueCoordinator` and `ActorValueWorld` in
`Sources/OpenSkyActors/`, answered by `ActorWorldAdapter`. That adapter also answers which
actors are resident, through `actorValueHolder(for:)` and `combatActors()`, because every
other adapter needs those reads. The perk and progression domain has `PerkCoordinator`,
`ProgressionCoordinator`, and the ports `PerkWorld` and `ProgressionWorld` in
`Sources/OpenSkyProgression/`, answered by `ProgressionWorldAdapter`. `OpenSkyProgression` may
not import `OpenSkyMagic`, so perk abilities are applied through `PerkWorld`.
The AI domain has four coordinators, all answered by `AIWorldAdapter`. `PackageCoordinator`
with `PackageCore` and `PackageWorld`, `AINavigationCoordinator` with `AINavigationCore` and
`AINavigationWorld`, and `NPCAnimationCoordinator` with `NPCAnimationWorld` live in
`Sources/OpenSkyWorld/`. `PerceptionCoordinator` with `PerceptionCore` and
`PerceptionSessionWorld` lives in `Sources/OpenSkyPerception/`. The perception coordinator is
the pass's `PerceptionWorld`: it filters the session's actors down to the observers.

A menu whose model lives in `OpenSkyMenus` cannot move into a feature module below it. Its
state and its movie code go in a small app class, such as `ContainerMenuController`, and
every transaction it runs is a coordinator call. `DialogueMenuController` and
`JournalMenuController` work the same way. `DialogueCameraController` holds the camera's
panel state and asks the dialogue coordinator to hold the speaker.

The HUD, the developer UI Lab, and the system menu have `HUDCoordinator`, `SWFLabCoordinator`,
`UILabCoordinator`, and `SystemMenuCoordinator` in `Sources/OpenSkyMenus/`. They share one
`SWFMovieSource`, and their port `SWFLayerWorld` gives them the renderer. The renderer has one
SWF layer, so a menu that shows a movie calls `HUDCoordinator.suspend()` first and
`HUDCoordinator.start()` when it closes. The HUD rules are in `HUDCore`. `SystemMenuWorld`
adds the audio state and quitting. The view controller is the one `MenuInputConsumer`, and it
routes each event by the top of the menu stack. It conforms to each panel protocol through a
`...ControlForwarding` protocol, like the audio panel.

The panel forwards live in `GameViewControllerPanels.swift`, so `GameViewController.swift`
stays under the file length limit.

A port is a protocol that names what the coordinator needs from outside, such as the streamed
references or the game hour. A test passes a fake that returns plain values. The app passes
itself or a small adapter. The coordinator holds the port `weak`, because the app owns the
coordinator.

The coordinator returns values, not text. The app turns a value into a readout line and runs
the menu or camera change. Example: `counterparty(for:vendorFaction:)` returns
`.failure(.chestNotResident(factionName:))`, and the app writes "... merchant chest is not
streamed in."

## Pure core, thin shell

Every coordinator splits into two parts:

- The core decides. It is pure: values in, values out. It imports no AppKit, Metal, or audio,
  reads no clock, and calls no port. A test calls it with plain values and needs no fake.
- The shell does the input and output. It holds the state and the port, reads the world,
  calls the core, and runs what the core returns.

A core has one of two shapes:

- A domain without state has pure functions. Example: `VendorCore.counterparty(vendor:actor:stock:)`
  takes the vendor and the stock the shell read, and returns the counterparty or a refusal.
- A domain with state has a value-type state machine:
  `(state, input) -> (newState, [Effect])`. An effect is a value that names one action, such
  as "play this sound" or "open this menu". The shell stores the new state and runs each
  effect through a port.

Loaded plugin data, such as `VendorResolver`, may sit inside the core. It does not change
while the game runs, so reading it keeps the core pure.

Test the decisions on the core. Test the shell only for its world reads, with a small fake
port. Example: `VendorCoreTests` covers every refusal with values, and
`VendorCoordinatorTests` checks that the shell reads the chest, the hour, and the keywords.

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
2. Write the core in the feature module. Every decision goes here, as a pure function or a
   state machine.
3. Write the coordinator and its port beside it. Every read of `streamer`, `renderer`, or
   another bridge state becomes one port member.
4. Test the core with values. Test the shell with a fake port.
5. In the app, add the stored property, the wire function, and the port adapter. Point every
   caller at the coordinator, and delete the old functions.
6. Run `make check` and `make test-fast T='<Feature>Tests'`, then `make verify-build`.

Do not add a new `GameViewController+X` file for new logic. A SwiftLint rule will enforce this
once every domain has moved ([code-health automation](/decisions/code-health-automation.md)).
