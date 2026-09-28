---
type: Process
title: Testing setup
description: The test targets, the make entry points, the real-data suites and the data root, the
  memory watchdog, the headless test host, perf gates, and fixture rules.
tags: [testing, tooling, process]
---

# Testing setup

Tests run through `make`. Fixture rules are in `Tests/OpenSkyTests/AGENTS.md`,
`Tests/OpenSkyRealDataTests/AGENTS.md`, `Tests/TestSupport/AGENTS.md`, and the legal section of
`AGENTS.md`: synthetic data built in code only, never files taken from the game. How the test plans,
the fast loop, coverage, and sanitizers work is on the [test runs](/tools/test-runs.md) page.

## Targets

- `OpenSkyFormatsTests`: unit tests for the `OpenSkyFormats` parser module, with
  `@testable import OpenSkyFormats`. A change to engine code does not rebuild them
  ([Swift modules](/tools/modules.md)).
- `OpenSkyTests`: unit tests with Swift Testing and `@testable import OpenSky`. Math, the virtual
  file system, the runtime, and the renderer through offscreen paths. None of it needs game data.
- `OpenSkyRealDataTests`: the suites that read the user's install and skip without a data root. They
  are a separate bundle so `make test` does not compile them and the `RealData` plan can select them
  by target.
- `OpenSkyUITests`: XCUITest smoke tests. The app launches, the main window appears, and there is no
  game data alert.

`Tests/TestSupport/` is not a target. Both `OpenSkyTests` and `OpenSkyRealDataTests` compile it,
the way `Sources/OpenSkyEngine/` is shared by the app and `OpenSkyCLI`. `Tests/FormatsTestSupport/`
holds the fixtures that only build bytes, and all three unit bundles compile it. Neither folder has
a `@Test`, because a test there would run in more than one bundle.

## Entry points

| Command | What it does |
| --- | --- |
| `make test` | The unit plan through the build system |
| `make test-fast [T='Suite/test()'] [B=1]` | The fast loop: build once, then run against the cached products. `B=1` forces a build |
| `make test-one T=Class[/test]` | One class or method through the build system. A bare name resolves under `OpenSkyTests/`. Name `OpenSkyFormatsTests/Class` for a parser suite |
| `make verify-build` | Compiles the app, the CLI, and both unit bundles without running a test. The only routine command that compiles the real-data suites |
| `make test-report` | Pass and fail counts, each failure's name and message, and code coverage, from the newest result bundle |
| `make realtest T='Class/method()' [CAP=MB]` | One real-data test under the memory watchdog |
| `make realtest-all [CAP=MB]` | The whole real-data set under the watchdog |
| `make realtest-perf` | The real-data set built optimized, for perf budgets |
| `make test-sanitize [SAN=Thread\|Address] [CAP=MB]` | The unit bundle under runtime sanitizers |
| `make test-ui` | The UI smoke tests. Needs the Accessibility grant |
| `make test-perms` | Checks the one-time permission grants |

Prefer `make test-fast T=...` while iterating. `make test-one` pays a whole build system pass for
the same selection.

No hook runs the tests. What to test for a change is the author's judgment, guided by the
`testing-and-verifying` skill, and the commit's `Tests:` section records what ran. `ci.yml` is kept
in sync with the local gates ([environment](/tools/environment.md)).

## Real-data suites and the data root

The real-data suites run the parser and renderer stack against a real Skyrim SE install. They are
gated on `OPENSKY_DATA_ROOT` with `@Test(.enabled(if: dataRoot != nil))`, so a machine without it
skips them. Tests that need Metal also check `device.supportsFamily(.metal4)`.

Plain `xcodebuild test` does not pass an exported `OPENSKY_DATA_ROOT` into the app-hosted test host:
the host sees nil. So exporting it in a shell does nothing, and the gated tests silently skip. The
`RealData` test plan carries the root instead:

```sh
make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make realtest-all
```

A single-selector run then checks that the result bundle says exactly one test passed.
`-only-testing` accepts a misspelled Swift Testing name and exits 0 after running nothing, so the
count after the run is the guard. On a zero-test run, near matches are printed from a cached list of
tests. `make realtest-all` has no selector to misspell, so it checks that at least one test ran and
none failed. Skips are allowed, because some suites also need a Metal 4 device.

`make realtest-perf` builds with optimization, because a physics step is a few hundred microseconds
of tight `simd` math, which `-Onone` slows by more than an order of magnitude. It keeps the Debug
configuration, because `@testable import` needs `ENABLE_TESTABILITY`, which Release turns off. It
changes only the optimization level and sets the `OPENSKY_OPTIMIZED` condition, so a test knows which
budget applies. Its products go in `DerivedData-optimized/`, so switching between it and `make test`
does not rebuild the engine each time ([dynamic bodies](/engine/dynamic-bodies.md)).

A gated suite written outside `Tests/OpenSkyRealDataTests/` fails `make lint`, because nothing would
ever run it: `make realtest-all` would not reach it, and `make test` would skip it.

## Memory watchdog

A cell streaming test once grew to about 30 GB resident and locked the machine. Mapping a BSA with
`.mappedIfSafe` on an external APFS volume can fall back to full reads. So `tools/memguard.sh`
watches the process tree of every real-data run and kills it past a cap in MB.

| Run | Cap | Time limit |
| --- | --- | --- |
| One real-data test | 4,096 MB | 15 minutes |
| The whole real-data set | 6,144 MB | 2 hours |
| Sanitizers | 12,288 MB | 3 hours |

The whole set gets more, because one host process runs every suite in turn and keeps their caches.
Sanitizers get more for their shadow memory. Never run a heavy real-data test with a raw
`xcodebuild` that skips the watchdog.

## Results and perf gates

After a run, `make test-report` names the failures. Do not read the `.xcresult` JSON by hand.

Set a perf budget from a real-install measurement: take a baseline, add margin, then set the cap.
Guessing a threshold and raising it after each failed bench wasted many multi-minute runs. Keep
correctness gates (always pass) apart from perf gates (wide margin during development). Other load
changes timings: no other OpenSky should be running, and Spotlight may be indexing build output.

## The headless test host

`@testable import` of an app target needs the app as test host. Hosting does not need UI. The app's
`main` checks `XCTestConfigurationFilePath`, which XCTest sets inside the host. When it is set, the
app skips its delegate: no window, no renderer, no game data probe, and no Dock icon or focus steal.
`NSApplication` still runs, so the injected bundle executes. An app launched by XCUITest has no such
variable and takes the full path, and the smoke test checks that.

So nothing that needs the app lifecycle runs in unit tests: no delegate, no window, no Metal view.

The host reads the app's own defaults and home folder. So the data root locator ignores both saved
data root sources under the same signal, and a unit test reaches the install only through
`OPENSKY_DATA_ROOT` ([game data locator](/engine/game-data-locator.md)). Before this, a machine where
the app pointed at an install on an external volume blocked `make test` forever inside `open()`.
`TEST_RUNNER_OPENSKY_DATA_ROOT=""` did not help, because it clears only the environment variable.

## Fixtures

- Fixtures are built in code (`BSAFixture`, `ESMFixture`, `NIFFixture`, `StringTableFixture`) or are
  tiny synthetic files the test writes. Never game files.
- Rendering checks prefer exact assertions (buffer contents, transform math), plus a capture in a
  run directory under `logs/` for a person to look at ([run output](/tools/run-output.md)).
  `print()` shows in the live console but not in the `.xcresult`, so a backgrounded run loses it.
  Assert on a value or write a file.
- Full-frame checks go through the offscreen renderer: one synchronous frame into an owned texture.
  Never render through `MTKView.currentDrawable` in a test, because a window-less drawable crashes in
  `waitForDrawable` ([renderer](/rendering/metal4-renderer.md#offscreen-render)).
