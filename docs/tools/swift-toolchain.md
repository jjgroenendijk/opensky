---
type: Tool
title: Swift toolchain and language mode
description: The Apple Swift 6.3.3 baseline, Swift 6 language mode across every target, the gate that enforces both, and the isolation patterns the migration settled on.
tags: [tool, build, concurrency, swift]
timestamp: 2026-08-03T00:00:00Z
---

# Swift toolchain and language mode

OpenSky builds with Apple Swift 6.3.3 (Xcode 26.6) and every Xcode build configuration
is in Swift 6 language mode. Both facts are checked by `tools/lint/swift-baseline.sh`,
reachable as `make swift-baseline`, so neither can regress silently.

## Contents

* [What is enforced](#what-is-enforced)
* [Where the gate runs](#where-the-gate-runs)
* [Default actor isolation](#default-actor-isolation)
* [Isolation patterns this codebase uses](#isolation-patterns-this-codebase-uses)
* [Raising the baseline](#raising-the-baseline)

## What is enforced

`tools/lint/swift-baseline.sh` fails, naming what it found, when either half slips:

* The compiler reported by `swiftc --version` is older than Apple Swift 6.3.3. The
  comparison is on the three version integers, so 6.3.2 and 6.2.0 both fail while 6.4.0
  passes. A missing or non-Apple `swiftc` fails the same way.
* Any `SWIFT_VERSION` build setting reads something other than `6.0`. Both places a
  setting can be declared are scanned: `Config/*.xcconfig`, where the one declaration
  covering every target lives today, and `opensky.xcodeproj/project.pbxproj`, where a
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
| Pre-commit hook | `.githooks/pre-commit/05-swift-baseline.sh` |
| CI | "Swift baseline" step in the `build-test` job |

The CI step sits behind the same `Xcode >= 26` guard as the build and test steps. A
hosted runner that lags the toolchain skips the whole job with a warning rather than
failing on a compiler it was never going to build with; the local hook covers that case
unconditionally, and it is the gate that actually runs today (see
[Local environment and external state](/tools/environment.md) for the CI suspension).

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

The Swift 6 migration (issues #310 through #314) settled on a small set of moves. In
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
   reason, which is what lets `PapyrusWorldAccess` hold one across its hops.
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

## Raising the baseline

The required version lives in one place: the `required_major`/`required_minor`/
`required_patch` variables at the top of `tools/lint/swift-baseline.sh`. Raising the
baseline is that edit plus a note in [the change log](/log.md); the language mode is a
separate constant in the same script and changes only when a new Swift language version
ships and every configuration moves to it together.
