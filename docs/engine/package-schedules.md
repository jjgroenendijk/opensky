---
type: Subsystem
title: Actor package schedules
description: How an actor's AI package is picked from its ordered stack, when it is picked
  again, the simple procedure machines, and what is not done yet.
tags: [engine, ai, actors, packages, schedules, navigation]
---

# Actor package schedules

An AI package tells an actor what to do at a time of day, such as "sleep at home from 22:00".
This page explains how OpenSky picks the current package for each loaded actor. The record is
on the [packages](/formats/packages.md) page.

## Picking a package

An actor's packages come from its `PKID` list. The list follows the template chain only when the
AI packages template flag is set (see [actor records](/engine/actor-resolution.md#template-chain)).
A local empty list stays empty when the flag is clear.

OpenSky walks the list in record order. It picks the first package whose `PSDT` schedule matches
the time and whose conditions are true.

A package can have a template chain. The package itself still owns the schedule and conditions.
The last template in the chain gives the procedure kind. A missing package is skipped while
picking. A missing template or a loop in the chain is an error.

## When to pick again

Picking happens on events, not every frame. The next pick is at the earliest of:

- the exact start or end of a daily schedule,
- 15 game minutes after the last pick, to catch calendar and condition changes,
- the clock moving backwards.

A callback fires only when the picked package changes.

`GetDisabled` reads a fixed snapshot of enable states: a runtime enable or disable wins,
otherwise the reference's "initially disabled" flag. This lets condition evaluation see enable
state without reaching into the live world state.

## Procedure machines

A procedure machine is a small state machine. It sends commands to movement and animation. It
does not own either system.

| Procedure | Behavior |
| --- | --- |
| Travel | Move to the target, then finish |
| Wander | Pick seeded random points in a radius, wait 1 second, repeat |
| Sandbox | Pick seeded random points in a radius, wait 4 seconds, repeat |
| Sleep | Move to the target, then ask for a sleep loop |
| Eat | Move to the target, then ask for an eat loop |

A movement failure ends the machine as failed. An unsupported procedure also fails, on purpose.
Random points are even over the area (the radius is `sqrt` of a random number), and use the same
seeded generator as conditions.

## In a session

On each world tick, the app adds actors that came into range and removes those that left. New
actors are picked against the live clock, quest and actor state, and enable state.

Not done yet:

- Sending procedure commands to movement and animation.
- Aliases and linked references as targets. They are decoded, but need their quest and
  reference runtime first.
- The branch graph inside a procedure tree.

A condition OpenSky cannot answer is false, with a reason. So an actor whose package depends on
such a condition will not pick it. Example: Heimskr's jail package before the siege of Whiterun.

When packages move actors, they will use the same movement path that already updates trigger
volumes, so triggers see the actor with no extra code.

## Controls

World > AI & Navigation > Package shows the selected actor's current package, its editor ID, its
procedure, and its schedule as a start time and duration.

The only control is Reevaluate, on purpose. The clock and conditions pick the package. A control
that set a package directly would show a state the schedule never makes. To watch the schedule
work, move the clock in World > Runtime State > Time and press Reevaluate.
