---
type: Subsystem
title: Actor package schedules
description: How an actor's AI package is picked from its ordered stack, when it is picked
  again, how its procedure tree and procedure machines run, and what is not done yet.
tags: [engine, ai, actors, packages, schedules, navigation]
---

# Actor package schedules

An AI package tells an actor what to do at a time of day, such as "sleep at home from 22:00".
This page explains how OpenSky picks the current package for each loaded actor. The record is
on the [packages](/formats/packages.md) page.

## Guard

The Guard procedure reads RestrictedArea, SuspiciousOf, WarnOnlyRadius, and
ImmediateAttackRadius, in that order (<https://ck.uesp.net/wiki/Guard_(Procedure)>). Both
radii are measured from the edge of the area. OpenSky guards only against the player:
SuspiciousOf is usually `PlayerFaction`, which names no single reference.

- Inside the immediate attack radius, the guard starts combat at once.
- Inside the warn radius, it draws its weapon (graph event `WeapEquip`) and says a `TRES`
  trespass line. It warns again every `fAITrespassWarningTimer` seconds (5), and attacks after
  `iGuardWarnings` warnings (2). Both come from the install. The CK wiki pages
  "FAITrespassWarningTimer" and "IGuardWarnings" give both uses.
- When the intruder leaves the warn radius, the count goes back to 0 and the guard sheathes
  (`Unequip`). Both event names were read from the human graph of the install.

`GetTrespassWarningLevel` reads the guard's count, including the warning being spoken. The
wiki names no exceptions OpenSky checks yet: owners, allies, and friends are warned too.
The graph event names are the vanilla ones as far as known; they are not in an open spec.

## Package lists

The AI Packages tab has more lists than the stack (<https://ck.uesp.net/wiki/AI_Packages_Tab>).
Each is a `FLST` of packages, read through the template chain with the same flag as the stack:
`DPLT` default, `SPOR` spectator, `OCOR` observe dead body, `GWOR` guard warn, `ECOR` combat.

The actor picks from the first list that gives a valid package:

1. A scene's packages, and nothing else while a scene holds the actor.
2. The script package, which `AddScriptPackage` gives (<https://ck.uesp.net/wiki/AddScriptPackage>).
   It needs no schedule or condition. Without "Must Complete" it goes at the next pick after it
   started; with it, it goes when its tree ends.
3. The override list of the situation the actor is in.
4. The quest alias packages, then the actor's own stack.
5. The default list.

The situations are code-driven behaviours. The wiki names them but not their ranges, so the
ranges are OpenSky's:

| Situation | When |
| --- | --- |
| Combat | The actor is engaged, or runs its combat override package and is still hostile |
| Spectator | Another actor fights within 2,048 units, and this one does not |
| Observe dead body | A dead actor lies within 1,024 units |
| Guard warn | Its Guard procedure has warned, until the warn package's tree ends |

A combat override package runs in place of combat: the combat loop treats the actor as one
whose package ignores combat. Only actors with an override list are checked, so the scan is
cheap in a crowd.

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

Two package flags change the pick. Source: <https://ck.uesp.net/wiki/Package_Flags>.

- Must Complete: the package stays picked until its procedure tree ends, whatever the
  schedule and conditions say. A scene package still takes over. A tree that never ends, such
  as a sandbox, keeps the package for good, as the wiki describes.
- Once Per Day: the package is not picked again within 24 game hours of the time it was first
  picked. When its tree ends, the actor picks again at once and skips it. The wiki notes that
  testing suggests the flag works only for a package with no start time and no duration.
  OpenSky applies it to every package, which changes nothing for a package with a schedule
  window, because the window has passed when the day is over.

`GetDisabled` reads a fixed snapshot of enable states: a runtime enable or disable wins,
otherwise the reference's "initially disabled" flag. This lets condition evaluation see enable
state without reaching into the live world state.

## Procedure machines

A procedure machine is a small state machine for one procedure. It sends commands to movement
and animation, and asks the world for every other act (`PackageAction`). It does not own any of
these systems. The parameter order of each procedure is the one on its Creation Kit wiki page,
for example <https://ck.uesp.net/wiki/Find_(Procedure)>. It was checked against the `BNAM`
input names of the vanilla templates.

| Procedure | Behavior |
| --- | --- |
| Travel, FollowTo | Move to the target, then finish |
| Patrol | Move to the start marker, then along its linked references, then finish |
| Orbit | Walk eight points round a circle between the two radii, as a patrol |
| Hover | Move to the place, raised by the height input, then finish |
| Wander | Pick seeded random points in a radius, wait 1 second, repeat |
| Sandbox | Timed activities in the place, and meals ([sandbox](/engine/sandbox.md)) |
| Sleep | Move to the target, then ask for a sleep loop |
| Eat | Move to the target, then ask for an eat loop |
| Sit | Move to a free seat of the target furniture, then sit; done when seated |
| UseIdleMarker | Move to the marker, then finish; the idle marker plays as in sandbox |
| Wait | Stay in place; with a time input, finish after it |
| HoldPosition, KeepAnEyeOn, FlightGrab | Move to the place, then stay there |
| Guard | Hold the place; warn an intruder, then attack (see below) |
| LockDoors, UnlockDoors | Lock or unlock the load doors in the place that the actor owns |
| Find | Look for matching references in the place; look again every 2 seconds |
| Acquire | Walk to the item, pick it up; try the next item of the list when one fails |
| Activate | Walk to the target, then activate it |
| Say | Speak one line of the topic, and finish when the line ends |
| ForceGreet | Wait for the player in the trigger place, walk up, open the conversation |
| DialogueActivate | Walk to the target, then turn the head to it for 3 seconds |
| Follow | Walk to the target each time it is out of range; sprint or sneak with it |
| Escort | Walk to the place; stop while the escorted actor is too far behind |
| Flee | Run to the place, or straight away from the threat until far enough |
| UseWeapon | Walk to the place, then start combat with the target |
| UseMagic, Shout | Walk to the place, then cast the spell, or the first word of the shout |

Where OpenSky differs from the game:

- ForceGreet opens the normal greeting. The package's own topic is not forced yet.
- DialogueActivate only turns the head. OpenSky has no conversations between two NPCs.
- UseWeapon can attack only by starting real combat, so it acts only when its
  "Allow Combat Start" input is true. Otherwise it fails.
- HoldPosition, KeepAnEyeOn, and FlightGrab hold the place. They do not look at the target
  or carry anyone.
- A follower sneaks while its target sneaks. It sprints while the target sprints, or while it
  is more than 300 units behind (`fFollowStartSprintDistance`,
  <https://ck.uesp.net/wiki/Follow_(Procedure)>). Only the player's gait is known, so a
  follower of an NPC sprints only to catch up.
- Followers of one leader keep `fFollowSpaceBetweenFollowers` (192 units) apart: a follower's goal
  moves away from each other follower that stands closer. A running follower slows on its last
  leg, down to `fFollowRunMinSlowdownMultiplier` (0.75) of its running speed. The CK wiki table
  names both settings with no use, so both uses are OpenSky's reading.
- A bumped actor leaves its package for a short time ([bump reactions](/engine/bump-reactions.md)).
- Find sees only references that are loaded now.
- Find selects by object type with the `PTDA` object type codes. Their names are not in an
  open spec. OpenSky reads them from how the vanilla templates use them: 10 furniture,
  11 weapon, 15 food, 26 bed, 27 chair. This is an inference, not a confirmed table.

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

A movement failure ends a walking machine as failed. An unsupported procedure also fails, on
purpose.
Random points are even over the area (the radius is `sqrt` of a random number), and use the same
seeded generator as conditions.

## Procedure tree

A template's branches form a tree ([packages](/formats/packages.md#procedure-tree)). OpenSky
rebuilds it from the flat list and runs it. The branch rules come from the Creation Kit wiki
page <https://ck.uesp.net/wiki/Category:Package_Templates>:

- Sequence runs its children in order. It fails when a child fails.
- Stacked runs the first child whose conditions are true.
- Random runs one child with true conditions, picked with the package's seeded generator.
- Simultaneous runs all its children at once. It ends when any child succeeds. A failed
  child stops alone, and the branch fails only when every child failed.
- A branch whose `PRCB` repeat flag is set starts again when it succeeds.
- A procedure with `FNAM` set ends the whole package when it succeeds.

Each procedure reads its parameters through its `PKC2` indexes. A Find writes what it found
into its third parameter, an object list. A later procedure that names the same input, such
as an Acquire, takes that list as its targets. A package with no branch list runs its own
procedure, with its first location and its first target as inputs.

Several procedures can run at once, but only one walks: the last one that asked for a move.
A seated Sit counts as success only when it has `FNAM`, so the vanilla `SitTarget` tree is
done once the actor sits.

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

Every simulated actor runs the procedure tree of its current package, whether the actor's own
schedule picked it or a scene or alias holds it. When the pick changes, the old tree stops: its
change fragment runs, a walk it started stops, and the new tree starts with its begin fragment.
A scene or alias package wins over the schedule while it holds the actor. When it lets go, the
schedule picks again and the new tree starts from its root.

The actor's own tree waits, and a new one starts after the wait:

- while a conversation or an arrest holds the actor,
- while the actor fights. A package with the Ignore Combat flag keeps the actor out of
  fights ([combat](/engine/combat.md#combat-state-is-derived)), so its tree runs on,
- while the actor is dead, for good,
- while the actor is a horse that walks its rider's package.

A sandbox procedure does not walk while the idle runtime has sent the actor to an idle marker
([idles](/engine/idle-runtime.md#marker-claim)). Its walk counts as done, so it waits and asks
again, and the marker's idles play.

Not done yet:

- Aliases and linked references as package locations. They are decoded, but need their quest
  and reference runtime first. A patrol start already resolves both.

A condition OpenSky cannot answer is false, with a reason. So an actor whose package depends on
such a condition will not pick it. Example: Heimskr's jail package before the siege of Whiterun.

When packages move actors, they will use the same movement path that already updates trigger
volumes, so triggers see the actor with no extra code.

## Scene packages

A scene's package action holds an actor ([scenes](/engine/scenes.md#package-actions)). While
it holds one, the selector picks from the action's packages, not from the actor's `PKID` list,
and picks again at once. When the action ends, the actor picks from its own list again.

A procedure's place is the package's first location input (`PLDT`). OpenSky can place
these kinds: near a reference, in a cell (the cell reference), a reference alias of the
scene's quest, near the actor itself, and the actor's editor location. The `move` command goes
to the NPC mover. The mover's arrival or give-up ends the move. A move that cannot start for
another reason, such as no path, fails the machine.

At most eight actors walk a path at once, to bound the cost with dozens of actors in a cell.
This limit is OpenSky's, not the game's. A move that finds all eight slots taken waits in a
queue, and the queue is asked again on each tick. Scene and alias walks go first, then the
others in the order they asked, so every actor gets a slot in the end. A waiting move searches
no path until a slot is free.

The action is done when the tree completes or fails. Travel completes on arrival. Wander,
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
package runs its begin fragment when its tree starts and its end fragment when the
machine completes. A failed machine runs no end fragment. The change fragment runs when the actor
leaves the package, whether it completed or not: another package replaced it, or its scene or
alias let the actor go, or a fight, a conversation, or death paused its tree. Each fragment
gets the actor as `akActor`. Layout: [VMAD](/formats/vmad.md).

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

The Package line shows the running procedures of every actor's current package, a schedule
package as well as a scene or alias one. The List line shows which list gave the package, the
situation, and any script package. Reevaluate picks the package again and starts its tree from
the root. The clock and conditions pick the package. To watch the schedule work, move the clock
in World > Runtime State > Time and press Reevaluate.

Add script package takes an editor ID or a FormID and does what `AddScriptPackage` does;
Remove does what `RemoveScriptPackage` does. This is the one way to set a package directly,
because the game has it too.
