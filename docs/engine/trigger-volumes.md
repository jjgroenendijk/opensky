---
type: Subsystem
title: Trigger volumes
description: Invisible volumes from NIF trigger bodies and XPRM primitives, the capsule
  test, enter and leave events once per frame, and leave events on cell unload.
tags: [engine, world, collision, triggers, papyrus, streaming]
---

# Trigger volumes

A trigger volume is an invisible shape. When the player walks in or out, a script gets
`OnTriggerEnter` or `OnTriggerLeave`. Each cell has a trigger set beside its
[static collision](/engine/collision-world.md). The Papyrus side is on the
[Papyrus activation](/engine/papyrus-activation.md#ontriggerenter-and-ontriggerleave) page.

## Two sources

| Source | What it is | Placement |
| --- | --- | --- |
| A NIF body on SkyrimLayer 12 | A `bhkRigidBody` in the reference's mesh whose Havok filter names the trigger layer | Reference, then body, then shape, like a solid shape |
| An `XPRM` primitive | A `REFR` field: an invisible volume with no mesh ([world records](/formats/world-records.md)) | The reference matrix: `DATA` position and rotation, and `XSCL` |

A body is a trigger only if it names layer 12 (`SKYL_TRIGGER`). That is not the same as "not
solid". Layer 15 (`SKYL_NONCOLLIDABLE`), the `No Collision` flag, and a non-simple response type
are all not solid, but they are not triggers. The count of filtered bodies still counts every
body that is not solid, triggers included.

The mesh pass runs after the solid build, over the same placements, and reads models from the
same cache. Nothing decodes twice. Exterior and interior builds both return the solid set and
the trigger set together, so neither path can forget one. Interiors matter: dungeons have many
triggers.

Each volume names its reference by `ReferenceKey`, because a script instance is addressed that
way. A reference with no runtime key could never reach a script. It is skipped and counted, not
placed under a guessed identity.

## Which primitives become volumes

Only `box` and `sphere`. The others are counted as excluded:

- `portalBox` is room portal geometry for occlusion, not gameplay.
- A `box` on a room marker (a reference with `XRMR`) is room bounds for occlusion too
  ([rooms and portals](/formats/placed-references.md#rooms-and-portals)).
- `line` is not a volume.
- `none` has no shape.

Making any of these a trigger would fire events for scripts that never asked. Vanilla
`Skyrim.esm` has 3135 portal boxes and 233 lines, so most non-box primitives are excluded, and
the count makes that visible.

A sphere's radius is `halfExtents.x`. Neither UESP's `REFR` page nor xEdit's
`wbStruct(XPRM, ...)` says which axis holds it. The data answers: all 137 sphere primitives in
`Skyrim.esm` store the same value on all three axes, so any axis works.

The half-extents are before scale, in the reference's own frame. The placement matrix carries
both pose and size. It is built by the same call as for meshes, so the engine has one `REFR`
rotation convention ([coordinates](/decisions/coordinates.md)). So `XSCL` scales an `XPRM` box the
same way it scales a mesh. A sphere's radius is multiplied by the longest column of the matrix.

## The capsule test

The broad phase uses the capsule's world box and the same kind of tree as the solid set. Then a
test per shape answers yes or no. It needs no contact normal or depth, so it is simpler than the
solid capsule collider:

| Shape | Test | Exact? |
| --- | --- | --- |
| `box` | The capsule segment moves into box space. The closest point pair is found by projecting back and forth, and both points go back to world space before measuring | Exact for rotation, translation, and uniform scale, which a `REFR` matrix has. Approximate for uneven scale |
| `sphere` | Segment to center distance against capsule radius plus scaled sphere radius | Exact |
| `capsule` | Segment to segment distance against the two radii | Exact |
| Convex, triangle mesh | World box overlap only | Too generous: a capsule in an empty corner of the box still counts as inside |

The mesh shortcut is on purpose. Creation Kit triggers are nearly always primitives. For a script
event, firing a little early is safer than missing it. The test uses a tolerance of 0.02 units,
like the solid collider, so a capsule that touches a surface also counts as inside a trigger at
the same place.

## Enter and leave

The test runs once per rendered frame, not in the 120 Hz movement steps. A trigger is a gameplay
event. A player standing still would otherwise queue 120 script events a second. The movement
step also stays pure capsule math. The cost: a volume can be entered up to one frame late.

The test runs only in walk mode, like the interaction ray. The fly camera has no body. The
walk controller's capsule pose is passed in, not derived again later. With no pose there is no
test. The test runs for both interiors and exteriors. An interior replaces the exterior world,
so it answers alone.

Each frame builds two sets:

| Set | Contents |
| --- | --- |
| occupied | Volumes the capsule is in at this frame's position |
| touched | occupied, plus volumes the capsule crossed between last frame and this one |

Then:

```text
entered = touched - previous
left    = (previous + touched) - occupied
```

`occupied` becomes the new previous set. Enter events go first, then leave events, each sorted by
`ReferenceKey`. The new set is stored before any handler runs, so a script that moves the player
sees a consistent state.

This gives four behaviors:

- Walking in fires one enter.
- Staying inside fires nothing.
- Walking out fires one leave.
- A jump through a volume in one frame fires an enter and then a leave. The short visit is
  reported, not missed.

The crossing test uses sample poses about one capsule radius apart, at most 16, without the two
end points. A normal walking frame moves much less than a radius, so it has no samples. A jump
longer than 16 radii samples more coarsely, so a very thin volume can still be missed. An exact
swept test was not worth the extra code for an event a script can also poll.

Leaving walk mode freezes the occupied set. Switching to fly inside a volume is not a leave the
player made. The leave fires on the first walk-mode frame that finds the capsule outside.

## Cell unload

A player cannot stay inside a volume whose cell is gone. So an unload fires a leave for every
occupied volume of that cell. It is never a silent drop. All unload paths pass through one
place: grid eviction, a coverage change, and a door replacing the scene. The leave fires even
if the cell's identity did not resolve, because the volume has a `ReferenceKey` either way.

The order matters. Detaching a cell from Papyrus retires its script instances and removes their
queued events. A leave queued after that would be thrown away. So the leave fires first. The
limit: a non-persistent instance is retired in the same frame, so its `OnTriggerLeave` is removed
by that purge. A persistent reference's instance survives and receives it.

## Lifetime

The trigger set is built on the build queue, in the same call as the render scene and the solid
set. It is immutable, travels to the main thread as a plain value, and is released with its cell.
Queries over several cells visit them in `(x, y)` order, not dictionary order, because the result
orders script events.

## Controls

World > World > Triggers, under the same destination as the fly and walk switch, because only
walk mode tests triggers:

```text
Volumes: 12 resident  Occupied: 1
Sources: mesh 8  primitive 4
Dropped: excluded 3  degenerate 1  unkeyed 2
Occupancy: walk mode, live
```

The Occupancy line names the gate: `walk mode, live`, `fly mode, frozen at n`, or
`fly mode, not tested`. A non-zero count in fly mode is correct, because leaving walk mode
freezes the set.

Below it is a short log of recent events, like `enter skyrim.esm:ABCDEF 0x000ABCDE`. A leave from
an unloaded cell shows `unloaded` in place of the FormID. The log is a normal event listener, so
it cannot change the order of the Papyrus handler. It lives on the streamer, not the panel,
because the panel is built late and rebuilt when settings reload. Clear empties it.
