---
type: Subsystem
title: GPU culling
description: How a compute pass culls the scene's static draw groups for the camera and each
  shadow cascade, how the draws read its result, and how to compare it with the CPU path.
tags: [rendering, metal4, performance, culling]
---

# GPU culling

Culling skips an instance whose bounding box lies outside a view. The CPU path tests each
instance of each draw group against the camera frustum, then again for each shadow cascade,
and copies the survivors' transforms into the instance ring. GPU culling moves that work into
one compute pass. The CPU then encodes one indirect draw per group and never touches an
instance.

## How it works

1. When the scene changes, the renderer writes one `CullInstance` per instance into a GPU
   buffer: its transforms, its world bounding box, its group, and where the group's output
   starts. This happens once per scene, not per frame.
2. Each frame, before the shadow pass, the CPU resets each group's
   `MTLDrawIndexedPrimitivesIndirectArguments` to zero instances and writes the frustum planes
   of the camera and of each cascade.
3. The `cullInstances` kernel runs one thread per instance and view. A thread that keeps its
   instance adds one to the group's instance count with an atomic add, and writes the
   transforms into the slot that add returned.
4. A barrier makes the vertex stage of later passes wait for the dispatches. Each group then
   draws with `drawIndexedPrimitives(...indirectBuffer:)`, with its instance transforms bound
   at the group's output.

The kernel uses the same positive-vertex test as `Frustum.intersects`, so both paths keep the
same instances. In an interior, the camera view first skips instances in rooms the camera
cannot see ([room and portal culling](/rendering/room-portal-culling.md)); the cascades do
not. Before it encodes a group's draw, the CPU tests the group's combined bounding box once.
A group outside the view gets no draw, and its instances count as culled.

## What stays on the CPU

- A group that holds a reference a physics body moves. Its pose changes every frame, and the
  GPU buffer holds the pose the scene was built with.
- The player's body, effects, the loading cover, terrain, grass, water, and particles. They
  are few, or they already have their own path.

Survivors of one group land in any order, because threads finish in any order. Opaque and
alpha-tested draws use a depth test, so the order does not change the image.

## Default and settings

The app culls on the GPU by default. The player setting `rendering.gpuCulling` turns it off,
and the next launch reads it. The launcher's Graphics page and the switch below both write
it. The `Renderer` type itself starts on the CPU path, so a render test that builds one tests
the CPU path unless it turns the GPU path on.

The frame HUD, the render debug panel, and the shadow readout show one count per view: the
CPU path's count plus the GPU path's count. The GPU part is a few frames old.

## Checking it

`Developer > Rendering Performance > GPU Culling` has the switch
(`GPUCullingEnabledControl`) and the counts of both paths apart (`GPUCullingStatsLabel`):
instances drawn and culled for the camera and for all cascades together. With the switch on,
the CPU counts cover only the groups that stay on the CPU.

`make benchmark` measures the GPU path, and `make benchmark ARGS=--cpu-culling` the CPU path.
The `encodeTime` field of the result holds the CPU time of the shadow and scene pass encoding
([benchmark](/tools/benchmark.md)).
