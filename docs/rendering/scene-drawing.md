---
type: Subsystem
title: Scene drawing
description: How a render scene reaches the GPU - the terrain splat pipeline and its texture binding
  choice, frustum culling, instanced draw groups, and swapping scenes between frames with a retire
  list and residency rules.
tags: [rendering, metal, terrain, culling, streaming]
---

# Scene drawing

This page covers what the [Metal 4 renderer](/rendering/metal4-renderer.md) does with a scene:
terrain, culling, instancing, and swapping.

## Terrain splat

Terrain has its own pipeline. It draws one item per `LAND` quadrant ([terrain](/engine/terrain.md)),
between the opaque and alpha-test lists. One draw blends the quadrant's `BTXT` base texture with up
to 8 `ATXT` layer textures by the per-vertex `VTXT` opacities (UESP LAND).

The textures bind per quadrant: the base at the diffuse slot, and the layers as an MSL
`array<texture2d<float>, 8>` on the 8 slots after it. Unused slots get the base texture again, so
every declared argument is valid. The shader loop stops at the layer count. Two other ways were
rejected:

- A `texture2d_array` needs the same size, format, and mip count in every layer. Vanilla `TXST`
  textures differ, so it would need copies at load time.
- One draw per layer needs a blending pipeline, a depth-equal state, and N draws with framebuffer
  blending. One pass with a shader loop is cheaper.

The cap is 8 layers, `ATXT` layer numbers 0 to 7, the format maximum per UESP and xEdit. Vanilla
peaks near 6 per quadrant ([land](/formats/land.md)), so nothing real is dropped. Extras are dropped
and counted.

Weights are a second vertex stream (two float4 lanes, stride 32), so the 48-byte static layout stays
as it is. `VTXT` positions 0 to 288 index the 17 by 17 quadrant grid row by row (UESP LAND), which is
the order the mesh builder writes vertices, so a sample maps to a vertex one to one.

The blend starts at the base and, in layer order, does `mix(albedo, layerColor, saturate(weight))`.
A straight blend is the plain reading of the opacities. The exact vanilla blend curve is not
confirmed. Lighting after the blend is the static path, so terrain matches buildings. Terrain is
always opaque and has no normal maps. The UV tiling density, 2 quads per repeat, is not confirmed
either, but looks right at Whiterun.

## Frustum culling

The frustum is six inward planes taken from the combined `P * V` matrix, after Gribb and Hartmann,
"Fast Extraction of Viewing Frustum Planes from the World-View-Projection Matrix" (2001). It differs
from the paper twice. Column vectors (`clip = M * v`) put the planes on the rows, not the columns.
Metal's clip z runs 0 to 1, not OpenGL's -1 to 1, so near is row 2 alone and far is row 3 minus row
2. This was checked against the real projection coefficients.

The box test checks, per plane, only the corner furthest along the normal. A box that crosses a plane
or is inside passes. Only a box fully outside one plane fails. So it never culls a visible box.

Every draw item has a world bounding box. A placement's box is shared by all its meshes, which is
safe. Terrain uses its patch box. An item with no box is never culled. One frustum is built per
frame from the exact view projection the shaders get. Draw stats count draw calls, drawn instances,
and culled instances.

## Instanced draws

Instances that share a mesh and a material draw as one instanced call. A group's key is the mesh and
the diffuse texture. A mesh belongs to one model, and the model fixes one material per slot, so the
mesh already implies the material. The texture is in the key only as a safety check. The first
appearance fixes group order, so frames are deterministic. Merging cells groups again across them,
so neighbor cells that place the same model share one draw.

Group data (UV, alpha, threshold) stays in the 256-byte-aligned draw ring. Instance data (model
matrix, normal matrix, and grass data, 160 bytes) goes in a packed ring. The vertex shader indexes it
with `[[instance_id]]`, bound at the group's first visible instance. `instance_id` starts at 0 in
each draw call, so the pointer lands on the group's visible instances.

Culling works per instance. Each frame writes only visible instances, packed, and draws the group
with that count. A fully culled group is skipped and uses no uniform slot. Terrain is not instanced.
Grass uses the instance ring with its own pipeline ([grass](/engine/grass.md)).

## Swapping scenes

A new scene replaces the old one between frames, which is what [cell streaming](/engine/cell-streaming.md)
needs. It runs on the same thread as drawing, so "between frames" comes from sharing that thread,
never from waiting on the GPU. A camera can come with it, which resets the sun and the fly pose.

- Rings have a capacity of the next power of two at or above the draw count, so most swaps reuse
  them. A bigger scene gets a new ring and retires the old one. A ring is never reused in place,
  because frames in flight may still read it.
- Retired allocations are kept alive in a list, tagged with the newest committed frame. An entry is
  dropped once the frame event shows that frame finished. The list is cleaned during drawing and
  swapping, and a swap never waits.
- Residency set membership has no reference count, and a removal takes effect at commit even if a
  queued frame still uses the allocation. So a swap only adds the new scene's allocations. Removal
  happens at cleanup, after the frame is proven done, and skips anything the live scene still uses.
  A swap from A to B and back to A, or two cells sharing a mesh, can make one allocation both retired
  and live.

The streamer keeps its cells in a composition keyed by cell coordinate. It merges them in (x, y)
order, so the merged scene is deterministic. Distant LOD joins the draw list and residency, but not
the bounds used to frame the first camera, so horizon models do not change the start view.
