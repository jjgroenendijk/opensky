# AGENTS.md — HostedTestSupport

Test support compiled into two unit-test bundles: `OpenSkyTests` and
`OpenSkyRealDataTests`. The folder exists because the two targets are separate modules with
no way to import each other, while a fixture like `FakeWorldProviders` is needed by both.
Membership follows the folder, exactly as `Sources/OpenSky/` builds into the app alone.

Only fixtures that need the app or two feature implementations belong here: the fake world
providers, the panel fakes, the acceptance harnesses, and chains such as
`CombatCastingChain`. A fixture that needs neither goes in a `Tests/OpenSky<Layer>Testing/` or
`Tests/<Name>Fixtures/` library, so the package test targets can use it too
(`Tests/AGENTS.md`).

## What belongs here

Fixtures, fakes, and harnesses — anything with no `@Test` of its own — that at least one
suite in each bundle uses. Support only the synthetic suites use stays in `Tests/OpenSkyTests/`;
support only the real-data suites use stays in `Tests/OpenSkyRealDataTests/`. Keeping the split
tight matters: a file here is compiled twice, once per bundle.

Fixtures are synthetic and built in code, never an extracted game file (root `AGENTS.md`,
Legal & IP boundary). The established byte builders, `BSAFixture`, `ESMFixture`, `NIFFixture`
and `PexFixture`, live in the `Tests/OpenSkyFormatsTesting/` library.

## No tests here

A `@Test` in this folder would run in both bundles, so the same unit test would also execute
under `make test-real`. Nothing enforces that, so it is a review point.

A suite that shares a fixture with other suites keeps its `@Test` methods in its own type,
and the fixture is a separate type. Example: `CellStreamerTests` in `OpenSkyWorldTests`
calls `CellStreamerFixture` in `OpenSkyWorldFixtures`, and the acceptance chains call the
same fixture.

A type whose shared part is only constants does not need that treatment: give the constants
their own namespace, as `WorldTimeAcceptanceClock` does, and leave the suite alone. Note that a
`struct` holding nothing but static members is rewritten to an `enum` by `make fix`
(SwiftFormat's `enumNamespaces`), which a Swift Testing suite type cannot be — the tests
would have nothing to instantiate.

## Isolation

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies here like everywhere else: a fake
touching AppKit is `@MainActor`, and an extension of a `nonisolated` type must say
`nonisolated extension` itself (root `AGENTS.md`, Conventions).
