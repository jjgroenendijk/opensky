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
`NiFloatData`: the fraction of the path at each time. Path flag bit 4 is constant velocity,
bit 5 follow.

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

The shader property controllers are on the [NIF sequences](/formats/nif-sequences.md) page.
The mesh preview in the sidebar lists the decoded fields of every block here. Lag bones,
lightning bolts, bone LOD, and look-at turns have no other consumer yet.
