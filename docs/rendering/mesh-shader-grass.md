---
type: Subsystem
title: Mesh-shader grass
description: How the renderer can draw grass with object and mesh shaders, which cull small
  clusters of triangles on the GPU, and how it compares with the classic instanced draw.
tags: [rendering, metal4, performance, grass]
---

# Mesh-shader grass

The classic grass path draws each grass group with one indexed, instanced draw. The vertex
shader runs for every vertex of every visible instance, even for blades behind the camera
or facing away. The mesh-shader path splits each grass mesh into meshlets: small clusters
of at most 64 vertices and 64 triangles. An object shader tests each meshlet of each
instance and starts a mesh shader only for the meshlets that can show.

Reference: Apple, "Metal Shading Language Specification", section on mesh and object
functions (`[[object]]`, `[[mesh]]`, `mesh_grid_properties`), and the Metal 4 API
`MTL4MeshRenderPipelineDescriptor` and `drawMeshThreadgroups`.

## When it runs

- It is off by default. The player setting `rendering.meshShaderGrass` stores the switch.
  It is in `Developer > Rendering Performance > Mesh-Shader Grass` and on the launcher
  Graphics page, under Grass.
- It needs a GPU with mesh shaders: Apple7 (M1) or Mac2. Other GPUs keep the switch
  disabled and say why.
- Render debug views keep the classic path, because only the classic path has their
  pipelines.
- The pipeline is built the first time the path draws. If it fails, the panel shows the
  error and the classic path draws.

## How it works

1. The first time a grass mesh draws on this path, the CPU reads its index and position
   buffers and splits it into meshlets, greedily in index order. Each meshlet stores a
   bounding sphere and a normal cone: the mean facing of its triangles and how far they
   spread. The meshlets of a mesh are dropped with the scene that held it.
2. Each grass group writes one `GrassMeshUniforms`: the six camera frustum planes, the
   meshlet and instance counts, whether back faces cull, and the largest sway offset.
3. `drawMeshThreadgroups` starts one object threadgroup of 32 threads per 32
   instance-meshlet pairs. Each thread moves its meshlet's sphere into world space with the
   instance transform, grows it by the sway offset, and tests it against the frustum. A
   single-sided mesh also tests the normal cone against the camera.
4. The threads that keep a pair compact it with a SIMD prefix sum
   (`simd_prefix_exclusive_sum`) into the payload, and the threadgroup starts that many mesh
   threadgroups.
5. Each mesh threadgroup runs the same vertex code as the classic path (`grassVertexOut`),
   so sway, lighting inputs, and fog match. The fragment shader is the classic one.

Two atomic counters per frame slot count the meshlets tested and drawn. The CPU reads them
when the slot comes round again, so the panel numbers are a few frames late.

Grass is double-sided in Skyrim, so the normal cone culls almost nothing there. The gain,
if any, comes from the frustum test per meshlet: the classic path keeps or drops whole
instances.

## Measured

`make benchmark ARGS='--mesh-shader-grass'` compares the paths ([benchmark](/tools/benchmark.md)).

On an M1, Release build, two runs of each path in turn, GPU time per frame:

| Path | Measured frames | Walk route |
| --- | --- | --- |
| Classic | 6.30 ms, 6.30 ms | 8.83 ms, 8.65 ms |
| Mesh shader | 6.63 ms, 7.47 ms | 8.99 ms, 9.27 ms |

The mesh path is a little slower here. Skyrim grass meshes are small (16 to 64 vertices,
one meshlet each), so a meshlet test culls no more than the CPU instance test already did,
and the object stage adds work. That is why the path is off by default.

## GPU memory limits

On the M1, the mesh path once failed with the GPU error "Too much geometry to support
memoryless render pass attachments" (`kIOGPUCommandBufferCallbackErrorOutOfMemoryForParameterBuffer`).
The triangles were correct, and the same frames drew fine with zero primitives. The cost
came from how the work was split:

- One object threadgroup per instance started many object threadgroups that each kept one
  meshlet. Real grass meshes have one meshlet each, so most of the work was wasted.
- With one lane per instance-meshlet pair instead, a meshlet limit of 124 triangles failed
  on every frame with `kIOGPUCommandBufferCallbackErrorOutOfMemory`.
- Pairs plus a limit of 64 triangles and 64 mesh threads ran the whole benchmark route with
  no error.

The GPU appears to reserve the declared maximum output for each mesh threadgroup, not what
the threadgroup writes. Keep the meshlet limits small when changing this path. The scene
depth stays memoryless, so the GPU cannot flush a pass that overflows; such a frame fails
instead of slowing down.
