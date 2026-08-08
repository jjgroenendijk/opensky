# AGENTS.md — openskyTests

Rules for writing tests in this target. Running engine code against the real install to
check a hypothesis is a different job: load the `probe` skill for that.

## Compile failures this target produces

- A test touching `Renderer`, `MTKView`, or any AppKit or MetalKit API must be marked
  `@MainActor`. Omitting it is the historical top compile error here (`error: main
  actor`). Patterns to copy: `RendererOffscreenTests`, `RendererUITests`.
- A Metal test gates on `device.supportsFamily(.metal4)`, like
  `CellSceneBuilderTests.hasDevice`, so machines without a Metal 4 device skip instead of
  failing.
- Everything parsing external data throws, so use `try` with `#require` rather than a
  force-unwrap, which is a hard lint error.

## Real-data tests live in another target

A suite that reads the user's own install belongs in `openskyRealDataTests/`, not here, and
`make lint` fails when one is written here instead: it would never run. `make realtest-all`
runs that bundle and only that bundle, and inside `make test` an env-gated suite silently
skips, because a plain `xcodebuild test` does not forward `OPENSKY_DATA_ROOT` into the host.
`openskyRealDataTests/AGENTS.md` has the shape to copy.

Nothing here reads a real install: `GameDataLocator` withholds the persisted
`OpenSkyDataRoot` default and the Steam fallback inside a test host, so a unit test cannot
quietly reach one even by accident (issue #362).

## Support shared with the real-data target

`openskyTestSupport/` is compiled into both unit-test bundles, and that is where a fixture
both a synthetic suite and a real-data suite need has to live — the two targets are separate
modules and cannot import each other. Support only this target uses stays here.

Three types are split across that seam: the fixture halves of `CellSceneBuilderTests`,
`CellStreamerTests` and `PapyrusWorldActivationTests` are declared in `openskyTestSupport/`,
and the `@Test` methods are extensions of the same type here. So a
file here can extend a type it does not declare, and a `private` member of such a fixture is
not reachable from this half. `openskyTestSupport/AGENTS.md` has the rule.

## Fixtures and output

- Fixtures are synthetic and built in code — never a real extracted file. The existing
  helpers are `BSAFixture`, `ESMFixture`, `NIFFixture`, and `StringTableFixture`.
- `print()` appears in the live `xcodebuild` console but is not in the `.xcresult`, so
  `make test-report` and any backgrounded run lose it. To capture a result, assert on the
  value or write an artifact to gitignored `logs/`.
- `make test-one T=Class[/method]` runs one class or method in `openskyTests`; use
  `T=Target/Class/method` for an explicitly qualified selector, which is how a class in
  another test target is reached. `make test-report`
  extracts failure names and messages from the newest result bundle.
- Accessibility ids are pinned as literal assertions here (`DestinationRegistryTests`) *and*
  exercised through `openskyUITests`. The two catch different things: a unit assertion pins
  the id string, and only a UI test proves the id is reachable in the built view hierarchy.
  Every sidebar row assertion passed here for months while
  `outlines["AppSidebar"].cells[...]` matched nothing in the running app (issue #380).
