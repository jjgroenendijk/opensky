---
type: Reference
title: Local environment and external state
description: Dated record of machine-specific and third-party facts that skills and AGENTS.md
  must not hardcode — TCC permissions, CI suspension, upstream spec-host quirks — each with
  the condition that retires it.
tags: [environment, tooling, ci, gotchas]
timestamp: 2026-07-26T00:00:00Z
---

# Local environment and external state

Single home for facts that are true of *this machine or the outside world right now*, not of
the repo. Skills and `AGENTS.md` state durable rules and link here; they do not carry copies,
because a copy has no date and nobody notices when it expires.

Every entry below carries the date it was observed and the condition that retires it. An
entry whose condition is met gets deleted, not amended.

## Contents

- Screen Recording and automation permissions (TCC)
- Real-data XCTest host hangs
- Continuous integration suspended
- Upstream spec hosts
- Memory watchdog for heavy real-data tests

## Screen Recording and automation permissions (TCC)

Observed 2026-07-20. `make test-ui` blocks at XCTest harness initialization, and UI tests
stall on "enabling automation mode". Screen Recording is not granted to the test runner, so
screenshot-based verification is unavailable too.

- Try `make test-perms` once per machine; it requests the permissions the harness needs.
- Until it succeeds, pin accessibility ids as literal assertions in unit tests
  (`DestinationRegistryTests`) and keep `openskyUITests` correct so it passes wherever the
  permission exists.

Updated 2026-08-05. A grant only sticks if the binary keeps the same code signature. Between
issue #343 landing and this note the app signed ad-hoc, so every build asked again — for
Automation, and for reading the game install off `/Volumes/data`, which manifested as a
real-data test host parked in `open()`. `tools/config-local.sh` now derives a real Apple
Development identity, and `codesign -dv` on the built app is the first thing to check when
the prompts come back.

Retires when `make test-ui` reaches the first test case on this machine.

## Real-data XCTest host hangs

Observed 2026-07-20. A real-data XCTest host sometimes hangs at 0% CPU before running any
test. Killing and retrying does not clear it. See `docs/testing.md` for the diagnosis.

Workaround: move the one-off check into `openskycli` and drive it with `make run-cli`.

Retires when the host launches reliably.

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
real-data runs; `make realtest` already wires it in.

Retires when the tests carry their own bounds.
