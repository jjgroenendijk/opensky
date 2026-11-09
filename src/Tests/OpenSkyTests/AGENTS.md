# AGENTS.md — OpenSkyTests

Rules for writing tests in this target. General test rules live in `src/Tests/AGENTS.md`.

## What stays in this target

The suites that need the app module, an acceptance chain, or two feature implementations.
The last kind lives in `<Feature>/`, for example `Magic/CasterRuntimeTests`. Every other suite
goes in a package test target, including one that builds a `Renderer`.

`src/Tests/HostedTestSupport/` holds the fixtures this bundle shares with
`OpenSkyRealDataTests`; `Support/` holds the ones only this bundle uses. Other fixtures come
from the testing and fixture libraries through `OpenSkyTestSupport`.

## Compile and run failures this target produces

- A test that touches `Renderer`, `MTKView`, AppKit, or MetalKit is `@MainActor`. Missing it
  is the most common compile error here (`error: main actor`). Copy
  `GameViewControllerScreenshotTests`.
- A test that renders gates on `OffscreenRendererFixture.hasMetal4Device`, so a CI runner
  without a Metal 4 GPU skips it. A test that only builds a cell scene gates on
  `CellSceneBuilderFixture.hasDevice`.
- A suite that reads the real install goes in `src/Tests/OpenSkyRealDataTests/` (gate:
  `tools/lint/realdata-plan.sh`). Here `GameDataLocator` withholds every data root.
- `print()` shows in the live console but not in the result bundle. To keep a result, assert
  on the value or write an artifact to `.logs/`.
- An accessibility ID is pinned twice: as a literal in a unit test (`LauncherTests`), and
  through `OpenSkyUITests`, which proves the view hierarchy reaches it.
