---
type: Convention
title: Architecture styles
description: The six architecture styles OpenSky follows - what each means here, where it applies,
  where it does not, and one example from the tree.
tags: [engine, architecture, modules, testing, concurrency]
---

# Architecture styles

OpenSky follows six architecture styles. Each one answers a different question. This page
names them, so a design discussion or a review can point at one rule.

| Style | Question it answers |
| --- | --- |
| The Modular Architecture | Which module may import which |
| Functional core, imperative shell | Where logic ends and side effects start |
| Ports and adapters | How code reaches files, Metal, audio, and the UI |
| One coordinator per domain | Where the state and logic of one game system live |
| Data-oriented layout | How hot data sits in memory |
| Isolation per subsystem | Which thread or actor runs the code |

## The Modular Architecture

A feature uses another feature only through its `Interface` module. The app and `openskycli`
build the implementations and pass them in. `make module-graph` checks the rules.

[The Modular Architecture](/decisions/modular-architecture.md) has the rules, the layers, and
the exceptions. This page does not repeat them.

## Functional core, imperative shell

The core is pure code: a function or a value type. It takes values and returns values. It
reads no file, no clock, and no global state. It calls no Metal, audio, or UI. The shell is
the thin layer around it. The shell holds the state, reads the inputs, calls the core, and
runs the side effects.

Why: a pure core is tested with plain values. The test needs no fake, no game install, and no
main thread.

Where it applies:

- Format parsers. A parser takes `Data` and returns a value or throws. Example:
  `XWMFile.init(data:)`. The code that finds and reads the file is the shell.
- Game rules. Example: `ArcheryDamage.resolve(bowDamage:arrowDamage:drawFraction:skill:bonusMultiplier:)`
  is a pure function. `ArcheryState.handle(_:)` is a value-type state machine: one graph
  event in, one state change out. `ArcheryRuntime` is the shell. It feeds graph events to the
  state and spawns projectiles into the world.

Where it does not apply:

- The renderer, the audio engine, and the app shell are mostly shell. Keep their pure parts
  (math, culling, mixing rules) in separate functions, but do not force the rest into this
  shape.
- A small runtime with almost no logic does not need a separate core.

A coordinator follows this style too: a pure core and a thin shell. [Coordinators](/engine/coordinators.md)
has the rule and the two shapes a core can take. A core lives in a file whose name ends in
`Core`, such as `VendorCore.swift`. The lint rule `pure_core_side_effect` fails such a file
when it imports AppKit, Metal, or an audio framework, or reads a clock such as `Date()`.

## Ports and adapters

A port is a protocol that names what code needs from the outside. An adapter is the concrete
type that does it. Code depends on the port. The app, the CLI, or a test picks the adapter.

Where it applies:

- Game data is a value, not a port. `WorldDataStores` holds every plugin store as a typed
  field, so a subsystem reads the field it needs and the compiler checks it. A store the load
  order does not have is `nil`. A test builds a `WorldDataStores` with only the stores it
  needs; the rest keep their synthetic defaults.
- The frame loop. `RenderFrameDriver` is what the renderer needs from the simulation. The
  renderer calls it at fixed points in the frame and never imports the game systems. Each
  frame the driver returns one `RenderFrameInput` value, built after every system has run:
  the view, the weather, the moved references, the player rigs, and the UI. The renderer
  reads game state only from that value, so nothing changes half way through an encode. A
  renderer without a driver draws the input its caller sets. Rule 10 of `make module-graph`
  keeps the renderer's dependencies to formats, loaded data, assets, and draw helpers, and
  the lint rule `renderer_downcast` fails a cast of the renderer or its driver.
- Controls. `AudioControlProviding` is what the audio sidebar section needs.
  `AudioVoiceSection` holds `any AudioControlProviding`, not the audio engine.
- Files. Code reads game files through `any GameFileSource`. `VirtualFileSystem` is the
  adapter over the install. A test passes `InMemoryFileSource` from `OpenSkyEngineTesting`,
  filled with synthetic bytes.
- The clock. The frame clocks read `Renderer.wallClock`, an `any WallClock`. The app uses
  `MediaWallClock`. A test passes `ManualWallClock` from `OpenSkyEngineTesting` and steps time
  by hand. Timing reads that only measure how long code took use `DispatchTime` directly.

Where it does not apply: pure code. A parser that takes `Data` needs no port. Do not add a
protocol that has one conformer and no test fake.

## One coordinator per domain

A coordinator owns the state and the logic of one game domain, such as inventory or combat.
It lives in that domain's feature module and is tested there. It imports no AppKit, so the CLI
and the package tests can use it. `GameViewController` keeps only the view, the input, the
render loop, and the panel wiring. It holds the coordinators and forwards to them. A
coordinator takes its port in its initializer and returns the changes it wants outside its
domain as commands, which the app runs. The lint rule `late_attached_world` fails a
late-attach method, such as `attach(world:)` or `wire(host:)`, in a package module. The lint
rule `controller_outside_composition_root` fails code that names `GameViewController` outside
the app shell and the `GameViewController` files; a comment may still name it.

Where it applies: every game domain that has a `GameViewController+X` file today. Issues 30.24
to 30.34 move them.

Where it does not apply: view code, input handling, and sidebar panels stay in the app.

[Coordinators](/engine/coordinators.md) has the pattern, the module rules, and the steps to
move a domain.

## Data-oriented layout

Hot data sits in plain structs in contiguous arrays, so a per-frame loop reads memory in
order. No class references and no dictionary lookups inside the loop.

Examples: `SkinningPalette` keeps its bone matrices in `[float4x4]`. `HKABonePose` and
`RagdollPose` are plain value types, stored in arrays.

The same goes for work whose inputs change only at load: a sort, a template resolve, or a bounds
union. Do it when the inputs change and store the result, not on every frame.

Where it applies: only a per-frame loop where a measurement, such as an Instruments Time
Profiler run, shows a cost. [Profiling](/testing.md#profiling) says how to record one.

Where it does not apply: everything else. Code that runs once per cell load or once per user
action stays in the clearest shape. A layout change without a measurement is a performance
idea, so it becomes a GitHub issue, not an inline change.

## Isolation per subsystem

Every package module uses `defaultIsolation(MainActor.self)` (see `librarySettings` in
`Package.swift`). So code runs on the main actor unless it says otherwise. Data that crosses
threads is a `nonisolated` `Sendable` value type, for example `SkinningPalette`. Shared
mutable state off the main thread uses `Mutex`, as in `WorldAudioEngine`.

Simulation stays on the main actor. Reading and decoding files runs off it.
[Concurrency](/decisions/concurrency.md) gives the isolation each subsystem uses and how a
loaded asset reaches the frame loop. Do not add a new
`@unchecked Sendable` class or `Task.detached`. A new `DispatchQueue` needs a row on that page.

The simulation runs in a declared order. A frame has three hooks, each a `FrameSchedule`: the
frame steps after the camera moves, the asset drains, and the world tick after the clock. Each
hook takes one step per case of its phase enum (`FrameStep`, `AssetDrain`, `WorldTickStep`),
and the enum order is the run order. So moving a wiring statement cannot reorder the
simulation, and a system wired late still runs in its own slot. A new system adds a case where
it must run; a unit test pins the world-tick order. The lint rule `frame_callback_property`
fails a closure property or a `CallbackFanOut` whose name says frame, tick, or update, so no
second list of per-frame callbacks grows beside the schedule.

## Machine checks

Every rule on this page and in [Coordinators](/engine/coordinators.md) has a check in
`make check` and CI. The SwiftLint rules are in `tools/lint/.swiftlint.yml`.

| Rule | Check |
| --- | --- |
| A feature uses another feature only through its `Interface` module | `make module-graph`, rules 1 to 9 |
| Only the composition root names `GameViewController` | SwiftLint `controller_outside_composition_root` |
| No `GameViewController` extension outside its own files | SwiftLint `game_view_controller_extension` |
| No late-attach method in a package module | SwiftLint `late_attached_world` |
| A panel action returns a typed outcome, not `String` | SwiftLint `action_returns_text`, `panel_action_returns_text` |
| A pure core imports no AppKit, Metal, or audio, and reads no clock | SwiftLint `pure_core_side_effect` |
| The renderer holds no game state and is not cast to the session | `make module-graph` rule 10, SwiftLint `renderer_downcast` |
| The Papyrus bridge gains collaborators only through a native family | SwiftLint `papyrus_loose_closure` |
| A system joins the frame only through a `FrameSchedule` phase | SwiftLint `frame_callback_property` |
| No new `@unchecked Sendable`, `Task.detached`, `DispatchQueue.main`, or semaphore in `Sources/` | SwiftLint `unchecked_sendable`, `detached_task`, `main_queue_or_semaphore` |
| A new `DispatchQueue` has a row in [Concurrency](/decisions/concurrency.md) | SwiftLint `new_dispatch_queue` |
| A module stays below 30,000 source lines | `make module-size` ([Module size](/tools/modules.md#module-size)) |
