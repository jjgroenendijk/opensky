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

- Screen Recording and automation permissions (TCC)
- Continuous integration suspended
- Upstream spec hosts
- Memory watchdog for heavy real-data tests
- Test plans, environment entries, and Swift Testing

## Screen Recording and automation permissions (TCC)

Observed 2026-07-20. `make test-ui` blocks at XCTest harness initialization, and UI tests
stall on "enabling automation mode". Screen Recording is not granted to the test runner, so
screenshot-based verification is unavailable too.

- Try `make test-perms` once per machine; it requests the permissions the harness needs.
- Until it succeeds, pin accessibility ids as literal assertions in unit tests
  (`DestinationRegistryTests`) and keep `openskyUITests` correct so it passes wherever the
  permission exists.

Updated 2026-08-05. A grant only sticks if the binary keeps the same code signature. The UI
test runner signed ad-hoc from the start, and the app joined it when issue #343 moved
signing into a per-developer file nobody filled in, so every build asked again — for
Automation, and for reading the game install off `/Volumes/data`, which manifested as a
real-data test host parked in `open()`. `Config/Signing.xcconfig` now names one Apple
Development identity for every target including the runner, so an approval survives
rebuilds. When the prompts come back, `codesign -dv --verbose=2` on the built app and on
`openskyUITests-Runner.app` is the first thing to check: `Signature=adhoc` is the cause.

Retires when `make test-ui` reaches the first test case on this machine.

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

Retires per bullet when the host or repository changes behaviour.

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

Retires when a later Xcode matches plan-level selection against Swift Testing identifiers,
at which point `tools/realtest.sh` can stop translating the plan's list into
`-only-testing` flags.
