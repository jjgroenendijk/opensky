---
type: Subsystem
title: Actor idle animation
description: Direct HKX idle sampling, skeleton-world composition, NIF palette refresh,
  streamed playback ownership, fallback accounting, and frame budget.
tags: [engine, actors, animation, hkx, skinning, streaming]
timestamp: 2026-07-20T00:00:00Z
---

# Actor idle animation

Milestone 6 adds direct idle-clip playback to streamed human actors. Scope stops before
behavior graphs, animation state machines, locomotion, AI, and root motion. Container,
skeleton, binding, and spline layouts come from the clean-room format work in
[HKX container](/formats/hkx-container.md), [hkaSkeleton](/formats/hka-skeleton.md), and
[hkaSplineCompressedAnimation](/formats/hka-animation.md).

## Playback path

`ActorAnimationPlayback` samples the gender-specific character `mt_idle.hkx` at renderer
time modulo clip duration. Binding resolves tracks to skeleton bone indices. Missing tracks
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

## Streaming lifecycle + fallback

`CellSceneBuilder` caches decoded immutable clips by normalized skeleton path + gender.
Every rendered actor gets a cell-owned `ActorAnimationPlayback`; composing resident scenes
composes those playback objects. Cell eviction drops its playback objects with its
`RenderScene`, while reusable clip data can remain cache-hot.

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

Synthetic gates cover hierarchy composition, reference-pose fallback, cycle rejection,
palette formula, triple-buffer isolation, and render output: two animated times differ while
two static frames remain byte-identical. Real read-only install probes on 2026-07-20 found:

* ChillfurrowFarmExterior `(7,-3)`: 7 rendered actors = 4 animated humans + 3 static
  unsupported creatures; 10 frames at 640x360 averaged 5.77 ms, p95 10.61 ms, under the
  33.33 ms frame budget.
* ChillfurrowFarm interior: 1 rendered actor = 1 animated human; exterior -> interior ->
  exterior door round trip completed.
* Full 35-cell fly: 55 actors discovered = 27 rendered + 27 disabled + 1 failed; rendered
  split 11 animated + 16 reason-tagged static. Animation update averaged 1.61 ms, p95
  2.99 ms vs 4 ms budget. Total frame avg 5.36 ms, p95 9.51 ms vs 33.33 ms budget.

Generated captures stay local. Repository evidence is deterministic pixel comparison,
exact accounting, timing metrics, and probe output in ignored `logs/`.
