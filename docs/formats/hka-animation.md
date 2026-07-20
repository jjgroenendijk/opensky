---
type: File Format
title: hkaSplineCompressedAnimation Object
description: Havok 2010 spline-compressed animation metadata, transform-block
  grammar, quantization, and per-track local-transform sampling as shipped in Skyrim SE.
tags: [format, havok, hkx, animation, spline]
timestamp: 2026-07-20T00:00:00Z
---

# hkaSplineCompressedAnimation object

Idle `.hkx` clips store bone-local animation as `hkaSplineCompressedAnimation`, linked to
bone indices by `hkaAnimationBinding`. This page covers both object layouts, transform
blocks, vector/quaternion quantization, B-spline sampling. Packfile container/fixups:
[HKX container](/formats/hkx-container.md). Skeleton/bind pose:
[hkaSkeleton](/formats/hka-skeleton.md).

Parser: `opensky/Formats/HKX/HKASplineCompressedAnimation.swift` +
`HKASplineBlock.swift`. Entry point:
`HKASplineCompressedAnimation.animations(in:)` + `HKAAnimationBinding.bindings(in:)`;
bone-indexed sampling: `boneLocalTransforms(at:binding:)`. CLI gate:
`openskycli animation <hkx-key>`
([CLI](/tools/cli.md)). Tests: `HKASplineAnimationTests` over synthetic packfiles.

## References + clean-room scope

No public Havok spec. Layout/codec reimplemented from independent open parsers, then
probe-verified against user's local SSE install:

* [exyorha/hkxparse](https://github.com/exyorha/hkxparse) (MIT) — Havok 2010 class
  reflection: member order/types, 32-bit layout cross-check.
* [ret2end/HKX2Library](https://github.com/ret2end/HKX2Library) (MIT) — SSE 64-bit
  hkaAnimation + hkaSplineCompressedAnimation member offsets/array types.
* [PredatorCZ/HavokLib](https://github.com/PredatorCZ/HavokLib) (GPLv3) — transform-mask
  semantics, block grammar, vector quantization, 40-bit quaternion packing. Algorithm
  independently expressed in Swift; no source copied.
* Piegl + Tiller, *The NURBS Book*, 2nd ed. — standard knot-span/de Boor B-spline
  evaluation.

No Havok SDK, Bethesda code, decompiled binary, extracted bytes, or game asset lands in
repo (AGENTS.md Legal & IP).

## Observed SSE clip

`meshes\actors\character\animations\male\mt_idle.hkx`, read in place from
`Skyrim - Animations.bsa`:

| property | observed |
| --- | --- |
| container | `hk_2010.2.0-r1`, fileVersion 8, 64-bit LE |
| object class / animation type | hkaSplineCompressedAnimation / 5 |
| duration / frames | 9.133333 s / 275 (frames 0...274, 30 Hz) |
| transform / float tracks | 99 / 4 |
| blocks | 2; starts 0 + 20,576 in m_data |
| max frames/block | 256; block duration 8.5 s |
| transform bytes/block | 20,552 + 4,216 (both decode cursors close exactly) |
| vector quantization | 16-bit (all 99 masks in both blocks) |
| rotation quantization | 40-bit (all masks) |
| spline degrees | 1 + 3 (one linear track/block; remaining dynamic tracks cubic) |
| binding | NPC Root [Root]; empty transform map -> identity tracks 0...98 |
| float-track map / blend hint | [4, 5, 6, 7] / 0 |

Production decode sampled all 275 x 99 transforms over full duration: no throw, NaN, inf,
or defensive-bound breach. Observed max absolute translation 121, max absolute scale 1,
normalized quaternion length 0.9999999...1.0000001.

## Object layout (176 bytes, 8-byte pointers)

At each hkaSplineCompressedAnimation virtual-fixup offset in `__data__`:

| off | size | field | observed / meaning |
| --- | --- | --- | --- |
| 0x00 | 16 | vtable + hkReferencedObject | zero/persisted ref metadata; ignored |
| 0x10 | 4 | hkaAnimation.m_type | 5 = spline compressed |
| 0x14 | 4 | m_duration | seconds |
| 0x18 | 4 | m_numberOfTransformTracks | 99 |
| 0x1C | 4 | m_numberOfFloatTracks | 4; skipped by 6.3 |
| 0x20 | 8 | m_extractedMotion ptr | fixup-managed; skipped |
| 0x28 | 16 | m_annotationTracks hkArray | skipped |
| 0x38 | 4 | m_numFrames | 275 |
| 0x3C | 4 | m_numBlocks | 2 |
| 0x40 | 4 | m_maxFramesPerBlock | 256 |
| 0x44 | 4 | m_maskAndQuantizationSize | transformTracks*4 + floatTracks = 400 |
| 0x48 | 4 | m_blockDuration | (maxFramesPerBlock-1)*frameDuration = 8.5 |
| 0x4C | 4 | m_blockInverseDuration | 1/blockDuration |
| 0x50 | 4 | m_frameDuration | 1/30 s |
| 0x54 | 4 | pad | ignored |
| 0x58 | 16 | m_blockOffsets hkArray\<u32\> | block starts relative to m_data |
| 0x68 | 16 | m_floatBlockOffsets hkArray\<u32\> | transform-region size per block |
| 0x78 | 16 | m_transformOffsets hkArray\<u32\> | empty in observed clip |
| 0x88 | 16 | m_floatOffsets hkArray\<u32\> | empty in observed clip |
| 0x98 | 16 | m_data hkArray\<u8\> | masks + compressed track data |
| 0xA8 | 4 | m_endian | 0 (LE) |
| 0xAC | 4 | pad | ignored |

hkArray uses same pointer/fixup descriptor documented under
[hkaSkeleton](/formats/hka-skeleton.md#hkarray-descriptor).

## Binding layout (72 bytes, 8-byte pointers)

At each hkaAnimationBinding virtual-fixup offset in `__data__`:

| off | size | field | observed / meaning |
| --- | --- | --- | --- |
| 0x00 | 16 | vtable + hkReferencedObject | zero/persisted ref metadata; ignored |
| 0x10 | 8 | m_originalSkeletonName ptr | local fixup -> `NPC Root [Root]` |
| 0x18 | 8 | m_animation ptr | fixup -> spline object at data offset 304 |
| 0x20 | 16 | m_transformTrackToBoneIndices hkArray\<i16\> | empty = identity mapping |
| 0x30 | 16 | m_floatTrackToFloatSlotIndices hkArray\<i16\> | [4, 5, 6, 7] |
| 0x40 | 1 | m_blendHint | 0 |
| 0x41 | 7 | pad | ignored |

Open HavokLib's exporter applies track index directly when transform map is empty;
production decode follows that compact identity rule. Non-empty maps must contain exactly
one non-negative bone index per transform track. Binding animation pointer must match the
sampled spline object's section + data offset; CLI rejects an unbound clip.

## Transform block

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
float data begins at block start + m_floatBlockOffsets[i]
```

Decoder must end exactly at `floatBlockOffsets[i]`; under/over-consumption throws
`blockSizeMismatch`. This caught layout drift during probe and proves both real block
grammars close without using next-block heuristics.

### Transform mask (4 bytes/track)

| byte | field | meaning |
| --- | --- | --- |
| 0 | quantization | bits 0-1 translation, 2-5 rotation selector, 6-7 scale |
| 1 | translation types | bits 0-2 static XYZ; bits 4-6 spline XYZ |
| 2 | rotation type | low nibble static; high nibble spline |
| 3 | scale types | bits 0-2 static XYZ; bits 4-6 spline XYZ |

Type precedence matches open parsers: spline -> static -> identity. Identity vector lanes
are 0 for translation, 1 for scale; identity quaternion is (0,0,0,1). Real mt_idle uses
quantization byte `0x45` on every track/block: u16 vector control points + 40-bit quats.
Unknown dynamic quantization throws `unsupportedQuantization`; it is never guessed.

### Vector track

No spline lanes: one f32 per static lane in XYZ order; identity lanes consume no bytes.
With any spline lane:

```text
u16 storedItemCount              controlPointCount = storedItemCount + 1
u8  degree
u8  knots[storedItemCount + degree + 2]
pad to 4
for XYZ: spline -> f32 minimum + f32 maximum
         static -> f32 value
for each control point, XYZ order: spline lane -> u8/u16 quantized value
pad to 4
```

Control value = `minimum + (maximum-minimum) * q/(2^bits-1)`. Knots must be
non-descending; degree 1...4 + enough control points required.

### 40-bit quaternion

Five LE bytes pack three 12-bit stored components, 2-bit omitted-largest lane index,
1-bit omitted-lane sign. Each stored integer `q` becomes
`(q-2047)*0.000345436` (range about +/-1/sqrt(2)); missing component magnitude is
`sqrt(max(0, 1-x*x-y*y-z*z))`. Sampled spline quaternions normalize before entering
`HKABonePose` -> compression/interpolation drift never grows the rotation matrix.

## Sampling

Input time clamps to `[0,duration]`. Block = `floor(time/blockDuration)`, clamped to last
block. Local frame = `(time - block*blockDuration)/frameDuration`. Static/identity lanes
return directly. Dynamic scalar/quaternion control points evaluate with standard
knot-span + de Boor interpolation; quaternion result normalizes. `localTransforms(at:)`
returns transform-track order; `boneLocalTransforms(at:binding:)` pairs each pose with its
resolved skeleton bone index.

## Defensive decode

Typed `HKASplineAnimationError` covers invalid/non-finite metadata, missing fixup data,
array/block bounds, table-count mismatch, unsupported quantization, invalid spline
degree/knots/bounds, exact block-size mismatch, non-finite/unbounded sampled transforms.
External input never force-unwraps/casts/traps. 6.3 decodes transform tracks only; four
float tracks are structurally skipped via mask count + floatBlockOffsets.
