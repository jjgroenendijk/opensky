---
type: Subsystem
title: Actor animation
description: How a clip becomes a skinning palette, how the player's behavior-graph pose shares
  the same path, why NIF rotations must be transposed, and how playback streams with cells.
tags: [engine, actors, animation, hkx, skinning, streaming, locomotion]
---

# Actor animation

This page covers how an actor's pose reaches the GPU. The file layouts are on the
[HKX container](/formats/hkx-container.md), [hkaSkeleton](/formats/hka-skeleton.md), and
[hkaSplineCompressedAnimation](/formats/hka-animation.md) pages.

Two kinds of actor are posed:

- An NPC plays one clip at a time: an idle, a walk or run while moving, or a short combat clip.
- The player is posed by a running [behavior graph](/engine/behavior-runtime.md).

Both end in the same skinning math.

## NPC clips

An NPC samples its clip at the renderer time, modulo the clip length. The same loader reads idle,
walk, run, and combat clips. The binding maps tracks to skeleton bones. A bone with no track
keeps its reference pose. Each bone's local translation, rotation, and scale go through the parent
chain to give skeleton-space transforms. A bad bone index or a loop in the parents stops the
update safely.

A moving NPC plays an in-place walk or run clip, while its capsule does the moving. A standing NPC
plays its idle and gets no movement controller.

A combat clip, such as an attack, stagger, or hit reaction, plays as a short override. It starts at
its own frame 0, not on the shared clock, and then returns to the latest walk, run, or idle clip.
Which clips are used is on the [combat](/engine/combat.md) page.

## Skinning palette

Skeleton transforms are matched to the NIF skin bones by name. A matched palette entry is:

```text
rootParentToSkin * animatedSkeletonWorld * skinToBone
```

A NIF bone with no match, such as a helper bone, keeps its bind pose matrix. The palette is kept on
the CPU. The GPU copy has one slot per frame in flight, and the renderer copies into the active
slot just before encoding. So an update never overwrites matrices an older GPU frame still reads.

This math has no Metal in it, so it is tested with hand-built matrices.

## The player

The player uses the same path, with three differences:

- Pose source: the behavior graph gives a full pose for every bone, not a sparse sample. It goes
  through the same parent chain, so both paths agree on what a bone without animation is.
- Clock: the graph steps on the simulation clock, the fixed 120 Hz steps that move the capsule,
  not on the renderer's animation clock. The graph is part of movement. It reads the same speed
  and direction the capsule moves by. A graph on a second clock could show a state the capsule
  was never in. The animation pass only publishes the pose the simulation made.
- Ownership: the player body belongs to no cell, so it is not unloaded with a cell. The renderer
  holds it. See [player camera and body](/engine/player-camera.md).

## Why NIF rotations are transposed

Once, any computed pose tore skinned actors into long flat shards, while the bind pose looked fine.
Even the skeleton's own reference pose, with no animation, tore. That pose is the same pose as the
NIF bind pose, so it should have given the bind palette. It did not.

The two files disagreed about which way a bone turns. NIF stores rotations for row vectors.
OpenSky multiplies column vectors, so every NIF `Matrix33` must be transposed when read
([NIF](/formats/nif.md)). It was not. Havok needs no transpose. So each bone came out of the two
files as transposes of each other.

It went unseen for two reasons. Vanilla statics hardly rotate their nodes, so the world looked the
same either way. And the bind palette cancels the error, because both of its halves come from the
same file. Only poses built on top of it were wrong.

With the transpose, the Havok reference pose matches the NIF bind pose to about 0.00005 units, and
the bind palette is the identity to about 0.00001. Before, they were apart by up to 62 units.

A render check that only asks "do two frames differ?" cannot see this, because a torn mesh also
differs. The real-data check also limits how much of the frame a posed body covers, compared with
the bind pose. Shards spread over the frame, so they fail it.

## Streaming

Decoded clips are cached by skeleton path and gender. Each drawn actor gets a playback object owned
by its cell, which is freed with the cell. The clip data can stay cached.

One update samples each clip once, and actors that play the same clip share that sample. Each
actor still has its own palette. The mesh cache shares the geometry and the textures, and each
loaded actor gets a copy of each skinned mesh with its own bone matrices. So two actors with the
same body can play different clips, and a ragdoll or a head turn on one does not move the other.
The cost is one draw per actor for each skinned mesh, instead of one instanced draw for all of
them.

A character skeleton under `meshes\actors\character\` plays the gendered `mt_` clips. A creature
skeleton, such as `meshes\actors\horse\character assets\skeleton.nif`, plays the clips in the
`animations` folder beside its `character assets` folder: `idle.hkx`, `walkforward.hkx`, and
`runforward.hkx`. These names were checked on the install for the horse and most other creatures.
A creature without one of them stays in its last clip. Its behaviour graph does not run.
Actors with a missing skeleton stay in the bind pose. Each drawn actor is counted as animated or
static, and each static one has its `ACHR` and a reason. So an actor with a missing clip still shows.

## Time and controls

The renderer clock moves by real frame time, capped at 100 ms per frame. Offscreen tests set exact
times. Benchmarks measure animation CPU time on its own against a budget.

World > Environment > Actor animation > Enabled turns animation off and on for NPCs and the player.
Off puts every skinned mesh back in the bind pose. On resumes from the renderer clock. The clock
keeps running while it is off, so grass and particles do not freeze.
