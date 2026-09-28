---
type: File Format
title: Factions (FACT, NPC_ SNAM)
description: FACT layout (relations, flags, crime values, ranks, vendor block), NPC_ faction
  membership, and faction membership at runtime.
tags: [format, plugin, records, factions, crime, vendor, actors]
---

# Factions (FACT, NPC_ SNAM)

A `FACT` record bundles four things under one editor ID:

- how its members treat other factions,
- how it reacts to crime in its area,
- the names of its ranks,
- for a merchant faction, what its shop sells and when.

An actor joins a faction through `NPC_ SNAM`, which holds the faction and the rank.

Hostility is worked out in [combat](/engine/combat.md). Flags and crime values are used by
[crime](/engine/crime.md). The vendor block is used by [barter](/engine/barter.md).

Sources: UESP [FACT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FACT) and
[NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas` `wbRecord(FACT, ...)`, and `Core/wbDefinitionsCommon.pas`
`wbFaction` and `wbFactionRelations`.

## Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `XNAM` | 12 bytes, repeats | Relation to another faction |
| `DATA` | uint32 | Flags |
| `JAIL` | `REFR` FormID | Jail marker outside |
| `WAIT` | `REFR` FormID | Follower wait marker |
| `STOL` | `REFR` FormID | Chest for stolen goods |
| `PLCN` | `REFR` FormID | Chest for the arrested player's items |
| `CRGR` | `FLST` FormID | Shared crime faction list |
| `JOUT` | `OTFT` FormID | Jail outfit |
| `CRVA` | 12, 16, or 20 bytes | Crime values |
| `RNAM` | uint32 | Rank index. Starts a rank group |
| `MNAM`, `FNAM` | lstring | Male and female rank title |
| `VEND` | `FLST` FormID | What the vendor buys and sells |
| `VENC` | `REFR` FormID | Merchant chest |
| `VENV` | 12 bytes | Vendor values |
| `PLVD` | 12 bytes | Where the vendor trades |
| `CITC`, `CTDA` | conditions | When the vendor trades |

A null FormID means absent.

## XNAM relations (12 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | FormID | The other faction: a `FACT` or a `RACE` |
| 4 | int32 | Disposition modifier |
| 8 | uint32 | Combat reaction: 0 neutral, 1 enemy, 2 ally, 3 friend |

xEdit allows a `RACE` here too. So a relation that does not match a faction is normal. The
disposition modifier has no effect in Skyrim. xEdit notes that the Creation Kit no longer
edits it. UESP found it non-zero on only one vanilla record.

## DATA flags

Names follow xEdit, which says which crime each "ignore" bit covers.

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

Other bits are kept raw.

## CRVA crime values

12, 16, or 20 bytes. Newer record versions added fields at the end. OpenSky reads only the
fields the data reaches and leaves the others empty, not zero.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint8 | Arrest |
| 1 | uint8 | Attack on sight |
| 2 | uint16 | Murder |
| 4 | uint16 | Assault |
| 6 | uint16 | Trespass |
| 8 | uint16 | Pickpocket |
| 10 | uint16 | Unused. Sometimes not zero. Never read as gold |
| 12 | float | Steal multiplier (16 bytes or more) |
| 16 | uint16 | Escape (20 bytes) |
| 18 | uint16 | Werewolf (20 bytes) |

Example: `CrimeFactionWhiterun` has murder 1000, assault 40, trespass 5, pickpocket 25, steal
multiplier 0.5, escape 100, and werewolf 1000.

A missing steal multiplier counts as 1. So a 12-byte `CRVA` charges the item's full value, not
nothing. Crime gold comes from these values, not from game settings. The vanilla install has
only two `iCrimeGold*` settings, and neither prices murder, assault, trespass, or theft.

UESP says `CRVA` is normally required, but `MS08AlikrFaction` has none. A faction without
`CRVA` prices nothing, but its crimes are still counted.

## Ranks

`RNAM` starts a rank group and holds the rank index. The `MNAM` and `FNAM` after it are that
rank's male and female titles. Either may be missing. A title lookup falls back to the other
gender. On a localized plugin the titles are string-table IDs.

A title with no open rank group is counted, not attached to the wrong rank. Vanilla has none.
xEdit also lists an unused `INAM` insignia field. Vanilla has none of those either.

## Vendor block

`VENV` is 12 bytes. The sources disagree about offsets 4 to 7:

| Offset | xEdit | UESP |
| --- | --- | --- |
| 4 | uint16 radius | uint32 radius |
| 6 | 2 unknown bytes | (part of the radius) |
| 8 | uint8 only buys stolen items | same |
| 9 | uint8 not sell/buy | same |
| 10 | 2 unknown bytes | uint16 unused |

OpenSky follows xEdit and counts records where the word at offset 6 is not zero. In the
vanilla load order there are none, so both readings give the same values. The count stays, so
a plugin where they differ is noticed instead of getting a radius in the tens of thousands.

`PLVD` is a type, one value whose meaning depends on the type, and a signed radius. The type
list is shared with package locations and is not implemented yet. The value stays raw.

The `CITC` and `CTDA` run is a normal [condition list](/formats/conditions.md). The vendor
trades only while it is true.

## NPC_ SNAM membership (8 bytes, repeats)

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | FormID | The `FACT` |
| 4 | int8 | Rank |
| 5 | 3 bytes | Unused |

The rank is signed. Vanilla uses negative ranks for members that no rank title names.

The list is inherited through the template flag `useFactions` (`0x0004` in `ACBS`). A record
takes its list from its template only when it has a `TPLT` and the flag is set. So a local
empty list stays empty (see [actors](/formats/actors.md)).

## Inspecting

`openskycli record <editorid>` and the Asset Browser type "FACT - Factions" show the flags,
crime values and their links, the rank table, the relations, and the raw vendor block. A link
that does not resolve prints as `[UNRESOLVED] <FormID>`, so a missing record never looks like
a name.

## Membership at runtime

`SNAM` says which factions an actor started in. What the actor belongs to now is stored in the
world state, one (faction, rank) row per faction. Joining, leaving, and promotion go through
the world state, so they are saved in the `FCTN` chunk of the
[save file](/formats/opensky-save.md).

The authored list is copied into the world state the first time anything asks about that
actor, not when the cell loads. Otherwise every townsperson would write a copy of what their
record already says. A membership that already exists wins over the authored one. So a quest
that promoted someone early is not undone by the later copy.

Two rules point in opposite directions on purpose:

- Joining a faction that the load order does not have is refused. Its key could never be read
  back.
- A stored membership whose faction stops resolving is kept. Removing a plugin must not
  destroy progress. The membership is just not shown.

Faction relations are flattened into one table from (faction, faction) to reaction, built once.
Hostility checks ask it for every pair of memberships of two actors, several times per frame.
Walking each faction's relation list every time would be too slow.
