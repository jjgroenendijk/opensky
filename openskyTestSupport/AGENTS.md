# AGENTS.md — openskyTestSupport

Test support compiled into **both** unit-test bundles: `openskyTests` and
`openskyRealDataTests`. The folder exists because the two targets are separate modules with
no way to import each other, while a fixture like `ESMFixture` or `FakeWorldProviders` is
needed by both (issue #418). Membership follows the folder, exactly as `opensky/Engine/`
builds into the app and `openskycli`.

## What belongs here

Fixtures, fakes, and harnesses — anything with no `@Test` of its own — that at least one
suite in each bundle uses. Support only the synthetic suites use stays in `openskyTests/`;
support only the real-data suites use stays in `openskyRealDataTests/`. Keeping the split
tight matters: a file here is compiled twice, once per bundle.

Fixtures are synthetic and built in code, never an extracted game file (root `AGENTS.md`,
Legal & IP boundary). `BSAFixture`, `ESMFixture`, `NIFFixture` and `PexFixture` are the
established builders.

## No tests here

A `@Test` in this folder would run in both bundles, so the same unit test would also execute
under `make realtest-all`. Nothing enforces that, so it is a review point.

That is why three types are split across the two folders: the fixture half of
`CellSceneBuilderTests`, `CellStreamerTests` and `PapyrusWorldActivationTests` is declared
here, and the suite's `@Test` methods live in extensions of the same type under
`openskyTests/`. The type name is deliberately unchanged, so no call site moved and no test
identifier changed. When splitting another one, keep the declaration and the reusable members
here, take the tests to `openskyTests/`, and widen any `private` member the tests still
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
