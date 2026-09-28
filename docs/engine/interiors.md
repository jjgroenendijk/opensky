---
type: Subsystem
title: Interior door transitions
description: How an interior cell is built, how a door's teleport target is resolved, and how
  exterior streaming pauses and resumes around a transition.
tags: [engine, world, interior, door, streaming]
---

# Interior door transitions

One path covers both directions: outside to inside, and inside to outside. The record fields
(`CELL`, `REFR` `XTEL`) are on the [world records](/formats/world-records.md) page.

## Building an interior

The builder finds the interior `CELL` through its block and sub-block groups (see
[finding an interior cell](/formats/world-records.md#finding-an-interior-cell)), then reads its
persistent and temporary children the same way as an exterior cell. The `DATA` interior flag
must be set.

An interior scene has no terrain, no sky, no exterior water plane, and no distant LOD. Its
lighting comes from `XCLL` and the lighting template, plus its own lights (see
[lighting](/formats/lighting.md)). Interior water and portals are not done yet.

## Finding the target

When a scene is built, each drawable `DOOR` reference with an `XTEL` is kept with its position
and target. So the main thread can pick a door without reading plugin bytes.

Exterior teleport doors are persistent. `Skyrim.esm` stores them under the worldspace's
persistent cell at (0, 0), not in the grid cell where they stand. The builder takes each such
door's position, finds its real cell by dividing by 4096 and rounding down, and adds the door to
that cell. The same rule picks the exterior cell to return to.

The transition is built on the same serial queue as cells:

1. Read the source `REFR` and its exact 32-byte `XTEL`.
2. Read the target `REFR`. Its base must be a `DOOR`.
3. Find the target's interior `CELL`, or work out the exterior cell from its position.
4. Build that cell, and return the scene with the `XTEL` position and rotation.

Transitions resolve inside the plugin being loaded. Doors across plugins wait for multi-plugin
world loading.

## Activation and streaming

A door is activated through the normal [interaction](/engine/interaction.md) target. Only an
"Open" target starts a transition, and it passes the exact door that was looked at. The same path
works for the return door.

While the transition builds, the current scene stays live. On arrival in an interior:

- The renderer swaps to the one interior scene.
- The camera moves to the `XTEL` position, with pitch from rotation X and yaw from rotation Z.
  Roll is ignored.
- The exterior cells stay in memory, but streaming stops: no grid changes, builds, LOD builds,
  or unloads.

On return, the target exterior cell is built or reused, streaming resumes around the new
position, and the normal grid rules remove old cells.

`openskycli interior` walks out, in, and back through the nearest door, and draws the arrival
view ([CLI](/tools/cli.md)).
