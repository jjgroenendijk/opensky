---
type: Subsystem
title: Actor idle animation
description: Direct HKX idle sampling, skeleton-world composition, NIF palette refresh,
  streamed playback ownership, fallback accounting, frame budget, and the graph-driven
  player path that shares the same composition.
tags: [engine, actors, animation, hkx, skinning, streaming, locomotion, milestone-14]
timestamp: 2026-08-09T00:00:00Z
---

# Actor idle animation

## Contents

* [Playback path](#playback-path)
* [The graph-driven player path](#the-graph-driven-player-path)
* [Streaming lifecycle and fallback](#streaming-lifecycle--fallback)
* [Timing and acceptance](#timing--acceptance)

Milestone 6 adds direct idle-clip playback to streamed human actors. Container, skeleton,
binding, and spline layouts come from the clean-room format work in
[HKX container](/formats/hkx-container.md), [hkaSkeleton](/formats/hka-skeleton.md), and
[hkaSplineCompressedAnimation](/formats/hka-animation.md).

Milestone 14 item 14.6 moved the boundary that used to sit at "before behavior graphs".
The *player* is now posed by a running
[behavior graph](/engine/behavior-runtime.md) through the same composition and the same
palette formula. M16 item 16.4 gives moving NPCs a kinematic locomotion drive: the capsule
owns travel while `ActorAnimationPlayback` selects an in-place walk or run clip. Parked NPCs
keep direct idle playback and allocate no movement controller.

Milestone 15 item 15.7 kept that boundary and widened the single-clip path by exactly one
notch: `ActorAnimationPlayback` now takes a **bounded clip override** and returns to the idle
clip when it expires, which is what lets the dev target play an attack, a stagger and a hit
reaction without a behavior graph. The override is sampled from its own frame zero rather
than from the shared clock, so a clip started mid-session starts at its beginning. Which
clips, and where their paths were read from, is in [combat loop](/engine/combat.md).

## Playback path

`ActorAnimationPlayback` samples the gender-specific character `mt_idle.hkx` at renderer
time modulo clip duration. `ActorAnimationClipLoader` does the decoding, taking the animation
path as a parameter so the same loader serves idle, walk, run, and combat reactions.
Binding resolves tracks to skeleton bone indices. Missing tracks
retain `hkaSkeleton.referencePose`; local translation-rotation-scale matrices compose through
the parent graph into skeleton-world transforms. Invalid indices or parent cycles fail the
update safely.

Skeleton-world transforms name-map onto each NIF skin palette. A matched palette entry is:

```text
rootParentToSkin * animatedSkeletonWorld * skinToBone
```

Unmatched NIF/helper bones keep their verified bind-pose matrix. Bone names and original
skin transforms flow from `NIFModel` into `MeshSkinning`; `RenderMesh` owns the mutable CPU
palette. GPU palette storage has one slot per frame in flight. Renderer copies the current
CPU palette into the active slot immediately before draw encoding, preventing updates from
overwriting matrices used by an older GPU frame.

## The graph-driven player path

`PlayerAnimationPlayback` conforms to the same `RenderAnimation` protocol as
`ActorAnimationPlayback` and ends in the same `RenderMesh.updateSkinningPose(_:)`. Three
things differ, and only three:

* **The pose source.** A `PlayerPoseBuffer` carries the dense
  [behavior-graph](/engine/behavior-runtime.md) pose across from the locomotion bridge.
  `SkeletonPoseMath.worldMatrices(skeleton:localPoses:)` composes a dense per-bone pose
  through the same parent graph the sparse sample overload uses, so the two agree on what
  an unanimated bone is.
* **The clock.** The graph is stepped by `LocomotionBridge.plan` on the *simulation* clock —
  the fixed 120 Hz substeps `Renderer.advanceCamera` drives — not on the renderer's
  wall-clock animation clock. That is deliberate: the graph is part of movement, it consumes
  the same `Speed` and `Direction` the capsule moves by, and a graph advanced on a second
  clock could report a state the capsule was never in. The wall-clock animation pass only
  publishes the pose the simulation already produced, which is why `update(at:)` ignores
  its time argument and why an unchanged pose revision costs one comparison.
* **The ownership.** The player body is not cell-owned, so it is not in
  `RenderScene.animations` — everything there is evicted with its cell. The renderer holds
  it directly; see [Terrain walk mode](/engine/walk-mode.md).

The `World > Environment > Actor animation` A/B toggle covers the player exactly as it
covers an NPC: off restores the bind palette, on recomposes.

### Why composed poses used to tear the mesh

Writing any composed pose into a skinned actor's palette tore the mesh into long flat
shards, while the same body drawn from its NIF bind palette rendered correctly. The
behavior graph was never involved: composing the rig's own reference pose — no animation at
all — tore it the same way, and that is the useful measurement, because `skeleton.hkx`'s
reference pose and `skeleton.nif`'s bind pose are the same pose. A palette built from the
reference pose therefore has to come out as the bind palette, and it did not.

The two files disagreed about which way a bone turns. NIF stores its rotations for row
vectors and OpenSky's matrices multiply column vectors, so a `Matrix33` has to be
transposed on the way in ([NIF](/formats/nif.md)); it was not being transposed. Havok needs
no such correction, so the same bone came out of the two files as transposes of each other.
Nothing before this had noticed, for two reasons. Vanilla statics rotate almost nothing at
the `NiNode` level, so the world rendered the same either way. And a skinned mesh's *bind*
palette cancels the error — it is built as `rootParentToSkin * boneBind * skinToBone` with
both halves read from the same file — so the bind pose looked right while every pose
composed on top of it inherited the disagreement.

Measured on the local install (2026-08-04): before the transpose, composing the reference
pose missed `skeleton.nif`'s bind transforms by up to 61.9 world units over the 96 bones the
two files share, and `rootParentToSkin * boneBind * skinToBone` on a vanilla body shape came
out about 10 units away from the identity on a thigh. After it, the rig reproduces the NIF
bind pose to 5.3e-5 and the palette identity holds to 8e-6.

The defect predated milestone 14 and applied to streamed NPCs through
`ActorAnimationPlayback` identically, which the M6 render gate missed: it only asserts that
two frames differ, and a torn mesh satisfies that. The real-data gate
(`PlayerBodyRenderRealDataTests`) now also bounds how much of the frame a posed body covers
against how much the bind-pose body covers. Shards spray across the frame, so their coverage
runs to several times a standing figure's; the bound is what a torn mesh cannot pass.

`SkinningPalette` holds the composition itself, away from Metal, so the round trip is
checked against hand-built matrices with no device in the way
(`SkinningPaletteBindPoseTests`).

## Streaming lifecycle + fallback

`CellSceneBuilder` caches decoded immutable clips by normalized skeleton path + gender.
Every rendered actor gets a cell-owned `ActorAnimationPlayback`; composing resident scenes
composes those playback objects. Cell eviction drops its playback objects with its
`RenderScene`, while reusable clip data can remain cache-hot.

`setLocomotionClip(_:)` changes the base clip beneath bounded combat overrides. A reaction
that is already playing keeps its own clock and returns to the most recent gait rather than
always returning to idle. The gait files and skeleton binding use the same decoded-clip
cache shape as reactions.

One render update samples each unique clip once, then refreshes each shared `RenderMesh`
palette once. Actor instances that share body assets also share the resulting pose, avoiding
duplicate spline sampling and palette work.

Only verified human character skeleton paths use direct idle playback. Creature or missing
rigs remain rendered in bind pose. Every rendered actor is accounted exactly as animated or
static fallback, and every fallback carries its ACHR + reason. This preserves visible actors
when an animation asset is absent or unsupported.

## Timing + acceptance

Drawable frames advance a monotonic renderer clock with wall-time deltas capped at 100 ms.
Deterministic offscreen tests set exact clip times. Sustained/fly benchmarks record animation
CPU time independently and gate average + p95 against the CLI animation budget (4 ms in
Debug by default).

`World > Environment > Actor animation > Enabled` is the durable A/B surface. Off resets
every skinned palette to bind pose; on resumes clip sampling from renderer time. Its live
readout reports playback count, updated bones, mode, and update time. Renderer time continues
while animation is off so unrelated grass/particle effects do not freeze.

Synthetic gates cover hierarchy composition, reference-pose fallback, cycle rejection,
palette formula, triple-buffer isolation, and render output: two animated times differ while
two static frames remain byte-identical. Real read-only install probes on 2026-07-20 found:

* ChillfurrowFarmExterior `(7,-3)`: 7 rendered actors = 4 animated humans + 3 static
  unsupported creatures; 10 frames at 640x360 averaged 5.77 ms, p95 10.61 ms, under the
  33.33 ms frame budget.
* ChillfurrowFarm interior: 1 rendered actor = 1 animated human; exterior -> interior ->
  exterior door round trip completed.
* M7.6 full 35-cell living-environment fly: 55 actors discovered = 27 rendered + 27 disabled
  * 1 failed; rendered split 11 animated + 16 reason-tagged static. Peak updated palette was
  445 bones. Animation update averaged 1.52 ms, p95 2.85 ms vs 4 ms budget. Total frame avg
  15.43 ms, p95 30.12 ms vs 33.33 ms with all M7 systems active.

Generated captures stay local. Repository evidence is deterministic pixel comparison,
exact accounting, timing metrics, and probe output in ignored `logs/`.
