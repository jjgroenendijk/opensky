---
type: File Format
title: Projectiles (PROJ)
description: PROJ DATA layout — flight, gravity, sounds, and optional trailing links.
tags: [format, plugin, records, projectile, archery]
---

# Projectiles

A PROJ is what an AMMO or a spell launches. Everything the flight needs is in one `DATA`
struct. How arrows fly is on [archery](/engine/archery.md). The AMMO that names a projectile
is on [item records](/formats/item-records.md).

Sources: UESP [`/PROJ`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PROJ) and xEdit
`dev-4.1.6` `wbDefinitionsTES5.pas` `wbRecord(PROJ, ...)` at line 5449, `DATA` at 5454.

## DATA

UESP and xEdit agree on every member. Vanilla writes 92 bytes:

| offset | type | meaning |
| --- | --- | --- |
| 0x00 | uint16 | flags: `0x01` hitscan, `0x02` explosion, `0x04` alternate trigger, `0x08` muzzle flash, `0x20` can be disabled, `0x40` can be picked up, `0x80` supersonic, `0x100` pins limbs, `0x200` passes through small transparent, `0x400` no combat aim correction, `0x800` rotation |
| 0x02 | uint16 | kind: `0x01` missile, `0x02` lobber, `0x04` beam, `0x08` flame, `0x10` cone, `0x20` barrier, `0x40` arrow |
| 0x04 | float32 | gravity, a multiplier on world gravity |
| 0x08 | float32 | speed, units per second |
| 0x0C | float32 | range |
| 0x10, 0x14 | FormID | light, muzzle-flash light (`LIGH`) |
| 0x18-0x20 | float32 | tracer chance, explosion proximity, explosion timer |
| 0x24 | FormID | explosion (`EXPL`) |
| 0x28 | FormID | sound in flight (`SNDR`) |
| 0x2C, 0x30 | float32 | muzzle-flash duration, fade duration |
| 0x34 | float32 | impact force |
| 0x38 | FormID | countdown sound (`SNDR`) |
| 0x3C | FormID | disable sound (`SNDR`) |
| 0x40 | FormID | default weapon (`WEAP`) |
| 0x44 | float32 | cone spread |
| 0x48 | float32 | collision radius |
| 0x4C | float32 | lifetime, seconds |
| 0x50 | float32 | relaunch interval |
| 0x54, 0x58 | FormID | decal data (`TXST`), collision layer (`COLL`); optional |

xEdit marks `DATA` "optional from element 22", the decal link, so 84 bytes is also valid.
OpenSky accepts any `DATA` of 16 bytes or more, because flags through range hold the whole
flight model, and a mod may write a short struct.
UESP calls 0x3C "uint32 always 0"; xEdit calls it `Sound - Disable`. The offset is the same.
"Always 0" describes vanilla data, not the field, so OpenSky follows xEdit. `VNAM` is the
sound level.

No source gives a unit for gravity. On the 20 arrow projectiles in `Skyrim.esm` it is at
most 1 while speed reaches the thousands, so it is a scale factor
([archery](/engine/archery.md)).
