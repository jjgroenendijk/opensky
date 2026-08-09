---
type: Subsystem
title: Runtime navigation
description: Resident navmesh graph, deterministic pathfinding, and the world-space
  navmesh and path debug overlay.
tags: [engine, world, navigation, navmesh, streaming, pathfinding, rendering, overlay]
timestamp: 2026-08-09T00:00:00Z
---

# Runtime navigation

Issue #200 turns decoded [NAVM geometry](/formats/navmesh.md) into a queryable graph whose
lifetime follows [cell streaming](/engine/cell-streaming.md). Issue #423 adds the first
consumer: capped NPC capsule movement over those corridors.

## Contents

* [Resident graph](#resident-graph)
* [Projection and search](#projection-and-search)
* [Funnel and clearance](#funnel-and-clearance)
* [Invalidation and budget](#invalidation-and-budget)
* [NPC path following](#npc-path-following)
* [Position, triggers, and handoff](#position-triggers-and-handoff)
* [Locomotion drive and cap](#locomotion-drive-and-cap)
* [World-space debug overlay](#world-space-debug-overlay)
* [Evidence and remaining gaps](#evidence-and-remaining-gaps)

## Resident graph

`CellSceneBuilder` decodes the NAVM records in each cell's persistent and temporary child
groups on its existing off-main build queue. A `CellScene` owns those immutable navmeshes
beside its render and collision data. `CellStreamer.reconcileNavigation` uses the same
location and state-sequence comparison as physics: it adds a newly resident or rebuilt
scene, and removes geometry and doors as soon as their scene departs.

Triangles use the stable pair `(NAVM FormID, triangle index)` as their runtime identity.
Local neighbours come from the triangle, while an edge-link flag redirects the neighbour
index through the NAVM edge-link table. That target is usable only when its navmesh is also
resident, so a cell boundary cannot leave a dangling path. Deleted and zero-area triangles
never project or participate in a transition. Door links are indexed by door reference;
paired `XTEL` references become explicit teleport transitions only while both door scenes
are resident.

## Projection and search

A query projects its start and target feet positions onto the closest valid triangle in XY,
then reconstructs Z from that triangle's plane. The closest point can lie on a face or an
edge. Search is bounded to 256 engine units by default and reports a start or target miss
instead of choosing distant geometry. Equal-distance candidates resolve by triangle
identity.

Deterministic A-star searches triangles. A shared-edge transition costs the distance from
the source centroid to the edge midpoint plus the distance from that midpoint to the target
centroid. Its heuristic is straight-line centroid distance. If the resident graph contains
a teleport door, the heuristic becomes zero so a world-space shortcut cannot make it
inadmissible; a door transition charges the two centroid-to-door legs but not the teleported
gap. Open entries tie-break by total estimate, remaining estimate, then triangle identity.
The binary heap, score maps, predecessor map, closed set, and corridor buffers retain their
capacity across queries.

The returned `NavigationPath` contains waypoints, door reference plus waypoint-index
crossings, nodes expanded, and triangle count. It also retains the corridor's cell sequence
snapshot and original target for exact invalidation.

## Funnel and clearance

The corridor's shared edges become oriented portals. Each endpoint moves inward by the
query capsule radius, which defaults to `PlayerCapsule.standard.radius`; a portal narrower
than twice the radius collapses to its midpoint. The deterministic funnel algorithm then
pulls the shortest polyline through those reduced portals. A door marker ends the current
funnel segment, emits the authored door point and crossing, and starts a new segment at the
paired door when the link teleports.

## Invalidation and budget

A path is current while every corridor cell still has the captured state sequence and the
target remains within the default 64-unit tolerance. An unload, rebuild, or larger target
move queues a replacement. Requests de-duplicate by follower identifier and keep insertion
order; `CellStreamer.maximumNavigationRepathsPerFrame` limits work to two replacements per
frame. Immediate `findPath` and projection calls remain available for user-driven queries
and inspection.

## NPC path following

`NPCMovementRuntime` owns at most eight `NPCMover` values. A mover is created only after
`MoveToPointControl.moveActor(_:to:)` finds a corridor; an actor with no destination owns no
capsule, controller, graph, or per-frame work. Each mover has a standard actor capsule and
its own `WalkController`, advanced through the same 120 Hz accumulator, terrain sampler,
static collision query, slope response, and collide-and-slide path the player uses. A long
rendered frame is clamped to 100 ms by the controller rather than becoming a teleport.

The next waypoint defines a world-space direction. Facing turns toward it by at most one
full revolution per second, and the mover publishes the same `LocomotionIntent` semantics
as the player (`moveForward = 1`, plus the resolved gait). A leg more than 512 units away
uses run speed; shorter legs use walk speed. The waypoint tolerance is 12 units. At a door
crossing the mover reaches the authored source waypoint, reports the door reference, and
resets its capsule at the paired destination waypoint before continuing. Jumping, swimming,
and destinations requiring either remain unsupported rather than silently bypassing the
navmesh.

Progress is distance to the current waypoint. Improving it by at least one unit resets the
stuck clock. Two seconds without such progress makes one replacement query from the capsule's
resolved position to the original target. A second two-second stall, or a replacement miss,
records `gaveUp`; there is never a repath loop.

## Position, triggers, and handoff

Live rendering, melee targeting, and combat observation read the mover transform while an
actor is walking. `ReferenceTransformOverride` is written only at four named boundaries:
arrival, give-up, a change in the projected navmesh cell, and immediately before a save.
The cell build now applies transform overrides to ACHR assembly as well as REFR assembly, so
the journalled placement becomes the rebuilt actor baseline. No fixed step writes the
journal.

Each active actor diffs its own trigger-volume set once per rendered movement frame. The
ordinary `TriggerTransitionEvent` now carries the occupying actor when it is not the player,
so `PapyrusWorldStateBridge` sends that actor's handle as `akActionRef`. Finishing a move
emits leaves for any volumes the actor still occupies. Player occupancy remains unchanged.

## Locomotion drive and cap

Travel and animation meet at `NPCLocomotionDriveUpdate`. The value contains actor identity,
directional intent, gait, yaw, and frame delta but no writable transform, so a later combat
or package drive can raise events without becoming a second movement authority. The current
app drive selects the observed gendered `mt_walkforward.hkx` and `mt_runforward.hkx` clips
on `ActorAnimationPlayback`; those clips animate in place while the capsule supplies travel.
Bounded combat overrides still interrupt the gait clip and return to it afterward.

The simultaneous-mover cap is `NPCMovementRuntime.maximumSimultaneousMovers` (eight), with
a named 2 ms CPU slice for all mover work in a 16.67 ms frame. The vanilla
graph-versus-kinematic decision and measured costs are recorded under evidence below rather
than treated as a taste preference. `MoveToPointControl` and
`npcMovementReadouts()` expose the selected actor command plus state, waypoint, gait, and
repath count for the M16 acceptance panel without placing AppKit in the engine.

## World-space debug overlay

`Renderer.worldOverlaySources` is a stable-order registry of per-frame builders. A source
receives the renderer's navmesh and path toggle state and appends per-vertex-color triangles,
line segments, or polylines to a pure `WorldOverlayDrawList`; replacing a source identifier
keeps its position, and removing it needs no renderer change. The navigation source reads the
same resident graph used for queries. It fills valid triangles with a deterministic color per
cell, highlights the latest current corridor, and draws its waypoint polyline. A small Z lift
avoids unstable coplanar depth ties. Both toggles default off.

`RendererOverlayPass` groups triangles before lines in one upload and draws them through one
premultiplied-alpha pipeline with read-only `lessEqual` depth. It runs after the 3D scene and
before SWF/UI in both drawable and `renderOffscreen` paths. The hard cap is 65,536 primitives
per frame; `WorldOverlayDrawStats` reports submitted, drawn, triangle, line, dropped, draw-call,
and truncation state. `AIOverlayControlProviding` exposes both toggles and that snapshot for
the M16 gate panel. `openskycli screenshot --navmesh-overlay` supplies real-data captures.

## Evidence and remaining gaps

Synthetic tests cover a deterministic 2x2 grid, a two-cell edge link that disappears on
unload, paired door traversal, sloped projection, degenerate and out-of-radius misses,
target and cell invalidation, and the two-per-frame repath cap. The 2026-08-09 real-install
probe measured the named Whiterun-hold launch to Chillfurrow Farm route at 4,471.50 units,
34 triangles, 768 expansions, and 6.36 ms. The exterior-to-interior route through door
`0001633D` measured 152.05 units, four triangles, ten expansions, and 1.67 ms, with one
door crossing. The numeric report remains locally under the gitignored `logs/navigation/`.

On the same Apple Silicon machine, eight independently instantiated vanilla behavior graphs
cost 25.20 ms per 60 Hz frame under the ordinary real-data build and 2.43 ms per frame under
the optimized build, measured over 240 frames. The optimized number exceeds the entire 2 ms
NPC movement slice before collision, path following, trigger occupancy, or drawing, so NPCs
use the kinematic gait-clip drive. The repeatable optimized command is
`make realtest-npc-perf`; the same test measures the selected drive at the cap and requires
it to stay within the slice. That selected path measured 0.011 ms per frame for eight movers.

The permanent offscreen real-data route starts at the Chillfurrow exterior return point,
follows the four-triangle corridor through door `0001633D`, teleports to the paired interior
waypoint, and arrives 96 units inside the farmhouse. It completed four waypoints in 32.54 ms
of offscreen wall time in the 2026-08-09 ordinary real-data run.

NPC movers now consume both routes. Dynamic obstacle avoidance between movers, jumping,
swimming, and general off-mesh traversal are not part of this graph yet.
