---
type: Subsystem
title: Static collision world
description: Per-cell placed NIF collision, BVH broadphase, streaming lifetime, and build
  budgets for exterior and interior cells.
tags: [engine, world, collision, nif, streaming, spatial-index]
timestamp: 2026-07-19T00:00:00Z
---

# Static collision world

Milestone 4.3 places decoded [NIF Havok collision](/formats/nif-collision.md) beside every
`CellScene`. Exterior statics stream with 5x5 cells; interior statics build with exact CELL.
This stage supplies immutable world geometry + broadphase only. Capsule response lands in
4.4.

## Build pipeline

`CellSceneBuilder` already owns authoritative REFR list after persistent-ref ownership,
base resolution, malformed-ref handling. Collision reuses that list:

1. Resolve STAT/ModelBase MODL path. Skip lights + marker bases.
2. Build REFR matrix from DATA position/rotation + XSCL.
3. Load cached `NIFCollisionModel` through `NIFCollisionLibrary`.
4. Keep bodies whose duplicate Havok filters + response types are player-solid.
5. Compose `reference x body x shape` matrices.
6. Partition large triangle soups into spatial broadphase leaves, compute conservative world
   AABBs, then build per-cell BVH.

Models without bhk bodies contribute no shapes. Render load success is irrelevant: a
collision-only NIF remains physical. One broken model increments load failures; sibling refs
still build. Unknown reachable bhk blocks + isolated root decode failures remain explicit
stats, never silent geometry loss.

`StaticCollisionShape` retains decoded geometry + final transform + world AABB + source REFR.
Triangle soups keep shared model arrays; repeated placements copy array headers, not vertex
storage. Primitive bounds cover convex vertices, box, sphere, capsule. `StaticCollisionStats`
accounts model refs, collision-bearing refs, bodies, filtered bodies, shapes, triangles,
decode/load gaps, estimated CPU bytes.

## Spatial index

Each `StaticCollisionSet` builds an immutable median-split AABB BVH. Split axis = widest node
extent; leaves hold at most four shape indexes. Query prunes node bounds, then exact-filters
leaf shape AABBs. Output follows source-shape order for deterministic physics/tests.

Large triangle soups split in stable source order, capped at 64 triangles per acceleration
leaf. Leaves share immutable vertex storage; their index slices + exact bounds preserve
original triangles/transforms. Logical shape/triangle stats remain NIF shape counts, while
BVH leaf count is an acceleration detail. This avoids retesting a full building collision
mesh for every capsule substep. M4.5 farm render alone measured 1.41 ms avg/3.33 ms p95;
unpartitioned active physics measured 18.45/40.66 ms at 480x270. Partitioned production
route at 640x360 measured 15.90/29.69 ms.

Repeated Debug fly-path runs during 4.5 measured unpartitioned p95 552.57 ms and partitioned
p95 533.67-635.78 ms after earlier 450-465 ms runs. Build budget moves from 500 to 700 ms to
cover observed utility-queue scheduler variance while retaining a measured p95 ceiling;
active physics keeps its separate 33.33 ms avg/p95 gate.

Index is per cell, not one global tree. `CellSceneComposition.collisionCandidates` queries
all resident cell BVHs so a capsule can overlap both sides of a streamed seam. While inside,
`CellStreamer` queries exact interior set instead. M4.4 narrowphase consumes returned shapes.

## Streaming lifetime + cache confinement

Collision builds inside same `SerialCellBuildRunner` call as render scene, on existing one
serial queue. `NIFCollisionLibrary`, `MeshLibrary`, `TextureLibrary` share confinement; main
thread receives immutable values only.

Decoded collision + triangle-partition caches use same canonical `meshes\\...` keys as render
cache. Each
`CellScene.assets.meshKeys` unions render + collision touches. Existing unload calculation
(`departed - resident union`) therefore retains a model shared by any live cell and evicts
all three caches on build queue when last owner leaves. Collision shapes + BVH live directly
on `CellScene`; removing exterior cell or replacing interior releases index with scene. Stale
build completions follow same drop path.

## Tooling + budgets

`openskycli collision --radius n` keeps center-cell per-asset decode diagnostics, then runs
production placement for every cell in target square. Per-cell row reports placed shapes,
triangles, build ms, estimated KiB. Grid acceptance requires zero load, decode, or reachable-
type gaps. Void cells report explicitly.

`bench --fly-path` records collision phase duration for every successful serial cell build.
Gate: p95 <= 750 ms. M7.6 warm-process full probe reached 723.09 ms after an isolated
574.22 ms run; 750 ms keeps a measured ceiling with scheduler room. Existing render gate
remains avg + p95 <= 33.33 ms; physical footprint cap remains 1,024 MB + plateau requirement.

Real read-only Tamriel probe, 2026-07-19:

- 5x5 `(4...8,-4...0)`: 1,795 placed shapes, 161,427 triangles, 137 filtered bodies,
  zero load/decode/unsupported failures. Estimated live geometry payload ~4.6 MiB.
- Production center -> east -> north fly path: 35 unique builds; 2,393 shapes, 230,034
  triangles processed; collision avg 112.78 ms, p95 464.63 ms, max 725.69 ms.
- Waypoint footprint 484 -> 537 -> 526 MB, peak 593 MB / 1,024 MB cap. 4,727 frames:
  render avg 3.12 ms, p95 5.77 ms, max 16.65 ms.

## Verification

Synthetic tests cover REFR scale/translation x bhk sphere placement, decoded-cache reuse,
interior collision attachment, BVH overlap + stable order, composition add/remove lifetime,
large-soup partition pruning with exact triangle preservation, serial fake-provider collision
metrics + eviction. NIF byte fixtures remain synthetic and cite
[NifTools layout doc](/formats/nif-collision.md); no game asset enters repo.

4.4 consumes broadphase shapes through production
[walk controller](/engine/walk-mode.md): swept capsule narrowphase, collide-and-slide,
ceiling response, ramp grounding, and bounded step offset. Static world remains immutable;
all transient contacts/controller state live outside streamed cells.

M4 route evidence + exact gate live in [terrain walk mode](/engine/walk-mode.md).
