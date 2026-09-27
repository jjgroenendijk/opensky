---
type: File Format
title: Item records (MISC, BOOK, ALCH, INGR, WEAP, AMMO, CONT, ARMO)
description: Layouts of carried items, their shared fields, effect lists, and container
  contents.
tags: [format, plugin, records, inventory, items]
---

# Item records

These records are things an actor can carry, plus container contents. The projectile an
arrow launches is on [projectiles](/formats/projectiles.md). Shared decode rules are on
[record decoders](/formats/records.md). The runtime is on
[inventory and equipment](/engine/inventory-equipment.md).

Sources: UESP "Skyrim Mod:Mod File Format" pages `/MISC`, `/BOOK`, `/ALCH`, `/INGR`,
`/WEAP`, `/AMMO`, `/CONT`, and `/ARMO`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), and xEdit `dev-4.1.6`
`wbDefinitionsTES5.pas` and `wbDefinitionsCommon.pas`. Line numbers below are in those
files.

## Shared fields

Every carried item repeats the same fields:

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `MODL` | zstring | model |
| `OBND` | 6 x int16 | bounds: minimum corner, then maximum corner (xEdit `wbOBND`, common line 8634) |
| `KSIZ` + `KWDA` | uint32 + FormID array | keywords |
| `ICON`, `MICO` | zstring | inventory icons |
| `YNAM`, `ZNAM` | FormID | pickup and drop sounds |

`DATA` is different for each type: 8 bytes on MISC, INGR, and ARMO (int32 value, float32
weight), 4 on ALCH, 10 on WEAP, 16 on BOOK, and 16 or 20 on AMMO.

## MISC

Gems, ingots, tools, gold, and clutter. Only the shared fields and the 8-byte `DATA`
(line 8303).

## BOOK

| field | type | meaning |
| --- | --- | --- |
| `DESC` | lstring | book text, from the `.dlstrings` table ([strings](/formats/strings.md)) |
| `CNAM` | lstring | inventory description |
| `DATA` | 16 bytes | see below |

`DATA` (line 4220): uint8 flags (`0x01` teaches skill, `0x02` cannot be taken, `0x04`
teaches spell), uint8 kind (0 book, 255 note; always 0 since SSE), 2 unused bytes, uint32
"teaches" word, uint32 value, float32 weight. The "teaches" word is an actor-value skill
index with flag `0x01`, a SPEL FormID with flag `0x04`, and unused otherwise. If a mod sets
both flags, OpenSky reads a spell.

## ALCH

Food, drink, potions, and poisons (line 4042). Here `DATA` is only a float32 weight. The
value is in `ENIT`, 20 bytes: int32 value, uint32 flags (`0x00001` no auto-calc, `0x00002`
food, `0x10000` medicine, `0x20000` poison), FormID addiction, float32 addiction chance,
FormID consume sound (`SNDR`).

## INGR

Alchemy ingredients (line 7909). The 8-byte `DATA`, and an 8-byte `ENIT`: int32 auto-calc
value (not the same as the value in `DATA`) and uint32 flags (`0x001` no auto-calc, `0x002`
food, `0x100` references persist).

## Effect lists

ALCH, INGR, SPEL, SCRL, and ENCH store effects as a run of fields, not a struct. `EFID`
names the MGEF, the next `EFIT` holds its numbers, and any `CTDA` after that is a condition
on that effect ([conditions](/formats/conditions.md)). Then the run repeats. xEdit: `wbEFID`
line 3832, `wbEFIT` 3834, `wbEffect` 4030.

| field | type | meaning |
| --- | --- | --- |
| `EFID` | FormID | the MGEF ([magic records](/formats/magic-records.md)) |
| `EFIT` | 12 bytes | float32 magnitude, uint32 area, uint32 duration |
| `CTDA` | 32 bytes | condition on this effect |

An `EFIT` without an `EFID` before it is dropped. An `EFID` without an `EFIT` still counts,
with magnitude 0.

## WEAP

| field | type | meaning |
| --- | --- | --- |
| `DATA` | 10 bytes | uint32 value, float32 weight, uint16 damage |
| `DNAM` | 100 bytes | animation type, speed, reach, flags, skill, stagger |
| `CRDT` | 16 or 24 bytes | critical hit data |
| `EITM` | FormID | enchantment (`ENCH`) |
| `EAMT` | uint16 | enchantment charge |
| `ETYP` | FormID | equip slot (`EQUP`, see [shouts and equip slots](/formats/shouts-equip-slots.md)) |
| `CNAM` | FormID | template, another WEAP |
| `INAM` | FormID | impact data set (`IPDS`) for a normal swing |
| `BIDS` | FormID | impact data set (`IPDS`) for a shield bash |

Record at line 10499, `DATA` 10530, `DNAM` 10535, `CRDT` 10604.

`DNAM` offsets: `0x00` uint8 animation type (0 other, 1 one-hand sword, up to 9 crossbow),
`0x04` float32 speed, `0x08` float32 reach, `0x0C` uint16 flags (`0x08` cannot drop, `0x20`
embedded, `0x80` not playable), `0x4C` int32 skill as an actor value (-1 for none), `0x60`
float32 stagger. The rest is padding, old Fallout fields, or rumble. Reach is a multiplier,
not a distance: UESP gives melee reach as `fCombatDistance * NPCScale * WeaponReach`
([melee combat](/engine/melee-combat.md)).

`CRDT` changed in SSE. The size picks the layout, not the form version, so older mod records
still read:

| bytes | layout |
| --- | --- |
| 16 | uint16 damage, 2 unused, float32 multiplier, uint8 on-death, 3 unused, FormID SPEL |
| 24 | the same, but 7 unused after on-death, SPEL at `0x10`, then 4 unused |

UESP calls `INAM` "Normal weapon swing impact set" and `BIDS` "Block bash impact data set".
A null link means the hit makes no impact sound. That is normal in vanilla.

## AMMO

`DATA` grew in SSE, so the size picks the layout (line 4087, `IsSSE` pair at 4101):

| offset | type | meaning |
| --- | --- | --- |
| 0x00 | FormID | projectile (`PROJ`, see [projectiles](/formats/projectiles.md)) |
| 0x04 | uint32 | flags: `0x01` ignores weapon resistance, `0x02` not playable, `0x04` not a bolt |
| 0x08 | float32 | damage |
| 0x0C | uint32 | value |
| 0x10 | float32 | weight; SSE only, the 16-byte form ends before it |

Vanilla SSE gives every arrow weight 0.1, but the game treats arrows as weightless.

## CONT contents

A container has the placeable fields ([world records](/formats/world-records.md)) plus its
contents:

| field | type | meaning |
| --- | --- | --- |
| `COCT` | uint32 | entry count; not trusted |
| `CNTO` | 8 bytes | FormID item, int32 count; repeated |
| `COED` | 12 bytes | owner data for the `CNTO` before it |
| `DATA` | uint8 + float32 | flags: `0x01` allow sounds, `0x02` respawns, `0x04` show owner |

xEdit: `wbCOED` line 2305, `wbCNTO` 2315, `wbCOCT` 2329, `wbRecord(CONT, ...)` 4505. A
`CNTO` item can be a carried item or an `LVLI`. The middle word of `COED` is a GLOB FormID
when the owner is an NPC_, and a faction rank when it is a FACT. The `DATA` float is
documented as a misplaced weight that is always 0.

## ARMO inventory fields

The appearance fields are on [armor records](/formats/armor.md). Inventory fields: the
8-byte `DATA`, keywords, `DNAM` (armor rating x 100, a uint32 of which only the low 16 bits
are used), and `EITM` (enchantment). ARMO has no `EAMT`: xEdit builds both records' link
from `wbEnchantment` and adds the charge only on WEAP. So enchanted armor has no charge.

## Vanilla items

In `Skyrim.esm`:

| measure | value |
| --- | --- |
| items | 6,930 (ARMO 2,762, WEAP 2,484, BOOK 821, ALCH 363, MISC 371, INGR 94, AMMO 35) |
| containers | 436 CONT with 9,597 `CNTO` entries |
| `CNTO` naming an item | 6,753; the rest are LVLI, KEYM, LIGH, SLGM, APPA, and SCRL |
| `CNTO` naming a type xEdit does not allow | 0 |
| `COCT` that disagree with `CNTO` | 0 |
| value / weight | 0 to 5,000 gold, 0.0 to 50.0 |

Every `CNTO` names an allowed type. That would not hold if item and count were in the other
order.

Examples: `IronSword` (WEAP `00012EB7`) has value 25, weight 9, damage 7, animation type
one-hand sword, speed 1, reach 1, critical damage 3. `SkillSmithing1` (BOOK `0001AFCE`)
teaches skill 10. `Wheat` (INGR `0004B0BA`) has 4 effects and auto-calc value 47.
`IronArrow` (AMMO `0001397D`) has damage 8 and projectile `0003BE11`. `BarrelFood01` (CONT
`00000845`) has 1 entry and flags `0x2`.
