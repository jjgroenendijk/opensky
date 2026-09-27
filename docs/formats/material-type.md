---
type: File Format
title: Material types
description: The MATT record, the CRC32 hash a NIF collision shape uses to name it, and
  LTEX MNAM for terrain.
tags: [format, plugin, collision, audio, material]
---

# Material types

Every surface has a material, for example stone or wood. A footstep picks its sound by it,
an arrow picks its hit effect by it, and a physics body picks its friction by it. The
`MATT` record defines a material.

Sources: UESP [`MATT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MATT), checked
against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
(`wbRecord(MATT, 'Material Type', ...)`, line 6303). The hash rule is from NifTools
[`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml), enum
`SkyrimHavokMaterial`.

## Two ways to name a material

A collision mesh and a landscape name their material in different ways. Both must lead to
the same `MATT`:

```text
NIF bhk shape  -> SkyrimHavokMaterial (uint32 hash) -> MATT
LAND quadrant  -> LTEX -> LTEX.MNAM                 -> MATT
                                                        |
                                     IPDS PNAM pairs ---+-> IPCT -> SNDR
```

After this step, the engine uses only the `MATT` FormID. See
[footstep records](/formats/footstep.md) for the lower part of the chart.

## MATT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `PNAM` | FormID | Parent `MATT` |
| `MNAM` | zstring | Creation Kit material name |
| `CNAM` | 3 x float32 | Havok display color |
| `BNAM` | float32 | Buoyancy |
| `FNAM` | uint32 | Flags: stair material, arrows stick |
| `HNAM` | FormID | Default impact data set (`IPDS`) |

OpenSky reads `EDID`, `MNAM`, `PNAM`, and `HNAM`. Nothing floats or sticks arrows yet, so it
does not read `BNAM` or `FNAM`.

`MNAM` is the most important field, because a collision mesh names a material by the hash of
this string. A `MATT` without `MNAM` can still be a parent, but no mesh can point at it.

`PNAM` chains are real in vanilla. For example, stone stairs have stone as their parent.
OpenSky does not follow them yet.

## The Havok material hash

`nif.xml` says the value is the "CRC32 of the lowercase of the Creation Kit Material Name".
Because it is a hash and not an index, a plugin can add a new material without a NIF format
change.

The exact CRC is: reflected polynomial `0xEDB88320`, initial value **0**, and **no** final
XOR. This is not zlib's CRC-32 (which inverts before and after), and not CRC-32/JAMCRC.

`nif.xml` does not say which CRC-32 variant it is. The parameters were found by trying
polynomial, initial value, reflection, and final XOR combinations against one known pair,
`Stone` -> `3741512247`. Then they were checked against every other named value in the
enum. The unit tests pin 32 of these pairs.

The names are not consistent about spaces. `SKY_HAV_MAT_HEAVY_STONE` hashes `heavy stone`,
with a space. `SKY_HAV_MAT_MATERIAL_CARPET` hashes `materialcarpet`, without one. So OpenSky
never guesses a name. It hashes the `MNAM` it reads.

If two materials have the same hash, the record order decides. A hash that no material
matches gives no material. This is normal: `nif.xml` lists some vanilla values that the
Creation Kit does not know. Such a surface uses the fallback.

## LTEX MNAM for terrain

Exterior ground is a `LAND` record, not a collision mesh, so it has no Havok material. Each
landscape texture names a material instead. `LTEX MNAM` is a `MATT` FormID (xEdit
`wbFormIDCk(MNAM, 'Material Type', [MATT, NULL])`). See
[terrain records](/formats/land.md) for the rest of `LTEX` and how texture layers stack.
