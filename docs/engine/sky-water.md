---
type: Subsystem
title: Sky and water
description: The procedural exterior sky, the flat per-cell water plane built from plugin data,
  and where both sit in the scene pass.
tags: [engine, rendering, sky, water, environment]
---

# Sky and water

An exterior scene has one sky and at most one water plane per loaded cell. The record fields
are on the [water](/formats/water.md) page. The renderer is on the
[Metal 4 renderer](/rendering/metal4-renderer.md) page.

## Sky

A worldspace without the "no sky" flag gets a sky. When scenes are merged, one sky is kept if any
of them has one. The sky is a full-screen triangle drawn first, before any depth-tested geometry.

With weather active, the sky uses the colors blended from the current weathers (see
[weather](/engine/weather.md)). With no weather, the shader uses built-in night, day, and
twilight colors and a soft sun disc, from the time of day (default 13:00). The CLI screenshot
takes `--time-of-day 0...24`. 24 is the same as 0.

## Water plane

A cell gets water only if it is an exterior, its `DATA` has the "has water" flag, it has a grid,
and its height resolves to a finite number. The cell's own height and water type override the
worldspace defaults, which come down through parent worldspaces. The special "no water" height
gives nothing.

One cached 4096 x 4096 quad serves every cell. It is moved to
`(gridX * 4096, gridY * 4096, waterHeight)`. The plane's box joins the cell's bounds, so camera
framing and culling include it. Each cell owns its water item, even though the mesh is shared.

## Draw order

Sky, cloud layers, opaque objects, terrain, alpha-tested objects, grass, water, then particles,
rain and snow, and overlays.

Water has its own pipeline: straight alpha blending, depth test "less", no depth writes, no
culling. The shader mixes the shallow and deep water colors by distance, adds the reflection
color by a Fresnel term from the view angle, and moves cheap crossed sine ripples over time.
