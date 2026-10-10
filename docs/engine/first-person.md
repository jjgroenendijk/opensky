---
type: Subsystem
title: First person
description: The first-person arms - a second behavior graph beside the third-person one, how the
  rig is anchored to the eye, which rig draws and casts in each mode, the depth range that keeps
  the arms in front of walls, the field of view, and first-person equipment models.
tags: [engine, animation, behavior, player, rendering, camera]
---

# First person

In first person the player sees the `_1stperson` arms, drawn from the eye and driven by a second
behavior graph. The install ships the first-person set as a peer of the third-person one, not a
variant of it. It has its own `0_master.hkx` under `meshes\actors\character\_1stperson\behaviors\`,
its own 99-bone `skeletonfirst.hkx`, and its own `skeleton.nif`. So OpenSky runs it as a peer.

## Two graphs, one bridge

The [movement bridge](/engine/locomotion-graph.md) holds an optional first-person graph beside the
third-person one. It sends every variable write, every event, and every update to both, in the same
order, in the same fixed step. The two share only the read-only decode. Node state is keyed per
instance, so neither can see the other's clip phase or crossfade. Both get the same input. Neither
leads the other.

Root motion from the first-person graph is dropped. The third-person graph is the one source of
movement ([walk mode](/engine/walk-mode.md)). A second graph moving the player would double every
step.

`IsFirstPerson` is the one input that differs. It is false on the third-person graph and true on the
first-person one, set at attach and again on every reset. The vanilla files declare it, and
transition conditions read it. Every other name goes to both graphs. A miss on either side is
counted separately, because the first-person files may spell names their own way.

## Anchoring the rig

The first-person skeleton has one bone the third-person skeleton does not: `Camera1st [Cam1]`. In
the install it sits at rig-space `(0, 0, 121)` with identity rotation, and it does not move across a
stepped movement cycle. So vanilla's movement graph does not animate it.

The rig is still anchored through it: `eyeMatrix * cameraBone.inverse`. So the bone lands exactly
on the eye whatever its pose. No view bob is made up, because the data has none. A set that does
animate the bone moves the view with no new code. A rig with no camera bone, or a singular one,
falls back to a fixed drop of 121 units from the eye.

## Which rig draws

One function decides the whole table, so a mode never disagrees with itself:

| Camera mode | Body drawn | Body casts shadow | Arms drawn | Arms cast shadow |
| --- | --- | --- | --- | --- |
| First person | No | Yes | Yes | No |
| Third person | Yes | Yes | No | No |
| Free fly | Yes | Yes | No | No |

Exactly one rig is drawn in each player mode. The shadow rule is OpenSky's own, because vanilla's
shadow pass is in its renderer and cannot be read from the install. The body casts in first person,
because a player with no shadow looks like a bug. The arms never cast, because they are the same
limbs the body already casts. A second copy at the eye would double the shadow.

The dialogue camera hides the arms. It draws the body only in third person: in first person its eye
is just behind the head, so the body stays hidden ([player camera and body](/engine/player-camera.md)).

## Depth

The arms sit 15 to 45 units in front of the eye, but the capsule radius is 24. So a player against a
wall has world geometry nearer than their own hands. This is a deliberate difference from the game:
vanilla's answer is in its renderer and cannot be observed, so OpenSky chooses its own.

The arms are drawn last, with the same projection and pipelines as everything else, into a viewport
whose depth range is squeezed to `[0, 0.02]`. The viewport transform is linear and keeps order, so
depth within the arms is unchanged: a hand behind a forearm stays behind it. Against the world, every
arm fragment is nearer than any world fragment further than `nearPlane / (1 - 0.02)`. With the
10-unit near plane that is about 10.2 units, well inside the capsule, so no world geometry can reach
it.

Two other ways were rejected:

- A second pass with a cleared depth buffer gives the same result, but costs an encoder and a
  full-screen depth clear every frame.
- Turning off the depth test breaks the arms hiding their own parts, which is the one thing they
  need.

## Field of view

The install has no first-person field of view OpenSky can read: no such game setting in
`Skyrim.esm`, and no matching key in `Skyrim_Default.ini`. So it is an OpenSky setting. It defaults
to the renderer's 65 degrees, is limited to 30 to 120, and applies to the whole frame, not only the
arms. Vanilla's is a comfort setting, not a lens on the hands.

## Equipment

The arms are built by the same actor assembly as the body, from the same resolved appearance, placed
on the first-person rig. So a runtime equipment change reaches them with no second resolution.

Each piece is swapped to its `MOD4` or `MOD5` model ([actor records](/formats/actors.md)). A piece
with neither is dropped with the reason `noFirstPersonModel`. That is why vanilla iron gauntlets show
nothing on the arms while the cuirass and hands do.

Dropping is a choice. The third-person mesh is skinned to the third-person skeleton, and the 99-bone
first-person rig does not have all of its bones. So a fallback would bind a mesh to bones that do not
exist. Nothing in the install says whether vanilla hides the piece, replaces it, or never meets the
case. Each drop is counted in the World > First person readout.

## Controls

World > First person has the arms toggle, the field of view slider, and a readout. The readout shows
the first-person graph, the arm meshes and every dropped piece with its reason, the camera bone, and
any name the first-person graph does not declare.
