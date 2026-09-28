---
type: Subsystem
title: Cell scene build
description: How one cell becomes a draw list - the group walk, base object lookup, what is
  skipped and counted, draw order, bounds, and how the app starts streaming.
tags: [engine, world, rendering, esm]
---

# Cell scene build

The cell scene builder turns one cell into a scene: draw lists, a load summary, and a world-space
box for the camera. It gets the target cell as input. The first target is on the
[first render cell](/decisions/first-render-cell.md) page. Sky and water are on the
[sky and water](/engine/sky-water.md) page. Interiors are on the
[interiors](/engine/interiors.md) page.

## Walk order

From the UESP "Groups" page:

1. The `WRLD` top group, then the `WRLD` record with the matching editor ID, then its world
   children group (type 1).
2. Depth first through the exterior block (type 4) and sub-block (type 5) groups. The block grid
   labels are not trusted. The cell is found by its decoded `XCLC` grid. So every exterior
   `CELL` in the worldspace is decoded once per build. That is acceptable at start-up. Using the
   labels as a hint could make it faster later.
3. The cell children group (type 6) that follows the matching `CELL`. No children group means a
   cell with no references, not an error.
4. Both the persistent (type 8) and temporary (type 9) groups, for their `REFR` records.

Persistent teleport doors are stored in the (0, 0) cell but are added to the cell where they
stand (see [interiors](/engine/interiors.md#finding-the-target)).

The walk is lazy. Only group headers are read. A record is decoded only when needed, and only
the record types the scene uses.

## Base objects

A reference's base FormID is looked up in two cached indexes: `STAT` first, then the placeable
base objects (`MSTT`, `TREE`, `FURN`, `ACTI`, `CONT`, `DOOR`, see
[world records](/formats/world-records.md)). `STAT` has one top group. The others have one each.

`MODL` paths do not start with `meshes\`. The mesh library adds it. This was checked against the
real archives ([first render cell](/decisions/first-render-cell.md)).

## Skips

A missing worldspace or cell is an error. Everything per reference or per file is logged,
skipped, and counted. It never crashes or stops the build.

| Bucket | Cause |
| --- | --- |
| malformed | The `REFR` does not decode (no `NAME` or `DATA`) |
| unsupported-base | The base is in neither index, such as `NPC_`, `MISC`, `FLOR`, or `SOUN` |
| marker | The base has no model (an editor marker) |
| load-failed | The mesh is missing, does not parse, or is empty |
| runtime-disabled | The world state disabled it ([runtime state](/engine/runtime-state.md)) |
| runtime-deleted | The world state deleted it |

Not counted: other records in the cell group, such as `NAVM` and `PGRE`, and deleted `REFR`
records. Actors (`ACHR`) have their own pass and count (see
[actor appearance](/engine/actor-appearance.md#streaming)). `LAND` becomes
[terrain](/engine/terrain.md). A bad group under `WRLD` is skipped with a log, and the other
blocks still load.

## Summary line

One line is logged per cell:

```text
[INFO] WhiterunExterior06 (6,-2): 16 refs, 16 drawn, 0 skipped,
9 models, 19 textures (0 missing), 4 terrain quads (14 splat layers)
```

Water cells add `, water`. Cells with actors add `, N actors (D drawn, S disabled, F failed)`,
where N must equal D + S + F. Only nonzero skip buckets are listed. The sky is not counted,
because it belongs to the worldspace, not the cell.

## Draw order

Objects are sorted by mesh path, then `REFR` FormID. So all copies of one model sit together,
ready for instanced draws, and the order is the same every run. Opaque objects come before
alpha-tested ones.

## Bounds

Each object's transform comes from `DATA` and `XSCL` ([coordinates](/decisions/coordinates.md)).
The mesh library keeps a model-space box for each model when it parses it, because the vertex
data is only on the GPU after upload. The builder moves the box's 8 corners per object and joins
them into the cell box. Terrain and the water plane join too. The sky does not.

## App start

No cell is built while the app starts. The app finds the game data, then gives the game view a
factory that makes the scene provider on the view's Metal device. The factory sets up the VFS, the
plugin, and the texture and mesh libraries. This is cheap: the plugin is memory-mapped and only
top group headers are read.

The renderer starts empty. A [cell streamer](/engine/cell-streaming.md) builds cells off the main
thread and frames the camera on the first one. If setup fails, the app logs `[ERROR]` and shows a
demo scene. It never crashes. A cell that fails to build is marked and not tried again, so one
broken cell cannot cause a storm of retries.

`openskycli render` and `bench` build cells directly and in one thread. They are one-shot tools,
not the live streaming loop ([CLI](/tools/cli.md)).
