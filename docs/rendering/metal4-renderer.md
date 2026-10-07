---
type: Subsystem
title: Metal 4 mesh renderer
description: The renderer's scene types, pipelines and pass order, shading and interior lighting,
  uniform rings and argument table binds, bind-pose skinning, frame pacing and GPU time, and the
  offscreen path.
tags: [rendering, metal, engine]
---

# Metal 4 mesh renderer

The renderer draws a `RenderScene` through sky, opaque, terrain, alpha-test, grass, and water
pipelines. The app hands in a built cell scene and a camera. With no scene, it falls back to a
synthetic demo scene built in code (a checker ground, three crates, and an alpha-test cutout), which
tests and a missing install use. The command flow follows the structure of Apple's Xcode Metal 4
game template.

How scenes are grouped, culled, and swapped is on the [scene drawing](/rendering/scene-drawing.md)
page.

## Scene types

- The static vertex layout is interleaved: position at byte 0, normal at 12, texture coordinate at
  24, color at 32, stride 48. A missing attribute gets a neutral default: a +Z normal, UV at the
  origin, white color.
- A render mesh is one engine mesh on the GPU: vertices, 16-bit indices, a local transform, and a
  material slot. A skinned mesh adds a 32-byte-per-vertex stream of weights and 16-bit bone indices,
  and a bone palette. Empty meshes, wrong skin array sizes, and out-of-range triangle or bone indices
  are typed errors, because mods ship broken data.
- A render model is a list of meshes and materials. Diffuse textures come from a texture provider.
  BCn textures upload directly. Legacy xRGB8888 becomes BGRA8 with X forced opaque, and RGBA8888
  becomes RGBA8 with its alpha. Color textures use sRGB, and normal and data textures use linear.
- A render scene is placements (model, transform, world bounding box) grouped into instanced draws.
  It also carries sky parameters for an exterior, water items, optional interior lighting, and point
  lights.
- The camera framing for a bounding box looks at its center from the south-west and above, at a
  distance of `radius / sin(fovY / 2) * 1.1`, so the enclosing sphere fits the 65 degree vertical
  field of view. Very small boxes use at least 64 units.

## Pass order

The shadow cascades draw first ([shadows](/rendering/shadows.md)). The scene pass then draws sky,
opaque groups, terrain, alpha-test groups, grass, water, particles, precipitation, the
[SWF layer](/rendering/swf-layer.md), and the [UI overlay](/rendering/ui.md) last.

Metal 4 does not track hazards between encoders. So the last cascade encoder issues a producer
barrier (`barrier(afterStages: .fragment, beforeQueueStages: .fragment, visibilityOptions:
.device)`), and the scene pass never samples the shadow array before its depth writes land.

## Render targets

Apple GPUs render the screen in tiles held in on-chip memory. A target that no later pass reads
can stay in that tile memory: it is memoryless, and it costs no GPU memory and no bandwidth.

| Target | Storage | Why |
| --- | --- | --- |
| Scene depth and stencil, live view and offscreen | memoryless | only the scene pass reads it |
| Shadow cascades | private | the scene pass samples them |
| Offscreen color | shared | the CPU reads it back |
| Grade copy and grade depth | private, made on first use | only a split grade needs them |

The [image space pass](/rendering/image-space.md) grades in tile memory, so most frames keep
depth memoryless. A grade with blur or double vision reads other pixels, so it splits the scene
pass in two. The first half then stores depth into the grade depth target. `Developer > Rendering
Performance > Render Targets` shows what each target costs.

## Pipelines and shading

Static and skinned meshes each have an opaque and an alpha-test pipeline. All four share one
fragment function, specialized by a function constant, so opaque draws pay nothing for discard.
Alpha-test draws discard below the material's threshold. The [render debug](/rendering/render-debug.md)
twins use a second function constant that no shipping pipeline defines.

Shading is: diffuse texture times (directional Lambert plus base ambient plus six-axis directional
ambient plus point lights). Vertex color is a baked tint, because Skyrim bakes ambient occlusion
there. Material alpha is multiplied through. There is no normal mapping yet, because there are no
tangents.

Depth is `depth32Float`, less-compare, with writes on. Metal 4 sets the depth format at pass time,
not in the pipeline. Near is 10 and far 65,536 ([coordinates](/decisions/coordinates.md)). The
front face is counter-clockwise seen from outside, back faces are culled, and a double-sided
material turns culling off per draw. The demo ground plane caught a wrong winding that closed boxes
had hidden.

The sky is a fullscreen triangle with no vertex buffer and no depth state. It draws a procedural
vertical palette and a sun disc from the time of day, and later geometry replaces its pixels. A
`WRLD` with no sky skips it. Water blends with straight alpha (source RGB times source alpha,
destination times one minus source alpha) and reads depth without writing it
([sky and water](/engine/sky-water.md)).

## Interior lighting

An interior resolves its [lighting records](/formats/lighting.md) before the renderer sees the
scene. The frame uniforms carry ambient, the directional light, six directional ambient colors, and
fog colors, range, power, and maximum. Static and terrain fragments apply fog by camera distance
after lighting. A bad fog range turns fog off.

Each visible draw uses at most 8 point lights. The CPU sorts the scene's lights by squared distance
to the draw's center, keeping scene order for equal distances. Attenuation is
`(1 - distance / radius)^falloff`, clamped to the range, times Lambert. Negative lights and spot
lights never reach the shader. Water and sky keep their own paths.

## Uniforms and binding

- Frame uniforms (view projection, camera position, lights, fog, time of day, animation time) take
  one 256-byte-aligned slot per frame in flight.
- Per-group draw uniforms (UV offset and scale, alpha, threshold) are a ring of frames in flight
  times group capacity, 256-byte aligned. Terrain and water uniforms share the ring, and the stride
  is the largest struct.
- Matrices live in a separate per-instance ring ([scene drawing](/rendering/scene-drawing.md)).

Every bind goes through one `MTL4ArgumentTable`, sized from the highest index in each `ShaderTypes.h`
enum. The table state is captured per draw, so setting addresses and textures between draws is the
binding model. The samplers are trilinear with 8x anisotropy and repeat, a shadow compare sampler
(less, linear, clamp), a linear clamp for the UI, and a linear repeat for SWF.

Residency is one app-owned `MTLResidencySet` holding the rings and every scene allocation, attached
to the queue. Offscreen targets are added and removed around each offscreen render.

## Bind-pose skinning

A skinned mesh selects the skinned pipeline. Buffer 6 holds normalized float4 weights and ushort4
bone indices, and buffer 7 holds mesh-local bone matrices. The vertex shader blends position and
direction by weight, then applies the instance matrices. With a bind-only palette, the palette is
identity within float error, so the mesh draws in its authored pose. Animated poses come from
[actor animation](/engine/actor-animation.md).

## Frame pacing and GPU time

Up to 3 frames are in flight, each with its own allocator, one reused command buffer, and a shared
event signaled with the frame index.

GPU time is the span that Metal's commit feedback reports for each frame's commit: from
`GPUStartTime` to `GPUEndTime`, in host seconds. It covers the shadow and scene passes together.
Command-buffer timestamps (`writeTimestamp`) are not used. On Apple GPUs they reported about
0.2 ms for frames that took several milliseconds, because the passes did not run between them.

Frame stats log one line per 120-frame window, and emit a signpost per frame for Instruments. Live
readouts use a separate 30-frame window, so reading it never moves the logged window. The counters
stay on the render thread, and only the finished snapshot crosses threads, behind a lock. So a 2 Hz
poll never sees a half-updated window. Before the first window closes, the snapshot says
"measuring", not zero frames per second. The frame HUD and the World panel read the same snapshot,
so they cannot disagree.

## Offscreen render

Offscreen rendering draws one frame into an owned color and depth target and waits for the GPU to
finish. There is no drawable and no compositor. Tests and the CLI use it. Never render through
`MTKView.currentDrawable` in a test: a window-less drawable crashes in `waitForDrawable`.

The sustained bench runs the same frame body on one reused target, with frame stats and timestamps
on every frame, and reports average and percentile frame times ([CLI](/tools/cli.md)). Each frame
waits for the GPU, so the numbers are an upper bound: a pipelined loop overlaps that round trip.

Matrix conventions (column-major, `M * v`, right-handed, camera looking down -z, depth mapped to
Metal's 0 to 1) are on the [coordinates](/decisions/coordinates.md) page.
