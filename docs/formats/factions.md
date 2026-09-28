---
type: File Format
title: Factions (FACT, NPC_ SNAM)
description: FACT record layout - relations, crime values, ranks, and the vendor block - plus
  NPC_ faction membership and membership at runtime.
tags: [format, plugin, records, factions, crime, vendor, actors]
---

# Factions (FACT, NPC_ SNAM)

A `FACT` record holds four things under one editor ID:

- how its members treat other factions,
- how it reacts to crime in its area,
- the names of its ranks,
- for a merchant faction: what its shop sells, and when.

An actor joins a faction through the `NPC_ SNAM` field, which gives the faction and a rank.
See [combat](/engine/combat.md) for hostility and [crime](/engine/crime.md) for bounties.

References: UESP [FACT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FACT) and
[NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas` (`wbRecord(FACT, ...)`) and `Core/wbDefinitionsCommon.pas`
(`wbFaction`, `wbFactionRelations`).

## Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `XNAM` | 12 bytes, repeats | Relation to another faction |
| `DATA` | uint32 | Flags |
| `JAIL` | `REFR` FormID | Jail marker outside |
| `WAIT` | `REFR` FormID | Follower wait marker |
| `STOL` | `REFR` FormID | Evidence chest for stolen goods |
| `PLCN` | `REFR` FormID | Chest for the arrested player's items |
| `CRGR` | `FLST` FormID | Shared list of crime factions |
| `JOUT` | `OTFT` FormID | Jail outfit |
| `CRVA` | 12, 16, or 20 bytes | Crime values |
| `RNAM` | uint32 | Rank index. Starts a rank group |
| `MNAM` / `FNAM` | lstring | Male and female rank title |
| `VEND` | `FLST` FormID | What the vendor buys and sells |
| `VENC` | `REFR` FormID | Merchant chest |
| `VENV` | 12 bytes | Vendor values |
| `PLVD` | 12 bytes | Where the vendor trades |
| `CITC` / `CTDA` | conditions | When the vendor trades |

A null FormID means the link is not set.

## XNAM: relations

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | FormID | The other faction: a `FACT` or a `RACE` |
| 4 | int32 | Disposition modifier |
| 8 | uint32 | Combat reaction: 0 neutral, 1 enemy, 2 ally, 3 friend |

xEdit allows a `RACE` in the link. So a link that is not a faction is normal. The
disposition modifier does nothing in Skyrim. xEdit notes that the Creation Kit no longer
edits it, and UESP sees it set on only one vanilla record.

## DATA: flags

Bit names from xEdit, which says which crime each "ignore" bit covers.

| Mask | Meaning |
| --- | --- |
| `0x00000001` | Hidden from NPC |
| `0x00000002` | Special combat |
| `0x00000040` | Track crime |
| `0x00000080` | Ignore murder |
| `0x00000100` | Ignore assault |
| `0x00000200` | Ignore stealing |
| `0x00000400` | Ignore trespass |
| `0x00000800` | Do not report crimes against members |
| `0x00001000` | Crime gold, use defaults |
| `0x00002000` | Ignore pickpocket |
| `0x00004000` | Vendor |
| `0x00008000` | Can be owner |
| `0x00010000` | Ignore werewolf |

## CRVA: crime values

The field grew over record versions, so it is 12, 16, or 20 bytes.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint8 | Arrest |
| 1 | uint8 | Attack on sight |
| 2 | uint16 | Murder |
| 4 | uint16 | Assault |
| 6 | uint16 | Trespass |
| 8 | uint16 | Pickpocket |
| 10 | uint16 | Unused. Sometimes not 0. Never a gold value |
| 12 | float32 | Steal multiplier (16 bytes or more) |
| 16 | uint16 | Escape (20 bytes) |
| 18 | uint16 | Werewolf (20 bytes) |

OpenSky reads only the fields the data reaches. A missing field stays missing, not 0, so
each user decides what it means. For a missing steal multiplier, crime uses 1, so a 12-byte
`CRVA` still charges the full item value.

UESP says `CRVA` is normally required, but `MS08AlikrFaction` has none. So a missing `CRVA`
is not an error. Such a faction charges no gold, but its crimes are still counted.

These values are where crime gold comes from. It does not come from game settings: the
install has only two `iCrimeGold*` settings, and neither prices murder, assault, trespass,
or theft.

Example, `CrimeFactionWhiterun`: murder 1000, assault 40, trespass 5, pickpocket 25, steal
multiplier 0.5, escape 100, werewolf 1000.

## Ranks

`RNAM` starts a rank group with its index. The `MNAM` and `FNAM` after it are the male and
female titles. Either may be missing, and then the other gender's title is used. On a
localized plugin, the titles are string IDs.

A title with no open rank group is counted and ignored, never given to the wrong rank.
Vanilla has none. xEdit also lists an unused `INAM` insignia; no vanilla record has one.

## Vendor block

`VENV` is 12 bytes. The sources disagree on offsets 4 to 7:

| Offset | xEdit | UESP |
| --- | --- | --- |
| 4 | uint16 radius | uint32 radius |
| 6 | 2 unknown bytes | (part of the radius) |
| 8 | uint8 only buys stolen items | same |
| 9 | uint8 not sell/buy | same |
| 10 | 2 unknown bytes | uint16 unused |

OpenSky follows xEdit and counts records where the word at offset 6 is not 0. In the whole
vanilla load order there are none, so both readings agree. The count stays so that a plugin
that disagrees shows up, instead of giving a radius in the tens of thousands.

`PLVD` is a location type, one value whose meaning depends on the type, and a signed
radius. The type list is shared with package locations (see [packages](/formats/packages.md)).
OpenSky keeps the middle value raw.

The `CITC`/`CTDA` conditions at the end (see [conditions](/formats/conditions.md)) must be
true for the vendor to trade.

## NPC_ SNAM: membership

8 bytes, one per faction:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `FACT` FormID | The faction |
| 4 | int8 | Rank |
| 5 | 3 bytes | Unused |

The rank is signed. Vanilla uses negative ranks for members without a rank title.

The list comes from a template when the `ACBS` flag "use factions" (`0x0004`) is set and the
record has a `TPLT`. A record without the flag keeps its own list, even when it is empty.
See [actors](/formats/actors.md).

## Runtime membership

`SNAM` gives the factions an actor starts in. Scripts and quests then add, remove, and
promote. OpenSky stores the current memberships per actor and saves them in the `FCTN`
chunk of the [OpenSky save](/formats/opensky-save-actor-chunks.md).

Design choices:

- An actor's `SNAM` list is copied in the first time something asks about that actor, not
  when the cell loads. A street of people the player never meets then writes nothing. A
  membership that is already stored wins over the copied one, so an earlier promotion is
  not undone.
- Joining a faction that the load order does not have is refused. Its key could never be
  read back.
- A stored membership whose faction disappears (a plugin was removed) is kept but not
  shown. Removing a plugin must not destroy progress.
- All `XNAM` relations of the load order are put into one table keyed by the two factions.
  Hostility asks about every pair of memberships of two actors, several times per frame,
  and some factions have up to 85 relations.

## Vanilla counts

On the five masters plus the Creation Club plugins of a stock install: 1,417 `FACT`
records, all decode. 74 track crime and 286 are vendors. 5,118 `NPC_` bases have 13,157
memberships after templates; 2,921 bases get them from a template. `GuardFactionWhiterun`
has 61 members. There are 1,185 `XNAM` relations, and all reactions are 0 to 3.
