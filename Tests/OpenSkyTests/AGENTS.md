# AGENTS.md — OpenSkyTests

Rules for writing tests in this target. Running engine code against the real install to
check a hypothesis is a different job: load the `probe` skill for that.

## Compile failures this target produces

- A test touching `Renderer`, `MTKView`, or any AppKit or MetalKit API must be marked
  `@MainActor`. Omitting it is the historical top compile error here (`error: main
  actor`). Patterns to copy: `GameViewControllerScreenshotTests`, and
  `RendererOffscreenTests` in `OpenSkyWorldTests`.
- A test that renders gates on `OffscreenRendererFixture.hasMetal4Device`, so a machine
  without a Metal 4 GPU, such as a CI runner, skips instead of failing. A test that only builds
  a cell scene gates on `CellSceneBuilderFixture.hasDevice`, which accepts any Metal device.
- Everything parsing external data throws, so use `try` with `#require` rather than a
  force-unwrap, which is a hard lint error.

## Real-data tests live in another target

A suite that reads the user's own install belongs in `Tests/OpenSkyRealDataTests/`, not here, and
`make lint` fails when one is written here instead: it would never run. `make realtest-all`
runs that bundle and only that bundle, and inside `make test` an env-gated suite silently
skips, because a plain `xcodebuild test` does not forward `OPENSKY_DATA_ROOT` into the host.
`Tests/OpenSkyRealDataTests/AGENTS.md` has the shape to copy.

Nothing here reads a real install: `GameDataLocator` withholds the persisted
`OpenSkyDataRoot` default and the Steam fallback inside a test host, so a unit test cannot
quietly reach one even by accident (issue #362).

## What stays in this target

This target holds the suites that need the app module, an acceptance chain, or two feature
implementations. The last kind lives in `<Feature>/`, for example `Magic/CasterRuntimeTests`.
Every other suite goes in a package test target, including one that builds a `Renderer`;
`Tests/AGENTS.md` has the rule.

`Tests/TestSupport/` is compiled into this bundle and `OpenSkyRealDataTests`. It holds the
fixtures both bundles use that need the app or two implementations. `Support/` holds the
ones only this bundle uses. Other fixtures are in the `Tests/<Name>Testing/` and
`Tests/<Name>Fixtures/` libraries, which this bundle links through `OpenSkyTestSupport`.

## Fixtures and output

- Fixtures are synthetic and built in code — never a real extracted file. The existing
  helpers are `BSAFixture`, `ESMFixture`, `NIFFixture`, and `StringTableFixture`, in
  the `Tests/Formats<Family>Testing/` libraries.
- `print()` appears in the live `xcodebuild` console but is not in the `.xcresult`, so
  `make test-report` and any backgrounded run lose it. To capture a result, assert on the
  value or write an artifact to gitignored `logs/`.
- `make test-fast T='Suite'` or `T='Suite/method()'` runs one suite or test in
  `OpenSkyTests` without paying the build system when nothing changed; the
  `testing-and-verifying` skill covers what to run. `make test-report` extracts failure
  names and messages from the newest result bundle.
- Accessibility ids are pinned as literal assertions here (`DestinationRegistryTests`) *and*
  exercised through `OpenSkyUITests`. The two catch different things: a unit assertion pins
  the id string, and only a UI test proves the id is reachable in the built view hierarchy.
  Every sidebar row assertion passed here for months while
  `outlines["AppSidebar"].cells[...]` matched nothing in the running app (issue #380).
