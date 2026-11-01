---
type: File Format
title: NIF controller sequences
description: How a NIF's named animations (NiControllerSequence) are laid out, and how
  OpenSky plays them on interface effect meshes such as the perk sky.
tags: [formats, nif, animation, effects]
---

# NIF controller sequences

A NIF can hold named animations, such as `Locked` and `Unlock` on a perk star. Each one
is an `NiControllerSequence` block under the root's `NiControllerManager`. OpenSky reads
them to play the interface effect meshes of the [perk sky](/engine/perk-sky.md).

Reference: niftools nif.xml (`NiControllerSequence`, `ControlledBlock`,
`NiTransformInterpolator`, `EffectShaderControlledVariable`), for version 20.2.0.7 with
user version 12 and stream version 100. All values are little-endian. The layouts below were
confirmed with `openskycli nif <path> --sequences` on the Skyrim SE meshes
`interface\intperkskydome.nif`, `intperkstars01.nif`, and `intperkline01.nif`.

## Sequence block

| Field | Size | Notes |
| --- | --- | --- |
| name | 4 | string index |
| controlled block count | 4 | |
| array grow by | 4 | |
| controlled blocks | 29 each | see below |
| weight | 4 | float |
| text keys | 4 | ref to `NiTextKeyExtraData` |
| cycle type | 4 | 0 loop, 1 reverse, 2 clamp |
| frequency, start, stop | 12 | floats, seconds |
| the rest | | manager ref, accum root name, and more; OpenSky does not read them |

A controlled block is 29 bytes: interpolator ref, controller ref, priority (1 byte), then
four string indexes: node name, property type, controller type, and controller ID. A
controlled block whose interpolator ref is -1 is skipped.

## Interpolators

| Block | Holds |
| --- | --- |
| `NiTransformInterpolator` | rest translation, rotation (quaternion, w first), scale, then a ref to `NiTransformData` |
| `NiFloatInterpolator` | rest value, ref to `NiFloatData` |
| `NiPoint3Interpolator` | rest value, ref to `NiPosData`; used for colours |
| `NiBoolInterpolator` | rest value (1 byte), ref to `NiBoolData`; used for visibility |

A rest value of `-3.402823466e+38` (`#INV_FLT#` in nif.xml) means "not set": the node
keeps its own value. Key arrays start with a count and a key type: 1 linear, 2 quadratic
(two tangents follow each value), 3 TBC (three floats follow), 4 XYZ rotation. OpenSky
reads past tangents and samples linearly, so a quadratic curve plays as straight lines
between its keys. On the perk meshes the keys sit one frame (1/30 s) apart, so the
difference is too small to see.

## Which value a track drives

The controller type string names the target:

| Controller type | Target | Value |
| --- | --- | --- |
| `NiTransformController` | the named node | translation, rotation, scale |
| `NiVisController` | the named node | shown or hidden |
| `BSEffectShaderPropertyFloatController` | the node's effect shader | one float variable |
| `BSEffectShaderPropertyColorController` | the node's effect shader | one colour variable |
| `BSNiAlphaPropertyTestRefController` | the named node's shapes | alpha test threshold, 0 to 255 |
| `NiFloatExtraDataController` | the extra data it names | one float |

The alpha test threshold changes only a shape whose material already uses an alpha test.
A float extra data named `hkVis:<node>` shows or hides that node
([NIF controllers](/formats/nif-controllers.md#what-opensky-does-with-them)).

A shader controller's variable is not in the controlled block. It is the last 4 bytes of
the controller block itself, after the 26-byte `NiTimeController` part (next controller,
flags, frequency, phase, start, stop, target) and the interpolator ref.

`EffectShaderControlledVariable`: 0 emissive multiple, 1 to 4 the falloff start angle,
stop angle, start opacity, and stop opacity, 5 alpha, 6 U offset, 7 U scale, 8 V offset,
9 V scale. Colour variable 0 is the emissive colour.

## Text keys

`NiTextKeyExtraData` holds a count, then a float time and a string index per key. Every
perk sequence has `start` and `end`. A key named `SoundPlay.<editor ID>` plays that sound
descriptor: the star's `Unlock` and `Own` sequences play `UISkillsPerkSelectA` at 0 s and
`UISkillsPerkSelectB` at 0.633 s.

## Billboard nodes

`NiBillboardNode` is an `NiNode` with a 2-byte billboard mode at its end. Gamebryo turns
the node so a local axis points at the camera. The mode names come from NifTools
`nif.xml` (`BillboardMode`); the axes were checked against vanilla meshes:

| Mode | nif.xml name | What OpenSky turns |
| --- | --- | --- |
| 0, 2 | `ALWAYS_FACE_CAMERA`, `RIGID_FACE_CAMERA` | +Z against the view direction, +Y toward camera up |
| 3, 4 | `ALWAYS_FACE_CENTER`, `RIGID_FACE_CENTER` | +Z at the eye, +Y toward camera up |
| 1, 9 | `ROTATE_ABOUT_UP`, `ROTATE_ABOUT_UP2` | about the node's own +Y; +Z toward the eye |
| 5 | `BSROTATE_ABOUT_UP` | about the node's own +Z; -Y toward the eye |

Other values turn like mode 4. The menu scene has no view direction, so there modes 0
and 2 also turn +Z at the eye. OpenSky does not tell the minimised turn (0, 3) from the
rigid one (2, 4).

How the axes were confirmed:

- The perk star's `FacingRoot` uses mode 2. Its glow quads sit 0.85 and 1.6 units along
  +Z, in front of the star quad.
- The perk line's `Plane05` and the light beams of `dlc1wayshrinelightbeam01.nif` use
  mode 1. Their nodes are turned 90 degrees about X, so own +Y is the beam's length.
- The window glow `effects\ambient\fxglowfillrndlitbrt.nif` uses mode 4. Its card lies
  flat in the node's XY plane, 2.2 units along +Z.
- The torch flames of `clutter\common\torchsconce01.nif` use mode 5. Each card lies in
  the node's XZ plane with its length along +Z, so the card turns about +Z. The glow
  card's normals point along -Y, so -Y is the face that turns to the eye.

On the install, the glow, light, candle, torch, and flame meshes use modes 0 to 5. None
of them uses 9.
