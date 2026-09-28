---
type: File Format
title: hkaSkeleton Object
description: Havok hkaSkeleton layout (bone names, parents, reference pose) in Skyrim SE
  packfiles, and how its bones map onto NIF skeleton nodes.
tags: [format, havok, hkx, skeleton, animation]
---

# hkaSkeleton object

An `hkaSkeleton` is a bone tree plus a bind pose. The bind pose is the rest position of
every bone. `skeleton.hkx` holds two: the animation rig (`NPC Root [Root]`, 99 bones) and
the ragdoll skeleton (`Ragdoll_NPC COM [COM ]`, 18 bones). The container that holds them is
described in [HKX container](/formats/hkx-container.md).

`openskycli skeleton <hkx-key> [--nif <nif-key>]` prints a skeleton and its NIF match (see
[CLI](/tools/cli.md)).

## References

There is no public Havok specification. The layout comes from open parsers and community
notes. Every field was then checked byte by byte against vanilla files: the human and wolf
`skeleton.hkx`, each with rig and ragdoll, all `hk_2010.2.0-r1`, 64-bit little-endian.

- exyorha/hkxparse (MIT): `hkArray` and `hkStringPtr` shapes, arrays with inline elements.
- ret2end/HKX2Library (MIT): Skyrim SE member order and string encoding.
- ZeldaMods wiki "Havok": member tables for `hkaSkeleton`, `hkaBone`, and `hkQsTransform`.

No Havok SDK or Bethesda code was used.

## hkaSkeleton: 112 bytes

The object starts at its virtual fixup offset in `__data__`. Pointers are 8 bytes.

| Offset | Size | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | 8 | vtable pointer | 0 on disk |
| 0x08 | 8 | `hkReferencedObject` (size and flags, reference count, padding) | 0 on disk. Do not trust |
| 0x10 | 8 | `m_name`, `hkStringPtr` | String found through a local fixup |
| 0x18 | 16 | `m_parentIndices`, `hkArray<hkInt16>` | One int16 per bone. -1 is the root |
| 0x28 | 16 | `m_bones`, `hkArray<hkaBone>` | Inline elements, 16 bytes each |
| 0x38 | 16 | `m_referencePose`, `hkArray<hkQsTransform>` | 48 bytes each |
| 0x48 | 16 | `m_referenceFloats`, `hkArray<hkReal>` | Not read |
| 0x58 | 16 | `m_floatSlots`, `hkArray<hkStringPtr>` | Not read |
| 0x68 | 16 | `m_localFrames`, `hkArray` | Size 0 in every file checked |

Skinning and animation need only the name, parents, bones, and reference pose.

## hkArray descriptor

`{ pointer (8 bytes, null on disk), int32 size at +8, uint32 capacityAndFlags at +12 }`.

The element data is found through the local fixup whose `fromOffset` equals the offset of
the array's pointer. Its `toOffset` is the start of the data in the section.

- Use `size` for the element count. Ignore `capacityAndFlags`. Its bit 31 is a Havok
  ownership flag and the low 30 bits are the capacity.
- An empty array has a null pointer and no fixup. This is valid and gives an empty list.

## hkaBone: 16 bytes, inline

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 8 | `m_name`, `hkStringPtr` |
| 0x08 | 1 | `m_lockTranslation`, `hkBool` |
| 0x09 | 7 | Padding |

`m_bones` holds the bones themselves, not pointers to them. So there is one local fixup per
bone name, at `bonesData + i * 16`. A bone without a name fixup is an error. Skinning and
the NIF map use the name as the key, so a nameless bone is malformed.

## hkQsTransform: 48 bytes

The bind transform of a bone, relative to its parent. This matches the local transform of a
NIF `NiNode`.

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 16 | Translation, float4 (x, y, z, w) |
| 0x10 | 16 | Rotation, quaternion (x, y, z, w) |
| 0x20 | 16 | Scale, float4 (x, y, z, w) |

The `w` of translation and scale is padding with random values. OpenSky drops it and does
not check it. The 10 used values (3 translation, 4 rotation, 3 scale) must be finite
numbers.

## hkStringPtr

An 8-byte pointer, null on disk. The string is found through the local fixup at the
pointer's offset. It is null-terminated ASCII at `toOffset`. A string pointer with no fixup
is a null string. This is valid.

## Error checks

- Every array must fit inside the section data.
- An array with size above 0 must have a fixup.
- Parents, bones, and reference pose must have the same count.
- A parent index must be -1 or a valid bone index.

In vanilla files, a parent always comes before its child. OpenSky does not require this.

## Mapping bones to NIF nodes

Skinning finds bone transforms by NIF `NiNode` name. So OpenSky matches each HKX bone to
the NIF node with exactly the same name. It does not ignore case or spaces, because that
would hide real differences. Some bones have no match on purpose.

Vanilla human rig (`skeleton.hkx` against `skeleton.nif`, 99 bones): 93 match, 6 exist only
in HKX, and 6 exist only in the NIF.

- HKX only: `x_NPC LookNode [Look]`, `x_NPC Translate [Pos ]`, `x_NPC Rotate [Rot ]`
  (animation control nodes), and `Shield`, `Weapon`, `Quiver` (attach points).
- NIF only: `CharacterBumper`, `NPC`, `skeleton.nif` (the root), and `SHIELD`, `WEAPON`,
  `QUIVER`.

`Shield` and `SHIELD` are the same attach point with different case. The exact match leaves
them apart. Body skinning does not use them, and a loose match would hide the difference.
