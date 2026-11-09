---
type: Tool
title: Acceptance record
description: The record every milestone acceptance writes into its closing PR - the openskycli game
  commands that force and inspect the new behaviour, what changed, and the tests behind it.
tags: [tool, acceptance, milestone, agent-control]
---

# Acceptance record

Every user-verifiable behaviour can be forced and inspected in the running game through
`openskycli game` (`AGENTS.md`, "Open work, docs, and checking a behaviour"). When a milestone
is accepted, the closing PR or issue carries one record that says how to check that behaviour
again. The record does not go in `docs/`.

## Evidence

The record is mandatory. A screenshot is not.

The deterministic tests are the evidence: the unit tests of the coordinator, the agent command
tests, and any offscreen render test the milestone already has. If they pass, the gate passes.

A capture can still help a human reviewer. It is optional, it goes in `.logs/`, and it is never
committed. A frame rendered from a real install contains Bethesda textures, meshes, and UI art,
so committing it would share game content (`AGENTS.md`, "Legal & IP boundary").

## Format

```text
Milestone: M8
Commands: openskycli game launch; openskycli game input press cameraMode;
  openskycli game state player
Observed: state player firstPerson.drawn changed from false to true
Deterministic tests: LocomotionBridgeFirstPersonTests, AgentCommandRouterTests
Run directory (optional, never committed): .logs/game/<UTC timestamp>/
```

- **Commands**: the `openskycli game` commands that force the behaviour and read it back, in
  the order they ran. A script replayed with `openskycli game run` may stand in for the list.
- **Observed**: the field of the reply whose value shows that the behaviour changed, with the
  value before and after. A record without it is incomplete, because nothing is left to check
  again.
- **Deterministic tests**: the test suites that check the same behaviour without the app.
- **Run directory**: a run directory under `.logs/` ([run output](/tools/run-output.md)), or
  `none`. `make prune` deletes old run directories, so the tests stay the lasting evidence.

A behaviour that no command can force or read yet gets the command in the same milestone. The
`driving-the-running-game` skill lists the commands.

## Tour check

A refactor must not change what the game does. `make tour-check` shows that it did not: it
replays one recorded tour and compares every state read with a reference run.

1. Before the refactor, on its base: `make build-app build-cli CONFIG=Release`, then
   `make tour-record`. The reference goes to the main checkout's `.logs/tour-record/`, so every
   worktree compares against the same one.
2. After the refactor: build the Release app again, then `make tour-check`. It builds nothing.
   It exits non-zero on any difference and prints each one as `[DIFF] <point>.<path>: old -> new`.

The tour is `tools/tour/tour.jsonl`. It runs hidden and muted (`game launch --hidden`), steps
the paused clock, and quits the app at the end. It goes to `WhiterunBanneredMare` at 13:00,
walks forward, turns, opens and closes the magic menu, readies the hands and attacks, and reads
the player, the actors, the target, the view, the menu, two actor values, `MQ101`, and the time.

A difference is a bug the refactor made, or a change the issue asked for; the PR says which.
The reference holds state reads only, never a capture, and stays in gitignored `.logs/`.

The fields that change on every run of one build are dropped before the compare, at any depth:
`seq`, `frame`, `frames`, `elapsed`, `elapsedSeconds`, `frameTime`, `frameTimeMs`, `gpuMemory`,
`skippedFrames`, `timeline`, `wallClock`, and `timestamp`. Animation clips load off the main
thread, so `clipsLoaded`, the graph `steps` and `recentEvents`, and the player's `lastFall` go
too (`tools/tour/volatile.txt`). Numbers match within 0.01, because float maths moves a value in
its last digits. A `position`, `distance`, or `feet` matches within 2 units: the app runs a
frame or two between `worldReady` and the tour's pause, and a walking actor moves about 1.2
units a frame. Measured 2026-11-09: three runs of one build differed only there.
