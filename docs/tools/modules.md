---
type: Tool
title: Swift modules
description: How the engine splits into Swift modules through the root Swift package, which way the
  modules depend on each other, and the access and import rules that follow.
tags: [tool, build, swift, modules, swiftpm]
---

# Swift modules

The lower layers of the engine are library modules in a Swift package. `Package.swift` at the
repository root declares them. The app and `OpenSkyCLI` link the package products through
`OpenSky.xcodeproj`. `OpenSky.xcworkspace` holds the project and the package side by side, and
`make` builds through it. The rest of the engine, under `Sources/OpenSkyEngine/`, still compiles into
the app and into `OpenSkyCLI`. The split goes bottom-up, one layer at a time.

## Why a module boundary

Swift recompiles a file when a declaration it uses changes. Inside one module, "uses" is wide. A
test file that imports the whole engine depends on most of it. So adding one method to a runtime
type recompiled every file in the unit-test bundle, parser tests included.

A module boundary stops that. A file in another module sees only the module's public interface.
A change to engine code never changes the interface of `OpenSkyFormats`, so the parser tests do
not rebuild when engine code changes.

The boundary costs something in the other direction. A change to a module's interface, for
example a new public method on `BinaryReader`, recompiles every file that imports the module. A
change inside a function body does not change the interface, so it stays cheap. Lower layers
change less often than runtime types, so the trade is worth it.

## Why a Swift package

A Swift package is the standard way to split Swift code into modules:

- `Package.swift` lists what each module depends on. The compiler rejects an import that is not
  listed, so an upward dependency fails the build instead of slipping in.
- A new module is a few lines in `Package.swift`. It needs no project-file edit, no xcconfig, and
  no framework embedding.
- The layout is the SwiftPM default: `Sources/<Module>/` and `Tests/<Module>Tests/`.
- `swift build --build-tests` builds the modules and their tests without Xcode.

Package products link statically into the app and the CLI. There is no framework to embed and no
run path to set.

## Modules

```text
OpenSkyFormats            parsers, binary readers, compression, geometry values
  ^
OpenSkyGameData           virtual file system, load order, record index, record stores
  ^
OpenSky app, OpenSkyCLI   also compile Sources/OpenSkyEngine/
```

| Target | Folder | Depends on |
| --- | --- | --- |
| `OpenSkyFormats` | `Sources/OpenSkyFormats/` | nothing |
| `OpenSkyGameData` | `Sources/OpenSkyGameData/` | `OpenSkyFormats` |
| `FormatsTestSupport` | `Tests/FormatsTestSupport/` | `OpenSkyFormats` |
| `OpenSkyFormatsTests` | `Tests/OpenSkyFormatsTests/` | `OpenSkyFormats`, `FormatsTestSupport` |
| `OpenSkyGameDataTests` | `Tests/OpenSkyGameDataTests/` | `OpenSkyGameData`, `FormatsTestSupport` |

The Metal shared structs in `Sources/ShaderTypes/` stay with the engine. A parser returns plain
values, and the engine packs them into GPU layouts.

`FormatsTestSupport` holds fixtures that build format bytes in code. It is a library, so the
package test targets and the Xcode test bundles share one copy.

## Keeping the lines clean

A lower module never imports a higher one. Three patterns keep it that way:

- A value type both sides need moves down, for example `CellCoordinate`, `ModelBounds`, and
  `ActorValueIdentity` in `OpenSkyFormats`.
- Behavior that needs a higher layer stays up there as an extension of the lower type, in a file
  named `Type+Feature.swift`. Examples: `Package+Schedule.swift` in the engine over a
  `OpenSkyFormats` record, and `EquipSlotStore+Hands.swift` and `FactionStore+Templates.swift` in
  the engine over `OpenSkyGameData` stores.
- A test that checks engine behavior over a lower type stays in `OpenSkyTests`. The record-dump
  tests are an example: they live in `Tests/OpenSkyTests/Preview/`, not with the store tests.

## Access and imports

A declaration another module uses is `public`. The rules that follow are the standard library
rules:

- A struct's implicit memberwise initializer is `internal`. A struct another module builds needs
  an explicit `public init(...)`. An `OptionSet` needs `public init(rawValue:)`.
- Swift does not infer `Sendable` for a public type. A public value type that crosses isolation
  states `Sendable` in its declaration. A type that holds a class reference or a closure, such as
  the AS2 interpreter values, does not. A generic type conforms conditionally, for example
  `extension RecordIndexDecodeResult: Sendable where Value: Sendable {}`.
- `MemberImportVisibility` is on. Every file that uses a module writes its own `import`. A
  missing import sometimes shows as a pattern error, for example "pattern variable binding cannot
  appear in an expression".
- Tests write `@testable import` to reach `internal` members.

The package sets the same language settings as the Xcode targets: Swift 6 mode, `MainActor`
default isolation, `MemberImportVisibility`, approachable concurrency, and warnings as errors.
Change both places together.

## Tests

The package test targets run in the `UnitTests` and `Sanitizers` plans next to `OpenSkyTests`. A
test plan names a package test target with `"containerPath" : "container:."`, the package at the
repository root. Only a workspace shows a scheme the test targets of a local package. Through
`-project OpenSky.xcodeproj`, xcodebuild reports that the target "isn't a member of the specified
test plan or scheme". `swift test` runs them without Xcode.

A test that needs only one module goes in that module's test target. A test that also builds
engine state stays in `Tests/OpenSkyTests/`.
