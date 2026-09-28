---
type: File Format
title: hkaSplineCompressedAnimation Object
description: Havok 2010 spline-compressed animation in Skyrim SE - object layout, block
  layout, quantization, annotations, and sampling.
tags: [format, havok, hkx, animation, spline]
---

# hkaSplineCompressedAnimation object

Skyrim SE animation clips (`.hkx`) store bone motion as `hkaSplineCompressedAnimation`. An
`hkaAnimationBinding` links the tracks to bone indices. This page covers both objects, the
data blocks, the value packing, and how to sample a pose. See
[HKX container](/formats/hkx-container.md) for the file around them and
[hkaSkeleton](/formats/hka-skeleton.md) for the bones.

`openskycli animation <hkx-key>` prints a clip (see [CLI](/tools/cli.md)).

## References

There is no public Havok specification. The layout comes from open parsers and a textbook,
then was checked against vanilla files:

- [exyorha/hkxparse](https://github.com/exyorha/hkxparse) (MIT): Havok 2010 member order and
  types.
- [ret2end/HKX2Library](https://github.com/ret2end/HKX2Library) (MIT): Skyrim SE 64-bit
  member offsets and array types.
- [PredatorCZ/HavokLib](https://github.com/PredatorCZ/HavokLib) (GPLv3): track mask meaning,
  block layout, vector packing, and 40-bit quaternions. OpenSky rewrote the algorithm in
  Swift. No code was copied.
- Piegl and Tiller, *The NURBS Book*, 2nd edition: standard B-spline evaluation (knot span
  and de Boor).

No Havok SDK or Bethesda code was used.

## Example clip

`meshes\actors\character\animations\male\mt_idle.hkx` in `Skyrim - Animations.bsa` is
type 5, 9.133333 s long, with 275 frames at 30 per second. It has 99 transform tracks and 4
float tracks in 2 blocks of at most 256 frames (block duration 8.5 s). Every track uses
16-bit vector points and 40-bit quaternions, with spline degrees 1 and 3. The binding names
`NPC Root [Root]` and has an empty track map. Every sampled pose is finite, and rotations
have length 0.9999999 to 1.0000001.

## Object layout: 176 bytes

The object starts at its virtual fixup offset in `__data__`. Pointers are 8 bytes.

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 16 | vtable and `hkReferencedObject` | Ignored |
| 0x10 | 4 | `hkaAnimation.m_type` | 5 means spline compressed |
| 0x14 | 4 | `m_duration` | Seconds |
| 0x18 | 4 | `m_numberOfTransformTracks` | |
| 0x1C | 4 | `m_numberOfFloatTracks` | Not read |
| 0x20 | 8 | `m_extractedMotion` pointer | See below |
| 0x28 | 16 | `m_annotationTracks` `hkArray` | See below |
| 0x38 | 4 | `m_numFrames` | |
| 0x3C | 4 | `m_numBlocks` | |
| 0x40 | 4 | `m_maxFramesPerBlock` | |
| 0x44 | 4 | `m_maskAndQuantizationSize` | `transformTracks * 4 + floatTracks` |
| 0x48 | 4 | `m_blockDuration` | `(maxFramesPerBlock - 1) * frameDuration` |
| 0x4C | 4 | `m_blockInverseDuration` | `1 / blockDuration` |
| 0x50 | 4 | `m_frameDuration` | 1/30 s |
| 0x54 | 4 | padding | |
| 0x58 | 16 | `m_blockOffsets` `hkArray<uint32>` | Block starts, from `m_data` |
| 0x68 | 16 | `m_floatBlockOffsets` `hkArray<uint32>` | Size of the transform part of each block |
| 0x78 | 16 | `m_transformOffsets` `hkArray<uint32>` | Empty in vanilla |
| 0x88 | 16 | `m_floatOffsets` `hkArray<uint32>` | Empty in vanilla |
| 0x98 | 16 | `m_data` `hkArray<uint8>` | Masks and packed track data |
| 0xA8 | 4 | `m_endian` | 0, little-endian |
| 0xAC | 4 | padding | |

The `hkArray` layout is described under
[hkaSkeleton](/formats/hka-skeleton.md#hkarray-descriptor).

### m_extractedMotion

This pointer can point at an `hkaAnimatedReferenceFrame`: the path the whole character
travels in the clip. No vanilla clip has one. OpenSky still reads whether the pointer is
set, because it is the only reliable way to tell an in-place clip from a root motion clip.
The root bone of a vanilla clip moves a little between samples, so a speed threshold gets
some physics steps wrong. See [walk mode](/engine/walk-mode.md).

### m_annotationTracks

An `hkArray<hkaAnnotationTrack>`. Skyrim keeps its footstep marks here. An annotation is a
time in the clip plus a short text that becomes an event. For example,
`mt_walkforward.hkx` has `FootLeft` at 0.2333 s and `FootRight` at 0.8 s. These are the
tags that the vanilla footstep sets answer to (see [footstep records](/formats/footstep.md)).

`hkaAnnotationTrack`, 24 bytes:

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 8 | `m_trackName` pointer | Bone name, or null |
| 0x08 | 16 | `m_annotations` `hkArray<Annotation>` | Empty on all but the first track |

`Annotation`, 16 bytes:

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 4 | `m_time` | Seconds from the clip start |
| 0x04 | 4 | padding | The pointer aligns to 8 |
| 0x08 | 8 | `m_text` pointer | For example `FootLeft` |

Havok writes one track per transform track, and vanilla leaves all but the first empty. So
OpenSky merges all tracks and sorts by time. A bad entry is skipped, because a clip with no
annotations still animates.

This is the only way a Skyrim footstep fires. The walk and run clip generators in
`mt_behavior.hkx` have empty `m_triggers`. See
[behavior graph runtime](/engine/behavior-clips.md#clip-triggers-and-annotations).

## Binding layout: 72 bytes

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 16 | vtable and `hkReferencedObject` | Ignored |
| 0x10 | 8 | `m_originalSkeletonName` pointer | For example `NPC Root [Root]` |
| 0x18 | 8 | `m_animation` pointer | The animation object |
| 0x20 | 16 | `m_transformTrackToBoneIndices` `hkArray<int16>` | Empty means track i is bone i |
| 0x30 | 16 | `m_floatTrackToFloatSlotIndices` `hkArray<int16>` | |
| 0x40 | 1 | `m_blendHint` | |
| 0x41 | 7 | padding | |

HavokLib's exporter uses the track index directly when the map is empty, and so does
OpenSky. A map that is not empty must have one bone index (0 or more) per transform track.
The binding's animation pointer must point at the animation being sampled.

## Block layout

Each block starts at `m_data + m_blockOffsets[i]`:

```text
transform masks: 4 bytes * numberOfTransformTracks
float masks:     1 byte  * numberOfFloatTracks (skipped)
pad to 4
for each transform track:
  translation vector track
  rotation quaternion track
  pad to 4
  scale vector track
float data starts at block start + m_floatBlockOffsets[i]
```

The transform data must end exactly at `m_floatBlockOffsets[i]`. Ending too early or too
late is an error. This check found layout mistakes during development. Both vanilla blocks
end exactly.

### Transform mask: 4 bytes per track

| Byte | Field | Meaning |
| --- | --- | --- |
| 0 | Packing | Bits 0-1 translation, 2-5 rotation, 6-7 scale |
| 1 | Translation types | Bits 0-2 static X, Y, Z; bits 4-6 spline X, Y, Z |
| 2 | Rotation type | Low 4 bits static; high 4 bits spline |
| 3 | Scale types | Bits 0-2 static X, Y, Z; bits 4-6 spline X, Y, Z |

A spline value wins over a static one, and a static one wins over identity. Identity is 0
for translation, 1 for scale, and (0, 0, 0, 1) for rotation. Vanilla uses packing byte
`0x45` everywhere: 16-bit vector points and 40-bit quaternions. An unknown packing is an
error. OpenSky does not guess.

### Vector track

With no spline parts: one float32 per static part, in X, Y, Z order. Identity parts use no
bytes. With any spline part:

```text
uint16 storedItemCount         controlPointCount = storedItemCount + 1
uint8  degree
uint8  knots[storedItemCount + degree + 2]
pad to 4
for X, Y, Z: spline -> float32 minimum, float32 maximum
             static -> float32 value
for each control point, X, Y, Z order: spline part -> uint8 or uint16 packed value
pad to 4
```

A value is `minimum + (maximum - minimum) * q / (2^bits - 1)`. Knots must not go down. The
degree must be 1 to 4, and there must be enough control points.

### 40-bit quaternion

Five little-endian bytes hold three 12-bit values, a 2-bit index of the left-out part, and
a 1-bit sign of the left-out part. Each stored value `q` becomes
`(q - 2047) * 0.000345436`, which covers about -1/sqrt(2) to +1/sqrt(2). The left-out part
is `sqrt(max(0, 1 - x*x - y*y - z*z))`. OpenSky normalizes every sampled quaternion, so
rounding error cannot grow the rotation.

## Sampling

Clamp the time to `[0, duration]`. The block is `floor(time / blockDuration)`, at most the
last block. The frame inside the block is `(time - block * blockDuration) / frameDuration`.
Static and identity parts return directly. Spline parts use the standard knot span and de
Boor evaluation, and quaternions are then normalized. OpenSky reads transform tracks only.
It skips the float tracks by their mask count and `m_floatBlockOffsets`.
