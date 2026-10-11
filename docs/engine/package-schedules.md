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
| Sit | Move to a free seat of the target furniture, then sit; done when seated |
| Wait | Stay in place and send no move, until another package wins |

A patrol walks each leg as a straight line when its "Static Pathing?" input is true, and on
the navmesh otherwise. A straight leg ignores static walls, so a rock or a fallen log on the
authored line does not stop it. It still stands on a static floor, such as a road or a bridge,
when the floor is within a step of its feet and within a step of the leg's line between its two
markers. The second limit matters where the line passes through a rock: without it, the rock's
ledges lift the walker a step at a time onto the rock's top. On the opening ride, both cart horses
climbed onto a rock arch above the road this way and stopped. This is a guess at the game's
behavior, not a confirmed rule. That input is the last of the Patrol procedure's six inputs, by the
`BNAM` names in the vanilla `PatrolStaticPathing` template. The opening's cart horses use it.

A package whose "Ride Horse if possible?" input is true rides the actor's horse, when the actor
has one ([vehicles](/engine/vehicles.md#riders)). The horse then walks the package, and its
arrivals move the rider's package on. The Travel and Patrol templates both have this input. It is
found by its `BNAM` name in the template, because its index differs: 2 in Travel (`00016FAA`), 6
in Patrol (`00017723`), read on the install. A package without the input, or with it false, takes
the rider off, and the horse stops where it is. In the opening, the riders wait on their horses
with a travel package (`MQ101TulliusHoldPosition`) before their patrols start.

A walk over an exterior cell whose terrain is not loaded slides along its path line instead of
falling. Without this, an actor ahead of the loaded area falls through the world.

A movement failure ends the machine as failed. An unsupported procedure also fails, on purpose.
Random points are even over the area (the radius is `sqrt` of a random number), and use the same
seeded generator as conditions.

## Furniture

A furniture mesh marks where an actor sits with its `BSFurnitureMarkerNode` block
([NIF](/formats/nif.md#bsfurnituremarkernode)). Each marker is one seat. The `FURN` record lists
the same markers by index (`ENAM`), and a marker can carry a keyword (`FNMK`). A sit package
picks its seat by these rules:

- A seat with a keyword is only for an actor whose base `NPC_` has that keyword (`KWDA`).
- An actor with a matching keyword takes that seat first. Otherwise it takes a free seat with
  no keyword.
- Two package actors never share a seat.

On arrival the actor is set at the seat's point, facing the marker heading plus the
reference's own z rotation. Then the furniture is activated by the actor, so its scripts get
`OnActivate`. A Creation Kit template whose procedure tree holds "Sit" is a sit package, even
when the tree also holds "Wait", because the vanilla `SitTarget` tree is
Sequence[Sit, Simultaneous[Sit, Wait]].

Example: `ExecutionerChoppingBlock` (`FURN` `0002E8EB`) has three markers. Marker 0 has the
keyword `isExecutioner` and marker 2 `isExecutionerGuard`; marker 1 has none, so the prisoner
gets it. The keyword rule is OpenSky's reading of the record. The entry points and the sit
animations are not used yet: the actor appears in the seat and plays no sit idle.

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
the move. At most eight actors walk a path at once, to bound the cost. A move that finds all
eight slots taken waits and is asked again on each tick; this limit is OpenSky's, not the
game's. A move that cannot start for another reason, such as no path, fails the machine.

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
through cells that are not loaded.

The patrol template's four Bool inputs are "Repeatable?", "Start At Nearest?", "Ride Horse if
Possible?", and "Static Pathing?". A repeatable patrol walks from its last marker back to its first
and goes on. Each lap ends the package: the end fragment and `OnPackageEnd` run, and a scene action
that waits for the package is done. The actor keeps walking for as long as it holds the package,
which is the Creation Kit wiki's note on `OnPackageEnd`. A one-marker patrol has no lap and ends.
"Start At Nearest?" starts the walk at the marker nearest the actor. A repeatable patrol walks the
markers it skipped on the way round. A plain one drops them.

The `MQ101` cart horse patrols are not repeatable (`0, 0, 0, 1`: static pathing only), so the carts
stop at the end of each leg.

The cart horses of `MQ101` drive the opening this way. Their patrols run the carts from the
start of the game into Helgen. A trigger box on the road sets a stage when a horse walks
through it.

## Package fragments

A package can carry Papyrus fragments in its `VMAD` (flag 0x01 begin, 0x02 end, 0x04 change). A
held package runs its begin fragment when its machine starts and its end fragment when the
machine completes. A failed machine runs no end fragment. The change fragment runs when the actor
leaves the package, whether it completed or not: another package replaced it, or its scene or
alias let the actor go. Each fragment gets the actor as `akActor`. Layout: [VMAD](/formats/vmad.md).

The same three moments queue `OnPackageStart(akNewPackage)`, `OnPackageEnd(akOldPackage)`, and
`OnPackageChange(akOldPackage)` on the actor's own scripts. Source: the Creation Kit wiki pages for
the three events. An actor that unloads leaves its package with no change event.

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
