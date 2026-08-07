---
type: Process
title: Testing setup
description: Test targets, make entrypoints, real-data suites, result reporting,
  the RSS watchdog, and this machine's known test-environment quirks.
tags: [testing, tooling, process]
timestamp: 2026-08-06T00:00:00Z
---

# Testing setup

Two test targets, driven through `make`. Fixture rules in `openskyTests/AGENTS.md` and
AGENTS.md "Legal & IP boundary" — synthetic data built in code only, never extracted game
files.

## Targets

* `openskyTests` — unit tests (Swift Testing, `@testable import opensky`).
  Format parsers, math, VFS, and the renderer via offscreen paths. This includes
  the env-gated real-data suites (see below), which skip without a data root.
* `openskyUITests` — XCUITest smoke tests: app launches, main window appears, no
  game-data alert.

## Entrypoints

* `make test` — unit tests only, through the `UnitTests` test plan
  (`-testPlan UnitTests`). Writes a fixed result bundle at
  `build/test-results/unit.xcresult`. The plan lists `openskyTests` alone, so
  `openskyUITests` is not compiled at all; see [Test plans](#test-plans).
* `make test-one T=Class[/test]` — one class or method. Bare names resolve to
  `openskyTests/`. Bundle: `build/test-results/one.xcresult`.
* `make test-report` — pass/fail summary plus each failing test's name and
  message, plus the code coverage percentage, read from the newest fixed bundle
  (falls back to the DerivedData glob). It waits for the bundle to finalize, so
  it no longer misreports a half-written `.xcresult` as a failure. See
  [Code coverage](#code-coverage).
* `make realtest T='Class/method()' [CAP=MB]` — run one real-data test against
  the install (see next section).
* `make realtest-all [CAP=MB]` — run the whole real-data set the same way. On
  demand and before a milestone acceptance; never on push, because it needs an
  install CI does not have.
* `make test-sanitize [SAN=Thread|Address] [CAP=MB]` — run `openskyTests` under
  the runtime sanitizers (see [Sanitizers](#sanitizers)). On demand and before a
  milestone, never on push.
* `make test-ui` — UI smoke tests, driving the real app through XCUITest. Runs
  the `UITests` plan; on demand, never on push, because it needs the
  Accessibility grant below.
* `make test-perms` — checks the one-time TCC grants that stop permission popups.

There is no required CI status right now: GitHub Actions is quota-suspended
(issue #70), so `ci.yml` is manual-dispatch only. The pre-push hook
(`.githooks/pre-push/20-build-test.sh`) is the sole merge gate: it runs
`make test` then `make cli` (the CLI build catches app-only source files that
Xcode's filesystem-synced groups silently pull into the `openskycli` target).
`OPENSKY_SKIP_BUILD=1` skips the gate for bootstrap/emergency only.

## Test plans

Which bundles a run touches is a checked-in test plan, not a flag (issue #346). The
`opensky` scheme references four, all under `Config/` beside the xcconfigs:

| Plan | Test targets | Used by |
| --- | --- | --- |
| `UnitTests.xctestplan` | `openskyTests` | `make test`, `make test-one`; the scheme default |
| `UITests.xctestplan` | `openskyUITests` | `make test-ui` |
| `RealData.xctestplan` | `openskyTests`, plus the data root | `make realtest`, `make realtest-all` |
| `Sanitizers.xctestplan` | `openskyTests`, one configuration per sanitizer | `make test-sanitize` |

`xcodebuild` builds every buildable in a scheme's Test action before it looks at
`-only-testing`, so a selector never saved the UI bundle's compile and link. Selecting a
plan does: the plan decides what gets built. `xcodebuild -scheme opensky -showTestPlans`
lists them.

The plans are where per-suite parallelization lives, they are where code coverage is
switched on (next section), and they are where the sanitizer variants live — as plan
configurations, diffable in review, rather than another flag combination in the `Makefile`.
`RealData` and `Sanitizers` are the two variants that pattern predicted; what `RealData` can
and cannot carry is below, and `Sanitizers` has its own section.

`make test-one T=...` rides on top of a plan: it adds `-only-testing` for the one class or
method, and switches from the unit plan to `UITests` when the selector names
`openskyUITests`, because the unit plan cannot select a test it does not list.

No plan lists both bundles, and that is deliberate (issue #380). `openskyTests` is
app-hosted — its test host *is* `opensky.app`. Put it in the same test session as the UI
runner and `xcodebuild` stands the app up as a test host, injecting
`libXCTestBundleInject.dylib`, so the app waits in
`-[XCTestDriver _prepareTestConfigurationAndIDESession]` for an IDE session that belongs to
the runner, while the runner waits for the app to enter automation mode. Neither moves, and
XCTest gives up after 60 seconds with `Timed out while enabling automation mode`. That
error names a permission, which is what sent four issues looking for a missing TCC grant,
but it is a deadlock. `-only-testing:openskyUITests` does not avoid it: a selector filters
which tests run, not which targets the session stands up. Only the plan does.

## Code coverage

`UnitTests.xctestplan`, `UITests.xctestplan`, and `Sanitizers.xctestplan` gather
line coverage for the `opensky` target alone (issue #382), so the number describes
engine code and not the test bundles measuring it. There is no separate entrypoint and no
`-enableCodeCoverage` flag anywhere: `make test` gathers it and `make test-report`
prints it under the pass/fail counts, overall and per target.

It is on by default, with no `make test-coverage` beside `make test`, because
measuring the cost found there was none to pay: coverage was already being
gathered on every single run and thrown away. `ENABLE_CODE_COVERAGE` defaults to
`YES` in Xcode and no `Config/*.xcconfig` overrides it, so a `.xcresult` from
before this change already answers `xcrun xccov view --report` — unscoped, which
is why it reported a meaningless 86.68% for `openskyTests.xctest` and 0/0 for
`openskyUITests.xctest` next to the number anyone actually wants. Adding
`-enableCodeCoverage YES` to a warm `make test` recompiled nothing (zero compile
lines in either transcript) and moved the wall clock from 37.5s to 35.5s, which
is to say inside the run-to-run noise, and the plan option measured the same at
35.6s. What the plan entry changes is not whether the number exists but whether
it is scoped and reviewable; what `make test-report` changes is whether anyone
ever sees it.

That leaves nothing to defer behind a separate target, which matters because
`make test` is on the pre-push path for every commit. If a cost ever does show
up, the shape to move to is a target passing `-enableCodeCoverage YES`, which
does override the plan.

There is deliberately no threshold gate and no coverage number in CI. The value
is finding defensive branches in the parsers that no test ever takes — the
malformed-input paths that AGENTS.md's "malformed input must not crash" is
about — not defending a percentage. A floor gets argued from a baseline, the
same discipline the perf budgets below already require.

Baseline at the time it landed: 80.31% of lines (57543/71652).

## Real-data suites and the data root

The `*RealDataTests` suites exercise the parser/renderer stack against a real
Skyrim SE install — the highest-value integration coverage in the repo, and the
only tests that touch a real install at all. They gate on the `OPENSKY_DATA_ROOT`
env var (`GameDataLocator.environmentKey`,
`opensky/Engine/GameData/GameDataLocator.swift`):
`@Test(.enabled(if: dataRoot != nil))`, so machines without it skip
deterministically. Metal-dependent tests also gate on
`device.supportsFamily(.metal4)`.

Plain `xcodebuild test` does NOT forward an exported `OPENSKY_DATA_ROOT` into the
unit-test host (proven: the host sees `<nil>`, issue #82), so exporting the var
in your shell is not enough — the gated tests silently skip, and they skip in
every `make test` run. Both entrypoints go through `tools/realtest.sh` instead,
which runs the `RealData` test plan under the watchdog:

```sh
make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make realtest-all
make realtest-perf
```

`make realtest` still validates that the selector resolves to exactly one test
before running it (`-only-testing` accepts a misspelled Swift Testing method and
exits 0 after running nothing), then asserts the result bundle says one test
passed. `make realtest-all` has no selector to misspell, so it asserts instead
that at least one test executed and none failed. Skips remain legal for the set,
because some of these suites also need a Metal 4 device.

`make realtest-perf` is the one real-data entrypoint that builds **optimized**
(`tools/realtest.sh -O`), and it exists because the dynamic-body step budget is
otherwise unmeasurable: a physics step is a few hundred microseconds of tight
`simd` arithmetic, which is exactly the code `-Onone` costs an order of magnitude
on, so the same run measures around twenty-four times slower unoptimized. Holding
it to the shipped 2 ms there would be measuring the compiler. The optimized run
keeps the **Debug configuration** — `@testable import` needs
`ENABLE_TESTABILITY`, which Release turns off, so a Release test build fails to
resolve the `opensky` module at all — and overrides only the optimization level
plus the `OPENSKY_OPTIMIZED` compilation condition, which is how the test knows
which budget it is held to. Its products go in `DerivedData-optimized/`, because
sharing the Debug tree would make every alternation between `make test` and this
rebuild the whole engine. A default `make realtest` still gates the same suite,
at a looser unoptimized ceiling. Details in
[dynamic rigid bodies](/engine/dynamic-bodies.md).

### What the RealData test plan does and does not do

`Config/RealData.xctestplan` — the third plan on the `opensky` scheme, alongside
`UnitTests` and `UITests` above — is where the set is written down. Three
measured xcodebuild behaviors shape it; dates and the conditions that retire
them are in [local environment](/tools/environment.md):

* A plan **environment entry does** reach the unit-test host. That is what
  replaced issue #82's workaround — `build-for-testing`, rewrite the generated
  `.xctestrun` with `plistlib`, `test-without-building` — with an ordinary
  `xcodebuild test -testPlan RealData`.
* A plan environment value is **not** macro-expanded: `$(OPENSKY_DATA_ROOT)`
  arrives at the host as those literal 21 characters. So the plan carries a
  literal install path, and that entry is the single place the data root is
  configured — `tools/realtest.sh` reads the root back out of the plan and
  refuses to run when a conflicting `OPENSKY_DATA_ROOT` is exported, rather than
  testing an install the plan does not name. Point the suite at a different
  install by editing the plan.
* A plan's **`selectedTests` does not match Swift Testing tests**. The
  identifiers do reach the runner (they show up as `OnlyTestIdentifiers` in the
  generated `.xctestrun`) but select nothing, so running the plan straight
  through executes zero tests — as does `skippedTests`, at suite level or at
  method level. Command-line `-only-testing` does work and replaces the plan's
  selection, so `tools/realtest.sh` reads the plan's `selectedTests` and passes
  one `-only-testing` per suite.

Because the plan's list is only as good as its spelling, `make realdata-plan`
(part of `make lint`) asserts it is exactly the set of env-gated suites in
`openskyTests` — every file that declares `dataRoot: GameDataRoot?` and has a
`@Test`. Adding a real-data suite and forgetting the plan is a lint failure, not
silent coverage loss.

## Sanitizers

`make test-sanitize` runs `openskyTests` under the runtime sanitizers through
`Config/Sanitizers.xctestplan` and `tools/test-sanitize.sh` (issue #383). Three
properties of this codebase make it worth the wall-clock: the decode-only ffmpeg
is reached across a C boundary where Swift's safety guarantees stop, the format
parsers slice `UnsafeRawBufferPointer` over memory-mapped archives where an
out-of-range read lands in mapped memory instead of tripping a bounds check, and
most of the engine's concurrency lives in the `nonisolated` declarations that opt
out of what Swift 6 checks statically.

The plan carries two configurations, because the two sanitizers cannot be
enabled in one build:

| Configuration | Plan options | Build |
| --- | --- | --- |
| `Thread` | `threadSanitizerEnabled` | `DerivedData/Build/Products/Variant-TSan/` |
| `Address` | `addressSanitizer.enabled`, `undefinedBehaviorSanitizerEnabled` | `.../Variant-ASan-UBSan/` |

Each configuration builds into its own `Variant-<sanitizer>` products directory,
and `xcodebuild` builds every configuration in the plan whether or not it runs
them: `-only-test-configuration Thread` was measured (2026-08-06, Xcode 26.5)
still producing `Variant-ASan-UBSan` alongside `Variant-TSan`. So
`make test-sanitize SAN=Thread` narrows what executes while iterating on a
finding, not what compiles.

That is also why this is a fourth plan rather than two more configurations on
`UnitTests`: there the sanitized builds would be compiled and run on every
`make test`, which is the pre-push gate for every commit. The first run of each
configuration recompiles the whole app and test bundle and takes far longer than
`make test` — a periodic and pre-milestone check, in the same category as
`make realtest-all`, deliberately not on the pre-push path.
The run goes through the memory watchdog below at a higher cap than the real-data
runs use, because sanitizer shadow memory multiplies resident size.

A sanitizer report surfaces as a failing test, so `make test-report` reads the
run like any other. A finding that turns out to be real becomes its own GitHub
issue rather than an inline fix. The first baseline (2026-08-06, recorded in
[the change log](/log.md)) was clean under Thread Sanitizer across the whole
bundle and produced one Address Sanitizer crash — the NIF scene-graph recursion
reaching the stack guard before its own depth cap fires, issue #388. That fix
landed on 2026-08-07 and both configurations are green, so a new report is a
regression rather than a known finding.

## RSS watchdog (mandatory for heavy real-data tests)

A cell-streaming test once ran away to ~30 GB RSS and locked the machine (BSA
`.mappedIfSafe` on an external APFS volume can fall back to full reads). Every
`make realtest` and `make realtest-all` run has `tools/memguard.sh` polling the
process tree and killing it past a cap (`CAP` MB) before it can wedge the
machine. The default is 4096 for one test and 6144 for the whole set, since one
host process runs every suite in turn and keeps their caches; the watchdog's own
lifetime scales the same way (15 minutes against 2 hours). `make test-sanitize`
runs under the same watchdog at 12288 MB for 3 hours, because a sanitized host
carries shadow memory on top of everything it would otherwise allocate. Do not
run a heavy real-data test with a raw `xcodebuild` invocation that bypasses the
watchdog — go through `make realtest`.

## Result reporting and perf gates

* After any run, `make test-report` names failures; you should not hand-parse
  the `.xcresult` JSON.
* Perf/bench budgets (per-cell build p95, actor build p95, frame time) must be
  calibrated from a real-install measurement before being locked — guessing a
  threshold then bumping it after each failing bench wasted many multi-minute
  reruns. Take a baseline sample, add margin, then set the cap. Keep correctness
  gates (must always pass) separate from perf gates (wide margin during active
  dev). Background load skews timings: no other OpenSky instance should be alive,
  and watch for Spotlight indexing build output.

## Headless unit-test host

`@testable import` of an app target requires the app as test host
(`TEST_HOST = opensky.app`). Hosting does not require UI: `OpenSkyApp.main()`
checks `XCTestConfigurationFilePath` (set by XCTest inside the host process) and
when present skips the `AppDelegate` entirely — no window, no `Renderer`, no
game-data probe — and sets activation policy `.prohibited` (no Dock icon, no
focus steal). `NSApplication` still runs so the injected bundle executes.

XCUITest-launched app instances lack that variable -> full app path. The smoke
test asserts that, so a broken guard shows up in `make test-ui`.

This is also why the two bundles cannot share a test session. Standing the app up
as a test host is what sets `XCTestConfigurationFilePath` in the first place, and
a host launched that way blocks in
`-[XCTestDriver _prepareTestConfigurationAndIDESession]` waiting to be told which
tests to run. Do that while the UI runner is trying to drive the same app and
neither side ever proceeds — see the test plan section above (issue #380).

Consequence: nothing app-lifecycle-dependent runs in unit tests — no delegate, no
window, no Metal device wired up. Code touching those belongs in the UI target or
needs its own setup.

Hosting in the app bundle also means the host reads the app's own defaults domain
and home directory, so `GameDataLocator` withholds both persistent data-root
sources under the same `XCTestConfigurationFilePath` signal — a unit test reaches
the install only through `OPENSKY_DATA_ROOT`. See
[game data locator](/engine/game-data-locator.md). Before that, a machine where
the app had been pointed at an install on an external volume ran `make test` into
an indefinite block inside `open()`, which also hung the pre-push hook
(issue #362). `TEST_RUNNER_OPENSKY_DATA_ROOT=""` did not prevent it, because it
clears only the environment variable.

## Known test-environment quirks (this machine)

* Permission popups: a TCC grant sticks only while the binary keeps one code
  signature, so `Config/Signing.xcconfig` names a real Apple Development identity
  for every target ([build system](/tools/build-system.md)). The grants are to
  the built products, not to the terminal that launches them: Accessibility for
  `openskyUITests-Runner.app`, which is what XCTest asks for when it enables
  automation mode, and file access for `opensky.app`, which macOS treats as a
  binary on a removable volume because `DerivedData/` sits in a checkout on an
  external disk. Each is one click per signature. `make test-perms` verifies what
  is checkable — that the data root is readable, and that both bundles carry a
  real identity rather than an ad-hoc signature, which is what makes a grant
  evaporate — and opens the right pane for the rest. TCC is SIP-protected, so the
  grant itself cannot be scripted, and `kTCCServiceAccessibility` lives in the
  root-owned system database, so a check cannot read it back without Full Disk
  Access of its own.
* Stale `testmanagerd`: a days-old XCTest daemon can wedge a fresh run (or the
  pre-push hook) at 0% CPU. The symptom is
  `The test runner hung before establishing connection` plus
  `Timed out after 120.0s while initiating control session with daemon`, and it
  hits `make test` and `make realtest` alike — `make realtest` shows it first as
  a selector that "must resolve to exactly one test", because the enumeration
  step hangs the same way. Recycle the daemon and retry (no `--no-verify`
  bypass). `killall testmanagerd` is not always enough: a wedged daemon ignores
  SIGTERM and stays up, so check `ps -eo pid,lstart,command | grep testmanagerd`
  for its start date and `kill -9` the pid if it survived. `launchd` respawns it
  on the next run. Observed 2026-08-06: a daemon two days old failed every test
  entrypoint until it was killed with `-9`; both went green immediately after.
* One xcodebuild at a time: two concurrent `xcodebuild` invocations against the
  same DerivedData (e.g. a probe while the pre-push hook builds) deadlock until
  the tool timeout. Let one finish before starting another.
* The build cache is `DerivedData/` inside the checkout, not the Xcode default
  under `$HOME` — the boot volume is too small to hold it. `make` passes
  `-derivedDataPath` on every `xcodebuild` call and exports
  `OPENSKY_DERIVED_DATA`. `make realtest` shares that one cache: it kept a
  separate `DerivedData/opensky-realtest` tree only because it rewrote the
  generated `.xctestrun`, and selecting a test plan changes no build setting, so
  the second tens-of-gigabytes tree bought nothing. A hand-run `xcodebuild` that
  omits the flag starts a second cache on the boot disk and rebuilds from
  scratch.
* Disk fills from caches nobody owns: each linked worktree keeps its own
  `DerivedData/`, and removing the worktree usually leaves it behind. `make
  prune` deletes those, along with result bundles and run output past the
  retention age ([run output layout](/tools/run-output.md)).

## Fixtures

* Built in code (`BSAFixture`, `ESMFixture`, `NIFFixture`, `StringTableFixture`)
  or tiny synthetic files the test generates. Never checked-in game assets.
* Rendering checks prefer deterministic assertions (buffer contents, transform
  math) + human review of a capture written to a run directory under `logs/`
  (gitignored, see [run output layout](/tools/run-output.md)). `print()`
  shows in the live xcodebuild console but is NOT in the `.xcresult`, so a
  backgrounded/polled run loses it — assert on a value or write an artifact.
* Full-path render checks go through `Renderer.renderOffscreen`
  (`RendererOffscreenTests`): synchronous frame into an owned texture, pixel
  assertions, temp PNG logged for human review. Never render through
  `MTKView.currentDrawable` in tests — windowless drawables crash in
  `waitForDrawable` (see [renderer](/rendering/metal4-renderer.md)).
