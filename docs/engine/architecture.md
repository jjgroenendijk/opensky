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
has the rule and the two shapes a core can take.

## Ports and adapters

A port is a protocol that names what code needs from the outside. An adapter is the concrete
type that does it. Code depends on the port. The app, the CLI, or a test picks the adapter.

Where it applies:

- Game data. `CombatDataProviding`, `MagicDataProviding`, and the other `*DataProviding`
  protocols in `Sources/OpenSkyWorld/Cells/CellBuildProviders.swift` hand plugin data to the
  runtimes. A test passes a small synthetic provider instead of a real install.
- The frame loop. `RenderFrameDriver` is what the renderer needs from the simulation. The
  renderer calls it at fixed points in the frame and never imports the game systems.
- Controls. `AudioControlProviding` is what the audio sidebar section needs.
  `AudioVoiceSection` holds `any AudioControlProviding`, not the audio engine.
- Files. Code reads game files through `any GameFileSource`. `VirtualFileSystem` is the
  adapter over the install. A test passes `InMemoryFileSource` from `GameDataTesting`,
  filled with synthetic bytes.
- The clock. The frame clocks read `Renderer.wallClock`, an `any WallClock`. The app uses
  `MediaWallClock`. A test passes `ManualWallClock` from `RenderingTesting` and steps time
  by hand. Timing reads that only measure how long code took use `DispatchTime` directly.

Where it does not apply: pure code. A parser that takes `Data` needs no port. Do not add a
protocol that has one conformer and no test fake.

## One coordinator per domain

A coordinator owns the state and the logic of one game domain, such as inventory or combat.
It lives in that domain's feature module and is tested there. It imports no AppKit, so the CLI
and the package tests can use it. `GameViewController` keeps only the view, the input, the
render loop, and the panel wiring. It holds the coordinators and forwards to them.

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
