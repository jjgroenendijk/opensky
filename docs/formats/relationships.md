---
type: File Format
title: Relationships (RELA, ASTP)
description: RELA record layout - the two NPC_ sides, the rank, the secret flags, and the
  association type - plus ASTP titles and scripted ranks.
tags: [format, plugin, records, relationships, actors, dialogue]
---

# Relationships (RELA, ASTP)

A `RELA` record links two actor bases and says what they are to each other. It has a rank
from lover to archnemesis, a secret flag, and an optional link to an `ASTP` record. An
`ASTP` record names the kind of link in words, for example `Spouse`, `ParentChild`, or
`JarlHousecarl`. It has four titles (male and female, for each side) and a family flag.

Hostility and the dialogue conditions `GetRelationshipRank` and `HasAssociationType` read
these records. See [factions](/formats/factions.md) for the related faction records.

References: UESP [RELA](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RELA) and
[ASTP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASTP); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`, `wbRecord(RELA, 'Relationship', ...)` and
`wbRecord(ASTP, 'Association Type', ...)`.

## Fields

`RELA`:

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `DATA` | 16 bytes | Everything else, below |

`ASTP`:

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `MPRT` | zstring | Male parent title |
| `FPRT` | zstring | Female parent title |
| `MCHT` | zstring | Male child title |
| `FCHT` | zstring | Female child title |
| `DATA` | uint32 | Flags. `0x01` is a family link |

The titles are plain zstrings, not lstrings. xEdit calls them `wbString`. So they are the
same in every language.

## RELA DATA

| Offset | Type | Field |
| --- | --- | --- |
| 0 | FormID | Parent: an `NPC_` or null |
| 4 | FormID | Child: an `NPC_` or null |
| 8 | uint16 | Rank |
| 12 | uint8 | Unknown. Always 0 in vanilla |
| 13 | uint8 | Flags |
| 14 | FormID | Association type: an `ASTP` or null |

"Parent" and "child" are only the names of the two ends. The association type says what the
link is: family, courtship, work, or rivalry. A `Spouse` link also has a parent and a child.

A null side means no actor. A record with only one side cannot describe a pair. A `DATA`
shorter than 16 bytes loses its values, but the editor ID still decodes.

## Rank

The stored value counts up from the friendliest rank. `GetRelationshipRank` counts down
from +4.

| Stored | Name | `GetRelationshipRank` |
| --- | --- | --- |
| 0 | Lover | +4 |
| 1 | Ally | +3 |
| 2 | Confidant | +2 |
| 3 | Friend | +1 |
| 4 | Acquaintance | 0 |
| 5 | Rival | -1 |
| 6 | Foe | -2 |
| 7 | Enemy | -3 |
| 8 | Archnemesis | -4 |

A value outside 0 to 8 is kept as unknown, with no signed rank. OpenSky does not clamp it,
because a clamp would turn a mod's value into a real rank.

"No record for this pair" is not the same as acquaintance. Acquaintance is a rank an author
chose on purpose.

## Two secret flags

The sources disagree on where the secret bit is. OpenSky reads both places.

- xEdit reads offset 12 as one unnamed byte and offset 13 as flags, with `0x80` named
  Secret. UESP reads offsets 12 and 13 as one uint16 with bit `0x8000`. In little-endian
  these are the same bit.
- xEdit also names bit 6 of the `RELA` record header flags Secret. UESP does not mention it.

No source says which one the game reads, and vanilla data does not agree: 7 records set the
`DATA` bit, 6 set the header bit, and `JulienneTasius` sets only the `DATA` bit. So OpenSky
keeps both and lets each user of the data choose.

## ASTP titles

Either side may have no titles. A symmetric link such as `Courting` has only parent titles
(`Boyfriend`, `Girlfriend`). When the title for the asked gender is missing, OpenSky uses
the other gender's title. `Spouse` has the same titles on both sides (`Husband`, `Wife`), so
it reads the same from either end.

## Scripted ranks

`RELA` gives the rank the author set between two bases. The Papyrus function
`Actor.SetRelationshipRank` changes it at runtime. OpenSky stores these changes per actor
and saves them in the `RELS` chunk of the [OpenSky save](/formats/opensky-save-actor-chunks.md). A
scripted rank wins over the record.

Design choices:

- A scripted rank is stored per placed actor, not per base. The player has no base record
  in OpenSky, and the player is one side of almost every vanilla call. So two placed copies
  of one base do not share a scripted rank. Vanilla scripts name unique actors, so this
  does not show in vanilla.
- A scripted rank is written on both actors, because a relationship is one fact about a
  pair. An actor cannot have a rank with itself.
- A rank outside -4 to 4 is refused, because there is no tenth rank to map it to.

## Vanilla counts

On the five masters plus the Creation Club plugins of a stock install: 673 `RELA` records
and 20 `ASTP` records, all decode. Every `RELA` names both sides, and no pair appears twice.
430 `RELA` records link an `ASTP`, and every link resolves. 10 `ASTP` records are family
links. No record sets a flag bit that neither source names.

Ranks: ally 257, friend 152, confidant 89, acquaintance 68, lover 50, rival 48, foe 8, enemy
1, archnemesis 0.

The 20 association types: `AuntUncle`, `BossEmployee`, `BusinessPartners`, `Conspirators`,
`Courting`, `Cousins`, `FavorTarget`, `GrandAuntUncle`, `GrandparentGrandchild`,
`GreatGrandparentGreatgrandchild`, `InLawAuntUncle`, `InLawBrotherSister`,
`InLawGrandparentGrandchild`, `InLawParentChild`, `JarlHousecarl`, `JarlSteward`,
`MasterAssistant`, `ParentChild`, `Siblings`, `Spouse`.
