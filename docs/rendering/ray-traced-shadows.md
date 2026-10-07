---
type: Subsystem
title: Ray-traced shadows
description: Optional ray-traced sun shadows on GPUs with hardware ray tracing, what they
  trace against, and why they are off on M1 and M2.
tags: [rendering, metal4, ray-tracing, shadows]
---

# Ray-traced shadows

The original game shadows the sun with shadow maps only. OpenSky can add a ray-traced sun
shadow on top: each pixel of a static mesh or of the terrain traces one ray toward the sun.
A hit means the pixel is in shadow. The shader keeps the darker of this result and the
shadow-map result, so a pixel is lit only when both say it is lit. This is an optional
visual upgrade. It is off by default, so the default look stays close to the game.

Reference: Apple's Metal documentation for `MTL4PrimitiveAccelerationStructureDescriptor`,
`MTL4InstanceAccelerationStructureDescriptor`, and the Metal Shading Language
`raytracing::intersector`.

## Which GPUs run it

Hardware ray tracing starts with the Apple9 GPU family, the M3. An M1 or M2 runs ray queries
in software, which is too slow for one ray per pixel. On those GPUs the setting stays off,
and the UI shows the reason. The check is `MTLDevice.supportsRaytracing` together with
`supportsFamily(.apple9)`.

The renderer builds the ray-traced pipelines at startup only where the GPU passes the check.
Their shader path sits behind two optional function constants. The shipping pipelines do not
define them, so their compiled code does not change.

## What the rays test against

- One primitive acceleration structure per mesh, from its vertex and index buffers.
- One instance acceleration structure that places every mesh in the world.
- Only rigid, opaque geometry that casts shadows goes in, plus the terrain.

Actors, references that a physics body moves, and alpha-tested foliage stay out. Their
shapes change each frame, or they need an alpha test on every hit. They still cast their
shadow-map shadows, because the shader keeps that result. Skinned actors and alpha-tested
surfaces also keep the shadow-map pipelines as receivers.

The structures are built again when the scene changes or when the setting turns on. They are
freed when it turns off.

## Settings and checking it

The player setting `rendering.rayTracedShadows` turns it on. The launcher's Graphics page
and `Developer > Rendering Performance > Ray-Traced Shadows` write it
(`GraphicsRayTracedShadowsControl`, `RayTracedShadowsEnabledControl`). The section also has
`RayTracedShadowsViewControl`, which draws the traced shadow alone: white is lit, black is
shadowed. Its readout (`RayTracedShadowsStatsLabel`) shows the reason when the GPU cannot run
it, and otherwise the number of meshes, instances, and structure memory.

The effect and its frame cost have not been checked on an M3 or later Mac yet. The
[benchmark](/tools/benchmark.md) records that cost once one is available.
