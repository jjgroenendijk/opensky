---
type: Decision
title: The Modular Architecture
description: Why OpenSky lays its modules out by The Modular Architecture (TMA) without Tuist,
  the rules the module-graph check enforces, the layer list, and the allowed exceptions.
tags: [decision, architecture, modules, swiftpm, lint]
---

# The Modular Architecture

OpenSky follows [The Modular Architecture](https://tuist.dev/en/docs/guides/features/projects/tma-architecture)
(TMA). A feature is a set of targets: `Feature`, `FeatureInterface`, `FeatureTesting`, and
`FeatureTests`, plus an optional `FeatureFixtures` (see below). A feature uses another
feature only through its Interface. The app and `OpenSkyCLI` build the implementations and
pass them in (dependency injection).
[Swift modules](/tools/modules.md) describes the layout and the `Package.swift` helpers.

## Why TMA

- A feature builds and tests alone. A change to magic does not rebuild combat, because combat
  imports only `OpenSkyMagicInterface`.
- The Interface is the public API. What another feature may call is one small module, not
  every `public` declaration in the implementation.
- A test uses a fake from a `Testing` library instead of the real runtime.

## Why no Tuist

TMA is a set of rules, not a tool. Tuist generates Xcode projects, and OpenSky already avoids
project-file edits: target membership follows the folder, and `Package.swift` declares every
module ([build system](/tools/build-system.md)). A second project generator would add a tool
and a second source of truth. So the rules are checked on the package graph instead.

## Why no Example apps

TMA gives each feature an `Example` app that runs the feature alone. In OpenSky the feature's
sidebar destination in the main app, plus its `openskycli` command, does that job. So there
are no `Example` targets.

## The check

`make module-graph` runs `tools/lint/module-graph.sh`. It reads the graph from
`swift package dump-package` and the `import` lines of each target, so it needs no build and
runs in about a second. `make lint` runs it, so `make check`, `make fix`, and CI run it too.

| Rule | What it says | Status |
| --- | --- | --- |
| 1. Layers | A lower module depends only on a module in a lower layer. It never depends on an Interface, a feature, or a composition module | Gate |
| 2. Feature -> Interface | A feature depends on lower modules and on Interfaces only, its own included | Gate |
| 3. Thin Interface | An Interface depends on lower modules and other Interfaces only | Gate |
| 4. Testing -> Interface | A `Testing` library depends on no feature implementation and no `Fixtures` library. A `Fixtures` library depends on no implementation but its own feature's | Gate |
| 5. Tests -> own feature | `FeatureTests` depends on no feature implementation and no `Fixtures` library but its own. A test that needs two real implementations goes in `OpenSkyTests` | Gate |
| 6. Complete sets | Every feature has all four targets, or an exception with a reason | Gate |
| 7. Declared imports | Every `import` of a package module names the target itself or a declared dependency | Gate |
| 8. Composition | `OpenSkyPreview`, the app, and the CLI may depend on anything | Allowed |

Rule 7 matters because Xcode builds all package modules into one product. A module can then
compile with an `import` it never declared, and break later in `swift test` or on another
build order.

`Package.swift` checks rules 1 and 2 partly too, when the manifest loads. It rejects a
dependency on a module declared later, and a dependency on a feature implementation. The
script adds the layer list, the Interface rules, the complete sets, and the imports.

## Fixtures libraries

Some fixtures need the feature's own implementation. Two examples: `FakeCombatWorld` fakes
`CombatLoopWorld`, a seam that `OpenSkyCombat` declares, and `CellSceneBuilderFixture` builds
real cell scenes. The feature's tests and the acceptance chains in the Xcode bundles both use
them, and a test target cannot import another test target. TMA has no target for this, so
OpenSky adds one: `FeatureFixtures`, in `Tests/FeatureFixtures/`.

Rules 4 and 5 keep it narrow. A `Fixtures` library may build only its own feature, and only
`FeatureTests` and the Xcode bundles link it. So another feature's tests still reach the
feature only through its Interface and its `Testing` fakes.

A fixture that needs two implementations is integration support. It goes in
`Tests/TestSupport/` when both Xcode bundles use it, else in `Tests/OpenSkyTests/Support/`.

## The layers

The lower modules, lowest first. The list is `LAYERS` in the script.

1. `OpenSkyShaderTypes`, `CFFmpeg`
2. `OpenSkyFormatsCore`
3. The format families: `OpenSkyFormatsESM`, `Mesh`, `Animation`, `Audio`, `PEX`, `SWF`
4. `OpenSkyGameData`
5. `OpenSkyBehavior`
6. `OpenSkyPhysics`, `OpenSkyDiagnostics`
7. `OpenSkyRendering`, `OpenSkyAudio`, `OpenSkyWorldState`
8. `OpenSkyConditions`

Every other target under `Sources/` is an Interface, a feature, or a composition module. The
script tells them apart by name: an Interface ends in `Interface`, and a composition module is
listed in `COMPOSITION`. Anything else is a feature, so a new module must bring its full set or
an exception.

## Exceptions

| Missing target | Reason |
| --- | --- |
| `OpenSkyMenusInterface` | Nothing depends on menus |
| `OpenSkyMenusTesting` | No other module's tests need menu fakes |
| `OpenSkySaveInterface` | Nothing depends on saves |
| `OpenSkyCombatTesting` | Its fakes fake seams the implementation declares, so they are in `OpenSkyCombatFixtures` |
| `OpenSkySaveTesting` | Nothing depends on saves |
| `OpenSkyScriptingTesting` | Its fixtures run the Papyrus implementation, so they are in `OpenSkyScriptingFixtures` |

The list is `MISSING` in the script. An exception whose target now exists fails the check, so
the list never goes stale.
