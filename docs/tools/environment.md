---
type: Reference
title: Local environment and external state
description: Dated record of machine-specific and third-party facts that skills and AGENTS.md must
  not hardcode - permissions, CI suspension, upstream spec host quirks, and xcodebuild behaviors -
  each with the condition that retires it.
tags: [environment, tooling, ci, gotchas]
---

# Local environment and external state

This page holds facts that are true of this machine or the outside world right now, not of the
repository. Skills and `AGENTS.md` state lasting rules and link here. They do not keep copies,
because a copy has no date and nobody notices when it expires.

Every entry has the date it was observed and the condition that retires it. An entry whose
condition is met is deleted, not changed.

## AVAudioPlayerNode.playerTime hangs offline rendering

Observed 2026-08-10 on Xcode 26.6 and macOS 26.5.2. Calling `AVAudioPlayerNode.playerTime(forNodeTime:)`,
or reaching it through `lastRenderTime`, on a node attached to an `AVAudioEngine` in `.offline`
manual rendering mode hangs the app-hosted test host. The process stops running tests and sits idle,
and `xcodebuild` waits until it is killed. Nothing reaches the result bundle, so it looks like an
endless test, not a failure. Every suite that reached the query hung, which is what showed the API
was at fault and not the caller.

So the playback position is counted from `manualRenderingSampleTime` instead of a node time query
([audio](/engine/audio.md)). Anything else that needs a sample-exact output position has to solve
this first.

Retires when a later macOS or Xcode answers the query under offline rendering.

## Continuous integration suspended

Observed 2026-07-20. The GitHub Actions CPU quota is used up. `ci.yml` runs only on manual dispatch,
and `main` has no required status checks, so the git hooks from `make bootstrap` are the only gate.
`ci.yml` is still kept in sync with the hooks, so turning it back on is only a quota change.

Retires when the quota returns.

## Upstream spec hosts

Quirks that cost time in every format parser session. Each retires when the host changes behavior.

- Observed 2026-07-20: UESP (`en.uesp.net`, `ck.uesp.net`) answers the WebFetch tool with HTTP 403.
  Use `curl -sL -A 'Mozilla/5.0' '<url>'`.
- Observed 2026-07-20: the `TES5Edit/TES5Edit` default branch is `dev-4.1.6`, not `main` or `dev`.
  Raw file URLs return 404 on the wrong branch. Check with `gh api repos/TES5Edit/TES5Edit`.
- Observed 2026-09-08: `ck.uesp.net` answers a direct `curl` with a Cloudflare "Just a moment..."
  page, so the user agent trick no longer works there. Its Wayback snapshots still load
  (`https://web.archive.org/web/2023/https://ck.uesp.net/wiki/<Page>`). Pages the Wayback Machine
  never saved cannot be reached from here. For a Papyrus signature, the install's own compiled
  script is the better source anyway ([actor natives](/engine/papyrus-actor-natives.md)).
- Observed 2026-08-07: `www.creationkit.com` serves a "down for backend maintenance" page for every
  path, and its Wayback snapshots redirect to that page. Use the `ck.uesp.net` snapshots above.

## No plugins.txt on this machine

Observed 2026-08-10. The install under `/Volumes/data/steam/steamapps/common/Skyrim Special
Edition/` has `Skyrim.ccc` and the ini files but no `plugins.txt`. There is no
`~/Library/Application Support/Skyrim Special Edition/`, and the Steam library has no `compatdata/`:
the game has never been launched here. So every [load order](/formats/plugins-txt.md) on this
machine takes the vanilla fallback, and the `plugins.txt` paths cannot be checked against a file the
game wrote. A probe of a modded load order needs a hand-made file named by `OPENSKY_PLUGINS_TXT`.

Retires when a `plugins.txt` appears in a searched location.

## Permission grants

Observed 2026-08-11 on macOS 26.6.1, and again 2026-09-28. `OpenSkyUITests-Runner.app` starts,
then XCTest times out after 60 seconds with "Timed out while enabling automation mode", although
the UI plan is isolated
correctly ([test runs](/tools/test-runs.md#test-plans)). The missing Accessibility grant is the rest
of the problem.

A grant belongs to the built product, not the terminal, and lasts only while the product keeps one
code signature, which is why signing names a real identity ([build system](/tools/build-system.md#signing)).
Accessibility goes to `OpenSkyUITests-Runner.app`. File access goes to `OpenSky.app`, which macOS
treats as a program on a removable volume, because `DerivedData/` is on an external disk. The grant
cannot be scripted: TCC is protected by SIP, and the Accessibility entry is in the root-owned system
database. `make test-perms` checks what it can (the data root is readable, and both bundles have a
real signature) and opens the right settings pane for the rest.

Retires when `make test-ui` reaches a test case on this machine.

## Stale testmanagerd

Observed 2026-08-06. A days-old XCTest daemon can stall a fresh run at 0% CPU. The signs are
`The test runner hung before establishing connection` and
`Timed out after 120.0s while initiating control session with daemon`, in `make test` and
`make realtest` alike. `killall testmanagerd` is not always enough, because a stuck daemon ignores
SIGTERM. Check its start date with `ps -eo pid,lstart,command | grep testmanagerd` and `kill -9` it
if it survived. `launchd` starts a new one on the next run.

Retires when a fresh daemon stops going stale over days.

## Memory watchdog for heavy real-data tests

Observed 2026-07-20. A runaway real-data test used about 30 GB of resident memory and locked the
machine. `tools/memguard.sh` caps resident size and must wrap heavy real-data runs
([testing](/testing.md#memory-watchdog)).

Retires when the tests carry their own bounds.

## Test plans, environment entries, and Swift Testing

Observed 2026-08-06 on Xcode 26.5 (build 25F70):

- A test plan's `environmentVariableEntries` reach the unit-test host. A plain `xcodebuild test`
  environment variable does not.
- A plan environment value is not macro-expanded. `$(OPENSKY_DATA_ROOT)` arrives at the host as that
  literal string, as read back from the generated `.xctestrun`. So a plan holds literal paths, and
  nothing in the environment can override one.
- A plan's `selectedTests` and `skippedTests` do not match Swift Testing tests. The identifiers reach
  the runner as `OnlyTestIdentifiers`, so a plan that selects any runs zero tests, and a plan that
  skips one skips nothing. Suite, method, and target-qualified spellings all behave the same.
  Command-line `-only-testing` works and replaces the plan's selection. Selecting a whole target in
  a plan works.

Retires when a later Xcode matches plan selection against Swift Testing names.

## build-for-testing and test-without-building

Observed 2026-08-08 on Xcode 26.6 and macOS 26.6.1:

- `build-for-testing` writes one `.xctestrun` per plan under `Build/Products/`, named
  `opensky_<Plan>_macosx26.5-arm64.xctestrun`. The version is the SDK, not the OS, so it moves with
  Xcode and the tools find it by glob. It is format version 2: the useful data is under
  `TestConfigurations[0].TestTargets[0]`.
- The RealData plan's `OPENSKY_DATA_ROOT` lands in the `.xctestrun` under `EnvironmentVariables`,
  and `test-without-building` passes it to the app-hosted test host.
- Command-line `-only-testing` overrides any `OnlyTestIdentifiers` in the `.xctestrun`. A misspelled
  Swift Testing selector still runs zero tests and exits 0.
- `-enumerate-tests` rejects `-derivedDataPath` with a usage error (exit 64) in any position, so it
  drops a small session log folder under Xcode's default DerivedData, and
  `tools/test-fast-suggest.sh` removes exactly the folders a run makes. It also refuses an existing
  `-test-enumeration-output-path` file with exit 64, so a file made by `mktemp` trips it.
- Plain `test-without-building` does accept `-derivedDataPath`, and without it the session logs land
  on the boot volume, so the flag stays.

Retires if a later Xcode lets `-enumerate-tests` take `-derivedDataPath`.
