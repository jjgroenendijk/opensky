---
type: Process
title: Testing setup
description: Test targets, make entrypoints, real-data suites, result reporting,
  the RSS watchdog, and this machine's known test-environment quirks.
tags: [testing, tooling, process]
timestamp: 2026-08-06T00:00:00Z
---

# Testing setup

Three test targets, driven through `make`. Fixture rules in `openskyTests/AGENTS.md`,
`openskyRealDataTests/AGENTS.md`, `openskyTestSupport/AGENTS.md` and AGENTS.md
"Legal & IP boundary" — synthetic data built in code only, never extracted game files.

## Targets

* `openskyTests` — unit tests (Swift Testing, `@testable import opensky`).
  Format parsers, math, VFS, and the renderer via offscreen paths. Everything
  here runs with no game data at all.
* `openskyRealDataTests` — the env-gated real-data suites, which read the user's
  own install and skip without a data root (issue #418). Same app host and the
  same fixture rules; a separate bundle so `make test` does not compile them and
  the `RealData` plan can select them by target.
* `openskyUITests` — XCUITest smoke tests: app launches, main window appears, no
  game-data alert.

`openskyTestSupport/` is not a target. It is the folder both unit-test bundles
compile — the shared fixtures and fakes, the way `opensky/Engine/` is shared by
the app and `openskycli`. It carries no `@Test`, because a test there would run
in both bundles.

## Entrypoints

* `make test` — unit tests only, through the `UnitTests` test plan
  (`-testPlan UnitTests`). Writes a fixed result bundle at
  `build/test-results/unit.xcresult`. The plan lists `openskyTests` alone, so
  `openskyUITests` is not compiled at all; see [Test plans](#test-plans).
* `make test-fast [T='Suite/test()'] [B=1]` — the iteration loop (issue #417):
  `build-for-testing` once, then `test-without-building` against the cached
  `.xctestrun`, which skips the build system entirely. `tools/test-fast.sh`
  regenerates the products when any source, `Config/` file, project file, or
  vendored input is newer than the `.xctestrun`; `B=1` forces that. Bundle:
  `build/test-results/fast/<run>/fast.xcresult`. See
  [The fast loop](#the-fast-loop-and-what-guards-it).
* `make test-one T=Class[/test]` — one class or method. Bare names resolve to
  `openskyTests/`. Bundle: `build/test-results/one.xcresult`. Prefer
  `make test-fast T=...` while iterating — `test-one` pays a full build-system
  pass per run for the same selection.
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
* `make test-sanitize [SAN=Thread|Address] [CAP=MB]` — run `openskyTests` alone under
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

The hook short-circuits when the pushed tree already passed (issue #417): green
`make test` and `make cli` runs write the tested tree hash (`git stash create`,
so a dirty tree stamps the content actually tested) to
`DerivedData/green-stamps/` through `tools/green-stamp.sh`, and the hook skips
its rebuild only when the working tree is clean and both stamps equal
`HEAD^{tree}`. A skip can only ever skip work that already passed on
byte-identical content; a dirty tree, a missing stamp, or any content change
runs the full gate, and `make clean` sweeps the stamps with the rest of the
build state. Only the canonical configuration stamps — a run with `CONFIG` or
`XCODEBUILD_FLAGS` overridden does not, and `make test-fast`, `make test-one`,
and `make realtest` never do.

## Test plans

Which bundles a run touches is a checked-in test plan, not a flag (issue #346). The
`opensky` scheme references four, all under `Config/` beside the xcconfigs:

| Plan | Test targets | Used by |
| --- | --- | --- |
| `UnitTests.xctestplan` | `openskyTests` | `make test`, `make test-fast`, `make test-one`; the scheme default |
| `UITests.xctestplan` | `openskyUITests` | `make test-ui` |
| `RealData.xctestplan` | `openskyRealDataTests`, plus the data root | `make realtest`, `make realtest-all` |
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

No plan lists the UI bundle beside an app-hosted unit bundle, and that is deliberate
(issue #380). `openskyTests` and `openskyRealDataTests` are both app-hosted — their test
host *is* `opensky.app`. Put either in the same test session as the UI runner and
`xcodebuild` stands the app up as a test host, injecting
`libXCTestBundleInject.dylib`, so the app waits in
`-[XCTestDriver _prepareTestConfigurationAndIDESession]` for an IDE session that belongs to
the runner, while the runner waits for the app to enter automation mode. Neither moves, and
XCTest gives up after 60 seconds with `Timed out while enabling automation mode`. That
error names a permission, which is what sent four issues looking for a missing TCC grant,
but it is a deadlock. `-only-testing:openskyUITests` does not avoid it: a selector filters
which tests run, not which targets the session stands up. Only the plan does.

## The fast loop, and what guards it

The dominant cost of a warm `make test` or `make realtest` is not the tests: it
is the build system standing up, resolving the scheme and plan, and re-checking
the whole graph, every invocation. Session mining across ten agent sessions
(issue #417) measured `make realtest` at 85 s average per run while the median
testing-elapsed inside it was 4.9 s, with the same single test re-run four to
eleven times while iterating.

`tools/test-fast.sh` splits the two halves. `xcodebuild build-for-testing`
compiles the products and writes one `.xctestrun` per test plan under
`DerivedData/Build/Products/` (`opensky_<Plan>_macosx<sdk>-arm64.xctestrun`);
`xcodebuild test-without-building -xctestrun` then runs against those products
with no build system involved at all. The `.xctestrun` is regenerated only when
an input is newer than it — sources, `Config/` (xcconfigs and plans both, since
the RealData root is baked in), the project file, `.vendor/ffmpeg` — an mtime
sweep that costs a fraction of a second where even a no-op `build-for-testing`
costs tens of seconds. `make test-fast B=1` (or `make realtest B=1`) forces the
rebuild when in doubt.

What issue #82 retired — `build-for-testing`, rewrite the `.xctestrun`,
`test-without-building` — comes back here *without* the rewrite step, which was
the part that made it fragile: a plan environment entry lands in the generated
`.xctestrun` verbatim, so the RealData root needs no injection, and
`tools/test-fast.sh` reads the root back out of the `.xctestrun` it is about to
run, checking exactly the value the host will see.

Measured on this machine, 2026-08-08, Xcode 26.6, warm products, wall clock
from `/usr/bin/time`:

| Run | Through the build system | Fast path |
| --- | --- | --- |
| One unit test, warm, no edits | ~79 s (`make test-one`, session average) | 4.2–4.9 s |
| One real-data test, warm, no edits | 85 s (session average, incl. the enumeration pre-pass) | 12–17 s |
| One test after editing one test file | — | 35 s (one incremental `build-for-testing`), then fast again |
| Full unit plan (3576 tests) | 189 s (`make test`, first run in a fresh worktree) | 125 s |

The remaining floor of a fast run is xcodebuild session startup plus
`xcresulttool`; the real-data row also carries the watchdog and one 8 s test.

Two properties are non-negotiable and carried over from `tools/realtest.sh`:
the RSS watchdog wraps every RealData run, and the result-bundle count
assertion runs after every run, because `-only-testing` with a selector that
matches nothing runs zero tests and exits 0 — under `test-without-building`
exactly as under `test`. The fast loop is for iteration; it never writes a
pre-push green stamp, so the full `make test` remains the gate a push relies
on.

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

The `openskyRealDataTests` bundle exercises the parser/renderer stack against a
real Skyrim SE install — the highest-value integration coverage in the repo, and the
only tests that touch a real install at all. They gate on the `OPENSKY_DATA_ROOT`
env var (`GameDataLocator.environmentKey`,
`opensky/Engine/GameData/GameDataLocator.swift`):
`@Test(.enabled(if: dataRoot != nil))`, so machines without it skip
deterministically. Metal-dependent tests also gate on
`device.supportsFamily(.metal4)`.

Plain `xcodebuild test` does NOT forward an exported `OPENSKY_DATA_ROOT` into the
unit-test host (proven: the host sees `<nil>`, issue #82), so exporting the var
in your shell is not enough — the gated tests silently skip, and they skip in
every `make test` run. The real-data entrypoints run the `RealData` test plan
under the watchdog instead:

```sh
make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make realtest-all
make realtest-perf
```

A bare `T=` selector resolves under `openskyRealDataTests/`.

`make realtest` goes through the fast path (`tools/test-fast.sh -p RealData`,
issue #417): the plan's `OPENSKY_DATA_ROOT` entry is baked into the generated
`.xctestrun` as an `EnvironmentVariables` value, so `test-without-building`
forwards it with no injection, and a warm rerun pays only the test plus
xcodebuild startup. `make realtest-all` and `make realtest-perf` stay on
`tools/realtest.sh` — the whole-set run rebuilds rarely enough not to matter,
and the `-O` overlay build cannot be represented in a cached `.xctestrun`.

Every single-selector run asserts afterwards that the result bundle says
exactly one test passed — `-only-testing` accepts a misspelled Swift Testing
method and exits 0 after running nothing, so the post-run count is the guard.
On a zero-test run, `tools/test-fast-suggest.sh` prints near-matches from a
cached flat enumeration (regenerated only when the `.xctestrun` changes). The
per-run `-enumerate-tests` validation pass that used to precede every
single-test run is gone; it cost an entire extra xcodebuild invocation on the
hot path. `make realtest-all` has no selector to misspell, so it asserts
instead that at least one test executed and none failed. Skips remain legal
for the set, because some of these suites also need a Metal 4 device.

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
  method level. Selecting a whole **target** is the one plan-level selection
  that does work, which is why the suites now live in their own bundle.

### Why the suites are their own target

Until issue #418 the real-data suites shared `openskyTests`, and both costs of
that were paid on every run. `make test` compiled all of them even though they
skip without a data root, and because a plan cannot select Swift Testing tests,
`Config/RealData.xctestplan` carried a 57-entry `selectedTests` list that existed
only for `tools/realtest.sh` to re-emit as one `-only-testing` flag per suite,
kept spelled right by a lint that parsed the suites out of the source.

Moving them into `openskyRealDataTests` replaced all of that with target-level
selection: the plan names the target, `tools/realtest.sh` runs the plan as-is,
and the list, the re-emission loop, and most of the lint are gone. Measured on
this checkout, the unit compile lost 56 files and 14 820 lines (579 files /
110 413 lines before, 523 / 95 593 after, counting `openskyTests` plus the
shared `openskyTestSupport`), which every `make test` and every incremental
`make test-fast` rebuild had been paying for suites it never ran.

The shared support is the trade: 38 files compile into both bundles rather than
one. Three types that mixed a reusable fixture with `@Test` methods were split down
that seam — the fixture half in `openskyTestSupport/`, the tests in an extension
of the same type under `openskyTests/` — so no call site moved and no test
identifier changed. `openskyTestSupport/AGENTS.md` has the rule.

What replaces the plan lint is structural: `make realdata-plan` (part of
`make lint`) asserts that every file declaring `dataRoot: GameDataRoot?` with a
`@Test` lives in `openskyRealDataTests/` rather than in the unit folders, that
the plan selects that target and nothing narrows it, and that no plan lists an
app-hosted bundle beside `openskyUITests`. A gated suite in the wrong folder is
still silent coverage loss — `make realtest-all` would not reach it and
`make test` would skip it — so it is still a lint failure.

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
