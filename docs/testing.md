---
type: Process
title: Testing setup
description: Test targets, make entrypoints, real-data suites, result reporting,
  the RSS watchdog, and this machine's known test-environment quirks.
tags: [testing, tooling, process]
timestamp: 2026-08-05T00:00:00Z
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

* `make test` — unit tests only (`-only-testing:openskyTests`). Writes a fixed
  result bundle at `build/test-results/unit.xcresult`. xcodebuild still compiles
  `openskyUITests` either way; see [Build system](/tools/build-system.md).
* `make test-one T=Class[/test]` — one class or method. Bare names resolve to
  `openskyTests/`. Bundle: `build/test-results/one.xcresult`.
* `make test-report` — pass/fail summary plus each failing test's name and
  message, read from the newest fixed bundle (falls back to the DerivedData
  glob). It waits for the bundle to finalize, so it no longer misreports a
  half-written `.xcresult` as a failure.
* `make realtest T='Class/method()' [CAP=MB]` — run one real-data test against
  the install (see next section).
* `make test-ui` — UI smoke tests. See "test-ui on this machine" below.
* `make test-perms` — one-time TCC setup that stops permission popups.

There is no required CI status right now: GitHub Actions is quota-suspended
(issue #70), so `ci.yml` is manual-dispatch only. The pre-push hook
(`.githooks/pre-push/20-build-test.sh`) is the sole merge gate: it runs
`make test` then `make cli` (the CLI build catches app-only source files that
Xcode's filesystem-synced groups silently pull into the `openskycli` target).
`OPENSKY_SKIP_BUILD=1` skips the gate for bootstrap/emergency only.

## Real-data suites and the data root

12 `*RealDataTests` suites exercise the parser/renderer stack against a real
Skyrim SE install. They gate on the `OPENSKY_DATA_ROOT` env var
(`GameDataLocator.environmentKey`, `opensky/GameData/GameDataLocator.swift`):
`@Test(.enabled(if: dataRoot != nil))`, so machines without it skip
deterministically. Metal-dependent tests also gate on
`device.supportsFamily(.metal4)`.

Plain `xcodebuild test` does NOT forward `OPENSKY_DATA_ROOT` into the unit-test
host (proven: the host sees `<nil>`), so exporting the var in your shell is not
enough — the gated tests silently skip. `make realtest` does it the reliable way
(`tools/realtest.sh`): `build-for-testing`, inject the data root into the
generated `.xctestrun`, then `test-without-building`. The selector must resolve
to exactly one fully-qualified test, e.g.:

```sh
make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
```

The underlying xcodebuild gap is tracked as issue #82.

## RSS watchdog (mandatory for heavy real-data tests)

A cell-streaming test once ran away to ~30 GB RSS and locked the machine (BSA
`.mappedIfSafe` on an external APFS volume can fall back to full reads). Every
`make realtest` run has `tools/memguard.sh` polling the process tree and killing
it past a cap (`CAP` MB, default 4096) before it can wedge the machine. Do not
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
  pre-push hook) at 0% CPU. If a test host hangs before running, recycle it:
  `killall testmanagerd`, then retry (no `--no-verify` bypass).
* One xcodebuild at a time: two concurrent `xcodebuild` invocations against the
  same DerivedData (e.g. a probe while the pre-push hook builds) deadlock until
  the tool timeout. Let one finish before starting another.
* The build cache is `DerivedData/` inside the checkout, not the Xcode default
  under `$HOME` — the boot volume is too small to hold it. `make` passes
  `-derivedDataPath` on every `xcodebuild` call and exports
  `OPENSKY_DERIVED_DATA`; `make realtest` uses `DerivedData/opensky-realtest`
  beside it, so a real-data run never invalidates the ordinary build. A hand-run
  `xcodebuild` that omits the flag starts a second cache on the boot disk and
  rebuilds from scratch.
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
