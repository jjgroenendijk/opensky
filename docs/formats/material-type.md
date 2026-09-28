---
type: File Format
title: Material types
description: The MATT record, the CRC32 a NIF collision shape names it by, and the LTEX.MNAM
  link for terrain.
tags: [format, plugin, collision, audio, material]
---

# Material types

Every surface has a material. A footstep picks its sound by the material. An arrow picks its
impact by it. A physics body picks its friction by it. The `MATT` record names a material.

Sources: UESP [`MATT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MATT), checked
against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
(`wbRecord(MATT, ...)`, line 6303). The hash rule comes from NifTools
[`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml), enum
`SkyrimHavokMaterial`.

## Two ways to name a material

A collision mesh and a painted landscape name their material in different ways. Both must
reach the same `MATT`:

```text
NIF bhk shape  -> SkyrimHavokMaterial (a uint32 hash) -> MATT
LAND quadrant  -> LTEX                -> LTEX.MNAM    -> MATT
                                                          |
                                       IPDS PNAM pairs ---+-> IPCT -> SNDR
```

After this step the engine uses one thing: a `MATT` FormID. The
[footstep chain](/formats/footstep.md) is the first user.

## MATT fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `PNAM` | FormID | Parent `MATT` |
| `MNAM` | zstring | Creation Kit material name |
| `CNAM` | 3 x float32 | Havok display color |
| `BNAM` | float32 | Buoyancy |
| `FNAM` | uint32 | Flags: stair material, arrows stick |
| `HNAM` | FormID | Default impact data set (`IPDS`) |

OpenSky reads `EDID`, `MNAM`, `PNAM`, and `HNAM`. Nothing floats or makes arrows stick yet,
so `BNAM` and `FNAM` are not read.

`MNAM` matters most. A collision mesh names its material by a hash of this string. A `MATT`
without `MNAM` can be a parent, but no mesh can point at it.

Vanilla uses `PNAM` chains. For example, stone stairs have stone as their parent. OpenSky
does not follow `PNAM` yet. See [footstep records](/formats/footstep.md) for the fallback.

## The Havok material hash

`nif.xml` gives the rule: "CRC32 of the lowercase of the Creation Kit Material Name." So a
plugin can add a new material, and meshes can use it, without a change to the NIF format.

The CRC is not the usual one. It uses the reflected polynomial `0xEDB88320`, an initial
value of **zero**, and **no** final XOR. So `zlib.crc32` gives different values, and so does
CRC-32/JAMCRC.

Example: `Stone` hashes to `3741512247`.

`nif.xml` only says "CRC32", and there are many CRC-32 variants. The parameters above were
found by trying combinations of polynomial, initial value, reflection, and final XOR against
the `Stone` pair. Then every other named value in the enum was checked.

Material names are not consistent about spaces. `SKY_HAV_MAT_HEAVY_STONE` hashes
`heavy stone`, with a space. `SKY_HAV_MAT_MATERIAL_CARPET` hashes `materialcarpet`, without
one. So OpenSky never guesses a name. It hashes the `MNAM` it reads.

When two materials hash to the same value, record order decides. A hash that no material
matches resolves to nothing. That is normal: `nif.xml` lists some vanilla values that the
Creation Kit does not know.

## LTEX.MNAM, for terrain

Exterior ground is a `LAND` record, not a collision mesh, so it has no Havok material. Each
landscape texture names its material instead. `LTEX.MNAM` is a `MATT` FormID (xEdit:
`wbFormIDCk(MNAM, 'Material Type', [MATT, NULL])`). See [terrain records](/formats/land.md)
for the rest of `LTEX`.
