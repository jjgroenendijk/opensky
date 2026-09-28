---
type: Subsystem
title: Locomotion graph
description: What the player's movement writes into the behavior graph each step - the variables
  and events it drives, how a name the graph does not declare is reported - and the
  Player & Locomotion panel.
tags: [engine, animation, behavior, locomotion, player]
---

# Locomotion graph

The movement bridge is where input, the behavior graph, and the character controller meet. Its rules
for moving the capsule are on the [walk mode](/engine/walk-mode.md) page. This page covers what it
does to a graph instance ([behavior graph runtime](/engine/behavior-runtime.md)).

## One step

Once per fixed 1/120 s step, in this order:

1. write the engine's state into graph variables;
2. raise the events for the changes the step crossed;
3. update the graph;
4. read root motion and the fired events back out.

A step of zero length does none of it.

## Names

Every name comes from the census of the install's own behavior files
([HKX behavior graph objects](/formats/hkx-behavior.md)), not from memory. `0_master.hkx` alone
declares 230 variables and 1,217 events, and a name that only sounds right resolves to nothing.

| Variable | Type | Written as |
| --- | --- | --- |
| `Speed`, `SpeedSampled` | real | The gait speed, or 0 when standing |
| `Direction` | real | Radians away from facing. Positive is left, 0 is straight ahead |
| `TurnDelta` | real | Yaw change over the step |
| `IsSprinting`, `IsSneaking` | bool | The resolved gait |
| `iIsInSneak` | int32 | The same sneak state, in its int spelling |
| `bInJumpState` | bool | True while off the ground |
| `SpeedWalk`, `SpeedRun` | real | The configured gait speeds |

Events: `moveStart` and `moveStop`, `SprintStart` and `SprintStop`, `SneakStart` and `SneakStop`,
`SwimStart` and `SwimStop`, and `JumpUp`, `JumpFall`, and `JumpLand`. Each is raised only when the
state changes, in a fixed order. So a step that changes several things raises the same sequence on
every run.

Ground events start only once the capsule is standing. A door is a reset, and a fresh controller
spends one step finding the ground. Without this rule, every door would report a fall and a landing
the player never made.

## Reporting a name the graph does not declare

Writing a variable and raising an event both answer whether the graph declares the name. The bridge
records both answers instead of dropping the write. A graph that spells a name differently, such as
a mod or a non-player graph, shows as a named miss in the readout, not as movement that does
nothing. The vanilla `0_master.hkx` has no misses for all ten variables and all eleven events.

A bridge with no graph is a supported setup. Movement still works, and the writes are dropped.

`IsFirstPerson` is the one variable written per instance. It is false on the third-person graph and
true on the first-person one ([first person](/engine/first-person.md)).

## The Player & Locomotion panel

World > Player & Locomotion shows everything above, and every key the player can press is also a
control. It has five sections.

- State: where the capsule is, the resolved gait, which source moved it, and the gait speeds with
  their source. It repeats the camera mode selector from World > World > Camera, because the
  capsule and both graphs only run outside fly mode. Frozen values with no way to unfreeze them
  from the same screen would break the main-app UI rule.
- Behavior Graph: the active state path (machine, state, and the state blending out with its
  weight), every variable the bridge writes with the value the graph holds, the events raised, the
  events that came back, the names the graph does not declare, and the tally's coverage line. A
  variable the graph does not declare is listed as `<not declared by the graph>`, not hidden, so a
  spelling mismatch looks like a failure.
- Bindings: every movement key and its live state. Sneak is a toggle. Jump requests exactly one
  jump, the same request the space bar makes. Run and sprint are held keys, so their rows turn
  active while held.
- Root Motion: two running totals that cannot both grow in one step (graph root motion and gait
  speed), and a trace of the steps where the source changed. A button clears both.
- Dev Controls: hold one gait regardless of input, or raise one graph event by name. A held gait
  writes the graph's inputs and the gait speed and nothing else. The capsule keeps its gravity,
  ground, and collision, so a forced swim shows the swim clips on dry land. Raising an event uses
  the same path the bridge uses and says whether the graph declares the name.

A held gait is the panel's one change from default: the sidebar dot lights for it, and "Reset all"
releases it. The camera mode belongs to World > World and is not counted twice. Sneaking, jumping,
and raising an event are actions, not settings, so they do not light the dot.
