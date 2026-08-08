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
lifetime follows [cell streaming](/engine/cell-streaming.md). It finds corridors and
waypoints only; actor steering and visualization belong to later M16 items.

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

Actor following and recovery are [issue #423](https://github.com/jjgroenendijk/opensky/issues/423).
Dynamic obstacle avoidance, jumping, swimming, and general off-mesh traversal are not part of
this graph yet.
