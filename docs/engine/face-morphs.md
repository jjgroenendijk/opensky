---
type: Subsystem
title: Face morph runtime
description: Per-actor named TRI weights, CPU delta composition, Metal skinning, shadows,
  and the app inspection surface.
tags: [engine, facegen, morph, animation, metal, actor, app-ui]
timestamp: 2026-08-11T00:00:00Z
---

# Face morph runtime

Issue #207 adds named FaceGen expression weights to resident actors. It deliberately stops
short of lip timing: a caller may set target weights from zero through one, and the renderer
applies the result, but `.lip` timing and expression scheduling belong to later work.

The container and record chain are documented in
[FaceGen TRI expression container](/formats/tri.md). Actor appearance and baked FaceGen
assembly remain documented in [actor records](/formats/actors.md).

## Contents

* Ownership and association
* Composition
* GPU stream and pipeline variants
* Frame safety and instancing
* Shadow parity
* Inspection surface
* Failure policy
* Verification
* Deliberate gaps

## Ownership and association

`ActorModelRole.faceGenHead` preserves the role of the baked face model after assembly.
`CellSceneBuilder.makeFaceMorphPlayback` uses that role to keep expression association away
from body and attachment meshes. It combines gendered RACE defaults with the resolved NPC_
head parts, removes duplicate FormIDs in record order, and attempts one HDPT-to-shape pair
for each expression-bearing record.

The binding map is keyed by `ObjectIdentifier(RenderMesh)`. A `FaceMorphPlayback` owns that
map, the actor FormID, paired VFS paths, reason-tagged misses, current named weights, unknown
target tally, and face world bounds. It is a sibling of `ActorAnimationPlayback` through the
shared `RenderAnimation` protocol; skeletal animation and face morphing do not own or reset
one another.

## Composition

`FaceMorphComposer` builds immutable target data when the actor is assembled:

1. Scale every signed TRI position component by the target's Float32 scale.
2. Compute area-weighted base normals from the TRI triangle topology.
3. Add one target's position deltas to the base positions and recompute its normals.
4. Store the target normal delta as `morphedNormal - baseNormal`.

On a weight change, the CPU creates one dense `MorphVertexDelta` array. For each known
target, it clamps the requested weight to `[0, 1]`, multiplies both position and normal
deltas, and adds them into the array. Missing names do not mutate a buffer and increment the
playback's inspection tally. Multiple active targets add in deterministic target order.

This CPU route is intentional. The interactive surface changes a small named weight set at
human input frequency, while the vertex shader consumes the already composed dense result
every frame. It avoids uploading every TRI target or evaluating a variable target loop per
vertex.

## GPU stream and pipeline variants

`MorphVertexDelta` is two SIMD-aligned `SIMD3<Float>` values: position at byte zero and
normal at byte 16, for a 32-byte stride. `BufferIndexMorphDeltas` is buffer 14; vertex
attributes eight and nine read the two Float3 values.

The main and debug scene pipeline sets add morph-capable skinned opaque and alpha-test
variants. `morphedSkinnedMeshVertex` adds position and normal deltas before applying the
existing four bone influences. This order is load-bearing: TRI deltas are in the face
shape's pre-skin space, so morphing after skinning would rotate neither the displacement nor
its normal with the actor's pose.

The cached `RenderMesh` remains immutable. `RenderPlacement.faceMorphs` carries the actor's
optional per-mesh streams, and `DrawGroup.faceMorph` selects the pipeline. The mesh can
therefore remain shared in `MeshLibrary` while every actor using it has independent weights.

## Frame safety and instancing

Each `FaceMorphBuffer` allocates one 32-byte-per-vertex region for every renderer frame in
flight. CPU state changes update `currentDeltas`; immediately before encoding, the renderer
copies them into the active ring slot. `frameMorphPrepared` spans the shadow and scene
passes, so each stream is copied at most once in a frame and no CPU write races a prior GPU
frame.

Morph-buffer identity is part of the draw-group key. Two actor placements sharing a cached
face mesh but owning different expression state cannot be folded into one instanced draw.
Ordinary rigid and skinned placements keep a nil morph and retain the grouping behavior they
had before this subsystem.

## Shadow parity

`shadowMorphedSkinnedVertex` performs the same position-delta-before-skinning operation as
the scene vertex function. Morph-capable groups choose the morph shadow pipeline and bind
the same frame-ring stream. A mouth or brow therefore cannot move in the color pass while
casting the bind-pose silhouette.

## Inspection surface

`World > HUD & Interaction > Face Morphs` follows the open dialogue speaker, falling back
to the actor under the crosshair. It exposes:

* `FaceMorphTargetControl`: all names in the actor's paired containers.
* `MorphWeightControl`: the selected target's zero-through-one weight.
* `FaceMorphResetControl`: clears every active weight.
* `FaceMorphStatsLabel`: actor, target and active counts, paired paths, association misses,
  and unknown-target writes.

A nonzero weight contributes to the destination's override indicator. Destination Reset
clears the weights through the same provider seam as the section button. The control never
reaches into `Renderer` directly; `FaceMorphControlProviding` keeps the AppKit section
independent of scene ownership.

## Failure policy

TRI parse and association failures are actor-local degradation. They do not reject a
renderable actor or its baked FaceGen head. The playback retains all misses for inspection,
and any successful pair still morphs. Structurally malformed TRI input throws typed
`TRIError` rather than crashing or indexing out of bounds.

## Verification

Synthetic suites cover header and payload validation, exact string termination, truncated
and trailing data, topology indices, weight clamping, additive position and normal deltas,
unknown target accounting, and the GPU layout. Panel tests pin all three required
accessibility identifiers and exercise weight/reset provider calls.

`FaceMorphRenderRealDataTests` assembles Heimskr from the read-only install. The gate
requires at least the head and mouth pairs, confirms `MaleHead.tri` and `MouthHuman.tri`,
renders `Aah` at zero and one, requires more than 20 changed pixels, and renders weight one
again with a zero-pixel residual. The 2026-08-11 run produced six pairs, 47 targets and 708
changed pixels. Its two PNGs live only in the gitignored timestamped test run.

## Deliberate gaps

* No `.lip` timing or dialogue-clock-to-weight scheduler.
* No RACE slider or character-creation morph controls.
* No body morph containers.
* No expression animation state machine or automatic idle expressions.
* No persistence of developer-panel weights across actor eviction or save/load.
