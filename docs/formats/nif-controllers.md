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

- Shader property controllers that play on their own clock. See the next section.

- Lightning bolts. Each `BSProceduralLightningController` becomes a bolt at its target
  shape, drawn as ribbon bands ([particles](/rendering/particles.md#ribbons)).

### Shader property controllers

A shader property's controller chain starts at its `NiObjectNET` controller ref. Each
`BSEffectShaderProperty...Controller` or `BSLightingShaderProperty...Controller` drives one
value. An active controller (flag bit 3) that no manager feeds (bit 5 clear) and whose
interpolator has more than one key plays on its own clock: its frequency, phase, start, stop,
and cycle type map the renderer's animation time into the keys. A manager-fed controller plays
only through its sequence ([NIF sequences](/formats/nif-sequences.md)).

The variable numbers come from nif.xml:

| Enum | Values OpenSky draws |
| --- | --- |
| `EffectShaderControlledVariable` | 0 emissive multiple, 1 to 4 falloff start and stop angle and opacity, 5 alpha, 6 U offset, 7 U scale, 8 V offset, 9 V scale |
| `EffectShaderControlledColor` | 0 emissive colour |
| `LightingShaderControlledFloat` | 0 refraction strength, 8 environment map scale, 9 glossiness, 10 specular strength, 11 emissive multiple, 12 alpha, 20 U offset, 21 U scale, 22 V offset, 23 V scale |
| `LightingShaderControlledColor` | 0 specular colour, 1 emissive colour |

Other lighting values (the parallax and multi-layer values, numbers 1 to 7 and 13 to 19)
are listed by `openskycli nif <path> --controllers` but not drawn. On an effect shape the
alpha and the emissive colour change the effect base colour. The weather aurora
`meshes\sky\skyrimaurora.nif` has seven float controllers, so its streaks scroll.

### Node controller rules

nif.xml gives the fields but not how the engine applies them. The path, lag bone, and bone LOD
rules below come from a clean-room behaviour read of the game (using-outside-sources skill); the
active and look-at rules are OpenSky's reading of the field names.

- Active. A controller without flag bit 3 leaves its node at rest. A manager-fed controller
  plays only through its sequence.
- Path follow. With bit 5, the node points its follow axis along the path's direction of travel.
  Up stays as close to +Z as the direction allows. Flip (bit 6) points the negative axis forward.
- Path smoothing. With bit 2, the smoothing value s is a share of each segment, the span between
  two path points. Where the segment's own 0 to 1 position t is at most s, or at least 1 - s, the
  direction leans toward the neighbour segment's direction with weight `(s - t) * 0.5 / s`, with
  t measured from the nearer end. At a point the weight is 50%.
- Path bank. With bit 3, the node rolls about its direction by the bank direction (-1 or 1) times
  the maximum bank angle. Where the bend c is below the path's largest bend cMax, the roll is
  scaled by `atan(c / cMax) * 4 / pi`, so the full angle applies at the sharpest turn. OpenSky
  measures c as the change of heading per unit of length, and rolls the other way in a right turn;
  the sign is not confirmed.
- Look-at. The node turns its look axis toward the target's position in the node's parent space,
  after the keyed nodes move, then rolls by the roll keys. Up stays as close to +Z as it can.
  On the install, the only look-at nodes are the `PreviewCam` cameras of the five forge and
  smelter meshes, aimed at `PreviewCamTarget` along +Z. A game camera never draws them.
- Lag bone. At the start the bone keeps its rest transform under its parent. Each frame:
  - the goal is the rest under the parent's new world transform, and d is the goal minus last
    frame's world position;
  - k is linear velocity times the frame time, a share per second;
  - if `|d| < k` the bone snaps to the goal; if `|d|` is within the maximum distance it moves
    `d * k`; past the maximum, the part of d beyond it is dropped at once and the rest moves by k;
  - with linear velocity 0 the bone stays at its rest;
  - the rotation is a normalised lerp from last frame's world rotation toward the rest, by linear
    rotation times the frame time, clamped to 0 and 1.

  nif.xml's description of linear velocity reads like a time; the game uses it as a rate.
  Vanilla values: `weapons\torch\torch.nif` 9, 0.1, 64; the chaurus `LagBone` 1, 1, 15.
  Lag bones play on placed meshes and effect art. On the 14 creature skeletons that carry one,
  such as the chaurus, the `LagBone` node is outside the Havok rig (37 bones on the chaurus).
  The actor build reads it from the skeleton mesh and adds it after the rig's bones, hung from
  the nearest rig bone above it. Each frame it trails that bone's motion in the world, where
  the actor's graph places the actor. Skins and props that name `LagBone` follow it, and
  `openskycli game state actors` shows each lag bone's trail under `lagBones`.
- Bone LOD. `BSBoneLODExtraData` pairs a bone name with a camera distance; nif.xml calls the
  block "Unknown". On the install, 52 actor `skeleton.nif` files carry it, and no placed mesh
  does. An entry counts when its distance is above 0 and its name is a bone. Past an entry's
  distance, the rig keeps updating only the bones before the named one, in the rig's order;
  the named bone and every bone after it keep their last pose. The rig orders bones by
  importance, which makes each cut a clean tail. The human rig `skeleton.hkx`
  (`openskycli skeleton --all`): `Camera3rd [Cam3]` (bone 97) at 128 stops the two camera bones,
  `NPC L Finger00 [LF00]` (67) at 768 stops all 30 fingers, and `NPC Head MagicNode [Hmag]` (49) at
  2048 also stops the toes, twist bones, and weapon nodes. The canine rig: `Canine_JawBone` (31)
  at 800, `Canine_LFrontLegToe` (27) at 2200, and `Canine_LFrontLegPalm` (20) at 3500, which also
  stops the tail. The distance is measured across the ground only (X and Y, not height), and
  divided by the actor's scale, so a large actor keeps its fine bones further away. A placed mesh
  has no rig order, so there the named node and its subtree stop.
- The Creation Kit lists `iBoneLODDistMult`, default 1000
  ([Settings](https://ck.uesp.net/wiki/Category:Settings)). The game reads no value of it, so
  OpenSky applies none.
- The `NiBSBoneLODController` node groups, on the centaur, werewolf, and wolf skeletons only,
  have no effect: the game's update for this controller does nothing. OpenSky parses them and
  uses none.
