---
type: Reference
title: Local environment and external state
description: Dated record of machine-specific and third-party facts that skills and AGENTS.md
  must not hardcode — TCC permissions, CI suspension, upstream spec-host quirks — each with
  the condition that retires it.
tags: [environment, tooling, ci, gotchas]
timestamp: 2026-08-06T00:00:00Z
---

# Local environment and external state

Single home for facts that are true of *this machine or the outside world right now*, not of
the repo. Skills and `AGENTS.md` state durable rules and link here; they do not carry copies,
because a copy has no date and nobody notices when it expires.

Every entry below carries the date it was observed and the condition that retires it. An
entry whose condition is met gets deleted, not amended.

## Contents

- AVAudioPlayerNode.playerTime hangs offline rendering
- Continuous integration suspended
- Upstream spec hosts
- No plugins.txt on this machine
- Memory watchdog for heavy real-data tests
- Test plans, environment entries, and Swift Testing
- build-for-testing and test-without-building

## AVAudioPlayerNode.playerTime hangs offline rendering

Observed 2026-08-10 on Xcode 26.6 / macOS 26.5.2, measured while writing the playback clock
for issue #206. Calling `AVAudioPlayerNode.playerTime(forNodeTime:)` — or reaching it through
`lastRenderTime` — on a node attached to an `AVAudioEngine` in `.offline` manual rendering
mode hangs the app-hosted test host: the process stops running tests, sits idle in its run
loop, and `xcodebuild` waits on it until it is killed. Nothing appears in the result bundle,
so it reads as an infinite test rather than a failure.

It is not specific to the new code. Any suite that reached the query hung, including the
pre-existing `WorldAudioEngineTests`, once `statsSnapshot()` started calling it — which is
what identified the API rather than the caller.

So `WorldAudioEngine.playbackPosition(ofSource:)` is elapsed-render accounting against
`manualRenderingSampleTime` instead of a node-time query
([World audio playback](/engine/audio.md)). Anything else that wants a sample-accurate output
position has to solve this first.

Retires when a later macOS or Xcode answers the query under offline rendering instead of
hanging, at which point the clock could read the node directly.

## Continuous integration suspended

Observed 2026-07-20. The GitHub Actions CPU quota is exhausted. `ci.yml` is manual-dispatch
only and `main` carries no required status checks, so the git hooks installed by
`make bootstrap` are the only gate. Tracked by issue #70.

`ci.yml` is still kept in sync with the hooks while suspended, so re-enabling is a quota
change and nothing else.

Retires when the quota returns and issue #70 closes.

## Upstream spec hosts

Observed 2026-07-20. Quirks that cost time on every format-parser session:

- UESP (`en.uesp.net`, `ck.uesp.net`) answers the WebFetch tool with HTTP 403. Use
  `curl -sL -A 'Mozilla/5.0' '<url>'`. If `ck.uesp.net` still refuses, fetch through the
  Wayback Machine (`web.archive.org`).
- The `TES5Edit/TES5Edit` default branch is `dev-4.1.6`, not `main` or `dev`; raw-file URLs
  return 404 on the wrong branch. Confirm with `gh api repos/TES5Edit/TES5Edit`.
- Observed 2026-08-07: `www.creationkit.com` serves an XWiki "down for backend maintenance"
  page for every path, and the Wayback Machine redirects its snapshots to that same live
  page. The `ck.uesp.net` mirror of the same wiki does answer through Wayback
  (`https://web.archive.org/web/2023/https://ck.uesp.net/wiki/<Page>`), which is how the
  Stats Tab, Class and Race pages were read for issue #194. Retires when
  `creationkit.com` comes back.

Retires per bullet when the host or repository changes behaviour.

## No plugins.txt on this machine

Observed 2026-08-10. The install under `/Volumes/data/steam/steamapps/common/Skyrim Special
Edition/` holds `Skyrim.ccc` and the ini files but no `plugins.txt`, there is no
`~/Library/Application Support/Skyrim Special Edition/`, and the Steam library has no
`compatdata/` — the game has never been launched here. So every
[plugin load order](/formats/plugins-txt.md) resolved on this machine takes the vanilla
fallback, and the `plugins.txt` parsing paths cannot be checked against a game-written file
locally. A real-data probe of a modded load order needs a file supplied by hand and pointed
at with `OPENSKY_PLUGINS_TXT`.

Retires when a `plugins.txt` appears in one of the searched locations.

## Memory watchdog for heavy real-data tests

Observed 2026-07-20. A runaway real-data test consumed roughly 30 GB of resident memory and
locked the machine. `tools/memguard.sh` caps resident size and is mandatory around heavy
real-data runs; `make realtest` and `make realtest-all` already wire it in.

Retires when the tests carry their own bounds.

## Test plans, environment entries, and Swift Testing

Observed 2026-08-06 on Xcode 26.5 (build 25F70), measured while wiring
`Config/RealData.xctestplan` for issue #381. Three behaviors, all of which
[testing setup](/testing.md) is built around:

- A test plan's `environmentVariableEntries` **does** reach the unit-test host, which a
  plain `xcodebuild test` environment variable does not (issue #82). This is what let
  `tools/realtest.sh` drop the `build-for-testing` / rewrite the `.xctestrun` /
  `test-without-building` sequence.
- A plan environment **value is not macro-expanded**. `$(OPENSKY_DATA_ROOT)` arrives at the
  host as that literal string, confirmed by reading `EnvironmentVariables` back out of the
  generated `.xctestrun`. So a plan carries literal paths, and nothing in the environment
  can override one.
- A plan's `selectedTests` and `skippedTests` **do not match Swift Testing tests**. The
  identifiers reach the runner as `OnlyTestIdentifiers`, so a plan that selects any of them
  runs zero tests; a plan that skips one skips nothing. Suite-level, method-level, and
  target-qualified spellings all behave the same way. Command-line `-only-testing` does
  work, and replaces the plan's selection entirely.

  Selecting a whole **target** in a plan does work, which is what
  `Config/RealData.xctestplan` does since issue #418; nothing translates a plan's test list
  into `-only-testing` flags any more.

Retires when a later Xcode matches plan-level selection against Swift Testing identifiers,
at which point a plan could narrow a run to individual suites again.

## build-for-testing and test-without-building

Observed 2026-08-08 on Xcode 26.6 / macOS 26.6.1, measured while wiring
`tools/test-fast.sh` for issue #417:

- `build-for-testing` writes one `.xctestrun` per test plan under
  `Build/Products/`, named `opensky_<Plan>_macosx26.5-arm64.xctestrun` — the
  version segment is the SDK, not the OS, so it moves with Xcode updates and
  the tooling resolves it by glob. FormatVersion 2: everything interesting
  lives under `TestConfigurations[0].TestTargets[0]`, not at the top level.
- The RealData plan's `OPENSKY_DATA_ROOT` entry lands in the `.xctestrun`
  verbatim under `EnvironmentVariables`, and `test-without-building` forwards
  it into the app-hosted test host — a gated test passes, not skips, with no
  injection anywhere.
- Command-line `-only-testing` **overrides** any `OnlyTestIdentifiers` baked into the
  `.xctestrun` by a plan's own (inert) test selection, and a
  misspelled Swift Testing selector still runs zero tests and exits 0 —
  identical to `xcodebuild test`, so the post-run result-bundle count stays
  the guard.
- `-enumerate-tests` **rejects `-derivedDataPath`** with a usage error (exit
  64) in any argument position, so an enumeration against an `.xctestrun`
  cannot be pointed at the checkout's cache and drops a small session-log
  directory under Xcode's default DerivedData; `tools/test-fast-suggest.sh`
  removes exactly the directories a run creates. Enumeration also **refuses an
  existing `-test-enumeration-output-path` file** with the same exit 64 —
  `mktemp` pre-creating the file is enough to trip it.
- Plain `test-without-building` does accept `-derivedDataPath`, and without it
  the session logs land on the boot volume, so the flag stays mandatory there
  (AGENTS.md derived-data gotcha).

Retires if a later Xcode lets `-enumerate-tests` take `-derivedDataPath`, at
which point the snapshot-and-remove dance in `tools/test-fast-suggest.sh` can
go.
