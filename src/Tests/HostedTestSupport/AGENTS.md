# AGENTS.md — HostedTestSupport

Test support compiled into two bundles, `OpenSkyTests` and `OpenSkyRealDataTests`, which
cannot import each other. Membership follows the folder.

## What belongs here

A fixture, fake, or harness with no `@Test` of its own, that needs the app or two feature
implementations, and that a suite in each bundle uses: the fake world providers, the
acceptance harnesses, and chains such as `CombatCastingChain`. A file here compiles twice, so
keep the set small:

- needs neither the app nor two implementations: a testing or fixture library
  (`src/Tests/AGENTS.md`);
- used by one bundle only: that bundle's own `Support/` folder.

## No tests here

A `@Test` here would run in both bundles, so it would also run under the `RealData` plan.
Nothing checks this; it is a review point. A suite that shares a fixture keeps its tests in
its own type and the fixture in another, as `CellStreamerTests` and `CellStreamerFixture` do.

A type that only shares constants gets its own namespace, as `WorldTimeAcceptanceClock` does.
`make fix` rewrites a static-only `struct` to an `enum`, which a Swift Testing suite cannot be.

## Isolation

The default actor isolation is the main actor here too: a fake that touches AppKit is
`@MainActor`, and an extension of a `nonisolated` type says `nonisolated extension`.
