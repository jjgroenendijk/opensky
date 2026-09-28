---
type: Tool
title: Swift modules
description: How the engine splits into Swift modules through the root Swift package, the layout
  rules of The Modular Architecture, and the access and import rules that follow.
tags: [tool, build, swift, modules, swiftpm]
---

# Swift modules

The engine is a set of library modules in a Swift package. `Package.swift` at the repository
root declares them. `OpenSky.xcworkspace` holds the Xcode project and the package side by side,
and `make` builds through it.

The app and `OpenSkyCLI` link one product, `OpenSkyModules`, which holds every library module.
The Xcode test bundles link one product, `OpenSkyTestSupport`, which holds every shared test
fixture library. `Package.swift` builds both lists itself, so a new module needs no edit to
`OpenSky.xcodeproj`.

## Why a module boundary

A module boundary makes the architecture visible and lets the compiler enforce it.
`Package.swift` lists what each module depends on, and the compiler rejects an `import` of a
module that is not listed. So an upward dependency fails the build instead of slipping in.

A module can also be built and tested alone: `make test-fast T='OpenSkyFormatsESMTests'` builds
only the package and runs one test target, without the app.

## The layout: The Modular Architecture

The layout follows [The Modular Architecture](https://tuist.dev/en/docs/guides/features/projects/tma-architecture)
(TMA) from Tuist. There are two kinds of module.

A **foundation module** is a library with a stable public API. Every module above it may import
it directly. Formats, game data, and the other low layers are foundation modules.

A **feature module** has up to four targets:

| Target | Holds | Exists when |
| --- | --- | --- |
| `X` | the implementation | always |
| `XInterface` | the protocols and value types other modules use | another module uses the feature |
| `XTesting` | fakes and fixtures other modules' tests share | another module's tests need them |
| `XTests` | the unit tests of `X` | `X` has tests |

A module that uses a feature imports its `XInterface`, never `X`. Only the composition roots,
the app and `OpenSkyCLI`, import feature implementations. They build the object graph at startup
and hand each module what it needs through its initializer. There is no dependency-injection
framework.

An `XInterface` holds protocols and value types only, with no runtime logic beyond small value
helpers. A declaration goes there only when another module uses it.

## How Package.swift enforces the rules

`Package.swift` declares modules bottom-up with two helpers:

```swift
targets += foundation("OpenSkyGameData", dependencies: ["OpenSkyFormatsESM", ...], tests: [...])
targets += feature("OpenSkyMagic", dependencies: [...], interface: [...], tests: [...])
```

`foundation` declares `X` and, when `tests` is given, `XTests`. `feature` declares `X` and, on
request, `XInterface`, `XTesting`, and `XTests`, with the dependencies wired as the table above
says. Both helpers check each dependency before the package loads:

- The dependency must be declared earlier. A module never depends on a module on its own layer
  or above.
- The dependency must not be a feature implementation.

A broken rule stops the manifest with a message that names both modules.

The helpers also give every target the same settings: the language settings of
`Config/Build/Base.xcconfig`, `MainActor` default isolation for library code, and the header
path of the vendored ffmpeg. Test targets also link ffmpeg, because a package test executable
has no `OTHER_LDFLAGS`. Change the settings in `Package.swift` and the xcconfig together.

## Modules

```text
OpenSkyFormatsCore        binary readers, compression, geometry values, BSA, string tables
  ^
OpenSkyFormatsESM         plugin records          OpenSkyFormatsMesh    NIF, TRI, LOD, DDS
OpenSkyFormatsAnimation   HKX, LIP                OpenSkyFormatsAudio   WAV, XWM, FUZ
OpenSkyFormatsPEX         compiled Papyrus        OpenSkyFormatsSWF     Flash menus, AS2
  ^
OpenSkyGameData           virtual file system, load order, record index, record stores
  ^
OpenSkyBehavior           Havok behavior graph evaluation, skeleton pose math
  ^
OpenSkyPhysics            static and trigger collision, dynamic bodies, ragdolls
OpenSkyDiagnostics        memory footprint, debug overlays; needs only OpenSkyShaderTypes
  ^
OpenSkyRendering          Metal renderer, scenes, cameras, terrain meshes, weather values
OpenSkyAudio              audio graph, decoders, sound and music record stores
OpenSkyWorldState         runtime state store, open component set, game clock, globals
  ^
OpenSkyConditions         condition evaluator, function registry, core functions
  ^
OpenSkyEngine             the rest of the engine, until it is split
  ^
OpenSky app, OpenSkyCLI   composition roots
```

The format families depend only on `OpenSkyFormatsCore`, never on each other. A parser change
rebuilds its family and the modules that import it, not every format.

Two more targets wrap C headers. `OpenSkyShaderTypes` holds the structs shared with Metal
([build system](/tools/build-system.md)). `CFFmpeg` is the clang module over the vendored ffmpeg
([ffmpeg](/decisions/ffmpeg-audio.md)).

`Sources/Shaders/Shaders.metal` is not in the package. The app and the CLI each compile it,
because `device.makeDefaultLibrary()` reads the main bundle.

## Keeping the lines clean

A lower module never imports a higher one. Three patterns keep it that way:

- A value type both sides need moves down, for example `CellCoordinate`, `ModelBounds`, and
  `ActorValueIdentity` in `OpenSkyFormatsCore` and `OpenSkyFormatsESM`.
- Behavior that needs a higher layer stays up there as an extension of the lower type, in a file
  named `Type+Feature.swift`. Examples: `Package+Schedule.swift` in the engine over a
  `OpenSkyFormatsESM` record, and `EquipSlotStore+Hands.swift` and `FactionStore+Templates.swift` in
  the engine over `OpenSkyGameData` stores.
- A lower module that must call up defines a protocol, and the higher module conforms to it.
  Example: `Renderer` draws, and it calls a `RenderFrameDriver` at fixed points of each frame
  to move the camera and run the world. The engine's `GameSession` is that driver.
- A lower module that stores something for every feature keeps an open set instead of a closed
  enum. `OpenSkyWorldState` stores any `WorldStateComponent`, and each feature declares its own
  `WorldStateComponentKind`. `ConditionContext` stores any `ConditionResolution` by type, and each
  feature adds an accessor such as `context.magic`. The code that names every feature, such as
  the `.standard` condition registry, lives above all of them.

## Access and imports

A declaration another module uses is `public`. The rules that follow are the standard library
rules:

- A struct's implicit memberwise initializer is `internal`. A struct another module builds needs
  an explicit `public init(...)`. So does a type whose `init()` is a default argument value. An
  `OptionSet` needs `public init(rawValue:)`.
- Swift does not infer `Sendable` for a public type. A public value type that crosses isolation
  states `Sendable` in its declaration. A type that holds a class reference or a closure, such as
  the AS2 interpreter values, does not. A generic type conforms conditionally, for example
  `extension RecordIndexDecodeResult: Sendable where Value: Sendable {}`.
- `MemberImportVisibility` is on. Every file that uses a module writes its own `import`. A
  missing import sometimes shows as a pattern error, for example "pattern variable binding cannot
  appear in an expression".
- Tests write `@testable import` to reach `internal` members.

After a module is renamed or removed, delete its old products from `DerivedData/Build/Products`
(including `PackageFrameworks/`) and from `.build/`. Otherwise a stale `.swiftmodule` still
satisfies an old `import`, and the build fails with two types of the same name, for example
"cannot convert value of type 'OpenSkyFormatsESM.FormID' to expected argument type
'OpenSkyFormats.FormID'".

## Tests

Shared test fixtures live in a testing library, `Tests/<Name>Testing/` (for a foundation
module, the name the module declares, for example `BehaviorTesting`). Its declarations are
`public`, and it may `@testable import` the module it builds fixtures for.

A testing library changes how Xcode builds the module it uses. The app and the test bundles
then share that module, so Xcode builds it as a dynamic framework. A module that depends on
`CFFmpeg` cannot be a framework: Xcode stops with "The workspace has a reference to a missing
target with GUID 'PACKAGE-TARGET:CFFmpeg'". So `OpenSkyAudio` has no testing library. Its
fixtures stay inside `OpenSkyAudioTests`.

The package test targets run in the `UnitTests` and `Sanitizers` plans next to `OpenSkyTests`. A
test plan names a package test target with `"containerPath" : "container:."`, the package at the
repository root. Only a workspace shows a scheme the test targets of a local package. Through
`-project OpenSky.xcodeproj`, xcodebuild reports that the target "isn't a member of the specified
test plan or scheme".

`make test-fast T='<Target>Tests/...'` runs one package test target through `swift test`
(`tools/test-package.sh`). It builds only the package, into `.build/`, and needs no app host.

A test that needs only one module goes in that module's test target. A test that needs the app,
the shader library in the app bundle, or the whole object graph stays in `Tests/OpenSkyTests/`.
