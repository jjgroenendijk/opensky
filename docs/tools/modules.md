---
type: Tool
title: Swift modules
description: Why the format parsers are their own Swift module, which way the modules depend on
  each other, the access and import rules that follow, and how to measure what one edit rebuilds.
tags: [tool, build, swift, modules]
---

# Swift modules

The format parsers build as their own Swift module, `OpenSkyFormats`. The rest of the engine,
under `Sources/OpenSkyEngine/`, still compiles into the app and into `OpenSkyCLI`. This page
explains why, and the rules that follow.

## Why a module boundary

Swift recompiles a file when a declaration it uses changes. Inside one module, "uses" is wide.
A test file that imports the whole engine depends on most of it. So adding one method to a
runtime type recompiled every file in the unit-test bundle, parser tests included.

A module boundary stops that. A file in another module sees only the module's interface. The
compiler recompiles it when that interface changes, and a change to engine code never changes
the interface of `OpenSkyFormats`. So the parser tests do not rebuild when engine code changes.

The boundary has a cost in the other direction. A change to the module's interface, for example
a new method on `BinaryReader`, recompiles every file that imports `OpenSkyFormats`. A change
inside a function body does not change the interface, so it stays cheap. Parser interfaces change
less often than runtime types, so the trade is worth it.

The split goes bottom-up. The parsers came first, because they depend on nothing else in the
engine.

## Dependency direction

```text
OpenSkyFormats            parsers, binary readers, compression, geometry values
  ^            ^
  |            |
OpenSky app    OpenSkyCLI  both also compile Sources/OpenSkyEngine/
```

`OpenSkyFormats` never imports engine code. A parser that needs a runtime type is in the wrong
module. Three patterns keep the line clean:

- A value type both sides need moves down into `OpenSkyFormats`, for example `CellCoordinate`,
  `ModelBounds`, and `ActorValueIdentity`.
- Behavior over runtime state stays in the engine as an extension of the record type, in a file
  named `Type+Feature.swift`. Examples: `Package+Schedule.swift`, `KeywordList+Store.swift`,
  `ActorValueIdentity+Kind.swift`, `PlacedReference+Spawn.swift`.
- A loader that reads through the virtual file system stays in `Sources/OpenSkyEngine/GameData/`,
  for example `PexScriptLoader` and `SWFMovieLoader`.

The OpenSky save format encodes runtime state, so it lives in `Sources/OpenSkyEngine/Save/`, not
in the parser module.

## Access and imports

The project sets `SWIFT_PACKAGE_NAME = OpenSky` in `Config/Build/Base.xcconfig`. Every target is
then in one package, and `package` access works across all of them. It is the level to use for a
parser declaration that engine code or a test calls. `public` is not needed, because no code
outside this project links the framework.

Three rules come from this:

- A struct's implicit memberwise initializer is `internal`, even when the struct is `package`. A
  type the engine builds needs an explicit `package init(...)`. An `OptionSet` needs an explicit
  `package init(rawValue:)`.
- `MemberImportVisibility` is on, so every file that uses a member from the module writes
  `import OpenSkyFormats`. Importing it in another file of the same target is not enough. A
  missing import sometimes shows as a pattern error, for example "pattern variable binding cannot
  appear in an expression", not as an import error.
- Tests write `@testable import OpenSkyFormats` to reach `internal` members.

## Targets and files

| Folder | Target | Built into |
| --- | --- | --- |
| `Sources/OpenSkyFormats/` | `OpenSkyFormats`, a dynamic framework | used by the app, the CLI, and every unit bundle |
| `Tests/OpenSkyFormatsTests/` | `OpenSkyFormatsTests` | the `UnitTests` and `Sanitizers` plans |
| `Tests/FormatsTestSupport/` | none | compiled into all three unit bundles |

Build settings are in `Config/Build/Formats.xcconfig` and `Config/Build/FormatsTests.xcconfig`.
The app embeds the framework in `Contents/Frameworks/`. The CLI finds it next to its own binary
through the run path `@executable_path` in `Config/Build/CLI.xcconfig`.

A parser test that only needs the parser goes in `Tests/OpenSkyFormatsTests/`. A parser test that
also builds engine state stays in `Tests/OpenSkyTests/Formats/`. A fixture that only builds bytes
goes in `Tests/FormatsTestSupport/`, so all three bundles can use it.

## Why the parser tests are app-hosted

`OpenSkyFormatsTests` does not need the app. It still runs inside `OpenSky.app` as a test host,
with `TEST_HOST` set and no `BUNDLE_LOADER`. Without a host, xcodebuild starts the plain `xctest`
runner. That runner loads the bundle from the external volume, and macOS then asks for permission
to read a removable volume. The run waits on that dialog and times out. The app already has the
grant, so the hosted bundle runs without a prompt ([environment](/tools/environment.md)).
