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
  modules and testing libraries below it. It may also import feature implementations,
  because only tests link it. `Package.swift` lists what it may import; any other import
  fails the build. It is declared after every implementation it builds.
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
- an acceptance chain in `Tests/OpenSkyTests/Acceptance/`.

Inside a target, test folders use the subfolder names of the source they test: tests for
`Sources/OpenSkyWorld/Terrain/DistantLOD.swift` live in `Tests/OpenSkyWorldTests/Terrain/`,
and tests for app code live under `Tests/OpenSkyTests/App/`. Only cross-cutting folders are
test-only: `Acceptance/` (milestone gates), `Fakes/`, and `Support/`.

A suite that builds a `Renderer` goes in a package test target too. It passes
`shaderLibrary: ShaderLibraryFixture.library(device: device)` from `RenderingTesting`, because a
package test has no app bundle to load `default.metallib` from. `make test-fast` compiles the
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
