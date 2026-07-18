---
type: Subsystem
title: Metal 4 static-mesh renderer
description: Static-mesh render path - pipeline variants, uniform rings, argument-table
  binds, counter-heap frame stats, offscreen render, scene types.
tags: [rendering, metal, engine]
timestamp: 2026-07-18T00:00:00Z
---

# Metal 4 static-mesh renderer

State after milestone 2.7 app wiring: `Renderer.swift` draws a `RenderScene` (engine
meshes + materials) through opaque and alpha-test pipeline variants. Scene source =
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
  transform, material slot. Rejects empty meshes/out-of-range indices (typed errors,
  mod-quirk rule).
* `RenderModel` — one engine `Model`: `RenderMesh`es + `RenderMaterial`s (diffuse
  `MTLTexture` resolved through a caller-supplied `TextureProvider` closure — demo scene
  feeds procedural textures, 2.7 feeds VFS + `TextureLoader`).
* `RenderScene` — (model, instance transform) pairs flattened to `DrawItem` lists:
  `modelMatrix = instance * meshLocal`, `normalMatrix` = inverse-transpose
  (`MatrixMath.normalMatrix`), opaque items grouped before alpha-tested so the pipeline
  switches once. `residencyAllocations` = deduped buffers + textures for the residency
  set. Alpha blending (`Material.alphaBlend`) renders opaque for now — out of 2.6 scope.
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

* Two `MTL4RenderPipelineState` variants from one fragment function
  (`staticMeshFragment`), selected via function constant `FunctionConstantAlphaTest`
  (`MTL4SpecializedFunctionDescriptor` + `MTLFunctionConstantValues`): opaque pays
  nothing for discard; alpha-test discards below `DrawUniforms.alphaThreshold`.
* Shading: diffuse map * (directional sun lambert + ambient), vertex color as baked
  tint (Skyrim bakes AO there), material alpha multiplied through. Normal mapping
  deferred (stretch goal) — no tangent attributes yet.
* Depth: `depth32Float` MTKView attachment, write-through less-compare
  `MTLDepthStencilState`. Metal 4 binds depth format at pass time, not in the pipeline
  descriptor. Near 10 / far 65 536 per [coordinates](/decisions/coordinates.md).
* Winding: front = counter-clockwise seen from outside, cull back, per-draw cull-none
  for double-sided materials. Verified on the demo ground plane; decision doc updated.

## Uniforms + binding

* `FrameUniforms` (viewProjection, camera position, sun direction/color, ambient) — one
  256-byte-aligned slot per in-flight frame.
* `DrawUniforms` (model + normal matrix, UV offset/scale, material alpha, alpha
  threshold) — ring of `maxFramesInFlight x scene.drawCount` 256-byte-aligned entries,
  written per draw each frame. Scene is fixed in 2.6; growth lands with 2.7 streaming.
* All binds through one `MTL4ArgumentTable` (3 buffers, 1 texture, 1 sampler); table
  state is captured per draw, so per-draw `setAddress`/`setTexture` between
  `drawIndexedPrimitives` calls is the binding model. Sampler: trilinear mipmapped,
  anisotropy 8, repeat, `supportArgumentBuffers`.
* Residency: app-owned `MTLResidencySet` holds uniform rings + every scene allocation
  (`RenderScene.residencyAllocations`), committed at scene build, attached to the queue.
  Offscreen targets are added/removed around each `renderOffscreen` call.

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
compositor. Used by `RendererOffscreenTests` (deterministic pixel assertions + temp PNG
for human review; Screen Recording TCC is unavailable on dev machines) and the committed
milestone screenshot (engine output, not window capture). Windowless
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
