---
type: Decision
title: The Modular Architecture
description: Why OpenSky lays its modules out by The Modular Architecture (TMA) without Tuist,
  the rules the module-graph check enforces, the layer list, and the allowed exceptions.
tags: [decision, architecture, modules, swiftpm, lint]
---

# The Modular Architecture

OpenSky follows [The Modular Architecture](https://tuist.dev/en/docs/guides/features/projects/tma-architecture)
(TMA). A feature is a set of targets: `Feature`, `FeatureInterface`, and `FeatureTests`, plus
an optional `FeatureFixtures` (see below). A feature uses another feature only through its
Interface. The app and `OpenSkyCLI` build the implementations and
pass them in (dependency injection).
[Swift modules](/tools/modules.md) describes the layout and the `Package.swift` helpers.

## Why TMA

- A feature builds and tests alone. A change to magic does not rebuild combat, because combat
  imports only `OpenSkyMagicInterface`.
- The Interface is the public API. What another feature may call is one small module, not
  every `public` declaration in the implementation.
- A test uses a fake from a `Testing` library instead of the real runtime.

## Why one Testing library for all features

TMA gives each feature its own `FeatureTesting` target. OpenSky keeps the fakes of every feature
Interface in one library, `OpenSkyFeaturesTesting`, as it keeps one testing library per layer
([tests](/tools/modules.md#tests)). Every target costs manifest and graph time on each build, and
a fake depends only on Interfaces, so one shared library builds no feature implementation.

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
| 6. Complete sets | Every feature has its `Interface` and `Tests` targets, or an exception with a reason. Every Interface has its feature | Gate |
| 7. Declared imports | Every `import` of a package module names the target itself or a declared dependency | Gate |
| 8. Composition | `OpenSkyPreview`, the app, and the CLI may depend on anything | Allowed |
| 9. World domains | A domain of the world feature depends on lower modules, Interfaces, and earlier domains. Of the features, only `OpenSkyWorld` depends on a domain. Every domain has a `Tests` target | Gate |
| 10. Renderer | `OpenSkyRendering` depends only on the formats, `OpenSkyGameData`, the asset cache, and its draw helpers. Game state reaches it in `RenderFrameInput` | Gate |

Rule 7 matters because Xcode builds all package modules into one product. A module can then
compile with an `import` it never declared, and break later in `swift test` or on another
build order.

`Package.swift` checks rules 1 and 2 partly too, when the manifest loads. It rejects a
dependency on a module declared later, and a dependency on a feature implementation. The
script adds the layer list, the Interface rules, the complete sets, and the imports.

## Fixtures libraries

Some fixtures need the feature's own implementation. Two examples: `FakeCombatWorld` fakes
`CombatLoopWorld`, a seam that `OpenSkyCombat` declares, and `CellStreamerFixture` builds a
real cell streamer. The feature's tests and the acceptance chains in the Xcode bundles both use
them, and a test target cannot import another test target. TMA has no target for this, so
OpenSky adds one: `FeatureFixtures`, in `Tests/FeatureFixtures/`.

Rules 4 and 5 keep it narrow. A `Fixtures` library may build only its own feature, and only
`FeatureTests` and the Xcode bundles link it. So another feature's tests still reach the
feature only through its Interface and its `Testing` fakes.

A fixture that needs two implementations is integration support. It goes in
`Tests/HostedTestSupport/` when both Xcode bundles use it, else in `Tests/OpenSkyTests/Support/`.

## The layers

The lower modules sit in layers, and the one list of them is `LAYERS` at the top of
`tools/lint/module-graph.sh`, lowest layer first. A new lower module goes into that list.

A target outside it is an Interface, a world domain, a feature, or a composition module. The
script tells them apart by name: an Interface ends in `Interface`, a domain is listed in
`DOMAINS`, and a composition module is listed in `COMPOSITION`
([world domains](/tools/modules.md#world-domains)). Anything else is a feature, so a new
module must bring its full set or an exception.

## Exceptions

| Missing target | Reason |
| --- | --- |
| `OpenSkyMenusInterface` | Nothing depends on menus |
| `OpenSkySaveInterface` | Nothing depends on saves |

The list is `MISSING` in the script. An exception whose target now exists fails the check, so
the list never goes stale.
