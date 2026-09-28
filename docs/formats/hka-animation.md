---
type: File Format
title: hkaSplineCompressedAnimation Object
description: Havok 2010 spline-compressed animation layout, annotations, transform blocks,
  quantization, and sampling in Skyrim SE clips.
tags: [format, havok, hkx, animation, spline]
---

# hkaSplineCompressedAnimation object

Skyrim `.hkx` clips store bone animation as an `hkaSplineCompressedAnimation`. An
`hkaAnimationBinding` links its tracks to skeleton bones. This page covers both objects, the
transform blocks, the quantization, and the spline sampling. The container is on the
[HKX container](/formats/hkx-container.md) page. The skeleton is on the
[hkaSkeleton](/formats/hka-skeleton.md) page.

## Sources

There is no public Havok specification. The layout and codec come from open parsers and were
then checked against the local SSE install.

- [exyorha/hkxparse](https://github.com/exyorha/hkxparse) (MIT): Havok 2010 member order and
  types, and a 32-bit layout cross-check.
- [ret2end/HKX2Library](https://github.com/ret2end/HKX2Library) (MIT): SSE 64-bit member
  offsets of `hkaAnimation` and `hkaSplineCompressedAnimation`.
- [PredatorCZ/HavokLib](https://github.com/PredatorCZ/HavokLib) (GPLv3): what the transform
  mask means, the block grammar, vector quantization, and 40-bit quaternions. OpenSky
  rewrote the algorithm in Swift. No source was copied.
- Piegl and Tiller, *The NURBS Book*, 2nd edition: standard knot-span and de Boor B-spline
  evaluation.

## Example: mt_idle.hkx

`meshes\actors\character\animations\male\mt_idle.hkx` in `Skyrim - Animations.bsa`:

| Property | Value |
| --- | --- |
| Container | `hk_2010.2.0-r1`, file version 8, 64-bit little-endian |
| Class, animation type | `hkaSplineCompressedAnimation`, 5 |
| Duration, frames | 9.133333 s, 275 frames at 30 Hz |
| Transform tracks, float tracks | 99, 4 |
| Blocks | 2, starting at 0 and 20576 in `m_data` |
| Frames per block | 256. Block duration 8.5 s |
| Vector quantization | 16-bit on every track |
| Rotation quantization | 40-bit on every track |
| Spline degree | 1 or 3 |
| Binding | `NPC Root [Root]`, empty track map, so tracks 0 to 98 are bones 0 to 98 |

## Object layout (176 bytes, 8-byte pointers)

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 16 | vtable, `hkReferencedObject` | Ignored |
| 0x10 | 4 | `m_type` | 5 means spline compressed |
| 0x14 | 4 | `m_duration` | Seconds |
| 0x18 | 4 | `m_numberOfTransformTracks` | |
| 0x1C | 4 | `m_numberOfFloatTracks` | Skipped |
| 0x20 | 8 | `m_extractedMotion` | Pointer. See below |
| 0x28 | 16 | `m_annotationTracks` | `hkArray`. See below |
| 0x38 | 4 | `m_numFrames` | |
| 0x3C | 4 | `m_numBlocks` | |
| 0x40 | 4 | `m_maxFramesPerBlock` | |
| 0x44 | 4 | `m_maskAndQuantizationSize` | `transformTracks * 4 + floatTracks` |
| 0x48 | 4 | `m_blockDuration` | `(maxFramesPerBlock - 1) * frameDuration` |
| 0x4C | 4 | `m_blockInverseDuration` | `1 / blockDuration` |
| 0x50 | 4 | `m_frameDuration` | 1/30 s |
| 0x54 | 4 | padding | |
| 0x58 | 16 | `m_blockOffsets` | `hkArray<uint32>`, block starts in `m_data` |
| 0x68 | 16 | `m_floatBlockOffsets` | `hkArray<uint32>`, size of the transform part per block |
| 0x78 | 16 | `m_transformOffsets` | `hkArray<uint32>`, empty in vanilla |
| 0x88 | 16 | `m_floatOffsets` | `hkArray<uint32>`, empty in vanilla |
| 0x98 | 16 | `m_data` | `hkArray<uint8>`, masks and track data |
| 0xA8 | 4 | `m_endian` | 0, little-endian |
| 0xAC | 4 | padding | |

`hkArray` works as described on the [hkaSkeleton](/formats/hka-skeleton.md#hkarray) page.

## Extracted motion

`m_extractedMotion` points at an `hkaAnimatedReferenceFrame`: how far the character travels
over the clip, stored apart from the bone tracks. No vanilla clip has one. The pointer is null
in every clip under `meshes\actors\character\`, and no file there has that object at all.

OpenSky still records whether the pointer is set. It is the only reliable way to tell an
in-place clip from a root-motion clip. A vanilla root bone always moves a tiny amount, so any
speed threshold gets some physics steps wrong. See [walk mode](/engine/walk-mode.md).

## Annotations

`m_annotationTracks` is an `hkArray<hkaAnnotationTrack>`. Skyrim keeps footstep marks here.
An annotation is a time in the clip and a short text. Example: `mt_walkforward.hkx` has
`FootLeft` at 0.2333 s and `FootRight` at 0.8 s. These are the tags the
[footstep records](/formats/footstep.md) answer to.

`hkaAnnotationTrack` (24 bytes):

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 8 | `m_trackName` | Pointer to a bone name, or null |
| 0x08 | 16 | `m_annotations` | `hkArray<Annotation>` |

`Annotation` (16 bytes):

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 4 | `m_time` | Seconds from the clip start |
| 0x04 | 4 | padding | The pointer is 8-byte aligned |
| 0x08 | 8 | `m_text` | Pointer to text such as `FootLeft` |

Havok writes one annotation track per transform track, and vanilla fills only the first.
OpenSky merges all tracks, sorts by time, and skips an unreadable entry.

The behavior runtime raises each annotation when playback passes it. This is the only way a
Skyrim footstep fires: the walking clip generators in `mt_behavior.hkx` have an empty
`m_triggers`. See [behavior runtime](/engine/behavior-clips.md#clip-triggers-and-annotations).

## hkaAnimationBinding (72 bytes)

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 16 | vtable, `hkReferencedObject` | Ignored |
| 0x10 | 8 | `m_originalSkeletonName` | Pointer to text such as `NPC Root [Root]` |
| 0x18 | 8 | `m_animation` | Pointer to the animation object |
| 0x20 | 16 | `m_transformTrackToBoneIndices` | `hkArray<int16>`. Empty means track i is bone i |
| 0x30 | 16 | `m_floatTrackToFloatSlotIndices` | `hkArray<int16>` |
| 0x40 | 1 | `m_blendHint` | Then 7 bytes of padding |

An empty map means track i is bone i, as in HavokLib. A non-empty map needs one non-negative
bone index per transform track.

## Transform block

Each block starts at `m_data + m_blockOffsets[i]`:

```text
transform masks: 4 bytes per transform track
float masks:     1 byte per float track (skipped)
pad to 4
for each transform track:
  translation vector track
  rotation quaternion track
  pad to 4
  scale vector track
float data starts at block start + m_floatBlockOffsets[i]
```

The decoder must end exactly at `m_floatBlockOffsets[i]`. Ending early or late is an error.
This check proves the real blocks are read correctly.

## Transform mask (4 bytes per track)

| Byte | Field | Meaning |
| --- | --- | --- |
| 0 | Quantization | Bits 0-1 translation, bits 2-5 rotation, bits 6-7 scale |
| 1 | Translation types | Bits 0-2 static X, Y, Z. Bits 4-6 spline X, Y, Z |
| 2 | Rotation type | Low 4 bits static, high 4 bits spline |
| 3 | Scale types | Bits 0-2 static X, Y, Z. Bits 4-6 spline X, Y, Z |

For each value, spline wins over static, and static wins over identity. Identity is 0 for
translation, 1 for scale, and (0, 0, 0, 1) for rotation. `mt_idle` uses quantization byte
`0x45` everywhere: 16-bit vector control points and 40-bit quaternions. An unknown
quantization is an error. OpenSky does not guess.

## Vector track

With no spline lane: one float32 per static lane, in X, Y, Z order. Identity lanes use no
bytes. With any spline lane:

```text
uint16 storedItemCount           control points = storedItemCount + 1
uint8  degree
uint8  knots[storedItemCount + degree + 2]
pad to 4
for X, Y, Z: spline lane -> float32 minimum, float32 maximum
             static lane -> float32 value
for each control point, X, Y, Z: spline lane -> uint8 or uint16 value
pad to 4
```

A control value is `minimum + (maximum - minimum) * q / (2^bits - 1)`. Knots must not go down.
The degree must be 1 to 4, with enough control points.

## 40-bit quaternion

Five little-endian bytes hold three 12-bit components, a 2-bit index of the largest
component (which is left out), and a 1-bit sign for it. Each stored value `q` becomes
`(q - 2047) * 0.000345436`, a range of about +/- 1/sqrt(2). The missing component is
`sqrt(max(0, 1 - x*x - y*y - z*z))`. Sampled quaternions are normalized, so rounding errors
cannot grow the rotation.

## Sampling

1. Clamp the time to `[0, duration]`.
2. Block = `floor(time / blockDuration)`, clamped to the last block.
3. Frame in the block = `(time - block * blockDuration) / frameDuration`.
4. Static and identity values are returned as they are. Spline values use the standard
   knot-span and de Boor evaluation. Quaternions are normalized.

Float tracks are skipped by using the mask count and `m_floatBlockOffsets`.
