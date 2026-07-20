---
type: File Format
title: hkaSkeleton Object
description: Havok hkaSkeleton object layout (bone names, parent indices,
  reference pose) inside the SSE packfile and how OpenSky name-maps it onto the
  NIF skeleton nodes bind-pose skinning uses.
tags: [format, havok, hkx, skeleton, animation]
timestamp: 2026-07-20T00:00:00Z
---

# hkaSkeleton object

The bone hierarchy + bind pose one Havok packfile holds. `skeleton.hkx` carries
two: the animation rig (`NPC Root [Root]`, 99 bones) and the ragdoll physics
skeleton (`Ragdoll_NPC COM [COM ]`, 18 bones). This page covers the object
internals only; the packfile container that locates them (header, sections,
fixups, class-name + object inventory) is [HKX container](/formats/hkx-container.md).

Parser: `opensky/Formats/HKX/HKASkeleton.swift` — `HKASkeleton.skeletons(in:)`
walks the container's virtual-fixup object inventory, decodes each
`hkaSkeleton`. Name-map: `SkeletonBoneMap.swift`. CLI dump:
`openskycli skeleton <hkx-key> [--nif <nif-key>]` ([CLI](/tools/cli.md)). Tests:
`HKASkeletonTests` + `SkeletonBoneMapTests` over synthetic `HKASkeletonFixture`.

## References

No public Havok spec. Object layout reimplemented from independent open
parsers + community docs, then every field probe-verified byte-by-byte against
the local SSE install (`skeleton.hkx` human rig + ragdoll, wolf rig + ragdoll —
all `hk_2010.2.0-r1` 64-bit LE, fileVersion 8):

* exyorha/hkxparse (MIT) — hkArray/hkStringPtr shape, inline-element arrays.
* ret2end/HKX2Library (MIT) — SSE-specific member order, string encoding.
* ZeldaMods wiki "Havok" — hkaSkeleton/hkaBone/hkQsTransform member tables.

No Havok SDK or Bethesda code consulted (AGENTS.md Legal & IP).

## hkaSkeleton object (112 bytes, 8-byte pointers)

At each `hkaSkeleton` virtual-fixup data offset in `__data__`. Member offsets:

| off | size | field | notes |
| --- | --- | --- | --- |
| 0x00 | 8 | vtable ptr | zero on disk |
| 0x08 | 8 | hkReferencedObject (memSizeAndFlags, referenceCount, pad) | both 0 in packfile — never trust |
| 0x10 | 8 | m_name hkStringPtr | null ptr, string via local fixup |
| 0x18 | 16 | m_parentIndices hkArray\<hkInt16\> | one i16 per bone (-1 = root) |
| 0x28 | 16 | m_bones hkArray\<hkaBone\> | INLINE elements, stride 16 |
| 0x38 | 16 | m_referencePose hkArray\<hkQsTransform\> | stride 48 |
| 0x48 | 16 | m_referenceFloats hkArray\<hkReal\> | read past — not needed for skinning |
| 0x58 | 16 | m_floatSlots hkArray\<hkStringPtr\> | read past |
| 0x68 | 16 | m_localFrames hkArray | size 0 in every probed file |

The engine decodes m_name, m_parentIndices, m_bones, m_referencePose only —
bind-pose skinning + animation retarget need nothing from referenceFloats /
floatSlots / localFrames.

## hkArray descriptor

`{ ptr(8, null on disk), i32 size @+8, u32 capacityAndFlags @+12 }`. Element
data is located only via the local fixup whose `fromOffset` equals the array
field's pointer offset; `toOffset` is the section-local data start. Rules:

* Use the `size` field for the element count. `capacityAndFlags` bit31 is a
  Havok owned-storage flag; the low 30 bits are capacity — ignore both.
* A size-0 array has a null pointer and NO fixup. Must not error — decode to an
  empty list.

## hkaBone (inline, stride 16)

| off | size | field |
| --- | --- | --- |
| 0x00 | 8 | m_name hkStringPtr (per-element local fixup at `bonesData + i*16`) |
| 0x08 | 1 | m_lockTranslation hkBool |
| 0x09 | 7 | pad |

m_bones holds inline hkaBone values (not a pointer array): N local fixups land
at stride-16 `fromOffset`s inside the bones data. A bone's name fixup is
required — a missing one throws `boneNameMissing` (the name keys skinning +
the NIF map, so a null bone name is treated as malformed, not skipped).

## hkQsTransform (48 bytes)

Parent-relative bind transform, matching NIF NiNode local transforms.

| off | size | field |
| --- | --- | --- |
| 0x00 | 16 | translation float4 (x, y, z, w) |
| 0x10 | 16 | rotation quat (x, y, z, w) |
| 0x20 | 16 | scale float4 (x, y, z, w) |

The w lane of translation + scale is junk padding — decoded to `SIMD3` so it
never reaches engine math, and not validated for finiteness. The 10 used lanes
(3 translation, 4 quat, 3 scale) must be finite; a NaN/inf there throws
`nonFiniteTransform`.

## hkStringPtr

`{ ptr(8) }`, null on disk. String located via the local fixup at the pointer
offset; NUL-terminated ASCII at `toOffset`. A hkStringPtr may legitimately have
no fixup (null string) — m_name decodes to `nil`, never traps.

## Defensive decode

Real files carry mod quirks; malformed input throws a typed `HKASkeletonError`,
never crashes (AGENTS.md reverse-engineering discipline):

* every array bound-checked against the section payload before reading
  (`arrayOutOfBounds`);
* size>0 array with no fixup -> `missingArrayData`;
* m_parentIndices / m_bones / m_referencePose counts must agree -> `countMismatch`;
* parent index neither -1 nor a valid bone index -> `parentOutOfRange`;
* parents are topological in vanilla files (parent index < child) but the
  parser does not require it — only the range is enforced.

## Name-map onto the NIF skeleton

Skinning already keys bone transforms on NIF NiNode names
(`NIFSkeleton.boneTransforms`). `SkeletonBoneMap` matches HKX bone names
against that set by exact name equality (the vanilla rig shares names verbatim;
normalization would mask real divergence) and reports mismatches both
directions with a reason tag. The map is partial by design.

Observed on the vanilla human rig (`skeleton.hkx` -> `skeleton.nif`, 99 bones,
99 unique NIF node names): 93 exact matches, 6 HKX-only bones, 6 NIF-only
nodes.

* HKX-only (no NIF node): `x_NPC LookNode [Look]`, `x_NPC Translate [Pos ]`,
  `x_NPC Rotate [Rot ]` (animation control nodes), `Shield`, `Weapon`,
  `Quiver` (attach nodes).
* NIF-only (no HKX bone): `CharacterBumper`, `NPC`, `skeleton.nif` (root) plus
  `SHIELD`, `WEAPON`, `QUIVER`.

The `Shield`/`Weapon`/`Quiver` bones and `SHIELD`/`WEAPON`/`QUIVER` nodes are
the same attach points spelled with different case — an exact map leaves them
unmatched by design (their transforms are irrelevant to body skinning; a fuzzy
match would silently paper over the case split). This split is the reason both
directions land on 6, not a lost bone.
