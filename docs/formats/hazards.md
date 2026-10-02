---
type: File Format
title: Hazard records
description: Skyrim SE HAZD hazard fields and the PHZD and PGRE placed hazards and projectiles.
tags: [format, plugin, magic]
---

# Hazard records

A hazard is a lasting area effect, such as a fire patch or a poison cloud. `HAZD` is the
base record. `PHZD` places a hazard in a cell, and `PGRE` places a projectile.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## HAZD

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `OBND` | 12 bytes | Object bounds |
| `FULL` | lstring | Name |
| `MODL`, `MODT` | model group | The hazard mesh |
| `MNAM` | FormID | `IMAD` image-space modifier |
| `DATA` | 40 bytes | See below |

`DATA` is always 40 bytes on the install (51 records).

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | Limit: how many may exist at once |
| 4 | float | Radius |
| 8 | float | Lifetime in seconds |
| 12 | float | Image-space radius |
| 16 | float | Target interval |
| 20 | uint32 | Flags: 0x01 affects player only, 0x02 inherit duration from spell, 0x04 align to impact normal, 0x08 inherit radius from spell, 0x10 drop to ground |
| 24 | FormID | `SPEL` |
| 28 | FormID | `LIGH` |
| 32 | FormID | `IPDS` |
| 36 | FormID | `SNDR` |

A null FormID reads as no link.

## PHZD and PGRE

Both use the placed-reference layout of [placed references](/formats/placed-references.md):
`NAME` base, `DATA` position and rotation, `XSCL`, `XESP`, `XOWN`, `XEZN`, `XLKR`, and
`VMAD`. `NAME` names a `HAZD` for `PHZD` and a `PROJ` for `PGRE`. The install holds 394
`PHZD` and 44 `PGRE` records; 369 `PHZD` carry an `XESP` enable parent.

## Links

The hazard store resolves the `DATA` spell, light, impact data set, and sound, and the
`MNAM` image-space modifier, relative to the plugin that holds the hazard. A link that
resolves to an identity no indexed record has is counted as dangling.

On the five masters none of the 51 `HAZD` records has a dangling link.
