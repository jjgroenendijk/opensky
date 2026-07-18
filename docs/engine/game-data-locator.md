---
type: Subsystem
title: Game data locator
description: How OpenSky finds the user's Skyrim SE install - resolution order, validation, fail-loud rules.
tags: [engine, io, config]
timestamp: 2026-07-09T00:00:00Z
---

# Game data locator

`opensky/GameData/GameDataLocator.swift`. Resolves + validates the Skyrim SE install at
launch. Install is read-only external input — never bundled, cached, or copied
(AGENTS.md Legal & IP).

## Resolution order

First configured source wins. Configured-but-invalid override -> throws, never falls
through to the next source.

1. `OPENSKY_DATA_ROOT` env var — tests, CLI runs, one-off launches.
2. `OpenSkyDataRoot` UserDefaults key — persistent per-machine setting:
   `defaults write nl.jjgroenendijk.opensky OpenSkyDataRoot "<install path>"`,
   or main app's Settings window.
3. Default Steam path:
   `~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition`.

Setting lives in one shared defaults domain `nl.jjgroenendijk.opensky`
(`GameDataLocator.settingsDefaults`). CLI reads it via `UserDefaults(suiteName:)`; main
app, whose own domain is shared one, uses `.standard` (`suiteName` rejects current bundle
id). Same plist either way.

## Persisting a choice

`GameDataLocator.saveUserChoice(path:)` — validates, then stores under the
defaults key; invalid path throws and leaves the stored setting untouched.
`clearUserChoice()` removes it (next locate falls back to the Steam default).
Main-app Settings window drives both.

## Validation

Path counts as install root when `Data/Skyrim.esm` exists under it. Path pointing at the
`Data/` folder itself (contains `Skyrim.esm` directly) also accepted — both shapes occur
in user configs. Tilde expanded.

## Result + failure

Success -> `GameDataRoot { installURL, dataURL, source }`; `dataURL` is the only root
engine reads go under. Failure -> `GameDataError` (typed, `LocalizedError`); AppDelegate
logs via `os.Logger` (subsystem `nl.jjgroenendijk.opensky`, category `GameData`) + shows
remediation inside World/Asset Browser. Settings stays reachable; successful change
rebuilds World dependencies + reloads browser without relaunch. No silent fallback.

Probe skipped in the unit-test host (`XCTestConfigurationFilePath` env present) — tests
must not depend on machine state. UI-tested app instances still run it; smoke test injects
a synthetic root via `OPENSKY_DATA_ROOT`.

## Tests

`openskyTests/GameDataLocatorTests.swift` — synthetic temp-dir installs (empty
`Skyrim.esm` marker), all sources injectable. Covers order, both root shapes, fail-loud
on invalid override, not-found message. UI smoke covers missing-data in-window state +
Settings Cmd+, opening.
