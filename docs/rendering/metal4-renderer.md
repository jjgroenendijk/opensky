---
type: Subsystem
title: Metal 4 mesh renderer
description: Static + skinned mesh paths - pipelines, uniform rings, argument-table
  binds, counter-heap frame stats, offscreen render, scene types.
tags: [rendering, metal, engine]
timestamp: 2026-07-20T00:00:00Z
---

# Metal 4 mesh renderer

`Renderer.swift` draws a `RenderScene` through sky, opaque, terrain, alpha-test, and
water pipeline variants. Scene source =
injection: `Renderer(view:scene:camera:)` takes a prepared `RenderScene` + `SceneCamera`
(the app hands in the built cell scene with `SceneCamera.framing(bounds:)`); nil scene
falls back to the synthetic `DemoScene` with its `.demo` camera (tests, missing game
data). Per-draw uniform ring is sized off the injected scene's `drawCount`. Command flow
adapted from Apple's Xcode Metal 4 game template (structure, not copied game code).

## Scene types (`opensky/Rendering/`)

* `StaticVertexLayout` — single source of truth for the interleaved vertex layout:
  float3 position (0), float3 normal (12), float2 texcoord (24), float4 color (32),
  stride 48, tightly packed. Owns the `MTLVertexDescriptor` + `interleave(Mesh)`.
  Missing attribute arrays -> neutral defaults (+Z normal, origin UV, white color).
* `RenderMesh` — one engine `Mesh` uploaded: vertex + uint16 index buffer, local
  transform, material slot. Skinned meshes add a 32-byte/vertex weights + uint16x4 index
  stream and float4x4 bone palette. Rejects empty meshes, bad skin array sizes,
  out-of-range triangle/bone indices (typed errors, mod-quirk rule).
* `RenderModel` — one engine `Model`: `RenderMesh`es + `RenderMaterial`s (diffuse
  `MTLTexture` resolved through a caller-supplied `TextureProvider` closure — demo scene
  feeds procedural textures, VFS + `TextureLoader` feeds real assets). `TextureLoader`
  uploads BCn directly; legacy xRGB8888 becomes BGRA8 with X forced opaque, RGBA8888
  becomes RGBA8 with stored alpha. Usage selects sRGB for diffuse/color, linear for
  normal/data.
* `RenderScene` — `RenderPlacement`s (model + transform + world AABB) flattened to
  instanced `DrawGroup` lists (section below): `modelMatrix = instance * meshLocal`,
  `normalMatrix` = inverse-transpose (`MatrixMath.normalMatrix`), opaque groups before
  alpha-tested so the pipeline switches once. `residencyAllocations` = deduped buffers +
  textures for residency. `SkyParameters?` marks exterior sky; `WaterDrawItem`s carry
  plane mesh, model matrix, WATR palette, bounds. Optional `RenderLighting` carries cell
  ambient/directional/fog; `RenderPointLight`s carry resolved LIGH placements. Static NIF
  `Material.alphaBlend` remains deferred; water owns the first dedicated blend path.
* `SceneCamera` — eye/target + sun/ambient consumed by `FrameUniforms`. `.demo` mirrors
  the DemoScene constants; `framing(bounds:)` frames a Z-up world AABB: target = box
  center, eye south-west of and above it along a fixed direction at distance
  `radius / sin(fovY / 2) * 1.1` (enclosing sphere fits the 65° vertical fov), minimum
  64 units for degenerate bounds. Unit-tested (`SceneCameraTests`). Replaced by the
  free-fly camera at 2.8.
* `DemoScene` — synthetic proving scene (checker ground, three crates, alpha-test cutout
  panel, camera + sun constants), built entirely in code (legal rule). Stays as the
  no-game-data fallback scene.

## Pipelines + shaders

* Static opaque + alpha-test variants use `staticMeshVertex`; skinned opaque + alpha-test
  variants use `skinnedMeshVertex`. All share `staticMeshFragment`, selected via function
  constant `FunctionConstantAlphaTest`
  (`MTL4SpecializedFunctionDescriptor` + `MTLFunctionConstantValues`): opaque pays
  nothing for discard; alpha-test discards below `DrawUniforms.alphaThreshold`. Further
  pipelines: terrain splat, procedural sky, water blend (sections below).
* Shading: diffuse map * (directional lambert + base ambient + six-axis directional
  ambient + point lights), vertex color as baked tint (Skyrim bakes AO there), material
  alpha multiplied through. Exterior scenes omit `RenderLighting` -> existing
  `SceneCamera` sun/ambient path stays unchanged. Normal mapping deferred (stretch goal)
  — no tangent attributes yet.
* Depth: `depth32Float` MTKView attachment, write-through less-compare
  `MTLDepthStencilState`. Metal 4 binds depth format at pass time, not in the pipeline
  descriptor. Near 10 / far 65 536 per [coordinates](/decisions/coordinates.md).
* Winding: front = counter-clockwise seen from outside, cull back, per-draw cull-none
  for double-sided materials. Verified on the demo ground plane; decision doc updated.

## Sky + water pipelines (todo 3.5)

Pass order = shadow cascade pre-pass ([shadows](/rendering/shadows.md)), then sky,
opaque groups, terrain, alpha-test groups, water last. Sky is
a fullscreen triangle with no vertex buffer or depth state. It reads time-of-day from frame
uniforms and writes a procedural vertical palette + sun disc; later depth-tested geometry
replaces its pixels. WRLD `no sky` suppresses the draw.

Water uses reusable cell-plane geometry + per-item `WaterDrawUniforms` (model matrix,
shallow/deep/reflection colors). Dedicated Metal 4 color attachment enables straight-alpha
blending: source RGB `.sourceAlpha`, destination `.oneMinusSourceAlpha`; alpha uses `.one`
plus `.oneMinusSourceAlpha`. Read-only depth (`.less`, write disabled) preserves earlier
terrain/object depth. Shader adds animated color ripples + view-angle reflection; geometry
stays flat. Details + real-frame evidence: [sky + water environment](/engine/sky-water.md).

## Interior forward lighting (todo 3.7)

Interior scene build resolves [XCLL/LGTM/LIGH](/formats/lighting.md) before renderer entry.
`FrameUniforms` carries ambient, directional direction/color, six directional-ambient
colors, fog colors/range/power/maximum. Static + terrain fragments apply fog by camera
distance after lighting. Invalid fog ranges disable fog.

Each visible draw selects at most `LightingConstantMaxPointLights = 8` lights. CPU sorts
scene lights by squared distance to draw center, retaining scene order for equal distance.
One shared `PointLightUniform` ring stores eight `{position, radius, color, falloff}` slots
per draw per frame. Fragment attenuation = `(1 - distance / radius)^falloff`, clamped to
range, times lambert. Negative + spot lights never reach ring. Water + sky stay on their
environment-specific paths.

## Terrain splat pipeline (todo 3.1)

Third pipeline (`TerrainSplat`, `terrainVertex`/`terrainFragment`, no function constants)
draws `RenderScene.terrain` — one `TerrainDrawItem` per LAND quadrant (built by
`CellSceneBuilder`, see [terrain](/engine/terrain.md)) — encoded between the opaque and
alpha-test lists. One draw blends the quadrant's BTXT base diffuse with up to 8 ATXT layer
diffuses by per-vertex VTXT opacities (UESP LAND).

Texture binding strategy — decision: per-quadrant multi-texture argument-table binds. Base
at `TextureIndexDiffuse`, layers as an MSL `array<texture2d<float>, 8>` at the 8 consecutive
slots from `TextureIndexTerrainLayer0`; per-draw `setTexture` like every other bind. Unused
slots rebind the base diffuse so every declared argument is valid; the shader loop stops at
`TerrainDrawUniforms.layerCount`. Rejected alternatives:

* `texture2d_array` — requires identical size/format/mip count across a quadrant's layer
  diffuses; vanilla TXST diffuses vary, forcing load-time re-encode/copies.
* per-layer draws — needs a new blending pipeline + depth-equal state and N draws per
  quadrant with framebuffer blend traffic; the single-pass shader loop is cheaper and keeps
  terrain in the one scene pass.

Layer cap: `TerrainConstantMaxLayers = 8` (ShaderTypes.h) — ATXT layer numbers 0-7, the
format maximum per the M3 plan pre-verification (UESP + xEdit). Vanilla peaks near 6 per
quadrant ([land](/formats/land.md) Verification), so nothing real is dropped; extras beyond
8 drop defensively and count into `CellLoadSummary.terrainLayerSkipCount`.

Weights: second per-vertex stream at `BufferIndexTerrainWeights` (`TerrainVertexLayout`:
two float4 lanes, stride 32) instead of forking the 48-byte `StaticVertexLayout` — the
static interleave + `RenderMesh` upload stay untouched. VTXT positions 0-288 index the
17x17 quadrant grid row-major (UESP LAND), exactly the builder's vertex emission order, so
`TerrainMeshBuilder.denseOpacities` + `packWeights` bake sample -> vertex 1:1.

Blend math: `albedo = base; for layer in ATXT-layer-number order: albedo = mix(albedo,
layerColor, saturate(weight))`. Straight lerp is the plain reading of the VTXT opacity
semantics; the exact vanilla blend curve is UNCONFIRMED. Lighting after the blend is
identical to the static path (sun lambert + ambient, vertex color tint) so terrain matches
the M2 buildings. Terrain is always opaque.

`TerrainDrawUniforms` shares the per-draw uniform ring (slot size = max of both structs,
256-byte aligned). Deferred: normal maps (TX01) — splat is diffuse-only like the static
pipeline; UV tiling density (`uvQuadsPerRepeat = 2`) remains UNCONFIRMED, visually
plausible at Whiterun.

## Frustum culling (todo 3.2)

`Rendering/Frustum.swift`, unit-tested (`FrustumTests`), renderer-independent.
`Frustum(viewProjection:)` extracts 6 inward
planes from a combined `P * V` matrix via Gribb/Hartmann ("Fast Extraction of Viewing
Frustum Planes from the World-View-Projection Matrix", 2001), adapted twice from the
paper: column vectors (`clip = M * v`) put the planes on the *rows* of the matrix instead
of columns, and Metal's z in [0, 1] clip range (vs the paper's OpenGL [-1, 1]) makes near
= row2 alone (not row3 + row2) and far = row3 - row2. Verified against
`MatrixMath.perspective`'s actual coefficients, not assumed from the paper.

`intersects(min:max:)` is a conservative positive-vertex (p-vertex) AABB test: per plane,
test only the box corner furthest along the plane normal. Straddling or fully-inside boxes
test true; only boxes fully outside some plane test false. Never culls a visible box.
`intersects(_:ModelBounds)` overload accepts `MeshLibrary.ModelBounds` directly; the core
API stays on plain `SIMD3<Float>` min/max to keep math decoupled from the mesh-loading
type.

Wiring (renderer core, 3.2): every draw item carries a world-space AABB —
`RenderPlacement` (model + transform + bounds) feeds `RenderScene`, which stamps the
placement's bounds onto each of its `DrawItem`s (model-level AABB shared by all meshes of
one instance — conservative); `TerrainDrawItem` carries its patch AABB. Sources: cell
build pushes `MeshLibrary.bounds(forPath:)` through the placement transform (the same
value the cell AABB unions), terrain uses the patch mesh bounds, `DemoScene` computes its
own. nil bounds -> never culled (preview single-model scenes, synthetic tests).
`encodeScenePass` builds one `Frustum` per frame from the exact view-projection the
shaders get and skips failing items; the per-draw uniform ring is indexed by a running
visible-draw cursor (visible <= `drawCount` = ring capacity, always safe), not
precomputed bucket offsets. Per-frame accounting lands in `Renderer.lastDrawStats`
(`SceneDrawStats`: drawCalls / drawnInstances / culledInstances) — asserted by
`RendererCullingTests` (culled far object keeps the frame pixel-identical; camera facing
away culls everything and renders pure clear). Encode path lives in
`Rendering/RendererScenePass.swift` (split from `Renderer.swift`, file-length limits).

## Scene swap + retire list (todo 3.2, streaming precondition)

`Renderer.setScene(_:camera:)` replaces the drawable scene between frames — the
precondition for cell streaming. Threading: same thread as `draw(in:)` /
`renderOffscreen` (main); the renderer has no locking, "between frames" comes from that
shared thread, never from blocking on the GPU. Optional camera reseeds sun/ambient + the
free-fly pose (first real scene after an empty launch scene needs a framing pose).

* Ring regrowth: the per-draw uniform ring is sized by `drawUniformSlotCapacity` = next
  power of two >= `drawCount` (min 1) so per-cell-crossing swaps rarely realloc; a swap
  whose `drawCount` exceeds capacity allocates a new ring and retires the old one (never
  reused in place — in-flight frames may still read it).
* Retire list: old scene allocations + replaced rings go into `RetiredAllocations`
  entries tagged with the newest committed frame index (`frameIndex - 1`). Strong refs
  keep them alive; entries drop once `endFrameEvent.signaledValue` proves the tag
  drained. Purged opportunistically in `draw(in:)` and `setScene` — swap never waits.
* Residency: `MTLResidencySet` membership is a plain set (no refcount) and removals take
  effect at `commit()` even if queued frames still reference the allocation — so
  `setScene` only ADDS the new scene's allocations (+ new ring) and commits; removal of
  the old ones happens at purge time, after the drain proof, filtered against the live
  set (current scene + rings) because a swap A -> B -> A or adjacent cells sharing
  meshes/textures make an allocation retired and live at once.

`World/CellSceneComposition.swift` is the streaming controller's cell container:
`[CellCoordinate: CellScene]` with `setCell`/`removeCell`, `composedScene()` via
`RenderScene(merging:)` in deterministic (x, y) order, `composedBounds()` union for a
first framing camera, `coordinates` as the `loaded` set for `CellGridManager.update`.
M3.4 adds optional `DistantLODScene` to draw-list merge + residency union, deliberately
excluded from `composedBounds()` so horizon assets do not alter launch framing.
Pure value logic (`CellSceneCompositionTests`); the async streaming controller that
drives it lands in a later 3.2 commit. Verified through real frames:
`RendererSceneSwapTests` (regrow swap keeps rendering, empty-scene swap renders pure
clear, camera reseed on swap).

## Instanced draws (todo 3.2)

Instances sharing one mesh + material draw as ONE `drawIndexedPrimitives(...
instanceCount:)`. `RenderScene` groups at construction: `DrawGroup` (mesh, material,
`[DrawInstance]`), key = (`ObjectIdentifier(mesh)`, `ObjectIdentifier(material.diffuse)`)
— a `RenderMesh` belongs to exactly one `RenderModel` whose materials array pins one
material per slot, so mesh identity already implies identical material scalars; the
diffuse id rides along defensively. First appearance fixes group order (deterministic
frames); `CellSceneBuilder`'s (mesh path, FormID) instance sort means group order matches
the old draw order within a cell. `RenderScene(merging:)` re-groups across cells —
adjacent cells placing the same cached model share one instanced draw.

Per-draw GPU data split: per-GROUP `DrawUniforms` (UV offset/scale, alpha, threshold)
stay in the 256-aligned ring (group count <= drawCount); per-INSTANCE `InstanceTransform`
(model + normal matrix, 128 bytes, no padding) moves to a tightly-packed ring (stride =
struct size, `instanceSlotCapacity` entries per in-flight slot, same pow2
regrow-on-swap). `staticMeshVertex` gains `[[instance_id]]` and indexes a `device
InstanceTransform*` bound at the group's base byte offset — instance_id starts at 0 per
draw call, so the pointer lands exactly on the group's visible instances. Opaque +
alpha-test variants share the vertex function (the function constant specializes only
the fragment); terrain stays non-instanced with its own uniforms.

Culling composes per instance: each frame writes only frustum-surviving instances'
transforms (contiguous, running cursor), draws the group with the visible count, skips
all-culled groups entirely (no uniform slot consumed). `SceneDrawStats`: drawCalls =
encoded groups + terrain items; drawnInstances counts written instances. Real-install
evidence (`openskycli render` draw-stats line): Whiterun (6,-2) 49 instances -> 32 draw
calls; 3x3 grid 711 instances -> 330 draw calls. Grid frame differs from the
pre-instancing baseline by 54 of 921 600 pixels (max channel delta 34) — draw-order
change at z-fighting edges, visually identical.

## Uniforms + binding

* `FrameUniforms` (viewProjection, camera position, directional/ambient/fog,
  time-of-day, animation time) — one
  256-byte-aligned slot per in-flight frame.
* `DrawUniforms` (UV offset/scale, material alpha, alpha threshold — per GROUP) — ring
  of `maxFramesInFlight x drawUniformSlotCapacity` 256-byte-aligned entries, written per
  visible group each frame; regrown on scene swap (section above). Matrices live in the
  per-instance `InstanceTransform` ring (instancing section).
* `WaterDrawUniforms` shares draw-ring slots with static/terrain uniforms; ring stride uses
  largest struct, 256-byte aligned.
* All binds through one `MTL4ArgumentTable` (8 buffers — vertices, frame + draw uniforms,
  terrain weights, instance transforms, point lights, skin attributes, bone matrices;
  1 + 8 + 1 textures — diffuse + terrain layer array + shadow-map array; 2 samplers);
  table state is captured per draw, so per-draw `setAddress`/`setTexture`
  between `drawIndexedPrimitives` calls is the binding model. Samplers: trilinear
  mipmapped, anisotropy 8, repeat, `supportArgumentBuffers`; shadow compare sampler
  (less, linear, clamp — [shadows](/rendering/shadows.md)).
* Residency: app-owned `MTLResidencySet` holds uniform rings + every scene allocation
  (`RenderScene.residencyAllocations`), committed at scene build, attached to the queue.
  Offscreen targets are added/removed around each `renderOffscreen` call.

## Bind-pose skinning (M5.3)

Skinned draw groups select pipeline by `RenderMesh.isSkinned`. Vertex buffer 6 carries
float4 normalized weights + ushort4 global bone indices; buffer 7 carries mesh-local
float4x4 bone matrices. Vertex shader computes weighted position + direction transforms,
then applies existing instance model/normal matrices. Static groups keep prior layout +
pipeline. Both skin buffers join scene residency sets.

Bind-only palettes resolve to identity within float error from NiSkinData inverse binds.
This draws each mesh in its authored bind pose; animation/current skeleton pose is M6+.
Real-data gate: textured `malebody_1.nif` through Asset Browser offscreen, CPU weighted
bounds equal source bounds within 0.01 units, lit pixels >1%.

## Frame pacing + stats

* Pacing unchanged from the skeleton: `maxFramesInFlight = 3`, allocator per slot, one
  reused `MTL4CommandBuffer`, `MTLSharedEvent` signaled with the frame index.
* GPU time: `MTL4CounterHeap` (timestamp type, 2 entries per slot),
  `commandBuffer.writeTimestamp` at frame start/end, resolved on the CPU when the slot's
  shared-event wait proves the frame finished. Tick -> ns via
  `MTLDevice.sampleTimestamps` correlation pairs per stats window (`FrameStats`).
* `FrameStats` logs one line per 120-frame window (subsystem `nl.jjgroenendijk.opensky`,
  category `FrameStats`): avg/max frame interval + fps, avg CPU encode, avg GPU ms;
  os_signpost interval per frame for Instruments. This is the measurable basis for the
  2.9 >30 fps gate.

## Offscreen render + sustained bench

Offscreen path lives in `Rendering/RendererOffscreen.swift` (split from
`Renderer.swift` for file-length limits, `RendererSetup.swift` precedent).
`Renderer.renderOffscreen(width:height:)` renders one frame into an owned color+depth
target and blocks on the shared event until the GPU finishes — no drawable, no
compositor. Used by `RendererOffscreenTests` (deterministic pixel assertions + local temp
capture for human review; Screen Recording TCC is unavailable on dev machines). Windowless
`MTKView.currentDrawable` rendering crashes in `waitForDrawable` — never test through
drawables.

`renderOffscreenSustained(width:height:frames:)` loops that frame body against one
reused target, every frame instrumented: FrameStats begin/end + counter-heap timestamp
writes, pair resolved right after the synchronous wait. Returns `OffscreenBenchResult`
(per-frame wall ms — avg / nearest-rank percentile, unit-tested — plus flushed
FrameStats window lines). Synchronous frames include the full CPU-GPU round trip a
pipelined loop overlaps -> numbers are a conservative upper bound. Consumed by
`openskycli bench`, the todo 2.11 ">30 fps sustained, measured" gate
([CLI](/tools/cli.md)).

## MatrixMath conventions

`MatrixMath.swift`, unit-tested. Column-major `float4x4`, `M * v`, right-handed, camera
looks down -z, projection maps z to Metal [0, 1]. `lookAt` builds the view straight from
Z-up world vectors; `placement` composes REFR transforms; `normalMatrix` =
inverse-transpose with identity fallback on singular input. Full conventions:
[coordinates](/decisions/coordinates.md).

## Verification

Demo scene visually confirmed on M1, 2026-07-10, via offscreen render PNG: textured
ground + crates, alpha-test holes show geometry behind them, per-face lighting. The
ground plane (only single-sided flat mesh) caught the inverted provisional winding —
closed boxes masked it. Rendering acceptance stays visual + frame stats; a green build
proves nothing on screen.

Milestone 2 shot — WhiterunExterior06 (Tamriel 6,-2) rendered by our engine from the
user's own install (`openskycli render --size 1920x1080 --zoom 1.8`, 2026-07-18, M1):
city wall segments with gate arch, Jorrvaskr roof, thatched houses. 15/16 refs drawn.
The original M2 shot retains its black-background baseline; current sky/water evidence:
[sky + water environment](/engine/sky-water.md). Engine output, not extracted game data.

Milestone 5 shot — Chillfurrow Farm (Tamriel 7,-3, Whiterun exterior) with placed
actors as bind-pose skinned bodies (`openskycli screenshot --x 7 --y -3 --zoom 10
--size 1920x1080`, 2026-07-20): four clothed farmhands stand at their ACHR poses by
the fence, cell reports 7 actors (7 drawn). Actor pipeline detail:
[actor records](/formats/actors.md). Engine output, not extracted game data.

Generated render captures stay local; numeric render + accounting results are retained here.

Same run's fps gate (todo 2.11), measured via `openskycli bench` on Apple M1, real
install: 360 frames @ 1280x720 avg 0.39 ms (2557 fps), p95 0.43 ms; @ 1920x1080 avg
0.54 ms (1846 fps), p95 0.61 ms — >30 fps sustained with wide margin (budget 33.33 ms).
