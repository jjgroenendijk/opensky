---
type: File Format
title: Head parts and colors
description: Skyrim SE HDPT head parts, CLFM colors and EYES records.
tags: [format, plugin, actor]
---

# Head parts and colors

`HDPT` is one piece of a face: the head mesh, hair, eyes, brows, or a scar. `CLFM` is a
named color used by hair and tints. `EYES` is the older eye record.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## HDPT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `MODL`, `MODT`, `MODS` | model group | The mesh |
| `DATA` | uint8 | Flags: 0x01 playable, 0x02 male, 0x04 female, 0x08 is extra part, 0x10 uses solid tint |
| `PNAM` | uint32 | Part type: 0 misc, 1 face, 2 eyes, 3 hair, 4 facial hair, 5 scar, 6 eyebrows |
| `HNAM` | FormID | Extra `HDPT` that comes with this one, repeated |
| `NAM0` | uint32 | Kind of the next `NAM1`: 0 race morph, 1 expression, 2 chargen morph |
| `NAM1` | zstring | A `.tri` morph file |
| `TNAM` | FormID | `TXST` texture set |
| `CNAM` | FormID | `CLFM` color |
| `RNAM` | FormID | `FLST` of races that may use the part |

An unknown `PNAM` value keeps its number. A `NAM0` outside 0 to 2 is tallied, and its
`NAM1` is dropped. Extra parts can link back to each other, so a walk over `HNAM` must stop
at a part it has already seen.

## CLFM

| Field | Type | Meaning |
| --- | --- | --- |
| `FULL` | lstring | Name |
| `CNAM` | 4 bytes | RGBA color |
| `FNAM` | uint32 | Nonzero: playable |

Header flag 0x04 marks a non-playable color.

## EYES

| Field | Type | Meaning |
| --- | --- | --- |
| `FULL` | lstring | Name |
| `ICON` | zstring | Texture, relative to `Data/textures` |
| `DATA` | uint8 | Flags: 0x01 playable, 0x02 not male, 0x04 not female |

## Lookup

Head parts are indexed by `PNAM` part type. Expanding a part walks its `HNAM` extra parts
depth first. A part already seen is counted as a cycle and not visited again. An extra
part that names no `HDPT` is counted as dangling. The color of a part is its `CNAM` `CLFM`,
and the hair color of an actor is its `NPC_` `HCLF` `CLFM`.

On the five masters the 805 winning `HDPT` records expand without a cycle or a
dangling extra part. The widest expansion holds 3 parts.
