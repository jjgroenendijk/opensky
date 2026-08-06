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
* `make test-ui` — UI smoke tests. See "test-ui on this machine" below.
* `make test-perms` — one-time TCC setup that stops permission popups.

There is no required CI status right now: GitHub Actions is quota-suspended
(issue #70), so `ci.yml` is manual-dispatch only. The pre-push hook
(`.githooks/pre-push/20-build-test.sh`) is the sole merge gate: it runs
`make test` then `make cli` (the CLI build catches app-only source files that
Xcode's filesystem-synced groups silently pull into the `openskycli` target).
`OPENSKY_SKIP_BUILD=1` skips the gate for bootstrap/emergency only.

## Test plans

Which bundles a run touches is a checked-in test plan, not a flag (issue #346). The
`opensky` scheme references three, all under `Config/` beside the xcconfigs:

| Plan | Test targets | Used by |
| --- | --- | --- |
| `UnitTests.xctestplan` | `openskyTests` | `make test`, `make test-one`; the scheme default |
| `AllTests.xctestplan` | `openskyTests`, `openskyUITests` | `make test-ui`, and any full run |
| `RealData.xctestplan` | `openskyTests`, plus the data root | `make realtest`, `make realtest-all` |

`xcodebuild` builds every buildable in a scheme's Test action before it looks at
`-only-testing`, so a selector never saved the UI bundle's compile and link. Selecting a
plan does: the plan decides what gets built. `xcodebuild -scheme opensky -showTestPlans`
lists them.

The plans are where per-suite parallelization lives, they are where code coverage is
switched on (next section), and they are where a sanitizer variant should go when one is
wanted — as an additional plan configuration, diffable in review, rather than another flag
combination in the `Makefile`. `RealData` is the real-data variant that pattern predicted;
what it can and cannot carry is below.

Two selectors still ride on top of a plan. `make test-one T=...` adds `-only-testing` for
the one class or method, and switches from the unit plan to `AllTests` when the selector
names `openskyUITests`, because the unit plan cannot select a test it does not list.
`make test-ui` runs `AllTests` with `-only-testing:openskyUITests`, since that plan carries
both bundles.

## Code coverage

`UnitTests.xctestplan` and `AllTests.xctestplan` gather line coverage for the
`opensky` target alone (issue #382), so the number describes engine code and not
the test bundles measuring it. There is no separate entrypoint and no
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
```

`make realtest` still validates that the selector resolves to exactly one test
before running it (`-only-testing` accepts a misspelled Swift Testing method and
exits 0 after running nothing), then asserts the result bundle says one test
passed. `make realtest-all` has no selector to misspell, so it asserts instead
that at least one test executed and none failed. Skips remain legal for the set,
because some of these suites also need a Metal 4 device.

### What the RealData test plan does and does not do

`Config/RealData.xctestplan` — the third plan on the `opensky` scheme, alongside
`UnitTests` and `AllTests` above — is where the set is written down. Three
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

## RSS watchdog (mandatory for heavy real-data tests)

A cell-streaming test once ran away to ~30 GB RSS and locked the machine (BSA
`.mappedIfSafe` on an external APFS volume can fall back to full reads). Every
`make realtest` and `make realtest-all` run has `tools/memguard.sh` polling the
process tree and killing it past a cap (`CAP` MB) before it can wedge the
machine. The default is 4096 for one test and 6144 for the whole set, since one
host process runs every suite in turn and keeps their caches; the watchdog's own
lifetime scales the same way (15 minutes against 2 hours). Do not run a heavy
real-data test with a raw `xcodebuild` invocation that bypasses the watchdog —
go through `make realtest`.

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

* test-ui on this machine: `make test-ui` reliably dies at harness init with
  "Timed out while enabling automation mode" — a TCC/automation-permission gap,
  not a code fault. `make test-ui` now surfaces that as an actionable message
  (via `tools/test-ui.sh`) instead of hanging to timeout, and points at
  `make test-perms`. Until the grant is in place, verify UI/render behavior with
  `Renderer.renderOffscreen` unit tests or `make run-cli ARGS="render ..."`.
* Permission popups: a TCC grant sticks only while the binary keeps one code
  signature, so `Config/Signing.xcconfig` names a real Apple Development identity
  for every target ([build system](/tools/build-system.md)). Granting Full Disk
  Access + Automation to the stable parent you launch tests from (Terminal /
  iTerm / Xcode) still helps, since child test hosts inherit it. `make test-perms`
  guides and opens the right pane; TCC is SIP-protected, so the actual grant is
  one manual click (it cannot be scripted).
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
