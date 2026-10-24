---
type: Decision
title: Session scope
description: How coordinators get their dependencies - an app scope and a session scope, built
  by hand with full initializers, the kinds of dependency and the target for each, declared
  frame and event order, the alternatives that lost, and the checks that keep the design.
tags: [decision, architecture, coordinators, dependency-injection, lint]
---

# Session scope

A coordinator gets every dependency in its initializer. All objects that belong to one loaded
game are built together in one place, the **session scope**, and are dropped together when the
game ends. There is no dependency-injection framework and no late setter.

Words used on this page:

- A **dependency** is an object or value that a coordinator needs to do its work, such as a
  record store or another feature's seam.
- A **late setter** is a method or a settable property that gives a coordinator a dependency
  after its initializer has run, such as `wire(store:)` or `storyEvents = self`.
- A **scope** is a group of objects with one lifetime. They are built together and released
  together.
- The **composition root** is the one place that builds the object graph. It is the only code
  that knows the concrete types.

## Why late setters must go

Coordinators used to be `lazy var` properties of the game view controller. A host protocol
could build one before the world data was wired, so the data arrived later, through `wire...`
methods and settable properties. This has four costs:

- A coordinator is half built until every setter runs. Every method checks for a missing
  runtime and returns nothing.
- A forgotten setter fails silently. Nothing crashes; a behaviour is missing.
- The order of the setter calls matters, and only comments say so. Example: "After `wireSkills`:
  the skill runtime banks into this one."
- A test that forgets a setter can pass without testing anything.

## The fact the design builds on

The world loads before the game view exists. The launcher loads the data root, the plugins,
and the cell session. Only then does the app build the game view and hand it the loaded world.
A Settings change that needs new data builds a new game view after a new load. So when the
game objects are built, their data is already there. Nothing needs to wait for it.

The early build had one other reason: a developer view held coordinators for the whole run.
That view is gone, so the reason is gone too.

## The decision

Two scopes, each built by hand by a composition root:

| Scope | Lifetime | Holds |
| --- | --- | --- |
| App | From launch to quit | The launcher, the data root locator, the asset cache, player settings, save-game files, agent control, the pipeline cache |
| Session | From one loaded world and its Metal view to the end of that game view | The loaded stores, the file source, the world state store, the cell streamer, the frame session and renderer, every coordinator, every world adapter, every menu controller |

The session scope is one final class, `GameSessionScope`. Its initializer takes the loaded
world, the cell build runner, the frame session, and the app services it needs
(`GameAppServices`). The game view builds it when the view loads, the one point where the
loaded world and the view both exist, and then calls `start()`.

Rules:

- A coordinator's initializer takes everything it needs. Nothing it needs is optional only
  because it arrives later. A store that the load order really lacks stays optional, and the
  coordinator says what it does without it.
- The session scope builds a dependency before the object that needs it. The compiler checks
  this order: code cannot pass a value that does not exist yet. No comment explains an order.
- An object in the app scope never holds an object of the session scope. When the session
  ends, releasing the session scope releases every game object.
- The game view holds the session scope and keeps only the view, the input, and the draw loop.
  Without game data there is no session scope. The renderer draws the demo scene, and agent
  control answers that no game is loaded.
- Only the composition roots build coordinators: the session scope in the app, and a test
  fixture in a test. `openskycli` builds no coordinator today; if it needs one, it builds a
  session scope the same way.

## The kinds of dependency

Each dependency is one of seven kinds. The kind decides how it arrives.

| Kind | Example | How it arrives |
| --- | --- | --- |
| World port | `CombatWorld`, `VendorWorld` | An initializer parameter, answered by a world adapter, as today |
| Feature seam | Crime witnesses from perception, story events | An initializer parameter. Build the feature that answers it first |
| Session data | Record stores, game settings, texts resolved from `GMST` | An initializer parameter, often grouped in one value per coordinator |
| Session object | The actor-value runtime, the streamer, the clip loader, the Papyrus VM | An initializer parameter, built earlier in the same scope |
| Event | A spell hit, an idle's animation event, the audio engine start | A command the coordinator returns, or a handler in a declared event schedule |
| Late asset | The player's behaviour graphs, idle clips | Requested at start and drained from a mailbox in the frame ([concurrency](/decisions/concurrency.md)) |
| Live input | A player setting changed in the launcher, an agent command's argument | A method argument, or a port member read each time. Never stored as a dependency |

A world adapter reads the session through its host protocol and holds the session scope
`unowned`. The session scope conforms to the host
protocols instead of the view controller.

A setting the player changes while the game runs is live input, not a dependency. Example: the
combat temperament switch calls `combat.load(settings:)` with the new value. That stays.

## Cycles

Two coordinators that need each other cannot both take the other in the initializer. Break the
cycle in this order of preference:

1. **A command.** The coordinator returns what it wants, and the app runs it. Most cross-domain
   changes already work this way ([coordinators](/engine/coordinators.md#commands)).
2. **A port answered by an adapter.** The coordinator takes a port. The adapter that answers it
   holds the session scope `unowned` and asks the other coordinator at call time. The session
   scope builds its members as `lazy` properties, so an adapter may be built before the
   coordinator it later reads.
3. **An event schedule.** The coordinator reports an event, and the other side registers a
   handler in a declared phase (below).

A setter is never the way out of a cycle.

## Frame order and event order

A frame hook is a `FrameSchedule` over a phase enum, and the enum order is the run order
([architecture](/engine/architecture.md#isolation-per-subsystem)).

Each multicast event uses the same type with its own phase enum. A handler registers in its
phase, and the enum order is the delivery order. One phase takes one handler, so a second
registration is a wiring bug and traps. So the session scope may register handlers in any
order. Examples:

- The streamer's interaction event (`InteractionStep`) reaches audio first, then the scripts,
  then the item pickup, then the agent event log.
- A cell attach (`CellAttachStep`) lets cell reset choose the references to reset before the
  scripts attach, and queue the reset events after.
- The activation gate asks its checks in `ActivationGateStep` order, and the first refusal
  wins: a rider is refused at a door before the lock is checked.

## The game UI and agent control

- A menu controller and the HUD belong to the session scope. They are built with it and read
  their coordinators through initializer parameters.
- Agent control (`openskycli game`) reads the session scope through the world adapters, one
  command at a time. It keeps nothing past the session.
- With no session scope, an agent command answers that no game is loaded.

## How other engines and apps do it

- **Unreal Engine** gives each subsystem the lifetime of an outer object: the engine, the game
  instance, the world, or a local player. A subsystem is built and destroyed with its outer
  object, and it may ask for another subsystem to start first. OpenSky copies the scopes: the
  app scope is the engine, the session scope is the world. Unreal finds subsystems by type at
  run time; OpenSky does not copy that, because the compiler can check our smaller graph.
  Source: [Programming Subsystems](https://dev.epicgames.com/documentation/en-us/unreal-engine/programming-subsystems-in-unreal-engine).
- **Bevy** runs systems over shared resources and orders them with explicit sets and
  `before`/`after` rules, not by the order they were added. OpenSky copies the declared order
  through phase enums. It does not copy resource lookup: a missing resource fails at run time.
  Source: [`bevy_ecs` schedules](https://docs.rs/bevy/latest/bevy/ecs/schedule/index.html).
- **Godot** autoloads are global singletons that any script reaches by name. That is a
  service locator, and it hides which object needs which. Not copied. Source:
  [Singletons (Autoload)](https://docs.godotengine.org/en/stable/tutorials/scripting/singletons_autoload.html).
- **Pure DI with a composition root** builds the whole graph by hand in one place, at the
  program's entry. This is the chosen design. Source:
  [Composition Root](https://blog.ploeh.dk/2011/07/28/CompositionRoot/).
- **Uber Needle** checks a scoped Swift graph at compile time with a code generator. Our graph
  has about 40 coordinators, and a hand-written root gives the same compile-time check without
  a generator in the build. Source: [Needle](https://github.com/uber/needle).
- **Point-Free `swift-dependencies`** reads a dependency from a task-local environment with a
  default value. A missing dependency gets the default, which is the silent failure this page
  removes. Source: [swift-dependencies](https://github.com/pointfreeco/swift-dependencies).

## Alternatives and why each lost

| Alternative | Why it lost |
| --- | --- |
| Keep late setters and add a debug check per coordinator that every setter ran | The object is still half built. The check runs only at run time, and only on the paths a run takes |
| One `load(_:)` per coordinator that takes all session data as one value | One setter instead of many, but the state is still optional until it runs. It only helps when data arrives after the coordinator, and it does not |
| A runtime container (Swinject, Factory, Resolver) with scopes | A missing registration fails at run time. The graph hides in registrations. It adds a dependency, and its global registry fights Swift 6 isolation |
| A compile-time container with code generation (Needle) | Same check as a hand-written root, plus a generator in the build and a new dependency. The size of our graph does not need it |
| A task-local environment or a service locator (`swift-dependencies`, Godot autoloads, singletons) | Dependencies are hidden in the body, not the signature. A default value hides a missing dependency |
| Coordinators read stores from one shared `WorldDataStores` port on demand | Every read can fail, so every method keeps the missing-data branch. It moves the late setter into a lookup |

## What is left

Every coordinator takes its session data in the initializer. Two parts of the start still run
after the scope is built:

- `start()` builds the streamer, so its users read it as an optional.
- Session start replaces the inventory, magic, and effects coordinators with ones built over
  the loaded world, instead of the scope building them once.

The `Papyrus` bridge's native families stay as they are. Each family is a value with optional
closures, and a missing family answers nothing on purpose, so a native refuses instead of
reading a half-wired family ([coordinators](/engine/coordinators.md)). The session scope fills
every family when it builds the bridge.

The bridge's feature seams, such as its quest layer and its inventory, arrive together in one
`PapyrusBridgeSeams` value when the bridge is built. They stay settable, so a test fixture can
give a built bridge one fake.

A spell hit leaves the magic coordinator as a `MagicCommand`. A hit applied outside the magic
frame steps, such as an arrow's or a script's, runs the commands at once, so the hit effects
and the ragdoll's push land in the same frame as the damage. Every cast reaches the Papyrus
`OnSpellCast` event through the `MagicWorld` port.

## What the checks enforce afterwards

- A lint rule fails a method in a package module whose name starts with `wire` or `install`.
  The existing rule `late_attached_world` keeps failing `attach(world:)` and the like.
- A lint rule fails a coordinator property that is settable from outside its module and holds a
  dependency: a type ending in `Store`, `Settings`, `Texts`, `Runtime`, `Catalog`, `Resolver`,
  `World`, `Seam`, `Reporting`, or `Presenting`, or a closure named `on...`.
- A lint rule fails a coordinator built under `Sources/` outside the session scope's files.
- There is no registration-ordered multicast type left, so a new event needs a phase enum.
- A unit test builds the session scope from a synthetic load and checks that it builds.
