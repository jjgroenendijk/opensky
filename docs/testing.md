---
type: Process
title: Testing setup
description: The test targets, the make entry points, the real-data suites and the data root, the
  memory watchdog, the headless test host, perf gates, profiling, and fixture rules.
tags: [testing, tooling, process]
---

# Testing setup

Tests run through `make`. Fixture rules are in `Tests/OpenSkyTests/AGENTS.md`,
`Tests/OpenSkyRealDataTests/AGENTS.md`, `Tests/TestSupport/AGENTS.md`, and the legal section of
`AGENTS.md`: synthetic data built in code only, never files taken from the game. How the test plans,
the tag plans, coverage, and sanitizers work is on the [test runs](/tools/test-runs.md) page.

## Targets

- `OpenSkyFormatsCoreTests`, `OpenSkyGameDataTests`, and the other `<Module>Tests`: package test
  targets, one per library module in `Package.swift`. A change to engine code does not rebuild them
  ([Swift modules](/tools/modules.md)).
- `OpenSkyTests`: unit tests with Swift Testing for what a package test target cannot hold: the
  app module and the acceptance chains. None of it needs game data.
- `OpenSkyRealDataTests`: the suites that read the user's install and skip without a data root. They
  are a separate bundle so `make test-unit` does not compile them and the `RealData` plan can select
  them by target.
- `OpenSkyUITests`: XCUITest smoke tests. The app launches, the main window appears, and there is no
  game data alert.

`Tests/TestSupport/` is not a target. Both `OpenSkyTests` and `OpenSkyRealDataTests` compile it,
the way the package modules are shared by the app and `OpenSkyCLI`. It has no `@Test`, because
a test there would run in both bundles. It holds only fixtures that need the app. Each
`Tests/<Name>Testing/` folder is a package library of shared fixtures, for example
`FormatsESMTesting` with the plugin byte builders. Every unit test target that needs one links it.

## Entry points

| Command | What it does |
| --- | --- |
| `make test-unit [T='Suite/test()'] [N=100]` | The unit plan. `T` picks a suite or test; a name that does not start with an `OpenSky*Tests` target resolves under `OpenSkyTests/`. `N` reruns until the first failure, to show a test is flaky |
| `make test-unit LOCALE=nl [T='Suite/test()']` | The unit plan in Dutch language and region, where the decimal separator is a comma |
| `make test-unit TAG=parser`, `TAG=gpu` | The unit tests tagged `.parser` or `.gpu`, through the `Parser` or `GPU` plan |
| `make compile [M='Module ...']` | `swift build` of the changed package modules, or the named ones, and every package target that depends on them. No Xcode, so it is the quick check while fixing compile errors |
| `make verify-build` | Compiles the app, the CLI, and every test bundle, the real-data suites included, without running a test. Needs no install |
| `make test-report` | Pass and fail counts, each failure's name and message, and code coverage, from the newest result bundle |
| `make test-real [T='Class/method()'] [CAP=MB]` | The real-data plan under the memory watchdog, narrowed by `T` |
| `make test-real PERF=1` | Every real-data test tagged `.perf`, built optimized, for perf budgets |
| `make test-sanitize SAN=thread`, `SAN=address` `[CAP=MB]` | The unit bundles under the Thread Sanitizer, or under ASan with UBSan |
| `make test-ui [T='Suite/test()']` | The UI smoke tests. A time-out in "enabling automation mode" means Automation Mode asks for a password; `make test-perms` names the fix |
| `make test-perms` | Checks the one-time permission grants |

There are four kinds of test, each with one target named `test-<kind>`: unit, UI, sanitizer, and
real-data. An option picks the plan inside a kind (`TAG`, `LOCALE`, `SAN`, `PERF`), so each run is
still one plain `xcodebuild test` call on one test plan ([test runs](/tools/test-runs.md)).

No automatic step runs the tests. What to test for a change is the author's judgment, guided by the
`testing-and-verifying` skill, and the commit's `Tests:` section records what ran. CI runs the lint
checks, not the tests ([continuous integration](/tools/ci.md)).

## Real-data suites and the data root

The real-data suites run the parser and renderer stack against a real Skyrim SE install. They are
gated on `OPENSKY_DATA_ROOT` with `@Test(.enabled(if: dataRoot != nil))`, so a machine without it
skips them. Tests that need Metal also check `device.supportsFamily(.metal4)`.

Plain `xcodebuild test` does not pass an exported `OPENSKY_DATA_ROOT` into the app-hosted test host:
the host sees nil. So exporting it in a shell does nothing, and the gated tests silently skip. The
`RealData` test plan carries the root instead:

```sh
make test-real T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make test-real
```

`-only-testing` accepts a misspelled Swift Testing name and exits 0 after running nothing. Nothing
checks this, so read the test count in the output.

`make test-real PERF=1` runs the Perf plan, which selects the real-data tests tagged `.perf`, so a new
perf gate joins by its tag alone. It builds with optimization, because a physics step is a few
hundred microseconds of tight `simd` math, which `-Onone` slows by more than an order of magnitude.
It keeps the Debug configuration, because `@testable import` needs `ENABLE_TESTABILITY`, which
Release turns off. It changes only the optimization level and sets the `OPENSKY_OPTIMIZED`
condition, so a test knows which budget applies. Its products go in `DerivedData-optimized/`, so
switching between it and `make test-unit` does not rebuild the engine each time ([dynamic
bodies](/engine/dynamic-bodies.md)).

A gated suite written outside `Tests/OpenSkyRealDataTests/` fails `make lint`, because nothing would
ever run it: `make test-real` would not reach it, and `make test-unit` would skip it.

## Memory watchdog

A cell streaming test once grew to about 30 GB resident and locked the machine. Mapping a BSA with
`.mappedIfSafe` on an external APFS volume can fall back to full reads. So `tools/memguard.sh`
watches the process tree of every real-data run and kills it past a cap in MB.

| Run | Cap | Time limit |
| --- | --- | --- |
| `make test-real`, with or without `PERF=1` | 6,144 MB | 3 hours |
| `make test-sanitize` | 12,288 MB | 3 hours |

The real-data cap fits the whole set, because one host process runs every suite in turn and keeps
their caches. `CAP=MB` lowers it for one test. Sanitizers get more for their shadow memory. Never
run a heavy real-data test with a raw `xcodebuild` that skips the watchdog.

## Results and perf gates

After a run, `make test-report` names the failures. Do not read the `.xcresult` JSON by hand.

Set a perf budget from a real-install measurement: take a baseline, add margin, then set the cap.
Guessing a threshold and raising it after each failed bench wasted many multi-minute runs. Keep
correctness gates (always pass) apart from perf gates (wide margin during development). Other load
changes timings: no other OpenSky should be running, and Spotlight may be indexing build output.

## Profiling

`make profile` records an Instruments Time Profiler trace of `openskycli bench --walk-path` on a
Release build. `MODE=fly` profiles `--fly-path` instead. `ARGS` passes more bench options, such as
`ARGS='--footprint-cap-mb 2048'` when a bench gate stops the run early. The run directory holds
the trace and `samples.xml`, the exported sample table, for reading without Instruments.

- Profile a Release build. A Debug build makes tight math code many times slower, so it points at
  the wrong loops.
- Start the process first, then run `xctrace record --attach <pid>`
  ([why not `--launch`](/tools/environment.md#xctrace---launch-never-starts-the-process)). Attach
  to the right PID: `$!` after a subshell is the shell, not the program.
- The CLI benches run the renderer, animation, streaming, and physics. Combat, factions, actor
  values, perception, and AI packages run only in the app. To profile those, launch the Release app
  from `DerivedData/Build/Products/Release/` with `OPENSKY_DATA_ROOT` set, and attach. The app
  opens a window, so tell the person at the machine first.
- To see one loop, keep only the samples whose backtrace contains its frame function, such as
  `Renderer.pumpOffscreen` or `Renderer.draw`. Cell builds on background threads otherwise
  dominate the totals.

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
the app pointed at an install on an external volume blocked the unit tests forever inside `open()`.
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
