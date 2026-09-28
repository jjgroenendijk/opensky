---
type: File Format
title: Item records
description: The shared item fields, MISC, BOOK, ALCH, INGR and their effect lists, WEAP, AMMO,
  PROJ, CONT contents, and the ARMO item fields.
tags: [format, esm, records, inventory, items, weapon, projectile]
---

# Item records

These records are the things an actor can carry, and the containers that hold them. The shared
decode rules are on the [record decoders](/formats/records.md) page. The runtime is on the
[inventory and equipment](/engine/inventory-equipment.md) page.

Sources: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format) pages
`MISC`, `BOOK`, `ALCH`, `INGR`, `WEAP`, `AMMO`, `PROJ`, `CONT`, and `ARMO`; xEdit `dev-4.1.6`
`Core/wbDefinitionsTES5.pas` and `Core/wbDefinitionsCommon.pas`.

## Shared fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `MODL` | zstring | Model path |
| `OBND` | int16 x 6 | Bounds: minimum corner, then maximum corner (xEdit `wbOBND`) |
| `KSIZ`, `KWDA` | uint32, FormID list | Keyword count and keywords |
| `ICON`, `MICO` | zstring | Inventory icons |
| `YNAM`, `ZNAM` | FormID | Pickup and drop sounds |

`MISC` (gems, ingots, tools, gold, clutter) has only these and `DATA`. Most items have an 8-byte
`DATA`: int32 gold value, float32 weight. But the size of `DATA`
depends on the record: 8 bytes on `MISC`, `INGR`, and `ARMO`, 4 on `ALCH`, 10 on `WEAP`, 16 on
`BOOK`, and 16 or 20 on `AMMO`.

## BOOK

| Field | Type | Meaning |
| --- | --- | --- |
| `DESC` | lstring | The book's text, from `.dlstrings` |
| `CNAM` | lstring | Short description in the inventory |
| `DATA` | 16 bytes | Below |

`DATA`: uint8 flags (`0x01` teaches a skill, `0x02` cannot be taken, `0x04` teaches a spell),
uint8 kind (0 book, 255 note; always 0 in SSE), 2 unused bytes, a uint32 "teaches" value, uint32
gold value, float32 weight.

The "teaches" value depends on the flags. With `0x01` it is an actor value index for a skill.
With `0x04` it is a `SPEL` FormID. If a mod sets both, the spell wins.

## ALCH

Food, drinks, potions, and poisons. Here `DATA` is only a float32 weight. The gold value is in
`ENIT`.

`ENIT` (20 bytes): int32 value, uint32 flags (`0x00001` no auto-calc, `0x00002` food, `0x10000`
medicine, `0x20000` poison), FormID addiction, float32 addiction chance, FormID use sound
(`SNDR`).

## INGR

Alchemy ingredients. `DATA` is the normal 8 bytes. `ENIT` is 8 bytes: int32 auto-calc value
(not the gold value) and uint32 flags (`0x001` no auto-calc, `0x002` food, `0x100` references
persist).

## Effect lists

`ALCH`, `INGR`, `SPEL`, `SCRL`, and `ENCH` store effects as a run of fields, not a struct:

| Field | Type | Meaning |
| --- | --- | --- |
| `EFID` | FormID | The magic effect (`MGEF`) |
| `EFIT` | 12 bytes | float32 magnitude, uint32 area, uint32 duration |
| `CTDA` | 32 bytes | Conditions on this one effect |

The run repeats. Conditions use the shared [conditions](/formats/conditions.md) decoder. An
`EFIT` with no `EFID` before it is dropped. An `EFID` with no `EFIT` still gives an effect, with
magnitude 0. The effect link is the part that matters most. See
[magic records](/formats/magic-records.md).

## WEAP

| Field | Type | Meaning |
| --- | --- | --- |
| `DATA` | 10 bytes | uint32 value, float32 weight, uint16 damage |
| `DNAM` | 100 bytes | Below |
| `CRDT` | 16 or 24 bytes | Critical hit data. Below |
| `EITM` | FormID | Enchantment (`ENCH`) |
| `EAMT` | uint16 | Enchantment charge |
| `ETYP` | FormID | Equip slot (`EQUP`) |
| `CNAM` | FormID | Template: another `WEAP` |
| `INAM` | FormID | Impact data set for a normal swing |
| `BIDS` | FormID | Impact data set for a block bash |

`DNAM` offsets that OpenSky reads:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint8 | Animation type: 0 other, 1 one-hand sword, up to 9 crossbow |
| 0x04 | float32 | Speed |
| 0x08 | float32 | Reach |
| 0x0C | uint16 | Flags: `0x08` cannot drop, `0x20` embedded, `0x80` not playable |
| 0x4C | int32 | Skill, as an actor value. -1 is none |
| 0x60 | float32 | Stagger |

Reach is a multiplier, not a distance. UESP gives melee reach as
`fCombatDistance * NPCScale * WeaponReach` (see [melee combat](/engine/melee-combat.md)).

`INAM` and `BIDS` choose the hit sound. UESP names `INAM` "Normal weapon swing impact set" and
`BIDS` "Block bash impact data set". A zero link means a silent hit, which is normal in vanilla.

`CRDT` changed between Skyrim and SSE. The field size picks the layout, not the form version, so
older mods still work:

| Size | Layout |
| --- | --- |
| 16 | uint16 damage, 2 unused, float32 multiplier, uint8 on death, 3 unused, FormID spell |
| 24 | The same, but 7 unused after on death, the spell at 0x10, then 4 unused |

Any other size gives no critical data.

## AMMO

`DATA` also grew in SSE, and the size picks the layout:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | FormID | Projectile (`PROJ`) |
| 0x04 | uint32 | Flags: `0x01` ignores weapon resistance, `0x02` not playable, `0x04` not a bolt |
| 0x08 | float32 | Damage |
| 0x0C | uint32 | Gold value |
| 0x10 | float32 | Weight. SSE only |

An older 16-byte `DATA` gives weight 0. The game treats arrows as weightless anyway.

## PROJ

Everything the flight needs is in `DATA`. UESP and xEdit agree on every member. Vanilla writes
92 bytes.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint16 | Flags: `0x01` hitscan, `0x02` explosion, `0x04` alternate trigger, `0x08` muzzle flash, `0x20` can be disabled, `0x40` can be picked up, `0x80` supersonic, `0x100` pins limbs, `0x200` passes small transparent, `0x400` no aim correction, `0x800` rotation |
| 0x02 | uint16 | Kind: `0x01` missile, `0x02` lobber, `0x04` beam, `0x08` flame, `0x10` cone, `0x20` barrier, `0x40` arrow |
| 0x04 | float32 | Gravity: a multiplier on world gravity |
| 0x08 | float32 | Speed, units per second |
| 0x0C | float32 | Range |
| 0x10 | FormID x 2 | Light, muzzle flash light. Not read |
| 0x18 | float32 x 3 | Tracer chance, explosion proximity, explosion timer. Not read |
| 0x24 | FormID | Explosion (`EXPL`) |
| 0x28 | FormID | Sound in flight (`SNDR`) |
| 0x2C | float32 x 2 | Muzzle flash duration, fade duration. Not read |
| 0x34 | float32 | Impact force |
| 0x38 | FormID | Countdown sound. Not read |
| 0x3C | FormID | Disable sound (`SNDR`) |
| 0x40 | FormID | Default weapon. Not read |
| 0x44 | float32 | Cone spread. Not read |
| 0x48 | float32 | Collision radius |
| 0x4C | float32 | Lifetime, seconds |
| 0x50 | float32 | Relaunch interval. Not read |
| 0x54 | FormID | Decal data (`TXST`). Optional |
| 0x58 | FormID | Collision layer (`COLL`). Optional |

xEdit marks `DATA` "optional from element 22", the decal link. So 84 bytes is as valid as 92.
OpenSky reads what is there, from 16 bytes up.

UESP calls 0x3C "uint32 always 0". xEdit names it `Sound - Disable`, an `SNDR` link. The offsets
agree. OpenSky uses the xEdit name, because "always 0" describes vanilla data, not the field.

Gravity has no documented unit. In vanilla arrows it is at most 1, while speed is in the
thousands. So it is a scale, not an acceleration. See [archery](/engine/archery.md).

## CONT contents

The container's model and sounds are on the [world records](/formats/world-records.md) page.
Its contents are a run of fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `COCT` | uint32 | Entry count. Only a hint |
| `CNTO` | 8 bytes, repeats | FormID item, int32 count |
| `COED` | 12 bytes | Owner data for the `CNTO` just before it |
| `DATA` | uint8, then more | Flags: `0x01` allow sounds, `0x02` respawns, `0x04` show owner |

An item can be a carried item or an `LVLI`, which the runtime expands. The middle word of `COED`
is a `GLOB` when the owner is an `NPC_`, and a faction rank when it is a `FACT`. The decoder
cannot tell which, so it keeps the word raw. A `COED` with no `CNTO` before it is dropped. UESP
says the float after the flags is a misaligned weight that is always 0. It is not read.

In vanilla, every `CNTO` names a record type that xEdit allows in that slot. That would not hold
if item and count were read in the wrong order.

## ARMO item fields

The look of armor is on the [armor records](/formats/armor.md) page. The item fields are the
shared ones, the 8-byte `DATA`, and:

- `DNAM`: armor rating times 100. It is a uint32, but only the low 16 bits are used.
- `EITM`: the enchantment. Armor has no `EAMT`. xEdit builds both records' link from
  `wbEnchantment`, and only `WEAP` asks for the charge. So enchanted armor has no charge.
