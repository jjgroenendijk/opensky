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
| Patrol | Move to the start marker, then along its linked references, then finish |
| Wander | Pick seeded random points in a radius, wait 1 second, repeat |
| Sandbox | Pick seeded random points in a radius, wait 4 seconds, repeat |
| Sleep | Move to the target, then ask for a sleep loop |
| Eat | Move to the target, then ask for an eat loop |

A patrol walks each leg as a straight line when its "Static Pathing?" input is true, and on
the navmesh otherwise. A straight leg follows the terrain and ignores static collision, so a
rock or a fallen log on the authored line does not stop it. This is a guess at the game's
behavior, not a confirmed rule. That input is the last of the Patrol procedure's six inputs, by the
`BNAM` names in the vanilla `PatrolStaticPathing` template. The opening's cart horses use it.

A patrol whose "Ride Horse if Possible?" input is true rides the actor's horse, when the actor
has one ([vehicles](/engine/vehicles.md#riders)). The horse then walks the patrol, and its
arrivals move the rider's patrol on. A package without the input takes the rider off.

A walk over an exterior cell whose terrain is not loaded slides along its path line instead of
falling. Without this, an actor ahead of the loaded area falls through the world.

A movement failure ends the machine as failed. An unsupported procedure also fails, on purpose.
Random points are even over the area (the radius is `sqrt` of a random number), and use the same
seeded generator as conditions.

## In a session

On each world tick, the app adds actors that came into range and removes those that left. New
actors are picked against the live clock, quest and actor state, and enable state.

Not done yet:

- Sending procedure commands to movement and animation for packages the schedule picks from
  the actor's own list. Only scene and alias packages run their machine.
- Aliases and linked references as package locations. They are decoded, but need their quest
  and reference runtime first. A patrol start already resolves both.
- The branch graph inside a procedure tree.

A condition OpenSky cannot answer is false, with a reason. So an actor whose package depends on
such a condition will not pick it. Example: Heimskr's jail package before the siege of Whiterun.

When packages move actors, they will use the same movement path that already updates trigger
volumes, so triggers see the actor with no extra code.

## Scene packages

A scene's package action holds an actor ([scenes](/engine/scenes.md#package-actions)). While
it holds one, the selector picks from the action's packages, not from the actor's `PKID` list,
and picks again at once. When the action ends, the actor picks from its own list again.

Only a held actor runs its procedure machine. The machine's place is the package's first
location input (`PLDT`). OpenSky can place these kinds: near a reference, in a cell (the cell
reference), a reference alias of the scene's quest, near the actor itself, and the actor's
editor location. The `move` command goes to the NPC mover. The mover's arrival or give-up ends
the move. A move that cannot start fails the machine.

The action is done when the machine completes or fails. Travel completes on arrival. Wander,
sandbox, sleep, and eat never complete. An unsupported procedure fails at once.

### The player in a scene package

The player has no NPC mover. After a script calls `SetPlayerAIDriven(true)`, a scene package
can hold the player too, with the base `Player` (`NPC_` 0x000007). A move finds a navmesh path, as an
NPC's move does, then turns the view to each waypoint and holds forward. The player's own
capsule and walk speed carry the player. A straight leg of a static-pathing patrol ignores static
collision, as an NPC's does. Arrival within 40 units of the last waypoint ends the
move. `MQ101` uses this after the cart ride: Scene4 walks the
player to `MQ101PlayerMoveLineMarker1`, then sets stage 75, which opens the race menu.

## Alias packages

A quest alias can add packages to the actor in it (`ALPC`). While the quest runs, the selector
picks from the alias packages first, then from the actor's own list. When several running quests
hold the actor, the quest with the highest priority gives the packages. Source: the Creation Kit
wiki page "Quest Alias Tab".

An alias package runs its machine, as a scene package does. A patrol's start marker is its first
single-reference input (`PTDA`): a reference, or a reference alias of the quest. The path is the
start marker, then each unkeyed linked reference (`XLKR`) after it, until the chain ends or comes
back to a marker it already passed. OpenSky reads the markers from the plugins, so a path can go
through cells that are not loaded. A patrol does not repeat yet, even when its "Repeatable?" input
is true.

The cart horses of `MQ101` drive the opening this way. Their patrols run the carts from the
start of the game into Helgen. A trigger box on the road sets a stage when a horse walks
through it.

## Package fragments

A package can carry Papyrus fragments in its `VMAD` (flag 0x01 begin, 0x02 end, 0x04 change). A
held package runs its begin fragment when its machine starts and its end fragment when the
machine completes. A failed machine runs no end fragment. Each fragment gets the actor as
`akActor`. The change fragment does not run yet. Layout: [VMAD](/formats/vmad.md).

`GetOwningQuest()` in a package fragment answers the package's owner quest, `PACK` `QNAM`. The
end fragments of the `MQ101` cart patrols set the stages that unload the carts this way.

## When a walk ends

A walk that ends reports its rest pose after the movement runtime has stored its own state. A
listener may start the next move right away, as a patrol does at each marker. If the report came
during the runtime's update, that update would write back its older copy and drop the new move.

## Walking into another cell

An actor that walks into another cell moves into that cell's references, the way `MoveTo` moves
one ([reference identity](/engine/reference-identity.md#moved-references)). The cell it left is
rebuilt without it. Without this, a horse that walked far from its plugin cell would vanish when
that cell unloads. A vehicle follower, such as a cart, does the same when its pose enters
another loaded cell ([vehicles](/engine/vehicles.md)).

## Controls

World > AI & Navigation > Package shows the selected actor's current package, its editor ID, its
procedure, and its schedule as a start time and duration.

The only control is Reevaluate, on purpose. The clock and conditions pick the package. A control
that set a package directly would show a state the schedule never makes. To watch the schedule
work, move the clock in World > Runtime State > Time and press Reevaluate.
