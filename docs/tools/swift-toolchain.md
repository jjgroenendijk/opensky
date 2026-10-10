---
type: Tool
title: Swift toolchain and language mode
description: The one Apple Swift version shared by local builds and CI, Swift 6 language mode across every target, the gate that enforces both, and the isolation patterns the migration settled on.
tags: [tool, build, concurrency, swift]
---

# Swift toolchain and language mode

OpenSky builds with Apple Swift 6.4 (Xcode 27.0), locally and in CI, and every Xcode build
configuration is in Swift 6 language mode. Both facts are checked by `tools/lint/swift-baseline.sh`,
reachable as `make swift-baseline`, so neither can regress silently.

## What is enforced

`tools/lint/swift-baseline.sh` fails, naming what it found, when either half slips:

* The compiler reported by `swiftc --version` is not Apple Swift 6.4. Each Swift release
  accepts code that another one rejects. So a newer local compiler passes code that fails in
  CI, and an older one fails code that passes there. The check wants the same version, not a
  minimum, so 6.3.3 and 6.4.1 both fail. A version without a patch number matches the same
  version with `.0`. A missing or non-Apple `swiftc` fails the same way.
* Any `SWIFT_VERSION` build setting reads something other than `6.0`. Both places a
  setting can be declared are scanned: `config/Build/*.xcconfig`, where the one declaration
  covering every target lives today, and `OpenSky.xcodeproj/project.pbxproj`, where a
  reintroduced per-target setting would override it. A project with no `SWIFT_VERSION` at
  all is treated as a failure rather than a pass. See
  [Build system and xcodebuild invocation](/tools/build-system.md).

The language-mode half matters more than it looks: one configuration falling back to
`SWIFT_VERSION = 5.0` turns off strict concurrency checking for a whole target without
failing the build, the linter, or the tests.

## Where the gate runs

| Gate | How it runs |
| --- | --- |
| Local one-shot | `make check` (first step) or `make swift-baseline` |
| CI | "Swift baseline" step in the `build-test` job |

Both run the same script. The CI job runs it before the build, so a runner with another
Xcode fails at once with the version it found, not later with compile errors.

## Default actor isolation

The app and CLI targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: a declaration
with no isolation annotation is main-actor isolated. That fits an AppKit program whose
renderer, streamer and world state all live on the main thread, and it means the
annotation burden falls on the code that is genuinely concurrent — format parsers,
math, and the off-main cell build — rather than on the UI.

Two consequences are easy to trip over and both are checked by the compiler now that
the module is in Swift 6 mode:

* A separately declared extension does not inherit the isolation of the type it
  extends. An extension of a `nonisolated` type must itself say `nonisolated extension`.
* Isolation is per declaration, not per file. A `nonisolated struct` at the top of a
  file says nothing about the `private struct` helper below it, which is main-actor
  isolated unless it says otherwise — even when the only thing that uses it is the
  nonisolated type above.

The test targets deliberately do **not** set the default. Test fixtures are pure byte
builders and belong off the main actor; a suite that exercises main-actor production
code declares `@MainActor` on itself instead.

## Isolation patterns this codebase uses

The Swift 6 migration settled on a small set of moves. In
preference order:

1. **State the truth about a type.** A pure parser, geometry routine, or value type is
   `nonisolated`. Most of the migration was this: helper types beside a nonisolated
   parser that had silently picked up main-actor isolation from the target default.
2. **State the truth about one member.** Where a main-actor type carries a pure
   constant or allocator — `Renderer.nearPlane`, `Renderer.makeUniformBuffer` — the
   member is marked `nonisolated` rather than the whole type being reclassified.
3. **Resolve before the hop.** A non-`Sendable` value must not cross into
   `MainActor.assumeIsolated`. Decode it on the calling side and send the result: the
   SWF menu bridges turn an `AS2` call into a menu action first, then hop with the
   action alone.
4. **Say `Sendable` where it is already true.** A `@MainActor` class is implicitly
   `Sendable`, but an existential over a `@MainActor` protocol is not unless the
   protocol says so. `PapyrusWorldQuestBridge` declares `Sendable` for exactly that
   reason. A conformance that brings `Sendable` in, directly or through a refined
   protocol, must sit in the same file as the class declaration. Apple Swift 6.4 rejects it in a
   satellite extension file, so `PapyrusWorldStateBridge` picks up
   `PapyrusWorldQuestBridge` through `PapyrusWorldBridge` on its primary declaration, and
   `PapyrusWorldStateBridgeQuests.swift` only adds members.
5. **Wrap what the compiler cannot prove, once, with the reason written down.**
   `WritableKeyPath` is not `Sendable`, so a `static let` table of key paths reads as
   shared mutable state. `QuestAliasDecoder`'s `AliasSlotTable` is a single
   `@unchecked Sendable` wrapper around those tables — key paths are immutable
   descriptors and the mutation happens on the caller's own root — instead of four
   suppressions or four dictionaries rebuilt per subrecord.

What the migration did **not** do is mark a subsystem `@MainActor` to silence an error
when it is semantically nonisolated. `SystemMenuSection.readout(for:)` and its
siblings are documented as pure so they can be tested without AppKit; under Swift 6 a
nonisolated test calling them trapped at runtime on an inserted isolation check, and
the fix was to make the pure helpers `nonisolated`, not to move the tests onto the
main actor.

The reverse also holds. The Papyrus VM is main-actor isolated, because its natives read
and write main-actor world state and the VM runs only from the main-actor tick. A
nonisolated VM would need a `MainActor.assumeIsolated` hop in every world call.

## Moving to a new Xcode

The version lives in two places that change in one commit: `required` at the top of
`tools/lint/swift-baseline.sh`, and `DEVELOPER_DIR` in `.github/workflows/ci.yml`, which
names the Xcode the runner uses ([CI](/tools/ci.md)). Install the new Xcode locally, then
change both; the language mode is a
separate constant in the same script and changes only when a new Swift language version
ships and every configuration moves to it together.
