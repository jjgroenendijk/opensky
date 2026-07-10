---
type: Subsystem
title: Metal 4 renderer skeleton
description: Current render loop - Metal 4 command flow, frame pacing, uniform
  ring buffer, argument tables, residency, MatrixMath conventions.
tags: [rendering, metal, engine]
timestamp: 2026-07-10T00:00:00Z
---

# Metal 4 renderer skeleton

State after milestone 1: `Renderer.swift` draws a rotating vertex-colored triangle to prove
the full Metal 4 pipeline end to end. Placeholder scene, real command flow — milestone 2.6
replaces the triangle with the static-mesh path but keeps these mechanisms. Command flow
adapted from Apple's Xcode Metal 4 game template (structure, not copied game code).

## Command flow (per frame, `draw(in:)`)

1. `MTLSharedEvent.wait` until GPU finished the frame that last used this slot
   (`frameIndex - maxFramesInFlight`) -> CPU never overwrites in-flight data.
2. Reset that slot's `MTL4CommandAllocator`; `beginCommandBuffer(allocator:)` on the single
   reused `MTL4CommandBuffer`.
3. Write uniforms into the slot's ring-buffer slice; encode one render pass.
4. `useResidencySet(metalLayer.residencySet)` -> `endCommandBuffer` ->
   `waitForDrawable` -> `commit` -> `signalDrawable` -> `signalEvent(frameIndex)` ->
   `present`.

## Mechanisms milestone 2.6 grows

* Frame pacing: `maxFramesInFlight = 3`, one `MTL4CommandAllocator` per slot, one
  `MTLSharedEvent` (`endFrameEvent`) signaled with the frame index at submit.
* Uniform ring buffer: one shared-storage `MTLBuffer`, `maxFramesInFlight` slots of
  `alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100`. 256-byte
  alignment satisfies Metal's buffer-offset requirement. Per-draw uniforms (2.6) extend
  this scheme to N draws per slot.
* Binding: `MTL4ArgumentTable` instead of encoder set-buffer calls —
  `argumentTable.setAddress(buffer.gpuAddress + offset, index:)`, table bound once per
  encoder via `setArgumentTable`. Indices come from `BufferIndex` in `ShaderTypes.h`
  (shared Swift <-> MSL).
* Residency: app-owned `MTLResidencySet` holds vertex + uniform buffers, committed once,
  attached to the queue via `addResidencySet`. New buffers/textures must be added +
  re-committed as they are created (2.6). Layer's drawable residency set attached per
  command buffer.
* Pipeline build: `MTL4Compiler.makeRenderPipelineState` from
  `MTL4RenderPipelineDescriptor` + `MTL4LibraryFunctionDescriptor` (no
  `MTLRenderPipelineDescriptor` function objects). Color `bgra8Unorm_srgb`, no depth yet —
  2.6 adds `depth32Float`.
* No-Metal-4 GPU (`.metal4` family unsupported) -> on-screen message, no crash
  (`GameViewController`).

## MatrixMath conventions

`MatrixMath.swift`, unit-tested (`openskyTests`). Column-major `float4x4`, `M * v`,
right-handed, camera looks down -z, projection maps z to Metal's [0, 1]. Helpers:
`radians(fromDegrees:)`, `rotation(radians:axis:)` (Rodrigues), `translation(_:)`,
`perspective(fovYRadians:aspectRatio:nearZ:farZ:)`. Skyrim Z-up basis change + lookAt +
TRS compose land with milestone 2.1 (see [todo](/todo.md)).

## Verification

Rotating triangle visually confirmed on M1, 2026-07-09, via XCUITest screenshot probe
(Screen Recording TCC unavailable on dev machine). Rendering acceptance stays visual +
frame stats — green build alone proves nothing on screen.
