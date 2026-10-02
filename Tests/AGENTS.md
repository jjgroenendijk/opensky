# AGENTS.md — Tests

Each folder here builds one target, named like the folder. `docs/tools/modules.md` lists
them and the rules `Package.swift` enforces.

## Testing libraries

A folder named `<Name>Testing/` is a library of shared fixtures, not a test target. Every
unit test target that needs the fixtures links it: package test targets, `OpenSkyTests`,
and `OpenSkyRealDataTests`.

- Declarations that tests use are `public`. A struct a test builds has an explicit
  `public init(...)`.
- A library may `@testable import` the module it builds fixtures for, and import the
  modules and testing libraries below it. It never imports a feature implementation, so a
  test that links it builds no other feature. `make module-graph` fails on such an import.
- A fixture that needs its feature's implementation, such as a fake of a seam the
  implementation declares, goes in that feature's `<Name>Fixtures/` library. Only
  `<Name>Tests` and the Xcode bundles may link it. Example: `FakeCombatWorld` in
  `OpenSkyCombatFixtures`. One used only by `<Name>Tests` stays in that target.
- A fixture that needs two implementations goes in `Tests/TestSupport/` when both Xcode
  bundles use it, else in `Tests/OpenSkyTests/Support/`.
- A fixture that a package test target and `OpenSkyTests` or `OpenSkyRealDataTests` both
  need goes in a library, never in two copies.
- A byte builder goes in the lowest library that can build it. A helper that wraps the bytes
  in a higher store is an extension in a higher library, for example
  `DialogueFixture+Store.swift` in `GameDataTesting` over `DialogueFixture` in
  `FormatsESMTesting`.
- A library holds no `@Test`. Put tests in the test target of the module they test.
- Fixtures are synthetic and built in code, never an extracted game file (root
  `AGENTS.md`, Legal & IP boundary).

## Where a suite goes

A suite goes in the package test target of the highest module it imports, in the order
`Package.swift` declares them. Example: a record test that imports `OpenSkyFormatsESM` and
`OpenSkyGameData` goes in `OpenSkyGameDataTests`.

A suite stays in `OpenSkyTests` when it needs something a package test target cannot
have:

- the app module (`@testable import OpenSky`),
- an acceptance chain in `Tests/OpenSkyTests/Acceptance/`,
- two feature implementations, for example a Magic suite that spends real actor values.
  It goes in `Tests/OpenSkyTests/<Feature>/`, named for the feature it tests, because a
  feature's tests may build no implementation but their own (`make module-graph`, rule 5).

Inside a target, test folders use the subfolder names of the source they test: tests for
`Sources/OpenSkyWorld/Terrain/DistantLOD.swift` live in `Tests/OpenSkyWorldTests/Terrain/`,
and tests for app code live under `Tests/OpenSkyTests/App/`. Only cross-cutting folders are
test-only: `Acceptance/` (end-to-end gates), `Fakes/`, and `Support/`. An acceptance suite
is named for the behavior it checks, such as `CombatAcceptanceTests`, never for a milestone
number.

A suite that builds a `Renderer` goes in a package test target too. It passes
`shaderLibrary: ShaderLibraryFixture.library(device: device)` from `RenderingTesting`, because a
package test has no app bundle to load `default.metallib` from. `make test-unit` compiles the
shaders first (`make shader-library`).

## Test plans

`Config/TestPlans/` holds the checked-in plans, so which bundles a run touches is
reviewable configuration, not a flag. `UnitTests` lists `OpenSkyTests` and the package test
targets, `UITests` lists `OpenSkyUITests` alone, and `RealData` lists `OpenSkyRealDataTests`
alone and carries the data root into the test host.

Never list the UI bundle in a plan beside an app-hosted unit bundle: the app blocks as a
test host while the UI runner waits for it, and the run deadlocks
(`docs/tools/test-runs.md`). An env-gated suite outside `Tests/OpenSkyRealDataTests/` fails
`make lint`, because no plan would ever run it.

## Tags

`Tests/TagsTesting/Tags.swift` holds the shared Swift Testing tags, and every test target
links it. Put a tag on the suite, `@Suite(.tags(.gpu))`, or on one test when only that
test needs it.

| Tag | Put it on |
| --- | --- |
| `.acceptance` | A suite under an `Acceptance/` folder |
| `.gpu` | A suite that reaches a Metal device |
| `.parser` | A suite in an `OpenSkyFormats*Tests` target |
| `.slow` | A test that takes seconds on a warm build |
| `.perf` | A timing gate. The Perf plan runs it, built optimized (`make test-perf`) |

`make lint-test-tags` fails a suite that misses `.acceptance`, `.gpu`, or `.parser`, and
`make lint-test-tags FIX=1` adds them. A tag selects a run (`make test-parser`) but
never a real-data test into a unit run: a plan picks bundles, a tag picks tests inside them.

## Flaky tests

A flaky test fails sometimes and passes sometimes on the same code. When you find one:

1. Disable it with the issue that tracks it: `@Test(.disabled("flaky: #NNN"))`.
2. Open a `bug` issue with the run directory of the failing run.
3. Never add a retry. A retry hides the failure, and the bug stays.

`make test-unit T='Suite/test()' N=100` reruns a test until it fails, to show it is flaky.
`make lint-test-tags` fails a `.disabled` trait that names no issue.
