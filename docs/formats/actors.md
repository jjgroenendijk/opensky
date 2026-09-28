---
type: File Format
title: Actor records
description: ACHR, NPC_, LVLN, LVLI, and OTFT layouts, and how the NPC_ template chain decides
  which record supplies each field.
tags: [format, esm, actors, achr, npc, leveled, template, outfit]
---

# Actor records (ACHR, NPC_, LVLN, LVLI, OTFT)

- `ACHR` places an actor in a cell.
- `NPC_` is the actor base: appearance, stats, AI data, and links.
- `LVLN` and `LVLI` are leveled lists of actors and items.
- `OTFT` is an outfit: a list of armor and leveled items.

Related pages: [race and class records](/formats/race-and-class.md),
[armor records](/formats/armor.md), [actor appearance](/engine/actor-appearance.md) (how these
records become a drawn actor), and [actor values](/engine/actor-values.md) (what the stats
feed). The container is on the [ESM](/formats/esm.md) page.

Sources: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format) pages
`ACHR`, `NPC_`, `LVLN`, `LVLI`, and `OTFT`; xEdit `dev-4.1.6` `wbDefinitionsTES5.pas` (template
flags) and `wbDefinitionsCommon.pas` (`wbLeveledListEntry`); the Creation Kit wiki pages
"Template Data" and [AI Data Tab](https://ck.uesp.net/wiki/AI_Data_Tab).

## ACHR

A placed actor. It has the same shape as `REFR` and sits in the same cell child groups. A
worldspace-persistent `ACHR` is stored under the persistent cell at (0, 0). Its position decides
which streamed cell owns it (see [cell scene](/engine/cell-scene.md)).

| Field | Type | Meaning |
| --- | --- | --- |
| `NAME` | FormID | The `NPC_` base. Required |
| `DATA` | float32 x 6 | Position, then rotation in radians. Required |
| `XSCL` | float32 | Scale. Absent means 1 |
| `VMAD` | varies | Script data (see [VMAD](/formats/vmad.md)) |

Record header flag `0x800` means "initially disabled": the actor exists but is hidden until a
quest or script enables it.

## NPC_ fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `ACBS` | 24 bytes | Flags, template flags, and stat inputs. Required |
| `CNAM` | FormID | Class (`CLAS`) |
| `DNAM` | 52 bytes | Skills, and the editor's own health, magicka, and stamina |
| `TPLT` | FormID | Template: an `NPC_` or `LVLN`. Absent means no chain |
| `RNAM` | FormID | Race. Required |
| `VTCK` | FormID | Voice type (`VTYP`) |
| `WNAM` | FormID | Skin armor. Absent means the race's skin |
| `PNAM` | FormID, repeats | Head parts (`HDPT`) |
| `DOFT` | FormID | Default outfit (`OTFT`) |
| `PKID` | FormID, repeats | AI packages, in order |
| `SNAM` | 8 bytes, repeats | Faction membership (see [factions](/formats/factions.md)) |
| `CRIF` | FormID | Crime faction: the faction the actor reports crimes to |
| `AIDT` | 20 bytes | AI data |
| `VMAD` | varies | Script data |

## ACBS (24 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | uint32 | Flags |
| `0x04` | int16 | Magicka offset |
| `0x06` | int16 | Stamina offset |
| `0x08` | uint16 | Level, or a level multiplier times 1000 |
| `0x0A` | uint16 | Minimum calculated level |
| `0x0C` | uint16 | Maximum calculated level |
| `0x0E` | uint16 | Speed multiplier (actor value 30) |
| `0x10` | uint16 | Base disposition. Not read |
| `0x12` | uint16 | Template flags |
| `0x14` | int16 | Health offset |
| `0x16` | uint16 | Bleedout override. Not read |

Flags: `0x01` female, `0x10` auto-calculated stats, `0x20` unique, `0x80` level is a multiple
of the player's level. An `ACBS` of 20 bytes is accepted. The health offset is then 0.

Template flags: `0x0001` traits, `0x0002` stats, `0x0004` factions, `0x0008` spell list,
`0x0010` AI data, `0x0020` AI packages, `0x0040` model and animation, `0x0080` base data,
`0x0100` inventory, `0x0200` script, `0x0400` default package list, `0x0800` attack data,
`0x1000` keywords. For `0x0040`, UESP writes "unused?", xEdit names it, and the Creation Kit
leaves it out. Do not rely on it.

## DNAM (52 bytes)

18 base skill bytes, 18 skill modifier bytes, then three int16 values at `0x24`, `0x26`, and
`0x28`: health, magicka, and stamina. UESP calls them "calculated health (if auto-calc stats is
on, otherwise seems to be random)". They are the editor's own answer. OpenSky never uses them
as input. It uses them only to check its own stat math. They are signed: a creature with a
negative magicka offset stores a negative sum.

## AIDT (20 bytes)

UESP and xEdit `wbAIDT` agree on the layout. The value names come from the Creation Kit.

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | uint8 | Aggression: 0 unaggressive, 1 aggressive, 2 very aggressive, 3 frenzied |
| `0x01` | uint8 | Confidence: 0 cowardly to 4 foolhardy |
| `0x02` | uint8 | Energy: how often the actor moves while sandboxing, 0 to 100 |
| `0x03` | uint8 | Morality: 0 any crime to 3 no crime |
| `0x04` | uint8 | Mood. The wiki says "Not used" |
| `0x05` | uint8 | Assistance: 0 helps nobody, 1 helps allies, 2 helps friends and allies |
| `0x06` | uint8 | Bit 0: uses aggro radius behavior |
| `0x07` | uint8 | xEdit "Unused". UESP sees junk |
| `0x08` | uint32 | Warn distance |
| `0x0C` | uint32 | Warn or attack distance |
| `0x10` | uint32 | Attack distance |

A field shorter than 8 bytes gives no AI data. One shorter than 20 bytes keeps the first 8
bytes and leaves the distances empty. A value outside a named range is kept raw.

An actor with no readable `AIDT` is unaggressive. OpenSky does not invent a will to attack for
a record that says nothing about it. See [combat](/engine/combat.md).

## LVLN and LVLI

Leveled actor, item, and spell lists share one layout. `LVSP` is on the
[shout and equip records](/formats/shout-records.md) page.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `LVLD` | uint8 | Chance none. Always 0 for `LVLN` |
| `LVLF` | uint8 | Flags: `0x01` all levels, `0x02` each count, `0x04` use all |
| `LVLO` | 12 bytes, repeats | One entry |

With "use all", the list is a bundle: every entry applies at once. Example:
`ArmorStormcloakSet` is boots, cuirass, gauntlets, and a helmet list. Without it, the list is a
choice of one entry.

UESP gives `LVLO` as uint32 level, FormID, uint32 count. xEdit reads uint16 level, 2 bytes of
padding, FormID, and accepts an 8-byte form with count 1. The two agree on normal values.
OpenSky reads the xEdit form. `COED` (owner data after an entry) is not read.

## OTFT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `INAM` | FormID list | Packed. Size / 4 entries |

Entries mix `ARMO` and `LVLI`. Guard outfits nest `LVLI` bundles. A size that is not a
multiple of 4 is malformed.

## Template chain

`TPLT` and the template flags decide which record supplies each group of fields. Sources: UESP
`NPC_` notes and the Creation Kit "Template Data" page.

| Flag | Fields |
| --- | --- |
| Traits | Race, gender, skin, height, weight, voice, head parts, death item |
| Inventory | Outfit (`DOFT`) and carried items |
| Base data | Name and the essential, protected, and respawn flags |
| Stats | Level, auto-calc, the three offsets, speed, bleedout, class |
| Factions | `SNAM` run and `CRIF` |
| AI data | `AIDT` |
| AI packages | The whole ordered `PKID` list |

Two groupings are OpenSky's own inference. `WNAM` is on the Creation Kit Traits tab, so it
follows the traits flag, but no source says so. `CRIF` follows the factions flag, because
both answer one question: is the actor a guard, and for whom? In vanilla, every guard names a
crime faction it is also a member of.

The rules:

- Follow `TPLT` always. The flags choose fields, not links.
- A record passes a field up the chain only if it has a `TPLT` and the field's flag is set. A
  flag without a `TPLT` does nothing. The last record in the chain always answers.
- An `LVLN` link picks the entry with the highest level, and the first one on a tie. It does
  not roll dice against the player's level.
- Every resolved field remembers which `NPC_` supplied it.
- A loop, a missing target, or an empty list is an error.

## Two races

The race can resolve twice. The traits race decides the skeleton and body. The stats race is
the `RNAM` of the record that supplied the stats, and the starting attributes come from it.
Neither UESP nor the Creation Kit says which race the stats use. The vanilla data answers it.
Compared with the editor's own `DNAM` values, the stats race gives fewer than half the
mismatches of the traits race. The remaining mismatches all come from one stale template. The
records that change are skeletons, draugr, and creatures, whose traits and stats come from
different records.
