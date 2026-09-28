---
type: File Format
title: hkaSkeleton Object
description: Havok hkaSkeleton layout (bone names, parents, reference pose) in SSE packfiles,
  and how OpenSky matches its bones to NIF skeleton nodes.
tags: [format, havok, hkx, skeleton, animation]
---

# hkaSkeleton object

An `hkaSkeleton` holds a bone tree and its bind pose (the rest pose). `skeleton.hkx` holds
two of them: the animation rig (`NPC Root [Root]`, 99 bones) and the ragdoll skeleton
(`Ragdoll_NPC COM [COM ]`, 18 bones). The container that locates the objects is on the
[HKX container](/formats/hkx-container.md) page.

`openskycli skeleton <hkx-key> [--nif <nif-key>]` prints a skeleton
([CLI](/tools/cli.md)).

## Sources

There is no public Havok specification. The layout comes from open parsers and notes, and
every field was checked byte by byte against real SSE files: the human and wolf rigs and
ragdolls, all `hk_2010.2.0-r1`, 64-bit, little-endian, file version 8.

- exyorha/hkxparse (MIT): the shape of `hkArray` and `hkStringPtr`, inline arrays.
- ret2end/HKX2Library (MIT): SSE member order and string encoding.
- ZeldaMods wiki "Havok": member tables for `hkaSkeleton`, `hkaBone`, and `hkQsTransform`.

No Havok SDK or Bethesda code was used.

## hkaSkeleton (112 bytes, 8-byte pointers)

The object starts at the offset its virtual fixup gives in `__data__`.

| Offset | Size | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | 8 | vtable pointer | Zero on disk |
| 0x08 | 8 | hkReferencedObject | Both values are 0 on disk. Do not trust them |
| 0x10 | 8 | m_name (`hkStringPtr`) | String found through a local fixup |
| 0x18 | 16 | m_parentIndices (`hkArray<hkInt16>`) | One int16 per bone. -1 is the root |
| 0x28 | 16 | m_bones (`hkArray<hkaBone>`) | Inline elements, 16 bytes each |
| 0x38 | 16 | m_referencePose (`hkArray<hkQsTransform>`) | 48 bytes each |
| 0x48 | 16 | m_referenceFloats (`hkArray<hkReal>`) | Not read |
| 0x58 | 16 | m_floatSlots (`hkArray<hkStringPtr>`) | Not read |
| 0x68 | 16 | m_localFrames (`hkArray`) | Empty in every file checked |

Skinning and animation need only the name, the parents, the bones, and the reference pose.

## hkArray

An `hkArray` is 16 bytes: a pointer (8 bytes, null on disk), an int32 size at +8, and a
uint32 `capacityAndFlags` at +12.

- The element data is found through the local fixup whose `fromOffset` equals the pointer's
  offset. Its `toOffset` is where the data starts in the section.
- Use `size` for the count. Ignore `capacityAndFlags`. Its bit 31 is a Havok ownership flag,
  and the low 30 bits are the capacity.
- An empty array has a null pointer and no fixup. That is valid, not an error.

## hkaBone (inline, 16 bytes)

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 8 | m_name (`hkStringPtr`) |
| 0x08 | 1 | m_lockTranslation (`hkBool`) |
| 0x09 | 7 | Padding |

The bones are stored inline, not as pointers. So there is one local fixup per bone name, at
`bonesData + i * 16`. A bone without a name fixup is an error. The name is the key for
skinning, so a nameless bone cannot be used.

## hkQsTransform (48 bytes)

The bind transform of a bone, relative to its parent. This matches a NIF `NiNode` local
transform.

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 16 | Translation, float4 (x, y, z, w) |
| 0x10 | 16 | Rotation quaternion (x, y, z, w) |
| 0x20 | 16 | Scale, float4 (x, y, z, w) |

The w value of translation and scale is padding with random content. OpenSky drops it and
does not check it. The other 10 values must be finite.

## hkStringPtr

An 8-byte pointer, null on disk. The string is found through the local fixup at the pointer's
offset. It is null-terminated ASCII. A string pointer without a fixup is a null string, which
is valid.

## Bad input

- Each array is checked against the section size before it is read.
- A non-empty array with no fixup is an error.
- The parent, bone, and pose arrays must have the same count.
- A parent index must be -1 or a valid bone index. In vanilla files a parent always comes
  before its child, but OpenSky does not require that.

## Matching bones to the NIF skeleton

Skinning finds bones by `NiNode` name in the NIF skeleton. OpenSky matches HKX bone names to
NIF node names by exact equality. Vanilla uses the same names in both. Fuzzy matching would
hide real differences.

On the vanilla human rig (`skeleton.hkx` to `skeleton.nif`), 93 of 99 bones match. Six bones
exist only in HKX, and six nodes exist only in the NIF:

- HKX only: `x_NPC LookNode [Look]`, `x_NPC Translate [Pos ]`, `x_NPC Rotate [Rot ]`
  (animation control nodes), and `Shield`, `Weapon`, `Quiver` (attach points).
- NIF only: `CharacterBumper`, `NPC`, `skeleton.nif` (the root), and `SHIELD`, `WEAPON`,
  `QUIVER`.

`Shield` and `SHIELD` are the same attach point with different case. Exact matching leaves
them apart on purpose. Their transforms do not affect body skinning.
