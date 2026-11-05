---
type: Subsystem
title: Trees in the wind
description: How trees sway and leaves flutter with the weather's wind - the TREE record
  values, the Tree_Anim wind weight, and OpenSky's sway model.
tags: [rendering, trees, wind, weather]
---

# Trees in the wind

A tree sways with the weather's wind, and its leaves flutter. OpenSky moves the vertices in the
static and skinned mesh vertex shaders. Grass has its own wind
([scene drawing](/rendering/scene-drawing.md)).

## What the data gives

A `TREE` record's `CNAM` holds twelve floats (UESP,
[TREE](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TREE)): trunk flexibility, branch
flexibility, trunk amplitude, front, back, and side amplitude, front, back, and side frequency,
leaf flexibility, leaf amplitude, and leaf frequency. For example, `TreePineForest01` has front
0.135, back 0.18, and side 0.153 amplitude, frequencies near 2, leaf amplitude 4.5, and leaf
frequency 1.75. Its trunk values are 0.

The Creation Kit wiki ([Tree](https://ck.uesp.net/wiki/Tree)) says:

- leaf amplitude and frequency move the parts of the mesh converted to `BSLeafAnimNode` and
  vertex painted;
- trunk and branch flexibility move the bones of a skinned `BSTreeNode` mesh, the trunk only
  sideways;
- the weather's wind speed moves `BSTreeNode` trees, and may or may not move leaves.

A shape with the shader flag `SLSF2` bit 29 (`Tree_Anim`) stores the leaf's wind weight in its
vertex alpha, not its opacity ([NIF](/formats/nif.md)). OpenSky keeps that alpha and draws the
shape opaque.

## OpenSky's model

Every mesh placed by a `TREE` reference moves. The weather's wind gives the direction and a speed
from 0 to 1.

- **Sway.** A vertex moves along the wind by
  `sway * speed * treeSwayTilt * height * (0.75 + 0.25 * sin(2 pi * frequency * time + phase))`.
  `height` is the vertex's height above the reference's origin, so the tree tilts like a bent
  trunk. `sway` and `frequency` are the means of the front, back, and side values.
- **Leaf flutter.** A wind-weighted vertex also moves up and down, and half as much along the
  wind, by `leafAmplitude * weight * speed * fade * sin(...)`. `fade` falls from 1 at the
  camera to 0 at `TreeWindPolicy.leafFadeDistance` units, so far leaves are still.
- A wind-weighted shape on a base that is not a `TREE` flutters with the Creation Kit's suggested
  starting values: leaf amplitude 3 and frequency 1.

The phase comes from the reference's position, so neighbouring trees do not move together. A calm
weather has speed 0, and nothing moves.

[WARNING] The game moves a skinned tree by its bones and splits front, back, and side motion.
OpenSky bends every tree as one shape, and the scales `treeSwayTilt` (0.1), the leaf side share
(0.5), and the fade distance are OpenSky's values. The shadow pass draws trees still. All are in
the [unverified values](/engine/unverified-values.md).

## Reading it

`state frame` shows `treeWind`: the wind `direction`, the `speed` the trees use, and the
`leafFadeDistance`.
