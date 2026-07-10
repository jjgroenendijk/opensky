---
type: Process
title: Testing setup
description: Test targets, make entrypoints, headless unit-test host, UI smoke
  test, and the synthetic-fixture policy.
tags: [testing, tooling, process]
timestamp: 2026-07-10T00:00:00Z
---

# Testing setup

Two test targets, two `make` entrypoints. Rules for fixtures in AGENTS.md
"Testing" + "Legal & IP" — synthetic data built in code only, never extracted
game files.

## Targets

* `openskyTests` — unit tests (Swift Testing, `@testable import opensky`).
  Format parsers, math, game-data locator, VFS. Pure logic, no UI.
* `openskyUITests` — one XCUITest smoke test: app launches, main window
  appears, no game-data alert (launches with `OPENSKY_DATA_ROOT` pointing at a
  synthetic install so the probe succeeds without real data).

## Entrypoints

* `make test` — unit tests only (`-skip-testing:openskyUITests`). Fast local
  gate; pre-push hook runs this.
* `make test-ui` — UI smoke test only (`-only-testing:openskyUITests`).
  Launches the app + drives it via macOS automation (expect the OS overlay).
* CI runs both; it is the full backstop for UI regressions.

## Headless unit-test host

`@testable import` of an app target requires the app as test host
(`TEST_HOST = opensky.app` in the project). Hosting does not require UI:
`OpenSkyApp.main()` checks `XCTestConfigurationFilePath` in the environment —
set by XCTest inside the host process — and when present skips the
`AppDelegate` entirely (no window, no `Renderer`, no game-data probe) and sets
activation policy `.prohibited` (no Dock icon, no focus steal). `NSApplication`
still runs so the injected test bundle executes.

XCUITest-launched app instances lack that variable -> full app path. That is
what the smoke test asserts, so a broken guard shows up in `make test-ui`.

Consequence: nothing app-lifecycle-dependent can run in unit tests — there is
no delegate, no window, no Metal device wired up. Unit-test code touching
those belongs in the UI target or needs its own explicit setup.

## Fixtures

* Built in code (`BSAFixture`, `ESMFixture`, `StringTableFixture`) or tiny
  synthetic files the test generates. Never checked-in game assets.
* Rendering checks prefer deterministic assertions (buffer contents, transform
  math) + manual visual confirmation of the real frame.
* Full-path render checks go through `Renderer.renderOffscreen`
  (`RendererOffscreenTests`): synchronous frame into an owned texture, pixel
  assertions, temp PNG logged for human review. Never render through
  `MTKView.currentDrawable` in tests — windowless drawables crash in
  `waitForDrawable` (see [renderer](/rendering/metal4-renderer.md)).
