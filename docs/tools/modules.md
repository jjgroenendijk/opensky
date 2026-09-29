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

A third helper, `interface`, declares only `XInterface`. It is for a feature that is split
later than a module that already needs its interface. Example: crime needs `InventoryAccess`
before inventory is split, so `interface("OpenSkyInventory", ...)` comes first, and a later
`feature("OpenSkyInventory", ...)` uses that interface instead of declaring a second one.

A fourth helper, `composition`, declares a module that the app and `OpenSkyCLI` share. It may
import feature implementations, because it is part of the composition roots, and no module may
import it. Example: `OpenSkyPreview` prints records with the whole-game condition registry, and
both the Preview panel and `openskycli record` use it.

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
OpenSkyGameData           virtual file system, load order, record stores, actor stats from records,
                          item index, equip slots, barter prices, projectile profiles
  ^
OpenSkyBehavior           Havok behavior graph evaluation, skeleton pose math
  ^
OpenSkyPhysics            static and trigger collision, dynamic bodies, ragdolls, melee hit sweeps
OpenSkyDiagnostics        memory footprint, debug overlays; needs only OpenSkyShaderTypes
  ^
OpenSkyRendering          Metal renderer, scenes, cameras, terrain meshes, weather values
OpenSkyAudio              audio graph, decoders, sound and music record stores
OpenSkyWorldState         runtime state store, open component set, game clock, globals
  ^
OpenSkyConditions         condition evaluator, function registry, core functions
  ^
OpenSkyWorldInterface     interaction events and rays, placed interactions, reference source,
                          movement limits, dialogue camera pose
OpenSkyInventoryInterface inventory state, holders, vendors, baselines, InventoryAccess,
                          EquipmentAccess
  ^
OpenSkyActorsInterface    actor state components, ActorValueAccess, actor conditions
OpenSkyMagicInterface     active effects, spell hits, enchantments, SpellCasting, SpellHitApplying
OpenSkyCombatInterface    combat settings, intents, script hits, CombatControlling, DeathReporting
OpenSkyQuestsInterface    quest and alias state, quest conditions, QuestAccess
OpenSkyDialogueInterface  dialogue state and selection, dialogue conditions, DialogueAccess
OpenSkyScriptingInterface Papyrus values, script world state, update timers, alias inspection
OpenSkyCrimeInterface     crime events, ledger, arrest state, ownership values, CrimeReporting
OpenSkyFactionsInterface  membership and relationship state, hostility values, seams
OpenSkyPerceptionInterface  detection values, settings, condition functions, seams
OpenSkyProgressionInterface perk and progress state, skill use events, PerkAccess
  ^
OpenSkyActors             actor value runtime
OpenSkyMagic              active effect, caster, spellbook, and enchantment runtimes
OpenSkyCombat             melee, archery, projectile, combat loop, and ragdoll runtimes
OpenSkyQuests             quest runtime, alias filler
OpenSkyDialogue           dialogue runtime, voice file lookup
OpenSkyScripting          Papyrus interpreter, script world runtime, native functions
OpenSkyWorld              cells, streaming, terrain, navigation, packages, player, weather,
                          the whole-game condition registry
OpenSkySave               OpenSky save files: encoder, decoders, store
OpenSkyMenus              menu models, movie bridges, panel seams that name several features
OpenSkyCrime              crime runtime, witnesses, ownership, guards, arrest, reporter
OpenSkyInventory          inventory, equipment, container, barter, and world item runtimes
OpenSkyFactions           faction and relationship runtimes, hostility derivation
OpenSkyPerception         perception runtime, detection formula, sight, overlay
OpenSkyProgression        perk, skill, and level runtimes, perk entry-point evaluator
  ^
OpenSkyPreview            asset catalog, record text dumps, reference inspector (composition)
  ^
OpenSky app, OpenSkyCLI   composition roots
```

The format families depend only on `OpenSkyFormatsCore`, never on each other. A parser change
rebuilds its family and the modules that import it, not every format.

Two more targets wrap C headers. `OpenSkyShaderTypes` holds the structs shared with Metal
([build system](/tools/build-system.md)). `CFFmpeg` is the clang module over the vendored ffmpeg
([ffmpeg](/decisions/ffmpeg-audio.md)).

`Sources/Shaders/Shaders.metal` is not in the package. The app and the CLI each compile it into
the `default.metallib` of their own bundle, and `Renderer` loads it with
`device.makeDefaultLibrary()` unless the caller passes a `shaderLibrary`. A package test has no
such bundle. `make shader-library` compiles the same file with `xcrun metal`
(`tools/shader-library.sh`), and `ShaderLibraryFixture` in `Tests/RenderingTesting/` loads it from
the path in `OPENSKY_SHADER_LIBRARY`. `make` sets that variable for `swift test`, and the
`UnitTests` plan sets it for xcodebuild. A test that runs without it fails; it does not skip.

SwiftPM can compile a `.metal` resource, but it ignores header search paths and the Metal settings
in `Config/Build/`, such as warnings as errors. So the shaders stay outside the package.

## Keeping the lines clean

A lower module never imports a higher one. These patterns keep it that way:

- A value type both sides need moves down, for example `CellCoordinate`, `ModelBounds`, and
  `ActorValueIdentity` in `OpenSkyFormatsCore` and `OpenSkyFormatsESM`.
- Behavior that needs a higher layer stays up there as an extension of the lower type, in a file
  named `Type+Feature.swift`. Examples: `Package+Schedule.swift` in `OpenSkyWorld` over a
  `OpenSkyFormatsESM` record, and `ItemDefinitionStore+MagicItemUse.swift` in `OpenSkyMagic` over an
  `OpenSkyGameData` store.
- A lower module that must call up defines a protocol, and the higher module conforms to it.
  Example: `Renderer` draws, and it calls a `RenderFrameDriver` at fixed points of each frame
  to move the camera and run the world. `GameSession` in `OpenSkyWorld` is that driver.
- Logic that only reads plugin records, with no runtime state, is not a feature. It moves down
  into `OpenSkyGameData`. Examples: actor templates, derived actor values, resistances,
  faction relations, the leveling and skill formulas, the item index, and barter prices.
- A feature that another module calls into offers a protocol in its interface. Examples:
  - Crime asks `DetectionObserving` which observers saw an act.
  - Magic and progression change actor values through `ActorValueAccess`.
  - Scripts change faction ranks through `FactionAccess`, cast through `SpellCasting`, and
    start and stop fights through `CombatControlling`.
  - Items report theft through `CrimeReporting`, and an arrest takes gold through
    `InventoryAccess`.
  - The spellbook readies a spell in a hand through `EquipmentAccess`.
  - Scripts and the journal menu set quest stages through `QuestAccess`, and the dialogue
    menu lists topics through `DialogueAccess`.

  The implementation conforms, and the app hands it over as that protocol.

  The app is the composition root, so it may downcast to the implementation it built, for
  example `questRuntime as? QuestRuntime` for the journal panel.
- A lower module never names a registry or default that a higher module owns. Example:
  `PerkRuntime`, `ActiveEffectRuntime`, and `DialogueRuntime` take their
  `ConditionFunctionRegistry` as a parameter, and the caller passes `.standard`, which lives
  in `OpenSkyWorld`, above every feature interface. A package test target builds its own
  registry from the install functions it can reach, for example `.magicTests` in
  `OpenSkyMagicTests`.
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

Shared test fixtures live in a testing library, `Tests/<Name>Testing/`. For a foundation
module the name is the one the module declares, for example `BehaviorTesting`. For a feature it
is the feature name plus `Testing`, for example `OpenSkyPerceptionTesting`. Its declarations are
`public`, and it may `@testable import` the module it builds fixtures for.

A testing library may depend on feature implementations, its own and others', because only
tests link it. The `testing` helper allows that, and it is the only helper that does. A module
that ships in the app can never depend on a testing library. The library is declared after
every implementation it uses. Example: `OpenSkyWorldTesting` comes after `OpenSkyWorld`, because
`CellSceneBuilderFixture` builds real cell scenes.

A testing library changes how Xcode builds the module it uses. The app and the test bundles
then share that module, so Xcode builds it as a dynamic framework. A framework cannot use a
system-library target, so `CFFmpeg` is a C target that carries its own link flags
([ffmpeg audio](/decisions/ffmpeg-audio.md)).

The package test targets run in the `UnitTests` and `Sanitizers` plans next to `OpenSkyTests`. A
test plan names a package test target with `"containerPath" : "container:."`, the package at the
repository root. Only a workspace shows a scheme the test targets of a local package. Through
`-project OpenSky.xcodeproj`, xcodebuild reports that the target "isn't a member of the specified
test plan or scheme".

`make test-fast T='<Target>Tests/...'` runs one package test target through `swift test`
(`tools/test-package.sh`). It builds only the package, into `.build/`, and needs no app host.

A suite goes in the test target of the highest module it imports, in `Package.swift` order. A
suite that builds a `Renderer` passes `ShaderLibraryFixture.library(device:)` as its
`shaderLibrary`. A suite that needs the app or an acceptance chain stays in `Tests/OpenSkyTests/`.
