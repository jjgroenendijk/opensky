---
type: File Format
title: Explosion and debris records
description: Skyrim SE EXPL explosions with their four DATA sizes, and DEBR debris models.
tags: [format, plugin, magic]
---

# Explosion and debris records

`EXPL` is a blast: light, sound, force, damage, and what it leaves behind. `DEBR` is a
list of debris meshes an explosion or a destroyed object throws.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## EXPL

| Field | Type | Meaning |
| --- | --- | --- |
| `OBND` | 12 bytes | Bounds |
| `FULL` | lstring | Name |
| `MODL` | model group | The blast mesh |
| `EITM` | FormID | `ENCH` or `SPEL` applied to what the blast hits |
| `MNAM` | FormID | `IMAD` |
| `DATA` | 40 to 52 bytes | See below |
| `VMAD` | script data | Scripts |

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | FormID | `LIGH` |
| 4 | FormID | Sound 1 |
| 8 | FormID | Sound 2 |
| 12 | FormID | `IPDS` |
| 16 | FormID | Placed object |
| 20 | FormID | Spawn projectile |
| 24 | float | Force |
| 28 | float | Damage |
| 32 | float | Radius |
| 36 | float | Image-space radius |
| 40 | float | Vertical offset multiplier (44 bytes and up) |
| 44 | uint32 | Flags (48 bytes and up) |
| 48 | uint32 | Sound level: 0 loud, 1 normal, 2 silent, 3 very loud (52 bytes) |

Flags: 0x02 world orientation, 0x04 always knock down, 0x08 knock down by formula, 0x10
ignore line of sight, 0x20 push source only, 0x40 ignore image-space swap, 0x80 chain,
0x100 no controller vibration. The install has all four sizes over 277 records.

## DEBR

Each `DATA` field is one model: a uint8 percentage, a zstring path, and a uint8 flag
(0x01 has collision). A `MODT` right after it holds that model's texture hashes.
