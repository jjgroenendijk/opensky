---
type: Subsystem
title: Static collision world
description: Per-cell placed NIF collision, BVH broadphase, trigger volumes, streaming
  lifetime, and build budgets for exterior and interior cells.
tags: [engine, world, collision, nif, streaming, spatial-index, triggers]
timestamp: 2026-07-31T00:00:00Z
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
4. Keep bodies whose duplicate Havok filters + response types are player-solid. A
   SkyrimLayer 12 body is not solid but is not discarded either: it routes to the trigger
   set below.
5. Compose `reference x body x shape` matrices.
6. Partition large triangle soups into spatial broadphase leaves, compute conservative world
   AABBs, then build per-cell BVH.

Models without bhk bodies contribute no shapes. Render load success is irrelevant: a
collision-only NIF remains physical. One broken model increments load failures; sibling refs
still build. Unknown reachable bhk blocks + isolated root decode failures remain explicit
stats, never silent geometry loss. Geometry that cannot produce a broadphase partition
increments decode failures too. A wholly degenerate shape contributes neither a logical
shape nor estimated bytes; valid sibling leaves of a partially malformed large soup remain
available while each dropped leaf makes grid acceptance fail.

`StaticCollisionShape` retains decoded geometry + final transform + world AABB + source REFR.
Triangle soups keep shared model arrays; repeated placements copy array headers, not vertex
storage. Primitive bounds cover convex vertices, box, sphere, capsule. `StaticCollisionStats`
accounts model refs, collision-bearing refs, bodies, filtered bodies, shapes, triangles,
decode/load gaps, estimated CPU bytes.

## Spatial index

Each `StaticCollisionSet` builds an immutable median-split AABB BVH, `BoundsSpatialIndex`,
which indexes a flat `[ModelBounds]` array by element position and is therefore shared with
the trigger set below. Split axis = widest node extent; leaves hold at most four shape
indexes. Query prunes node bounds, then exact-filters
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
active physics keeps its separate 33.33 ms average gate. Its p95 gate is 33.33 ms in Release
and 66.67 ms in Debug; see [terrain walk mode](/engine/walk-mode.md) for the variance policy.

Index is per cell, not one global tree. `CellSceneComposition.collisionCandidates` queries
all resident cell BVHs so a capsule can overlap both sides of a streamed seam. While inside,
`CellStreamer` queries exact interior set instead. M4.4 narrowphase consumes returned shapes.

## Trigger volumes

Issue #173 adds a second per-cell set beside the solid one. A body whose duplicate Havok
filters name `SKYL_TRIGGER` (SkyrimLayer 12) is never player-solid, so the static build
drops it; it now becomes a `TriggerVolume` instead of vanishing. `NIFCollisionFilter` and
`NIFCollisionBody` answer that with `isTriggerVolume`, which tests layer 12 specifically.
That is deliberately not the negation of `isPlayerSolid`: layer 15
(`SKYL_NONCOLLIDABLE`), the `No Collision` flag, and a non-simple response type all fail
player-solidity without naming a trigger. `filteredBodyCount` keeps its existing meaning —
bodies that are not player-solid, whatever the reason — because the CLI grid acceptance and
the 5x5 Tamriel probe figure above assert on it.

`TriggerVolume` carries the authoring REFR's `ReferenceKey` and `FormID`, the world
transform, the decoded geometry, and a world-space AABB.
`TriggerVolume.placed(reference:formID:transform:geometry:)` builds one: it unions the
local bounds of `StaticCollisionShape.partitions(for:)` and pushes the result through the
transform by 8-corner reboxing, returning nil when the geometry has no finite bounds. The
partition helper is reused rather than reimplemented so both sets agree on what each
geometry case's local extent is.

`TriggerVolumeSet` holds the cell's volumes plus a `BoundsSpatialIndex`, the median-split
AABB BVH extracted from `StaticCollisionSet` in the same change so one implementation
serves both. It splits on the widest node extent, holds at most four element indices per
leaf, and returns query results sorted, so candidate order is deterministic for tests and
for event ordering. `candidates(overlapping:)` prunes on node bounds and then exact-filters
element AABBs, exactly as the solid set does.

`volumes(intersecting:at:)` answers the real question — does the player capsule intersect
this volume — with the capsule's world AABB as broadphase and a per-geometry narrowphase
behind it. Because the answer is a boolean, not a contact normal and depth, the narrowphase
is simpler than `CapsuleWorldCollider`:

| geometry | test | exactness |
| --- | --- | --- |
| `box` | capsule segment pushed into box-local space, closest local point pair solved by alternating projection, both points mapped back to world before measuring | exact for a rigid transform with uniform scale, which is what a REFR matrix composes; approximate under non-uniform scale |
| `sphere` | segment-to-centre distance against the capsule radius plus the scaled sphere radius | exact |
| `capsule` | closed-form segment-to-segment distance against the summed radii | exact |
| `convexVertices`, `triangleSoup` | world AABB overlap only | conservative approximation: a capsule in a corner the mesh does not fill still reports inside |

The mesh approximation is deliberate. Creation Kit trigger volumes are primitives in
practice, a mesh trigger is rare, and firing `OnTriggerEnter` slightly early is the safer
failure for a script event than missing it. Both the code and this table record it so a
later stage can replace it with the exact triangle path without rediscovering the choice.
The narrowphase uses a 0.02-unit tolerance, matching `CapsuleWorldCollider`, so a capsule
the solid path treats as touching a surface also counts as inside a coincident trigger.

### The two authored sources

`CellSceneBuilder.buildTriggerVolumes(refs:entries:location:)`
(`opensky/World/CellTriggerBuilder.swift`, a satellite of `CellCollisionBuilder.swift`)
collects both sources into one set:

| source | what it is | how it is placed |
| --- | --- | --- |
| SkyrimLayer 12 NIF body | a `bhkRigidBody` in the reference's mesh whose duplicate Havok filters name the trigger layer | `placement x body x shape`, the same matrix chain a solid shape gets |
| `XPRM` primitive | the REFR subrecord itself, an invisible volume with no mesh behind it ([record decoders](/formats/records.md)) | the REFR placement matrix: DATA position, DATA rotation, `XSCL` |

The mesh pass runs after the solid build, over the placements
`resolveCollisionPlacements` already resolves, and reads models back out of the same
build-queue-confined `NIFCollisionLibrary` cache the solid build filled. Nothing decodes a
second time, and the solid loop is left exactly as it was so `filteredBodyCount` keeps
counting every non-player-solid body, trigger or not.

The exterior and interior cell builds both reach it through
`buildCollision(resolved:location:)`, which returns the solid set and the trigger set
together as a `CellCollisionBuild`, so neither path can collect one and forget the other.
Interiors matter here: authored trigger volumes are common in dungeons.

Both sources name their authoring reference by `ReferenceKey`, taken from the cell's
runtime index entries (`RuntimeReferenceEntry`), because that is the identity a script
instance is addressed by. A reference the index does not know has no runtime identity, so
its volume could never reach a script; it is skipped and counted rather than placed under a
guessed identity.

### Which primitives become volumes

Only `box` and `sphere` do. `portalBox` is occlusion room-portal geometry rather than
gameplay authoring, `line` is not a volume at all, and `none` describes no shape, so making
any of them a trigger would fire `OnTriggerEnter` for scripts that never asked for it. The
three excluded types are counted in `TriggerVolumeStats.excludedPrimitiveCount` rather than
dropped silently — vanilla `Skyrim.esm` holds 3135 portal boxes and 233 lines, so the
exclusion is the majority of the non-box population and worth being able to see.

A sphere's radius is `halfExtents.x`. Neither UESP's REFR page nor xEdit's
`wbStruct(XPRM, ...)` names which axis carries it, so the answer comes from the data: all
137 sphere primitives in `Skyrim.esm` store the same value in all three axes
(`PlacedReferenceXPRMRealDataTests`, observed 2026-07-31), which makes the axes
interchangeable and the choice non-arbitrary.

The stored half-extents are pre-scale and in the reference's own frame, so the placement
matrix carries both pose and size: it is built by the same `MatrixMath.placement`
call `resolveCollisionPlacements` uses, so there is exactly one REFR Euler convention in
the engine ([coordinates + units](/decisions/coordinates.md)). `XSCL` therefore scales an
`XPRM` box the same way it scales a mesh, and the sphere narrowphase multiplies the radius
by the matrix's largest column length.

### Accounting and lifetime

`TriggerVolumeStats` is a separate tally rather than extra fields on
`StaticCollisionStats`, because `filteredBodyCount` there has a pinned meaning the CLI grid
acceptance and the 5x5 Tamriel probe assert on. It counts mesh volumes, primitive volumes,
excluded primitives, degenerate sources that produced no finite bounds, and references with
no runtime key; `volumeCount` sums the first two.

The set is built on the build queue inside the same `SerialCellBuildRunner` call as the
render scene and the solid set, is immutable once built, and travels to the main thread as
`CellScene.triggerVolumes`, a plain value. It is released with its cell, so no trigger
outlives the cell that authored it. `CellSceneComposition` fans queries across resident
cells: `triggerCandidates(overlapping:)` for the broadphase,
`triggerVolumes(intersecting:at:)` for the capsule question, and `triggerStats()` for the
summed tally. Unlike `collisionCandidates(overlapping:)`, the trigger queries visit cells
in `(x, y)` coordinate order, because their output orders script events and must not depend
on dictionary iteration order.

### Occupancy, edge events, and the walk-mode gate

Geometry above answers "is the capsule inside this volume". The runtime half answers "what
changed since last frame", and lives in `CellStreamerTriggers.swift`, a satellite of
`CellStreamer` shaped like `CellStreamerAmbience`: keep the previous answer, diff, emit only
the difference.

The test runs **once per rendered frame**, from `CellStreamer.update(...)`, and never from
the 120 Hz substep loop in `WalkController`. Two reasons, both decided here: a trigger is a
gameplay-rate event, so a player standing still would otherwise queue 120 script events a
second for the same containment; and the substep loop is a hot path that must stay pure
capsule-versus-solid math. The cost of the choice is stated: containment is sampled at frame
rate, so a volume is entered up to one frame late.

Trigger testing is **walk mode only**, gated exactly as the interaction ray is
(`GameViewControllerStreaming.playerCapsule(of:)` mirrors `interactionRay(of:)`). The fly
camera is a developer view with no body. The streamer is driven with the *eye* position, and
feet are eye minus `PlayerCapsule.eyeHeight` only while walking, so the authoritative pose
arrives as a `PlayerCapsuleState` parameter — `WalkController.feetPosition` and `.capsule` —
rather than being re-derived downstream. The parameter is defaulted to nil, meaning "not in
walk mode, do not test", which is what keeps every streaming test that calls
`update(cameraPosition:)` unchanged.

`update` runs the test on both paths that can own the view: the interior early return and
the exterior tail. Interiors carry most authored trigger volumes, so skipping the interior
branch would have missed the common case. The query itself is interior-aware in the same
shape as `collisionCandidates(overlapping:)`: an interior scene replaces the exterior
composition entirely, so it answers alone.

Per frame:

| set | how it is built |
| --- | --- |
| `occupied` | volumes the capsule intersects at this frame's feet position |
| `touched` | `occupied` plus volumes intersected at swept sample poses between last frame's feet position and this one |

and the diff is `entered = touched - previous`, `left = (previous ∪ touched) - occupied`,
with `occupied` becoming the new `CellStreamer.occupiedTriggers`. Enters dispatch before
leaves, each in ascending `ReferenceKey` order, the same determinism rule
`queueOnActivate` follows. Occupancy is committed before any handler runs, so a script that
moves the player from inside its own handler sees a consistent set.

That shape gives the four behaviours the runtime owes scripts. Entering fires one enter.
Dwelling fires nothing, because a volume already in `occupiedTriggers` is not in `entered`.
Leaving fires one leave. A teleport across a volume in a single frame fires enter followed by
leave, because the volume appears in `touched` but not in `occupied` — the transient visit is
reported rather than silently missed.

The sweep is sampled, not swept exactly: `CellStreamer.sweepSamples(from:to:radius:)` places
intermediate poses about one capsule radius apart, excluding both endpoints, capped at
`maximumTriggerSweepSamples` (16). A normal walking frame moves far less than a radius and
produces no samples at all, so the sweep costs nothing until something teleports. The stated
limit: a jump longer than 16 radii samples at coarser spacing, so a very thin volume on a
very long teleport can still be missed. Exact swept-capsule narrowphase was not worth the
complexity for an event a script can also poll.

Leaving walk mode freezes occupancy rather than clearing it. Toggling to fly inside a volume
is not a leave the player performed, so none is fabricated; the leave fires on the first
walk-mode frame that finds the capsule outside.

### Cell-unload containment policy

A player cannot stay inside a volume whose cell has gone, so unload is an explicit leave and
never a silent drop. `CellStreamer.releaseTriggers(in:)` fires leave for every occupied
volume the departing scene authored, and it is called from `emitCellDetached(_:)` — the
single funnel every unload path already goes through: grid eviction, a coverage-transition
drop, and a door transition replacing the previous scene. Release runs before the location
guard, because a volume has a `ReferenceKey` whether or not the CELL identity resolved.

Ordering is the whole point. `PapyrusWorldRuntime.detach(cell:)` retires the cell's
instances *and removes their queued events*, so a leave queued after the detach would be
discarded without ever being seen. Firing the leave first is what gives a script its cleanup
opportunity. The honest limit, pinned by tests: a non-persistent instance is retired in the
same frame, so its `OnTriggerLeave` is dropped by that queue purge; an instance whose
reference entry was `isPersistent` survives the detach and receives it. Queuing first is all
the engine can offer a script whose instance is going away.

The dispatch side — event names, `akActionRef`, and the bridge seam — is in
[Papyrus VM](/engine/papyrus-vm.md).

### Sidebar verification surface

Trigger volumes are user-verifiable behaviour, so they extend an existing destination rather
than adding a top-level row: `World > World > Triggers` sits under the same panel as the
fly/walk selector, because occupancy is only tested in walk mode. The section
(`TriggerVolumeSection`, header `PanelSection-triggerVolumes`) reads one
`TriggerStatsSnapshot` per 2 Hz tick through `TriggerControlProviding` and shows four lines:

```text
Volumes: 12 resident  Occupied: 1
Sources: mesh 8  primitive 4
Dropped: excluded 3  degenerate 1  unkeyed 2
Occupancy: walk mode, live
```

`Sources` separates the two authored kinds, and `Dropped` surfaces exactly the counters that
would otherwise truncate silently. `Occupancy` names the gate — `walk mode, live`,
`fly mode, frozen at n`, or `fly mode, not tested` — because leaving walk mode freezes the
set, so a non-zero count in fly mode is correct rather than a bug. With no streamer the
readout says `Trigger volumes: unavailable` instead of showing zeros.

Below it, `TriggerEventStatsLabel` prints the tail of `TriggerEventLog`, a bounded
newest-last ring of `phase reference formID` lines (`enter skyrim.esm:ABCDEF 0x000ABCDE`;
`unloaded` where the authoring cell has already gone, which is what a leave fired by
`releaseTriggers(in:)` looks like). The log is an ordinary `onTriggerTransition` subscriber
registered by `CellStreamer.installTriggerLogging()`, so it costs one closure call per edge
and cannot displace or reorder the Papyrus handler. It lives on the streamer, not the panel,
because a panel is built lazily on first reveal and rebuilt by a Settings reload.
`TriggerLogClearControl` empties it; that leaves no provider state behind, so the section is
action-only and reports no override.

```text
Milestone: M11.2.3
Sidebar path: World > World > Triggers
Destination id: Destination-world
Controls exercised: TriggerLogClearControl, CameraMovementModeControl (walk-mode gate)
Readout: TriggerVolumeStatsLabel, TriggerEventStatsLabel
Deterministic tests: WorldPanelTests, TriggerEventLogTests, DestinationRegistryTests
Local A/B (optional, never committed): none
```

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
large-soup partition pruning with exact triangle preservation, fail-loud degenerate and
invalid-leaf accounting, serial fake-provider collision metrics + eviction.
`TriggerVolumeWorldTests` covers the empty set, BVH node count + deterministic candidate
order, AABB rejection, a capsule inside, outside, and grazing a box face, a rotated box
tested in its own space, sphere and capsule geometry, the conservative triangle-soup path,
and a degenerate geometry producing no volume. `NIFCollisionTriggerLayerTests` pins layer 12
true, layer 15 false, layer 1 false, and that a trigger body is never player-solid.
`CellTriggerBuilderTests` covers the collection step end to end over a built cell: an `XPRM`
box becoming one volume at the scaled world transform, an `XPRM` sphere taking its radius
from the first axis, `none`/`portalBox`/`line` producing no volume but an exclusion count, a
layer-12 body routed to the trigger set while a layer-1 body stays in `staticCollision`, a
cell with neither source yielding an empty set, and `filteredBodyCount` still counting a
trigger body as filtered. `TriggerEventLogTests` covers the readout log: the line format,
the `unloaded` FormID case, the bounded ring keeping the newest records while still counting
the dropped ones, `clear()`, and a streamer recording its own dispatched edge.
`TriggerVolumeCompositionTests` covers the multi-cell fan-out:
coordinate-ordered candidates over two resident cells, the summed stats, and a capsule
matching only the cell it stands in. NIF byte
fixtures remain synthetic and cite
[NifTools layout doc](/formats/nif-collision.md); no game asset enters repo.

4.4 consumes broadphase shapes through production
[walk controller](/engine/walk-mode.md): swept capsule narrowphase, collide-and-slide,
ceiling response, ramp grounding, and bounded step offset. Static world remains immutable;
all transient contacts/controller state live outside streamed cells.

M4 route evidence + exact gate live in [terrain walk mode](/engine/walk-mode.md).
