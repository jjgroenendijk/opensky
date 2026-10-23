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
