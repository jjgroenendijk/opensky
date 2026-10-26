---
type: File Format
title: NIF controllers and interpolators
description: The animation controller and interpolator blocks of Skyrim SE meshes beside
  the transform and particle controllers, and how OpenSky uses each.
tags: [format, mesh, animation]
---

# NIF controllers and interpolators

A controller animates one value of its target object over time. Most controllers read
their keys through one interpolator. The transform controller is on the
[NIF](/formats/nif.md#camera-animation) page. The particle controllers are on the
[NIF particle systems](/formats/nif-particles.md) page. Named sequences are on the
[NIF sequences](/formats/nif-sequences.md) page.

Reference: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
develop commit `292bb9403cbf4052c58d66e80906b6bde1700779`. The layouts were confirmed by
`openskycli gaps`, which decodes every block of every vanilla mesh and reports a block
whose bytes are not used up exactly.

## Time controller

Every controller starts with the `NiTimeController` fields, 26 bytes:

| Field | Type |
| --- | --- |
| Next controller | Ref |
| Flags | uint16 |
| Frequency, phase, start time, stop time | 4 x float32 |
| Target | Ptr |

Flag bits 1 and 2 are the cycle: 0 loop, 1 reverse, 2 clamp. Bit 3 is active. Bit 5 says
that an `NiControllerManager` feeds the controller from a sequence. A controller with one
interpolator (`NiSingleInterpController`) adds the interpolator Ref.

## Controllers

After the time controller fields:

| Block | Fields |
| --- | --- |
| `BSEffectShaderPropertyFloatController`, `BSLightingShaderPropertyFloatController` | Interpolator, uint32 controlled variable |
| `BSEffectShaderPropertyColorController`, `BSLightingShaderPropertyColorController` | Interpolator, uint32 controlled colour |
| `BSNiAlphaPropertyTestRefController` | Interpolator |
| `BSFrustumFOVController` | Interpolator |
| `NiFloatExtraDataController` | Interpolator, string index of the extra data name |
| `BSLagBoneController` | float32 linear velocity, linear rotation, maximum distance |
| `BSProceduralLightningController` | 9 interpolator Refs, uint16 x 3, float32 x 5, uint8 x 3, shader property Ref |
| `NiBSBoneLODController` | uint32 LOD, uint32 level count, uint32 group count, then per level a Ref list |
| `NiControllerManager` | uint8 cumulative, Ref list of sequences, Ref to the object palette |

The lightning interpolators drive, in order: generation, mutation, subdivision, branches,
branch variation, length, length variation, width, and arc offset. Its other fields are
subdivisions, branches, branch variation, length, length variation, width, child width
multiplier, arc offset, and three flags: fade main bolt, fade child bolts, animate arc
offset.

`NiDefaultAVObjectPalette` names the objects a manager's sequences animate: a scene Ptr,
then a uint32 count of pairs, each a `SizedString` name and an object Ptr.

## Interpolators

| Block | Fields |
| --- | --- |
| `NiBlendFloatInterpolator`, `NiBlendBoolInterpolator`, `NiBlendPoint3Interpolator` | uint8 flags, uint8 array size, float32 weight threshold, then items unless flag bit 0 is set, then the value |
| `NiPathInterpolator` | uint16 flags, int32 bank direction, float32 maximum bank angle, float32 smoothing, int16 follow axis, path data Ref, percent data Ref |
| `NiLookAtInterpolator` | uint16 flags, look-at Ptr, string index of the look-at name, a rest transform (32 bytes), three interpolator Refs |

A blend interpolator with flag bit 0 (manager controlled) stores no items. One that stores
items has a uint8 interpolator count, uint8 single index, int8 high and next-high
priorities, float32 single time, high weight sum, next-high weight sum, and high ease
spinner, then 17 bytes per item: Ref, weight, normalised weight, uint8 priority, ease
spinner. The value is a float32, a uint8 (2 is unset), or a Vector3. Every vanilla blend
interpolator is manager controlled.

The path data is an `NiPosData`, a `KeyGroup<Vector3>`. The percent data is an
`NiFloatData`: the fraction of the path at each time. The path flags (nif.xml `PathFlags`) are
bit 3 bank, bit 4 constant velocity, bit 5 follow, and bit 6 flip. The bank direction is -1 or 1,
and the maximum bank angle is in radians. The follow axis is 0 for X, 1 for Y, 2 for Z.

The look-at flags (nif.xml `LookAtFlags`) are bit 0 flip, bit 1 Y axis, and bit 2 Z axis; with
neither axis bit, the node looks along X. The three interpolators give the node's translation,
roll, and scale. A target Ptr of -1 is resolved by the look-at name.

## What OpenSky does with them

- Cinematic cameras. A camera on a path moves by its percent keys. With constant
  velocity, equal fractions cover equal distances along the points; without it, a fraction
  picks the point time between the first and last key. A `BSFrustumFOVController` on the
  camera's chain gives the horizontal field of view in degrees. The renderer uses it while
  the shot plays and keeps the drawable's aspect ratio.
- Sequences. `BSNiAlphaPropertyTestRefController` keys set an animated shape's alpha
  test threshold (0 to 255) in the effect pose. `NiFloatExtraDataController` keys feed the
  extra data they name. When that name starts with `hkVis:`, the rest is a node name, and a
  value below 0.5 hides the node. On the install, 160 controllers name an `hkVis:` value,
  for example in the werewolf `skeleton.nif` and the Dawnguard castle entrance dial
  `cassecentrancedialcm.nif`. The 0.5 threshold is OpenSky's choice.
- A manager-controlled particle controller reads its keys from the sequence through the
  blend interpolator it points at.

- Node controllers that play on their own clock. A transform controller that no manager feeds,
  a lag bone, and a bone LOD controller move nodes of a placed mesh
  ([object animation](/engine/object-animation.md#node-controllers)). The rules follow.

The shader property controllers are on the [NIF sequences](/formats/nif-sequences.md) page.
Lightning bolts have no consumer yet.

### Node controller rules

nif.xml gives the fields but not how the engine applies them. These rules are OpenSky's reading
of the field names and descriptions, checked only against the shape of the vanilla data:

- Active. A controller without flag bit 3 leaves its node at rest. A manager-fed controller
  plays only through its sequence.
- Path follow. With bit 5, the node points its follow axis along the path, from a point just
  behind it to a point just ahead. The look-ahead is the smoothing value as a path fraction,
  at least 0.01. Up stays as close to +Z as the direction allows. Flip (bit 6) points the
  negative axis forward.
- Path bank. With bit 3, the node rolls about its follow axis by the bank direction, times the
  maximum bank angle, times the heading change over the look-ahead divided by 90 degrees,
  clamped to -1 and 1.
- Look-at. The node turns its look axis toward the target's position in the node's parent space,
  after the keyed nodes move, then rolls by the roll keys. Up stays as close to +Z as it can.
  On the install, the only look-at nodes are the `PreviewCam` cameras of the five forge and
  smelter meshes, aimed at `PreviewCamTarget` along +Z. A game camera never draws them.
- Lag bone. nif.xml calls the block "a controller that trails a bone behind an actor". It
  describes linear velocity (default 3, range 0 to 500) as "how long it takes to rotate about an
  actor back to rest position", linear rotation (default 1, range 0 to 15) as "how the bone lags
  rotation", and maximum distance (default 400) as "how far bone will tail an actor". The first
  description reads like a time, not a speed; no other public source explains the fields.
  OpenSky treats both as rates: each frame the bone's world position closes linear velocity
  times the frame time of its gap to its rest under the parent, and its rotation turns linear
  rotation times the frame time of the way. The gap never grows past the maximum distance.
  Vanilla values: `weapons\torch\torch.nif` 9, 0.1, 64; the chaurus `LagBone` 1, 1, 15.
  Lag bones play on placed meshes and effect art. On the 14 creature skeletons that carry one,
  such as the chaurus, the `LagBone` node is outside the Havok rig (37 bones on the chaurus),
  so the actor animation does not move it, and OpenSky does not trail it yet.
- Bone LOD. `BSBoneLODExtraData` pairs a bone name with a camera distance; nif.xml calls the
  block "Unknown". On the install, 52 actor `skeleton.nif` files carry it, and no placed mesh
  does. Each entry names one bone, often only the left-side one, so it reads as a cut in the
  rig's bone order: past the distance, the named Havok rig bone and every bone after it keep
  their last pose. The rig orders bones by importance, which makes each cut a clean tail. The
  human rig `skeleton.hkx` (`openskycli skeleton --all`): `Camera3rd [Cam3]` (bone 97) at 128
  stops the two camera bones, `NPC L Finger00 [LF00]` (67) at 768 stops all 30 fingers, and
  `NPC Head MagicNode [Hmag]` (49) at 2048 also stops the toes, twist bones, and weapon nodes.
  The canine rig: `Canine_JawBone` (31) at 800, `Canine_LFrontLegToe` (27) at 2200, and
  `Canine_LFrontLegPalm` (20) at 3500, which also stops the tail. The rule is OpenSky's
  reading of that pattern. The Creation Kit lists `iBoneLODDistMult`, default 1000
  ([Settings](https://ck.uesp.net/wiki/Category:Settings)); OpenSky does not apply it, because
  no source says how, and the distances already read as world units. A placed mesh has no rig
  order, so there the named node and its subtree stop. The `NiBSBoneLODController` node groups,
  on the centaur, werewolf, and wolf skeletons only, are read but not used.
