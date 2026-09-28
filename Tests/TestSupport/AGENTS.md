# AGENTS.md — openskyTestSupport

Test support compiled into two unit-test bundles: `OpenSkyTests` and
`OpenSkyRealDataTests`. The folder exists because the two targets are separate modules with
no way to import each other, while a fixture like `FakeWorldProviders` is needed by both
(issue #418). A fixture that only builds bytes and needs no engine code goes in
`Tests/FormatsTestSupport/` instead, so the parser bundle can use it too. Membership follows
the folder, exactly as `Sources/OpenSkyEngine/` builds into the app and `OpenSkyCLI`.

## What belongs here

Fixtures, fakes, and harnesses — anything with no `@Test` of its own — that at least one
suite in each bundle uses. Support only the synthetic suites use stays in `Tests/OpenSkyTests/`;
support only the real-data suites use stays in `Tests/OpenSkyRealDataTests/`. Keeping the split
tight matters: a file here is compiled twice, once per bundle.

Fixtures are synthetic and built in code, never an extracted game file (root `AGENTS.md`,
Legal & IP boundary). The established byte builders, `BSAFixture`, `ESMFixture`, `NIFFixture`
and `PexFixture`, live in `Tests/FormatsTestSupport/`.

## No tests here

A `@Test` in this folder would run in both bundles, so the same unit test would also execute
under `make realtest-all`. Nothing enforces that, so it is a review point.

That is why three types are split across the two folders: the fixture half of
`CellSceneBuilderTests`, `CellStreamerTests` and `PapyrusWorldActivationTests` is declared
here, and the suite's `@Test` methods live in extensions of the same type under
`Tests/OpenSkyTests/`. The type name is deliberately unchanged, so no call site moved and no test
identifier changed. When splitting another one, keep the declaration and the reusable members
here, take the tests to `Tests/OpenSkyTests/`, and widen any `private` member the tests still
reach — the two halves are no longer one file, so file-private no longer spans them.

A type whose shared part is only constants does not need that treatment: give the constants
their own namespace, as `M10AcceptanceClock` does, and leave the suite alone. Note that a
`struct` holding nothing but static members is rewritten to an `enum` by `make fix`
(SwiftFormat's `enumNamespaces`), which a Swift Testing suite type cannot be — the tests
would have nothing to instantiate.

## Isolation

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies here like everywhere else: a fake
touching AppKit is `@MainActor`, and an extension of a `nonisolated` type must say
`nonisolated extension` itself (root `AGENTS.md`, Conventions).
