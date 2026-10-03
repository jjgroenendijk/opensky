---
type: Subsystem
title: Drawing moving bodies
description: How a simulated body is drawn at its live pose without rebuilding its cell, by
  applying a per-reference transform delta where instance matrices are uploaded.
tags: [engine, rendering, physics, streaming]
---

# Drawing moving bodies

A cell build bakes one world matrix per draw instance. A cell is rebuilt only when its world state
changes. That is right for geometry placed once, but a [dynamic body](/engine/dynamic-bodies.md)
moves every frame. Without extra work, a pushed barrel would collide, roll, and settle while its
mesh stayed where the plugin put it. A settle writes the resting pose to the world state but
rebuilds no cell, so the delta below draws the body until some other change rebuilds the cell.

## The delta

The baked matrix stays. The difference is applied where instance matrices are uploaded. For each
body, the delta is the rigid move from the pose the build drew the reference at to the pose the
solver has now:

```text
live matrix = delta * baked matrix
```

The delta goes on the left of a matrix that already holds the reference's `XSCL` scale and the
mesh's own local transform. So neither has to be known.

Each frame the deltas are collected by `REFR` FormID and given to the renderer. The renderer
applies them in the two places instance matrices reach the GPU: the scene pass and the shadow pass.
So a moving body's shadow moves with it. The culling box goes through the same delta, so a body
that left its baked bounds is still drawn.

## Keeping it cheap

- A draw instance carries a reference FormID only when a body owns it. Every other instance has
  zero, costs one integer compare, and never touches the table.
- A body resting exactly where it was placed is left out of the table. Settled clutter costs what
  static clutter costs, and a still world publishes nothing.
- A draw group is keyed by mesh and material, which a move does not change. Nothing regroups and no
  buffer grows.

The player body works the other way: it rebuilds its draw groups when it moves. Skinned geometry is
placed by its bone palette as well as its model matrix, and the palette is in skeleton space. Rigid
clutter has no such limit.

## After a rebuild

The pose the delta is measured from is refreshed at every rebuild, not only for new bodies. A
rebuild that bakes a settled pose into the scene must move the starting point too. Otherwise the
object would be drawn moved twice. The same refresh makes the panel's reset return a body to the
pose the current build drew, not to the plugin's pose.

## Crossing a cell border

A body's draw follows the cell it occupies, not the cell that placed it. Each tagged reference's
draw instances are split off from their cell's scene. They keep the same baked matrices and deltas.
Only their owner changes. They are added once under the occupied cell, survive the removal of the
placing cell, and are removed with the occupied cell. Terrain, lighting, animations, and untagged
instances stay with their own cell.
