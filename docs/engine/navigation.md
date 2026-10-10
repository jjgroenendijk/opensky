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
- It sends the same movement intent the player does: forward, with a gait. A leg longer than 512
  units runs. A shorter one walks.
- A waypoint counts as reached within 12 units.
- At a door, the mover reaches the door point, reports the door, and moves its capsule to the
  paired door.
- At a ledge crossing, the mover leaves its walk controller and follows an arc to the landing
  point. The arc peaks 32 units above the higher end. It takes the horizontal distance over the
  run speed, between 0.35 and 1.2 seconds. The controller starts again at the landing.
- In water, the mover swims with the player's depths: water at least 90 units deep over its feet
  starts a swim, and less than 70 ends it. A swimmer floats at the surface, uses the swim gait
  and the swim speed, and reaches a waypoint on the bed below it.
- Walkers steer around each other, and around the player and standing NPCs. Actors are not
  collision shapes, so this bends the walk direction instead. A neighbour ahead, within 96 units
  past touching, turns the walker to the side away from it. A neighbour dead ahead is passed on
  the right, so two actors walking at each other both turn right. Two that overlap push apart.
  A marker another actor stands on counts as reached, or both would wait for it. These rules are
  OpenSky's own.

Progress is the distance to the next waypoint. Getting at least one unit closer resets the stuck
timer. After two seconds with no progress, the mover searches again once, from where it is to the
original target. A second stall, or a failed search, gives up. There is no loop of retries.

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
`make test-real PERF=1` measures both ([testing](/testing.md)).

## Debug overlay

The renderer keeps an ordered list of overlay sources. Each frame, a source can add colored
triangles, lines, or polylines to a draw list. Replacing a source keeps its place in the order.

The navigation source reads the same graph as the search. It fills triangles with one color per
cell, highlights the latest current corridor, and draws its waypoint line. A small lift in Z stops
flicker against the ground. Both toggles are off by default.

The overlay pass draws triangles, then lines, with premultiplied alpha and a read-only
"less or equal" depth test. It runs after the 3D scene and before the UI, both on screen and
offscreen. It draws at most 65,536 primitives per frame, and counts what it drew and dropped.
`openskycli screenshot --navmesh-overlay` captures it ([CLI](/tools/cli.md)).

## Not done yet

Movers do not jump over an obstacle the navmesh does not link with a ledge. A swim follows the
navmesh path, so water with no navmesh under it is not crossed.

## Controls

World > AI & Navigation has three sections:

- Overlays: navmesh and path toggles, and a readout of what was drawn and dropped.
- Actor: pick the actor the rest of the panel is about, from a list or under the crosshair.
- Movement: send the actor to the crosshair point, stop it, and read its state, waypoint, gait,
  and search count.

The move target is where the crosshair ray hits, put on the nearest triangle by the path search.
The ray reaches 4096 units, and works in any camera mode. It is longer than the use key's reach,
because sending an actor across a market is an inspection, and arm's length would only send it to
its own feet. It is no longer than needed, because the collision search box grows with it. The
result is cached for the current camera pose, so several panel sections reading it twice a second
cost one raycast.
