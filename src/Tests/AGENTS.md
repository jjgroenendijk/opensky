# AGENTS.md — Tests

Each folder here builds one target, named like the folder, except `HostedTestSupport/`: a
source folder that `OpenSkyTests` and `OpenSkyRealDataTests` both compile. `docs/tools/modules.md` lists
them and the rules `src/Package.swift` enforces.

## Testing libraries

A folder named `OpenSky<Layer>Testing/` is a library of shared fixtures, not a test target. There
is one per layer: `OpenSkyFormatsTesting` (byte builders, one subfolder per format family),
`OpenSkyEngineTesting` (game data, behavior, physics, rendering, world state),
`OpenSkyFeaturesTesting` (fakes of the feature interfaces), and `OpenSkyWorldTesting` (cell
scenes, actor visuals, and fakes over the world domains below `OpenSkyWorld`). Every unit
test target that needs the fixtures links it: package test targets, `OpenSkyTests`, and
`OpenSkyRealDataTests`.

- Declarations that tests use are `public`. A struct a test builds has an explicit
  `public init(...)`.
- A library may `@testable import` the module it builds fixtures for and import what lies
  below it, never a feature implementation (gate: `tools/lint/module-graph.sh`).
- A fixture that needs its feature's implementation, such as a fake of a seam the
  implementation declares, goes in that feature's `<Name>Fixtures/` library. Only
  `<Name>Tests` and the Xcode bundles may link it. Example: `FakeCombatWorld` in
  `OpenSkyCombatFixtures`. One used only by `<Name>Tests` stays in that target.
- A fixture that needs two implementations goes in `src/Tests/HostedTestSupport/` when both Xcode
  bundles use it, else in `src/Tests/OpenSkyTests/Support/`.
- A fixture that a package test target and `OpenSkyTests` or `OpenSkyRealDataTests` both
  need goes in a library, never in two copies.
- A byte builder goes in the lowest library that can build it. A helper that wraps the bytes
  in a higher store is an extension in a higher library, for example
  `DialogueFixture+Store.swift` in `OpenSkyEngineTesting` over `DialogueFixture` in
  `OpenSkyFormatsTesting`.
- A library holds no `@Test`. Put tests in the test target of the module they test.
- Fixtures are synthetic and built in code, never an extracted game file (root
  `AGENTS.md`, Legal & IP boundary).

## Where a suite goes

A suite goes in the package test target of the highest module it imports, in the order
`src/Package.swift` declares them. Example: a record test that imports `OpenSkyFormatsESM` and
`OpenSkyGameData` goes in `OpenSkyGameDataTests`.

A suite stays in `OpenSkyTests` when it needs something a package test target cannot
have:

- the app module (`@testable import OpenSky`),
- an acceptance chain in `src/Tests/OpenSkyTests/Acceptance/`,
- two feature implementations, for example a Magic suite that spends real actor values.
  It goes in `src/Tests/OpenSkyTests/<Feature>/`, named for the feature it tests, because a
  feature's tests may build no implementation but their own (`tools/lint/module-graph.sh`, rule 5).

Inside a target, test folders use the subfolder names of the source they test: tests for
`src/Sources/OpenSkyWorld/Streaming/CellStreamer.swift` live in `src/Tests/OpenSkyWorldTests/Streaming/`,
and tests for app code live under `src/Tests/OpenSkyTests/App/`. Only cross-cutting folders are
test-only: `Acceptance/` (end-to-end gates), `Fakes/`, and `Support/`. An acceptance suite
is named for the behavior it checks, such as `CombatAcceptanceTests`, never for a milestone
number.

A suite that builds a `Renderer` goes in a package test target too. It passes
`shaderLibrary: ShaderLibraryFixture.library(device: device)` from `OpenSkyEngineTesting`, because a
package test has no app bundle to load `default.metallib` from. `make test` and `make test-package`
compile the shaders first.

## Test plans

`src/config/TestPlans/` holds the checked-in plans, so which bundles a run touches is
reviewable configuration, not a flag. A plan builds only the bundles it lists, so the
smaller the plan, the quicker the run. `make test PLAN=<name>` picks one:

| Plan | Bundles |
| --- | --- |
| `Quick` (the default) | every package test target, without the `.slow` and `.gpu` tests |
| `GPU` | every unit target, only the `.gpu` tests |
| `UnitTests` | everything; CI runs it on every push |

`UITests` lists `OpenSkyUITests` alone. `RealData` runs the `.smoke` real-data suites;
`RealDataAll` runs the whole bundle. `T=` narrows a plan to some targets, such as
`T=OpenSkyFormatsESMTests`. Which bundles each plan lists, and that no plan puts the UI bundle
beside an app-hosted one (a deadlock), is checked (gate: `tools/lint/test-plans.sh`,
`docs/tools/test-runs.md`).

## Tags

`src/Tests/OpenSkyTagsTesting/Tags.swift` holds the shared Swift Testing tags. A test target that
tags its tests lists `OpenSkyTagsTesting` in its `tests:` list in `src/Package.swift`, because rule
12 of the module graph rejects a dependency no file imports. Put a tag on the suite,
`@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))`, or on one test when only that test needs it.
A `.gpu` or `.slow` tag outside `OpenSkyRealDataTests` always comes with `.unlessPlanSkips` of
the same tag: Xcode ignores a plan's `skippedTags`, so the `Quick` plan names the tags to skip
in `OPENSKY_SKIPPED_TAGS` and this trait reads it.

| Tag | Put it on |
| --- | --- |
| `.acceptance` | A suite under an `Acceptance/` folder |
| `.gpu` | A suite that reaches a Metal device |
| `.parser` | A suite in an `OpenSkyFormats*Tests` target |
| `.slow` | A test that takes seconds on a warm build |
| `.perf` | A timing gate. The Perf plan runs it, built optimized (`make test PLAN=Perf`) |
| `.smoke` | A real-data suite in the smoke set that `make test PLAN=RealData` runs by default: one quick suite per format family and subsystem |

A missing tag or `.unlessPlanSkips` fails the check, and `make fix` adds it (gate:
`tools/lint/test-tags.sh`). A plan picks bundles; a tag picks tests inside them.

## Test order

Every plan runs its tests in random order, with no `.serialized` (gate:
`tools/lint/test-order.sh`). A test that shares state reads only its own part of it.

## Flaky tests

A flaky test fails sometimes and passes sometimes on the same code. When you find one:

1. Disable it with the issue that tracks it: `@Test(.disabled("flaky: #NNN"))`.
2. Open a `bug` issue with the run directory of the failing run.
3. Never add a retry. A retry hides the failure, and the bug stays.

`make test T='Target/Suite/test()' N=100` reruns a test until it fails, to show it is flaky.
`tools/lint/test-tags.sh` fails a `.disabled` trait that names no issue.
