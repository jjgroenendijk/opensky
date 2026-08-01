# AGENTS.md — openskyTests

Rules for writing tests in this target. Running engine code against the real install to
check a hypothesis is a different job: load the `probe` skill for that.

## Compile failures this target produces

- A test touching `Renderer`, `MTKView`, or any AppKit or MetalKit API must be marked
  `@MainActor`. Omitting it is the historical top compile error here (`error: main
  actor`). Patterns to copy: `RendererOffscreenTests`, `CellRenderRealDataTests`.
- A Metal test gates on `device.supportsFamily(.metal4)`, like
  `CellRenderRealDataTests.device`, so machines without a Metal 4 device skip instead of
  failing.
- Everything parsing external data throws, so use `try` with `#require` rather than a
  force-unwrap, which is a hard lint error.

## Real-data tests

`CellRenderRealDataTests.swift` is the canonical env-gated real-data test — copy its shape.
Gate on `GameDataLocator.environmentKey` being set, and deliberately do not consult the
Steam-default fallback, so a machine without `OPENSKY_DATA_ROOT` skips deterministically.

Plain `xcodebuild test` does not forward `OPENSKY_DATA_ROOT` to the unit-test host, so an
env-gated test silently skips under it. Use `make realtest T='Class/method()'`, which
injects the data root the reliable way and runs under the RSS watchdog
(`tools/realtest.sh`); the selector must resolve to exactly one fully-qualified test. A
heavy real-data test without that watchdog once ran the machine out of memory.

## Fixtures and output

- Fixtures are synthetic and built in code — never a real extracted file. The existing
  helpers are `BSAFixture`, `ESMFixture`, `NIFFixture`, and `StringTableFixture`.
- `print()` appears in the live `xcodebuild` console but is not in the `.xcresult`, so
  `make test-report` and any backgrounded run lose it. To capture a result, assert on the
  value or write an artifact to gitignored `logs/`.
- `make test-one T=Class[/method]` runs one class or method in `openskyTests`; use
  `T=Target/Class/method` for an explicitly qualified selector. `make test-report`
  extracts failure names and messages from the newest result bundle.
- `make test-ui` is TCC-blocked on this machine, so accessibility ids are pinned as literal
  assertions here (`DestinationRegistryTests`) rather than exercised through the UI target.
