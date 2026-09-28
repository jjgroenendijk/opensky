---
type: Subsystem
title: Static collision world
description: How placed NIF collision is built per cell, the bounding volume tree used to find
  nearby shapes, surface materials, and how collision streams and is budgeted.
tags: [engine, world, collision, nif, streaming, spatial-index]
---

# Static collision world

Every cell scene has a set of static collision shapes, built from the decoded
[NIF Havok collision](/formats/nif-collision.md) of its placed references. Exterior cells stream
in the 5x5 grid. An interior builds with its own cell. This layer only holds fixed world geometry
and a way to find shapes near a point. The capsule that moves against it is on the
[walk mode](/engine/walk-mode.md) page. Trigger volumes are on the
[trigger volumes](/engine/trigger-volumes.md) page.

## Building a cell's shapes

The cell builder already has the final list of `REFR` records: persistent references are
assigned, bases are resolved, and broken references are handled. Collision reuses that list:

1. Find the `STAT` or other model base's `MODL` path. Skip lights and markers.
2. Build the reference matrix from `DATA` position and rotation and `XSCL` scale.
3. Load the cached NIF collision model.
4. Keep the bodies whose Havok filters and response types make them solid for the player. A body
   on SkyrimLayer 12 is not solid, but it is not thrown away: it becomes a trigger volume.
5. Combine the matrices: reference, then body, then shape.
6. Split large triangle meshes into pieces, compute safe world bounds, and build the cell's tree.

A model with no Havok bodies adds no shapes. Whether the model drew is not relevant: a NIF that
has only collision is still solid. One broken model is counted as a load failure, and the other
references still build. An unknown Havok block, a root that does not decode, and geometry that
cannot be split are all counted. Geometry is never lost silently. A fully degenerate shape adds
neither a shape nor bytes. A large mesh with some bad pieces keeps its good pieces, and each
dropped piece is counted.

A triangle mesh placed many times shares one copy of its vertex arrays.

## Surface material

Each shape also keeps the `MATT` material of its surface. The NIF stores a Havok material value,
which is a hash of a Creation Kit material name. The build resolves it through the material type
index, so nothing later has to know about the hash ([material types](/formats/material-type.md)).

A NIF shape has one material for all its geometry, so every piece of a split mesh has its shape's
material. A capsule contact and a step probe both report the material they touched. That is how
walk mode knows what the player stands on.

## Spatial index

Each cell's shapes are indexed by a bounding volume hierarchy (BVH). A BVH is a tree of boxes:
each node's box holds its children, so a query can skip whole branches that do not overlap.

- A node splits along its widest axis, at the middle element.
- A leaf holds at most four shapes.
- A query skips nodes whose box does not overlap, then checks each shape's own box.
- Results come back in the shapes' original order, so physics and tests always see the same order.

The same tree code serves the trigger volumes.

Large triangle meshes are split, in their original order, into pieces of at most 64 triangles.
The pieces share the mesh's vertex storage. Each piece keeps its own index range and exact
bounds, so the original triangles do not change. Shape and triangle counts still count NIF
shapes. The number of pieces is only a detail of the tree.

The split matters: without it, a capsule step tests a whole building mesh. A test drive over a
farm cost about ten times more physics time without the split.

There is one tree per cell, not one for the world. A query searches every loaded cell's tree, so
a capsule can touch both sides of a cell border. Inside an interior, only the interior is
searched.

## Movable bodies

A solid body whose Havok data says it can move leaves the static set when the cell builds. It is
simulated as a [dynamic rigid body](/engine/dynamic-bodies.md). Dynamic bodies give their shapes
back to the same queries at their current pose. So the capsule, the interaction ray, and shape
sweeps see one list of shapes, and do not need to know which kind each one is.

## Streaming

Collision builds in the same serial build call as the render scene, on the same queue. The NIF
collision, mesh, and texture caches all belong to that queue. The main thread receives only
immutable values.

Collision caches use the same `meshes\...` keys as the render cache. Each cell scene lists every
mesh key it used, for rendering and for collision. When a cell unloads, a model is kept if any
loaded cell still uses it. Otherwise all three caches drop it, on the build queue. The shapes and
tree belong to the cell scene, so they go away with it. A build that finishes after its cell is
no longer wanted is dropped the same way.

## Tools and budgets

`openskycli collision --radius n` prints diagnostics for each asset of the center cell, then runs
the real placement for every cell in the square. Each cell row reports shapes, triangles, build
time, and estimated memory. The check passes only with zero load, decode, or unsupported-type
failures. Empty cells say so.

`openskycli bench --fly-path` records the collision time of every cell build. The limit is a p95
of 750 ms per build. The build limit allows for the uneven timing of the background queue, which
shows up in repeated runs. The render limit is a mean and p95 of 33.33 ms per frame, and the
memory limit is 1,024 MB with a steady plateau. See [walk mode](/engine/walk-mode.md) for how
timing noise is handled.
