---
type: Subsystem
title: Game data locator
description: How OpenSky finds the user's Skyrim SE install - the search order, what counts as
  an install, and why test hosts ignore saved settings.
tags: [engine, io, config]
---

# Game data locator

OpenSky finds the user's Skyrim SE install when it starts. The install is read-only input. It is
never bundled, cached, or copied.

## Search order

The first source that is set wins. A source that is set but invalid is an error. The search does
not go on to the next source.

1. The `OPENSKY_DATA_ROOT` environment variable. For tests, the CLI, and one-off runs.
2. The `OpenSkyDataRoot` user default. This is the saved setting:
   `defaults write nl.jjgroenendijk.opensky OpenSkyDataRoot "<install path>"`, or the app's
   Settings window.
3. The default Steam path:
   `~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition`.

The setting lives in one shared defaults domain, `nl.jjgroenendijk.opensky`. The CLI reads it
with `UserDefaults(suiteName:)`. The app uses `.standard`, because its own domain is that
domain and `suiteName` refuses the app's own bundle ID. Both read the same file.

## What counts as an install

A path is an install if `Data/Skyrim.esm` exists under it. A path to the `Data` folder itself is
also accepted, because both forms appear in user settings. `~` is expanded.

The result has the install folder, the data folder, and which source was used. All engine reads
go under the data folder.

## Failure

A failure is a typed error. The app logs it (category `GameData`) and shows how to fix it in the
World and Asset Browser views. Settings stays open to use. A new valid path rebuilds the world and
reloads the browser without a restart. There is never a silent fallback.

`saveUserChoice(path:)` checks a path before saving it. An invalid path is an error, and the old
setting stays. `clearUserChoice()` removes the setting.

## Test hosts ignore saved settings

Inside the unit test host, only the environment variable counts. The saved setting and the Steam
path are skipped. The test host is detected by the `XCTestConfigurationFilePath` variable, as in
[testing](/testing.md).

The reason: the test host is the app, and the app reads the app's settings. On a machine where
the app pointed at a real install, unit tests that must not depend on an install read that
install anyway. Clearing the environment variable does not help, because the saved setting is
still there. This once made `make test-unit` hang, opening a real INI file.

Real-data suites check the environment variable, so this does not affect them. UI tests pass a
made-up install through `OPENSKY_DATA_ROOT`.

## plugins.txt

The load order file is found the same way: `OPENSKY_PLUGINS_TXT`, then the `OpenSkyPluginsText`
user default, then the places a macOS install can keep it. A test host skips the saved setting
and the home folder for the same reason. Unlike the install, a missing `plugins.txt` is not an
error. It means the vanilla masters. See [plugins.txt](/formats/plugins-txt.md).
