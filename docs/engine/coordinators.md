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

`GameViewController` keeps only the view, the input, and the render loop. It holds the
coordinators and forwards to them.

The reference example is the vendor domain in `Sources/OpenSkyInventory/`: `VendorCore` and
`VendorCoordinator`. Their tests are `VendorCoreTests` and `VendorCoordinatorTests` in
`Tests/OpenSkyInventoryTests/`. Copy its shape.

## Why

Logic in a `GameViewController+X` file runs only inside the app. A test must build the app
host, and the CLI cannot call it. The view controller also grows with every milestone. A
coordinator in a package module is tested with `make test-unit` in seconds.

## Parts

| Part | Where it lives | Example |
| --- | --- | --- |
| Core: the pure rules | The feature module | `VendorCore` |
| Coordinator: the shell around the core | The feature module | `VendorCoordinator` |
| Port: what the coordinator reads from the world | The same file, as a protocol | `VendorWorld` |
| Result and refusal values | The same file, as value types | `BarterCounterparty`, `BarterOpenRefusal` |
| Adapter: the app's answers to the port | The app, beside the wire function | `InventoryWorldAdapter: VendorWorld` |
| Wire function: builds the coordinator | The app | `InventoryWorldAdapter.wireWorldItems(provider:streamer:)` |
| Effects: menus, camera, sound | The app | `ContainerMenuController.openBarter(with:vendorFaction:)` |

When a domain's last `GameViewController+X` file goes, the adapter and the wire functions move
into a small app class that holds the view controller, such as `CombatWorldAdapter`. The view
controller keeps only the stored coordinator. The combat domain
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
coordinator sits in `OpenSkyWorld`, not `OpenSkyAudio`, because the directors it owns live
there.
The ragdoll domain has `RagdollCoordinator` and `RagdollSessionWorld` in `Sources/OpenSkyCombat/`,
answered by `RagdollWorldAdapter`. It lives beside `RagdollRuntime`, and it is the runtime's
`RagdollWorldSeam`. The player has `PlayerCore`, `PlayerCoordinator`, and `PlayerWorld` in
`Sources/OpenSkyPlayer/`, and face morphs have `FaceMorphCoordinator` and
`FaceMorphWorld`. `PlayerWorldAdapter` answers both ports.
The dialogue domain has `DialogueCore`, `DialogueCoordinator`, and `DialogueWorld` in
`Sources/OpenSkyDialogue/`, answered by `DialogueWorldAdapter`. The core's speaker focus is a
state machine: it returns hold, face, and release effects, and the coordinator returns them
as `DialogueCommand` values. The journal has `JournalCore`, `JournalCoordinator`, and
`JournalWorld` in `Sources/OpenSkyQuests/`.
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
`Sources/OpenSkyAIPackages/`. `PerceptionCoordinator` with `PerceptionCore` and
`PerceptionSessionWorld` lives in `Sources/OpenSkyPerception/`. The perception coordinator is
the pass's `PerceptionWorld`: it filters the session's actors down to the observers.
Runtime state has `RuntimeStateCore`, `RuntimeStateCoordinator`, and
`RuntimeStateWorld` in `Sources/OpenSkyRuntimeState/`, answered by `RuntimeStateWorldAdapter`.
The coordinator owns the `GlobalStore` and the clock scrubs. Save and load go through the port,
because `OpenSkyRuntimeState` may not import `OpenSkySave`. The adapter also builds the live condition
context, because it reads every feature's runtime. Papyrus has `ScriptCoordinator` and
`ScriptWorld` in `Sources/OpenSkyScripting/`, answered by `ScriptWorldAdapter`, which also gives
the natives their collaborators. `WorldRenderControls` in `Sources/OpenSkyWorld/Session/` holds
the renderer and streamer controls that agent control uses. It has no core, because it only reads
and writes the renderer. `WorldSessionWiring` in the app builds the streamer and runs every wire
function in order.

A menu whose model lives in `OpenSkyMenus` cannot move into a feature module below it. Its
state and its movie code go in a small app class, such as `ContainerMenuController`, and
every transaction it runs is a coordinator call. `DialogueMenuController` and
`JournalMenuController` work the same way. `DialogueCameraController` holds the camera's
state and asks the dialogue coordinator to hold the speaker.

The HUD and the system menu have `HUDCoordinator` and `SystemMenuCoordinator` in
`Sources/OpenSkyMenus/`. They share one
`SWFMovieSource`, and their port `SWFLayerWorld` gives them the renderer. The renderer has one
SWF layer, so a menu that shows a movie calls `HUDCoordinator.suspend()` first and
`HUDCoordinator.start()` when it closes. The HUD rules are in `HUDCore`. `SystemMenuWorld`
adds the audio state and quitting. The view controller is the one `MenuInputConsumer`, and it
routes each event by the top of the menu stack.

A port is a protocol that names what the coordinator reads from outside, such as the streamed
references or the game hour. A test passes a fake that returns plain values. The app passes a
small adapter. The coordinator takes the port in its initializer and keeps it, so a coordinator
is never half built. The adapter holds the session `unowned`, so there is no retain cycle.
When the adapter owns the coordinator, or the port is the view controller itself, the
coordinator keeps the port as `weak let`, and the app builds it in a `lazy var`. The lint rule
`late_attached_world` fails a late-attach method, such as `attach(world:)`, in a package
module. How the other dependencies reach a coordinator, and which late setters remain, is in
[session scope](/decisions/session-scope.md).

An adapter reads the session through its own host protocol, such as `CombatWorldHost`. The
protocol lists only the coordinators and values that adapter reads. `GameViewController`
conforms to every host protocol in one file, and an adapter holds `unowned let game: any
CombatWorldHost`, never the view controller itself. Only the composition root, the app shell
and the `GameViewController` files, names the view controller in code. The lint rule
`controller_outside_composition_root` fails any other use; a comment that says which type
conforms is fine. A value that a Settings
reload replaces, such as the renderer or the streamer, is a get-only requirement, so the
adapter always reads the live one. A small adapter that reads two or three parts takes a
dependency struct instead, such as `HazardWorldDependencies`, with a closure for each
replaceable value. `FactionWorldAdapter`, `HazardWorldAdapter`, `TrapControlAdapter`, and
`MenuSoundPlayer` work this way. An adapter keeps no game state of its own: the furniture
seat holders and the last package moves live in `PackageCoordinator`, where a unit test
reaches them.

The Papyrus bridge gets its collaborators as one value per native family:
`actorNatives`, `magicNatives`, `progressionNatives`, `crimeNatives`, `playerNatives`,
`perceptionNatives`, `sessionNatives`, `gameNatives`, and `factionNatives`. Each member is an optional
closure. The default value answers nothing, which matches a load without that data, so a
native refuses rather than reading a half-wired family. A new collaborator goes in a family.
The lint rule `papyrus_loose_closure` fails a closure property on the bridge itself.

The coordinator returns values, not text. The app turns a value into text and runs
the menu or camera change. Example: `counterparty(for:vendorFaction:)` returns
`.failure(.chestNotResident(factionName:))`, and the app writes "... merchant chest is not
streamed in."

Every action returns a typed outcome, such as `ItemActionOutcome` or
`LockActionOutcome`. The outcome's `text` gives the line the app shows. An outcome whose
words come from the load order takes them as an argument, such as `text(training:)` or
`text(texts:)`. A test compares outcomes, not English sentences. The lint rule
`action_returns_text` fails a `@discardableResult` function that returns `String` in a package
module.

## Commands

A coordinator does not change the world outside its domain through its port. It returns a
command instead, and the app runs it. A command is a value of the domain's command enum, such
as `InventoryCommand`. Example: an equip returns
`InventoryResult(outcome, commands: [.equipmentChanged(holder)])`, and
`InventoryWorldAdapter.run(_:)` asks magic to re-read the hands.

- An action that changes the world returns its answer and its commands together, such as
  `InventoryResult<Value>`. An action without an answer returns the command list.
- Every caller in the app passes the result through the adapter's `run(_:)`.
- A call that must answer at once, such as reporting skill use for the experience it gives,
  stays a port member, because a command has no answer.
- An effect that must land before the next line of the same step also stays a port member.
  Examples: a loading screen pauses the world as a door transition starts, and a perk grant
  applies its abilities before the next formula reads them.
- A test compares the returned commands. It needs no fake that records calls.

A frame step returns its commands. When other calls also raise commands, such as a hit
report, the coordinator collects them in `pendingCommands`, and the frame
step returns them through `takeCommands()`. Such a command waits at most one frame. Crime,
combat, magic, progression, scenes, and the social pass work this way. A frame step that
only computes a pose returns a value instead: `CinematicCameraCoordinator.tick(realSeconds:)`
returns a `CinematicFrame`, and the adapter writes it to the renderer.

## Pure core, thin shell

Every coordinator splits into two parts:

- The core decides. It is pure: values in, values out. It imports no AppKit, Metal, or audio,
  reads no clock, and calls no port. A test calls it with plain values and needs no fake.
  The lint rule `pure_core_side_effect` checks the imports and the clocks of a `...Core` file.
- The shell does the input and output. It holds the state and the port, reads the world,
  calls the core, and returns what the core decided, with its commands for the app.

A core has one of two shapes:

- A domain without state has pure functions. Example: `VendorCore.counterparty(vendor:actor:stock:)`
  takes the vendor and the stock the shell read, and returns the counterparty or a refusal.
- A domain with state has a value-type state machine:
  `(state, input) -> (newState, [Effect])`. An effect is a value that names one action, such
  as "play this sound" or "open this menu". The shell stores the new state and returns each
  effect that leaves the domain as a command.

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
   and input code in the app.
2. Write the core in the feature module. Every decision goes here, as a pure function or a
   state machine.
3. Write the coordinator and its port beside it. Every read of `streamer`, `renderer`, or
   another bridge state becomes one port member.
4. Test the core with values. Test the shell with a fake port.
5. In the app, add the stored property, the wire function, and the port adapter. Point every
   caller at the coordinator, and delete the old functions.
6. Run `make check` and `make test-unit T='<Feature>Tests'`, then `make build-app`.

Do not add a new `GameViewController+X` file for new logic. The lint rule
`game_view_controller_extension` fails an extension of the view controller outside its own
files ([code-health automation](/decisions/code-health-automation.md)).
