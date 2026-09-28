---
type: File Format
title: Shout and equip records
description: SHOU, WOOP, LVSP, DUAL, and EQUP layouts, and how an equip slot turns into the
  hands an item fills.
tags: [format, esm, magic, shout, equipment, record]
---

# Shout and equip records (SHOU, WOOP, LVSP, DUAL, EQUP)

These five small records support shouts and equipment. Spells and effects are on the
[magic records](/formats/magic-records.md) page.

## SHOU and WOOP

Sources: UESP [SHOU](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SHOU) and
[WOOP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WOOP); xEdit `dev-4.1.6`
`wbRecord(SHOU, ...)` (line 7173) and `wbRecord(WOOP, ...)` (line 10639).

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `MDOB` | FormID | Menu display object |
| `DESC` | lstring | Description |
| `SNAM` | 12 bytes, repeats | One word of the shout |
| `ETYP` | FormID | Not read. No vanilla shout has it |

Each `SNAM` is a `WOOP` FormID, a `SPEL` FormID, and a float32 recovery time. Every vanilla
shout has exactly three. Racial and creature powers that are not real shouts have three
all-zero entries, not none. OpenSky keeps them as entries with no links.

OpenSky does not require three. UESP says an override with fewer entries takes the missing ones
from the record it overrides, and one with more corrupts memory in the original game.

Example: `FireBreathShout` (`Skyrim.esm` `0003F9EA`) has the words `WordYol`, `WordToor`, and
`WordShul`, the spells `VoiceFireBreath1` to `VoiceFireBreath3`, and recovery times of 30, 50,
and 100 seconds.

A `WOOP` is `EDID`, `FULL` (the word as written in the dragon alphabet font, for example `Y3`
for Yol), and `TNAM` (the word in the plugin's language). Every vanilla word has `TNAM`, but it
is often an empty string. That is data, not an error.

## LVSP

A leveled spell list. It uses the same layout as `LVLN` and `LVLI`: `EDID`, `OBND`, `LVLD`
(chance none), `LVLF` (flags), `LLCT` (entry count), and 12-byte `LVLO` entries. xEdit
`wbRecord(LVSP, ...)` (line 8058) uses the same `wbLeveledListEntry`. Only the allowed targets
differ: `SPEL` or another `LVSP`. The entry layout is on the [actors](/formats/actors.md) page.

## DUAL

The art a spell uses when cast with both hands. Only an `MGEF` points at it. Sources: UESP
[DUAL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DUAL); xEdit `wbRecord(DUAL, ...)`
(line 7543). Fields: `EDID`, `OBND`, and a 24-byte `DATA`:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | FormID | Projectile (`PROJ`) |
| `0x04` | FormID | Explosion (`EXPL`) |
| `0x08` | FormID | Effect shader (`EFSH`) |
| `0x0C` | FormID | Hit effect art (`ARTO`) |
| `0x10` | FormID | Impact data set (`IPDS`) |
| `0x14` | uint32 | Inherit scale: `0x01` hit art, `0x02` projectile, `0x04` explosion |

A `DATA` shorter than 24 bytes is counted, and the record keeps its identity.

## EQUP

Every `ETYP` link points at an `EQUP`. Sources: UESP
[EQUP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/EQUP); xEdit `wbRecord(EQUP, ...)`
(line 7192).

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `PNAM` | FormID list | Parent slots |
| `DATA` | uint32 Boolean | Use all parents |

`PNAM` is one field with a packed list, not one field per parent. If a record spreads its
parents over several `PNAM` fields, they are all added. A partial FormID at the end is dropped.

`Skyrim.esm` has seven:

| Editor ID | Parents | Use all parents |
| --- | --- | --- |
| `RightHand` | none | false |
| `LeftHand` | none | false |
| `EitherHand` | `LeftHand`, `RightHand` | false |
| `BothHands` | `LeftHand`, `RightHand` | true |
| `Shield` | `LeftHand` | true |
| `Voice` | none | false |
| `Potion` | none | false |

## From equip slot to hands

The `EQUP` tree has structure but no meaning. It says `BothHands` is "all of `LeftHand` and
`RightHand`", but not what `LeftHand` is. The original game names the leaves. OpenSky does the
same, by editor ID, because a mod's copy would have the same editor ID. Then it walks the
parents:

- No parents: a leaf. `RightHand` and `LeftHand` are their hand. Any other leaf (`Voice`,
  `Potion`, or a mod's own) fills no hand. That is right for a shout or a potion.
- Parents, with "use all parents" set: the union of the parents' hands. So `BothHands` fills
  both hands, and `Shield` (whose only parent is `LeftHand`) fills the left.
- Parents, without it: the item fills one of them. The game lets the player choose. OpenSky
  picks the right hand when it is an option, because the skeleton's `Weapon` node hangs from
  the right hand.
- A loop stops at depth 8. Vanilla chains are one step deep.

A link to no `EQUP` gives no answer, not an empty set. So a caller can tell a broken link from a
slot that fills no hand.

In vanilla, every weapon and spell with an `ETYP` resolves. A few weapons have no `ETYP`. They
use the right hand. See [inventory and equipment](/engine/inventory-equipment.md).
