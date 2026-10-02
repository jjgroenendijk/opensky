---
type: File Format
title: Shouts and equip slots
description: SHOU, WOOP, LVSP, DUAL, and EQUP layouts, and how an equip slot maps to hands.
tags: [format, esm, magic, record, equipment]
---

# Shouts and equip slots

This page covers five small records near the magic records: SHOU (shout), WOOP (word of
power), LVSP (leveled spell), DUAL (dual-cast data), and EQUP (equip type). EQUP answers
"which hands does this item fill" for [equipment](/engine/inventory-equipment.md). MGEF,
SPEL, and SCRL are on [magic records](/formats/magic-records.md); ENCH is on
[enchantments](/formats/enchantments.md).

Sources: the UESP pages
[`SHOU`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SHOU),
[`WOOP`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WOOP),
[`DUAL`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DUAL), and
[`EQUP`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/EQUP). Field order and link
types come from xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`: `wbRecord(SHOU, 'Shout', ...)`
(line 7173), `wbRecord(EQUP, 'Equip Type', ...)` (line 7192), `wbRecord(DUAL, 'Dual Cast
Data', ...)` (line 7543), `wbRecord(LVSP, 'Leveled Spell', ...)` (line 8058), and
`wbRecord(WOOP, 'Word of Power', ...)` (line 10639).

All integers and floats are little-endian. A zero FormID means "no link".

## SHOU

| field | type | meaning |
|---|---|---|
| `EDID` | zstring | editor ID |
| `FULL` | lstring | display name |
| `MDOB` | FormID | menu display object |
| `DESC` | lstring | description |
| `SNAM` | repeated 12-byte struct | one entry per word |
| `ETYP` | FormID | equip slot; no vanilla master writes it on SHOU |

Each `SNAM` is 12 bytes: a `WOOP` FormID, a `SPEL` FormID, and a float32 recovery time in
seconds. Every vanilla shout has exactly three entries. Racial and creature powers are
stored as shouts too. They also have three entries, but all bytes are zero.

UESP notes two engine effects of a different count. An override with fewer than three
entries takes the missing ones from the record it overrides. An override with more than
three corrupts memory in the original engine. OpenSky does not force the count to three.

Example: `FireBreathShout` (Skyrim.esm `0003F9EA`) has the words `WordYol`, `WordToor`, and
`WordShul`, the spells `VoiceFireBreath1` to `VoiceFireBreath3`, and recovery times of 30,
50, and 100 seconds.

## WOOP

| field | type | meaning |
|---|---|---|
| `EDID` | zstring | editor ID |
| `FULL` | lstring | the word in the dragon alphabet's Latin spelling, for example `Y3` for Yol |
| `TNAM` | lstring | the word in the plugin's language |

Every vanilla word has `TNAM`, but it is often an empty string. That is valid data.

## LVSP

LVSP uses the same leveled-list layout as LVLN and LVLI. xEdit reuses the same
`wbLeveledListEntry`. Only the allowed targets change: an entry names a `SPEL` or another
`LVSP`. The fields are `EDID`, `OBND`, `LVLD` (chance none), `LVLF` (flags), `LLCT` (entry
count), and a run of 12-byte `LVLO` entries. The entry layout is on
[actor records](/formats/actors.md).

## DUAL

DUAL is the art that a spell uses when it is dual-cast. Only an MGEF links to it (`DATA`
offset `0x6C`). The fields are `EDID`, `OBND`, and a 24-byte `DATA`:

| offset | type | meaning |
|---:|---|---|
| `0x00` | FormID | projectile (`PROJ`) |
| `0x04` | FormID | explosion (`EXPL`) |
| `0x08` | FormID | effect shader (`EFSH`) |
| `0x0C` | FormID | hit effect art ([`ARTO`](/formats/art-objects.md)) |
| `0x10` | FormID | impact data set (`IPDS`) |
| `0x14` | uint32 | inherit-scale flags: `0x01` hit effect art, `0x02` projectile, `0x04` explosion |

## EQUP

Every `ETYP` link points at an EQUP record.

| field | type | meaning |
|---|---|---|
| `EDID` | zstring | editor ID |
| `PNAM` | packed FormID array | parent slots that this slot is made of |
| `DATA` | uint32 boolean | "use all parents" |

`PNAM` is one subrecord that holds all parents. OpenSky still accepts several `PNAM`
subrecords and joins them. A trailing partial FormID is dropped.

Skyrim.esm has seven EQUP records:

| editor ID | parents | use all parents |
|---|---|---|
| `RightHand` | none | false |
| `LeftHand` | none | false |
| `EitherHand` | `LeftHand`, `RightHand` | false |
| `BothHands` | `LeftHand`, `RightHand` | true |
| `Shield` | `LeftHand` | true |
| `Voice` | none | false |
| `Potion` | none | false |

## Equip slot to hands

The EQUP graph gives structure but not meaning. It says `BothHands` is all of `LeftHand` and
`RightHand`, but not what `LeftHand` is. So OpenSky names the leaf slots by editor ID, which
a mod's copy of the slot also carries. The walk over parents works like this:

- A slot with no parents is a leaf. `RightHand` and `LeftHand` fill their hand. Any other
  leaf (`Voice`, `Potion`, or a slot a mod adds) fills no hand. This is correct for shouts
  and potions.
- A slot with "use all parents" set fills the union of its parents' hands. So `BothHands`
  fills both hands, and `Shield` fills the left hand.
- A slot without that flag fills one of its parents. In the game the player chooses.
  OpenSky picks the right hand when it is an option, because the skeleton's `Weapon` attach
  node is on the right hand.
- The walk stops at depth 8, so a loop that a mod creates ends. Vanilla chains are one link
  deep.

A link that names no EQUP gives "unknown", not "no hands". This keeps a broken link apart
from a slot that takes no hand.

On the vanilla install, 3,354 of 3,359 weapons name a slot, and every one resolves. The other
5 weapons have no `ETYP` and use the right hand by default. All 1,560 spells name a slot that
resolves.

## Vanilla counts

Measured on this machine's active load order: 117 SHOU, 107 WOOP, 33 LVSP, 2 DUAL, and 7 EQUP
records. There are 351 `SNAM` entries in total. Every DUAL `DATA` is 24 bytes.
