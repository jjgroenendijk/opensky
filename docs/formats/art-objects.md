---
type: File Format
title: Art objects (ARTO)
description: Layout of Skyrim SE ARTO records and the magic-effect and dual-cast links that
  name them.
tags: [format, plugin, records, magic]
---

# Art objects

An `ARTO` art object is a model that the magic system attaches to something: the hands of a
caster, the body of a target, or an enchanted weapon. The record holds only the model and what
kind of art it is. The effect that uses it is on [magic records](/formats/magic-records.md).

Sources: UESP "Skyrim Mod:Mod File Format/ARTO"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARTO>) and xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/9fb016884bec138ea6c7b872cec831537d464c3e/Core/wbDefinitionsTES5.pas)
(`wbRecord(ARTO, ...)` at line 7446). All integers are little-endian.

## Fields

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `OBND` | 6 x int16 | bounds |
| `MODL` | zstring | model path, relative to `meshes/` |
| `MODT`, `MODS` | bytes | model texture hashes and alternate textures; not read |
| `DNAM` | uint32 | art type (below) |

Art type, from the xEdit enum:

| value | meaning |
| --- | --- |
| 0 | magic casting |
| 1 | magic hit effect |
| 2 | enchantment effect |

An unknown value is kept as its number. A field that is too short is counted as malformed and
the rest of the record still decodes.

## Links that name an ARTO

| record | where | meaning |
| --- | --- | --- |
| `MGEF` | `DATA` offset `0x5C` | casting art |
| `MGEF` | `DATA` offset `0x60` | hit-effect art |
| `MGEF` | `DATA` offset `0x74` | enchant art |
| `DUAL` | `DATA` offset `0x0C` | hit-effect art of a dual cast |

`MGEF DATA` offset `0x6C` is the dual-cast art. It names a `DUAL`, not an `ARTO`. Each link
resolves relative to the plugin that wrote it, like every other FormID link.

## Confirmed on the real install

The five masters (`Skyrim.esm`, `Update.esm`, `Dawnguard.esm`, `HearthFires.esm`,
`Dragonborn.esm`) carry 318 ARTO records, and all of them decode. By art type: 80 magic
casting, 225 magic hit effect, 13 enchantment effect. No record has an unknown type. 314
records carry `MODT`, which OpenSky does not read; no other field is left unread.

The MGEF and DUAL records of the same files hold 1,046 non-null ARTO links. Every one
resolves in the art-object store. Examples: `AbsorbBlueHandFX01` is casting art,
`AbsorbSpellHitEffect01` is hit-effect art, and `BoundSwordEnchEffects` is enchantment art.
