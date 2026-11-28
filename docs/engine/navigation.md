---
type: Subsystem
title: Runtime navigation
description: The loaded navmesh graph, path search and the funnel, when a path is replaced,
  NPC path following, the movement cap, and the world-space debug overlay.
tags: [engine, world, navigation, navmesh, streaming, pathfinding, rendering, overlay]
---

# Runtime navigation

Navigation turns the decoded [navmesh](/formats/navmesh.md) into a graph that can be searched,
and moves NPCs along the paths it finds. The graph follows [cell streaming](/engine/cell-streaming.md).

## Loaded graph

The cell builder decodes each cell's `NAVM` records on its background queue. The cell scene owns
them. When a scene loads or is rebuilt, its navmeshes are added. When it leaves, its geometry and
doors are removed at once. This is the same rule physics uses.

A triangle is named by the pair (`NAVM` FormID, triangle index). Neighbors inside a navmesh come
from the triangle. An edge-link flag sends the neighbor through the navmesh's edge link table
instead. Such a link counts only while the other navmesh is loaded too, so a cell border never
leaves a path pointing at nothing. Deleted triangles and triangles with zero area are never used.

Door links are indexed by door reference. A pair of doors joined by `XTEL` becomes a teleport link,
but only while both door scenes are loaded.

## Search

A query puts its start and target feet onto the nearest valid triangle, measured in XY, and takes
Z from that triangle's plane. The nearest point can be on a face or an edge. The search reaches at
most 256 units and reports a miss instead of using far geometry. Equal distances are broken by
triangle ID.

A start or target with no triangle in that reach falls back to the highest walkable triangle
straight below it, within 1 unit in XY. An actor placed in the air, such as a creature placed at a
jumping player, then paths from the ground below. Its mover starts at the placed height, and the
character controller's gravity brings it down while it walks. Example: a creature placed 460 units
above the navmesh lands in under a second and walks to its target. A point with no navmesh below
it still misses.

A-star search runs over triangles:

- Crossing a shared edge costs the distance from the source center to the edge middle, plus from
  the edge middle to the target center.
- The estimate is the straight-line distance between centers. If the graph has a teleport door,
  the estimate is 0, because a door can be a shortcut through space and the estimate must never be
  too high.
- A door costs the two legs to and from the door, not the jump between them.
- A ledge edge link (type 1, ledge up, or type 2, ledge down) costs the walk to the edge middle,
  the jump to the nearest point of the target triangle, the walk on, and 128 more units. So a
  path walks around a ledge when the way round is short. The 128 is OpenSky's own number.
- A leg inside a water triangle (triangle flag bit 9) costs 4 times its length, and a step from a
  land triangle into a water triangle costs 5 times. So a path swims only where walking round is
  far longer.
- Ties are broken by total estimate, then remaining estimate, then triangle ID. So the result is
  the same every time.

The search reuses its heap and tables between queries.

The path holds its waypoints, its door crossings, the nodes searched, and the triangle count. It
also keeps the state of the cells it passes and the original target, to tell when it is out of
date.

## Funnel

The corridor's shared edges become portals. Each portal end moves inward by the capsule radius. A
portal narrower than two radii shrinks to its middle point. The funnel algorithm then pulls the
shortest line through the portals. A door ends the current funnel part, adds the door point, and
starts a new part at the paired door. A ledge does the same: the funnel part ends at the edge
middle, and the next part starts at the landing point.

## Replacing a path

A path is current while every cell on it has the same state as when it was found, and the target
has moved less than 64 units. An unload, a rebuild, or a larger target move queues a new search.
Requests merge per follower and keep their order. At most two are run per frame. Direct queries
for user actions and inspection are not limited.

## NPC path following

At most eight NPCs move at once. A mover exists only after a path is found. An actor with no
target has no capsule, controller, or work.

Each mover has a standard actor capsule and its own walk controller. It uses the same 120 Hz steps,
terrain, collision, slope rules, and sliding as the player ([walk mode](/engine/walk-mode.md)). A
long frame is clamped to 100 ms, so it cannot jump.

- The mover turns toward the next waypoint, at most one full turn per second.
- It sends the same movement intent the player does: forward, with a gait. A package whose
  "preferred speed" flag (`PKDT` general flag `0x2000`) is set picks the gait: walk and fast walk
  walk, jog and run run. Example: Lokir's escape package in the opening sets the flag and run.
  Without the flag, a leg longer than 512 units runs and a shorter one walks.
- An NPC has only the walk and run gaits, so jog plays the run and fast walk the walk. Their speed
  sits between the two, as the blend below gives.
- [WARNING] The 512-unit rule is OpenSky's choice; the game's default speed rule is not documented.
- A gait's speed is the forward walk or run of the movement type (`MOVT` `SPED`) that the actor's
  graph state names: `iState` 60 is `iState_HorseDefault`, so a horse uses the `MOVT` named
  `HorseDefault`, walk 125.11 and run 450. Without a graph state, the race's own walk type
  (`RACE` `WKMV`) is used, then the default `NPC_Default_MT`, walk 80.1 and run 370 ([actor state
  graph](/engine/actor-state-graph.md#how-the-game-picks-istate)).
- A race can replace a type's speeds: an `MTYP` with a `SPED` after it in the `RACE` record gives
  that race its own speeds for that type. Example: `ChickenRace` walks `Chicken_Default_MT` at
  34.71 and runs at 251.94.
- The speeds are multiplied in this order:
  1. the actor's scale times its [height](/engine/actor-resolution.md#height);
  2. the size of `SpeedMult` over 100, where 0 counts as 100;
  3. on a run only, the worn weight share of [walk mode](/engine/walk-mode.md#speed). The run
     never drops below the walk. Example: a run of 450 and a walk of 125 at share 0.7 give 315.
  An actor that cannot run walks instead. The player cannot run over its carry weight. An NPC
  has no carry weight check.
- An NPC's weapon counts as drawn while it fights. The game blends the speed s
  between gaits, with W the walk and R the run: s up to 1 gives s × W, s from 1 to 2 gives (2 − s) ×
  W + (s − 1) × R. Fast walk is 1.25 and jog is 1.5 (clean-room read of `SkyrimSE.exe`, 2026-11-07).
- The game changes an actor's speed toward its goal at a bounded rate: each frame by at most dt
  times the acceleration, or dt times the deceleration when it slows. The race's acceleration and
  deceleration rates (`RACE` `DATA`) divide these; a rate whose size is at most 0.0001 counts as
  1. Combat doubles both.
  Nord and horse races have rate 1. [WARNING] The base rate in units per second squared was not
  found, so an OpenSky NPC reaches its new speed at once.
- Turning to face a point stops within the race's angular tolerance (degrees). With a bow,
  staff, or crossbow, `fAIUseWeaponToleranceDegrees` (10) is used instead. In combat the
  turn accelerates at `(1 / angular acceleration rate) * fCombatPathingRotationAccelerationMult`
  (2.0), and turns at `fCombatPathingNormalizedRotationSpeed` (2.25).
- A race with `DATA` flag `0x200` is immobile: AI movement never starts for it, and movement
  and teleport code treat it as unable to move.
- While an actor flies, path requests use the race's flight radius times its scale.
- A waypoint counts as reached within 12 units.
- At a door, the mover reaches the door point, reports the door, and moves its capsule to the
  paired door.
- At a ledge crossing, the mover leaves its walk controller and follows an arc to the landing
  point. The arc peaks 32 units above the higher end. It takes the horizontal distance over the
  run speed, between 0.35 and 1.2 seconds. The controller starts again at the landing.
- In water, the mover swims by the player's rule
  ([ground and water contact](/engine/ground-and-water-contact.md#water)), with float level 1.6.
  It walks out where the ground rises under it. A swimmer uses the swim gait and the swim speed,
  and reaches a waypoint on the bed below it.
- Walkers steer around each other, and around the player and standing NPCs. Actors are not
  collision shapes, so this bends the walk direction instead. A neighbour ahead, within 96 units
  past touching, turns the walker to the side away from it. A neighbour dead ahead is passed on
  the right, so two actors walking at each other both turn right. Two that overlap push apart.
  A marker another actor stands on counts as reached, or both would wait for it. A rider, the
  player included, is not a neighbour: it takes up its vehicle's space. Otherwise a horse steers
  away from the rider in its own saddle. These rules are OpenSky's own.

Progress is the distance to the next waypoint. Getting at least one unit closer resets the stuck
timer. After two seconds with no progress, the mover searches again once, from where it is to the
original target. A second stall, or a failed search, gives up. There is no loop of retries.

## Blocked walks

The game checks a walker that cannot go on in three ways. None of them ends the package.

- Steering. Each frame the walker checks whether its wanted direction hits something within
  1 s, and at least 0.25 s ahead. If it does, it tries a few other headings and may slow to half
  speed. It takes a clear heading, and its blocked time goes back to 0. With no clear heading it
  keeps pushing in its wanted direction, and the frame time adds to its blocked time.
- Other actors. The walker watches up to 10 actors within its speed times 3 s, kept between
  256 and 512 units, plus half its own radius. An actor slower than 5 units a second counts as
  standing. A standing actor, or one watched for over 1 s, gets an avoid zone of its radius
  plus 11 units, and the path is planned again around it. A walker blocked for over 1 s by
  actors without a zone fails its path.
- Stuck check. Over a window of at least 1 s the game compares where the walker wanted to go
  with where it went. Less than 10% of the wanted move counts as stuck. When the wanted move
  was small, at most 0.66 times the walker's radius, path following only starts again.
  Otherwise the path fails, and an avoid zone goes just ahead of the walker, so the next path
  goes round that spot. A cart is not an actor, so a horse behind a cart meets this check.

None of the three runs within about half the walker's radius of the path's end. A search that
finds no route also fails the path. A walk has no overall time limit. Repeated failures at one
spot lead to the fallback in [a walk whose path fails](#a-walk-whose-path-fails).

A Patrol procedure does not fail when its path fails. On a later update it asks for a new walk
to the same point. It does not skip the point and does not turn back, so a blocked horse stands
and pushes against what blocks it. A point is reached when the path completes, or when the
walker is within the patrol radius plus 50 units across and about 180 units up or down. A
walker blocked just short of a point therefore goes on. A patrol fails only when its start
reference, its point list, or its current point cannot be found. A running or resumed patrol
keeps its points and its place along them. A new package starts at the start point, or at the
nearest point when Start At Nearest is set. Riders and towed carts have no rules of their own.

Example: in the Helgen opening the second cart's horse reaches the first cart, which waits at
the gate. The horse stands behind it and asks for the same point again until the way is free.

OpenSky keeps its own stuck rule above: two seconds without progress, one new search, then the
walk gives up. A Patrol then walks to the same point again on the next update. Other procedures
fail as [package schedules](/engine/package-schedules.md#in-a-session) describes.

## A walk whose path fails

The game counts path failures per actor. A path that works sets the count to 0. A failure
more than 50 units from the last one starts the count again at 1, so only failures at about the
same spot add up.

At 3 failures the game asks for two fallback paths to the goal, one of them for a very thin
actor of radius 5. It takes a point on the path that works, 100 units back along it. The actor
is moved to that point as soon as the point is off screen, or after 5 seconds.

A patrol walks to the same point again ([blocked walks](#blocked-walks)). The
Activate procedure plans the path again on later updates, with no time-out
([activate procedure](/engine/activate-procedure.md#a-blocked-path)). Whether a travel package ends
after a failure was not found.

## Position and triggers

While an actor walks, drawing, melee targeting, and combat read the mover's position. The saved
transform is written only at four moments: arrival, giving up, entering a new navmesh cell, and
just before a save. The cell builder applies saved transforms to actors too, so a rebuilt actor
starts where it was. No fixed step writes it.

A walk or a turn starts where the actor is drawn. That is the mover's own pose when it has one.
After a load the movement runtime is empty, so it is the saved transform, and only then the
placed `ACHR`.

The published heading follows the placement rule: `angleZ` turns clockwise from north
([player camera](/engine/player-camera.md)). A walk direction is an angle counter-clockwise from
+X, so the heading is a quarter turn minus the walk angle. An actor that walks east is drawn
facing east.

### Standing height

An `ACHR` height can sit inside the road or floor mesh the actor stands on. In Helgen, the
prisoners are placed up to a knee deep in the cobbled road. The game's character controller
pushes an actor out of the floor. The cell build does the same: it lifts an actor onto the
highest walkable static surface above its feet, up to half the actor capsule. A floor higher than
that is a roof or a bridge over the actor, so the actor stays where it is. An actor is never
moved down.

Each moving actor checks which trigger volumes it is in once per frame. The trigger event carries
the actor when it is not the player, so scripts get that actor as `akActionRef`. When a move ends,
the actor leaves any volumes it is still in.

## Animation and the cap

Movement and animation meet in one value: actor, direction, gait, yaw, and frame time. It has no
writable transform, so a later combat or package system can use it without becoming a second owner
of movement. The app plays `mt_walkforward.hkx` or `mt_runforward.hkx` for the actor's gender. The
clips play in place while the capsule moves the actor. Combat clips still interrupt and return
([actor animation](/engine/actor-animation.md)).

Movers are capped at eight, with a 2 ms CPU budget for all of them in a 16.67 ms frame. Why NPCs
use in-place clips instead of full behavior graphs was measured, not guessed: eight vanilla
behavior graphs cost more than the whole 2 ms budget even in an optimized build, before
collision, paths, triggers, or drawing. The clip drive uses a small part of the budget.
`make test PLAN=Perf` measures both ([testing](/testing.md)).

## Debug overlay

The renderer keeps an ordered list of overlay sources. Each frame, a source can add colored
triangles, lines, or polylines to a draw list. Replacing a source keeps its place in the order.

The navigation source reads the same graph as the search. It fills triangles with one color per
cell, highlights the latest current corridor, and draws its waypoint line. A small lift in Z stops
flicker against the ground. Both toggles are off by default.

The overlay pass draws triangles, then lines, with premultiplied alpha and a read-only
"less or equal" depth test. It runs after the 3D scene and before the UI, both on screen and
offscreen. It draws at most 65,536 primitives per frame, and counts what it drew and dropped.
`openskycli render --navmesh-overlay` captures it ([CLI](/tools/cli.md)).

## What the game does the same way

The game also jumps only at ledge links: it has no jump over a gap or an obstacle the navmesh
does not link. A swim also follows the navmesh, which covers water surfaces with water triangles,
so an NPC crosses open water only where that navmesh exists. The game splits a path at each
ledge and at each land and water crossing, as OpenSky does. The water costs above come from the
same read (clean-room read of `SkyrimSE.exe`, 2026-11-07).

## Swimming after the player

The game has a store per follower for the player's swim path, so a follower with no water navmesh
can swim after the player. How the game fills and uses it was not traced. OpenSky keeps one trail:
while the player swims, it drops a point every 128 units and keeps the last 64. When a move finds
no navmesh path, and its target is within 512 units of the newest point, the actor joins the trail
at its nearest point, within 1,024 units, and swims along it to the target.
Leaving the water keeps the trail, so a follower left on the far bank still crosses.
