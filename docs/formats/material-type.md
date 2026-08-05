---
type: File Format
title: Material types
description: The MATT record, the CRC32 a NIF collision shape names it by, and the two
  lookups (Havok material value, LTEX.MNAM) that turn a surface into the material an impact
  table is keyed by.
tags: [format, plugin, collision, audio, material]
timestamp: 2026-08-05T00:00:00Z
---

# Material types

A surface in Skyrim has a material, and almost everything that touches a surface asks for
it: a footstep picks its sound by it, an arrow picks its impact by it, a physics body picks
its friction by it. The record that names one is `MATT`, and reaching it is the whole of
issue #358 — the collision world had geometry but no surface vocabulary, so every footstep
sounded like the same stone floor.

The field inventory follows the UESP
[`MATT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MATT) page, cross-checked
against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
(`wbRecord(MATT, 'Material Type', ...)` at line 6303). The hash rule comes from NifTools
[`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml), enum
`SkyrimHavokMaterial`.

## Contents

- Two currencies, one material
- `MATT` material type
- The Havok material hash
- Where the parameters came from
- `LTEX.MNAM` — the terrain half
- What OpenSky does with it

## Two currencies, one material

Nothing in the game says "this floor is stone" in one way. A collision mesh and a painted
landscape name their material differently, and the two have to arrive at the same record:

```text
NIF bhk shape  -> SkyrimHavokMaterial (a uint32 hash) -> MATT
LAND quadrant  -> LTEX                -> LTEX.MNAM    -> MATT
                                                          |
                                       IPDS PNAM pairs ---+-> IPCT -> SNDR
```

`MaterialTypeIndex` owns both lookups, so past it the engine speaks one language: a MATT
FormID. The [footstep chain](/formats/footstep.md) is the first consumer.

## `MATT` material type

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `PNAM` | FormID | optional parent `MATT` |
| `MNAM` | zstring | the Creation Kit material name |
| `CNAM` | 3 x float32 | Havok display colour |
| `BNAM` | float32 | buoyancy |
| `FNAM` | uint32 | flags: stair material, arrows stick |
| `HNAM` | FormID | optional default `IPDS` impact data set |

`MaterialType` decodes `EDID`, `MNAM`, `PNAM`, and `HNAM`. `CNAM` is a Creation Kit
affordance, and nothing floats or sticks arrows yet, so `BNAM` and `FNAM` stay undecoded —
a field the decoder does not read cannot go stale against the spec.

`MNAM` is the field that matters most, because it is the string a collision mesh hashes.
A `MATT` without one exists and is a valid parent, but no mesh can ever point at it.

`PNAM` is a real chain in vanilla — stairs-of-stone declare stone as their parent — but
nothing walks it yet. A footstep whose impact table has no pair for the material falls back
to that table's representative entry instead, which is documented in
[footstep records](/formats/footstep.md).

## The Havok material hash

`nif.xml` states the rule on `SkyrimHavokMaterial` directly: "CRC32 of the lowercase of the
Creation Kit Material Name." That is why the enum's values are large arbitrary-looking
integers rather than 0, 1, 2 — a plugin can author a new material and have meshes point at
it without a NIF format change, because the pointer is a hash rather than an index.

`HavokMaterialHash.value(ofMaterialName:)` implements it: the reflected polynomial
`0xEDB88320` with a **zero** initial register and **no** final complement. That is the
familiar CRC-32 table without zlib's pre- and post-inversion, so `zlib.crc32` does not
produce these values and neither does CRC-32/JAMCRC.

## Where the parameters came from

`nif.xml` says "CRC32" and stops, and there are dozens of CRC-32 variants. The parameters
above were recovered by searching polynomial, initial value, reflection and final-XOR
combinations against one known pair (`Stone` -> `3741512247`), then confirmed against every
other named value the enum lists. `HavokMaterialHashTests` pins 32 of those pairs, so a
regression in the hash is a test failure rather than a subtly wrong footstep.

The material names themselves are inconsistent about spacing, which is worth knowing before
guessing one: `SKY_HAV_MAT_HEAVY_STONE` hashes `heavy stone` with the space, while
`SKY_HAV_MAT_MATERIAL_CARPET` hashes `materialcarpet` without one. OpenSky never guesses a
name — it reads `MNAM` and hashes that.

## `LTEX.MNAM` — the terrain half

Exterior ground is a `LAND` record, not a collision mesh, so it carries no Havok material
at all. Each landscape texture names its material instead: `LTEX.MNAM` is a `MATT` FormID
(xEdit `wbFormIDCk(MNAM, 'Material Type', [MATT, NULL])`). See
[terrain records](/formats/land.md) for the rest of `LTEX` and for how a quadrant's base
texture and its painted layers stack.

## What OpenSky does with it

`MaterialTypeIndex` is built once per plugin from the `MATT` and `LTEX` top groups and
answers three questions:

| question | method |
| --- | --- |
| which MATT does this mesh material name? | `material(forHavokMaterial:)` |
| which MATT does this landscape texture name? | `material(forLandTexture:)` |
| what do I call this material in a readout? | `describe(_:)` |

Two materials whose names hash alike would be indistinguishable to the game engine too, so
record order decides; a value no loaded material hashes to resolves to nothing rather than
to a neighbour. That last case is normal rather than a fault — `nif.xml` lists several
vanilla material values as unknown to the Creation Kit, and a mesh carrying one falls back
exactly as an unresolved surface always has.
