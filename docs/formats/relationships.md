---
type: File Format
title: Relationships (RELA, ASTP)
description: RELA layout (the two NPC_ ends, rank, secret flags, association link), ASTP
  titles, pair lookup, and scripted ranks at runtime.
tags: [format, plugin, records, relationships, actors, dialogue]
---

# Relationships (RELA, ASTP)

A `RELA` record links two actor bases and says what they are to each other. It holds a rank
from lover to archnemesis, a secret flag, and an optional link to an `ASTP` record. An `ASTP`
names the kind of link in words, such as `Spouse`, `ParentChild`, or `JarlHousecarl`. It has
four titles and a flag that says whether the link counts as family.

Hostility and dialogue conditions such as `GetRelationshipRank` and `HasAssociationType` read
these records.

Sources: UESP [RELA](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RELA) and
[ASTP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASTP); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`, `wbRecord(RELA, ...)` and `wbRecord(ASTP, ...)`.

## Fields

`RELA` has `EDID` (editor ID) and `DATA` (16 bytes, below).

`ASTP`:

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `MPRT` | zstring | Male parent title |
| `FPRT` | zstring | Female parent title |
| `MCHT` | zstring | Male child title |
| `FCHT` | zstring | Female child title |
| `DATA` | uint32 | Flags. `0x01` is family |

The titles are plain zstrings, not lstrings. xEdit types them `wbString`. So they are the same
in every language.

## RELA DATA (16 bytes)

| Offset | Type | Field |
| --- | --- | --- |
| 0 | FormID | Parent, an `NPC_` or null |
| 4 | FormID | Child, an `NPC_` or null |
| 8 | uint16 | Rank |
| 12 | uint8 | Unknown. Always 0 in vanilla |
| 13 | uint8 | Flags |
| 14 | FormID | Association type, an `ASTP` or null |

"Parent" and "child" are only the names of the two ends. They say nothing about family. The
association type says what the link is. A `Spouse` link also has a parent end and a child
end.

A null end means absent. A record with only one end can be looked up by ID, but it is not a
pair. A `DATA` shorter than 16 bytes loses its value, not the record.

## Rank

The stored rank counts up from the friendliest. `GetRelationshipRank` counts down from +4.

| Stored | Name | `GetRelationshipRank` |
| --- | --- | --- |
| 0 | lover | +4 |
| 1 | ally | +3 |
| 2 | confidant | +2 |
| 3 | friend | +1 |
| 4 | acquaintance | 0 |
| 5 | rival | -1 |
| 6 | foe | -2 |
| 7 | enemy | -3 |
| 8 | archnemesis | -4 |

A value outside 0 to 8 is kept as unknown and has no signed rank. It is not clamped, because
a clamp would turn a mod's value into a real rank. Vanilla has no such value, and no
archnemesis at all.

## Two secret flags

The sources disagree about where the secret bit is. OpenSky reads both places:

- In `DATA`. xEdit reads offset 12 as an unknown byte and offset 13 as flags, with `0x80`
  named Secret. UESP reads offsets 12 and 13 as one uint16 with bit `0x8000`. In little-endian
  these are the same bit.
- In the record header. xEdit also names bit 6 of the `RELA` record header flags Secret. UESP
  does not.

No source says which one the game reads. The real data does not agree either. A few records
set the `DATA` bit, a few set the header bit, and `JulienneTasius` sets only the `DATA` bit.
So a caller that needs "is this secret" must choose which flag to trust.

## Association types

Each `ASTP` has a gendered title pair for the parent end and one for the child end. Either
pair can be missing. A symmetric type such as `Courting` names only the parent titles
(`Boyfriend`, `Girlfriend`). A title lookup falls back to the other gender if the asked one
is missing.

`Spouse` uses the same pair on both ends (`Husband`, `Wife`). So in practice it is symmetric.

Vanilla has 20 types, and half are family types: `AuntUncle`, `BossEmployee`,
`BusinessPartners`, `Conspirators`, `Courting`, `Cousins`, `FavorTarget`, `GrandAuntUncle`,
`GrandparentGrandchild`, `GreatGrandparentGreatgrandchild`, `InLawAuntUncle`,
`InLawBrotherSister`, `InLawGrandparentGrandchild`, `InLawParentChild`, `JarlHousecarl`,
`JarlSteward`, `MasterAssistant`, `ParentChild`, `Siblings`, `Spouse`.

## Looking up a pair

The main question is "what are these two actors to each other?", asked without knowing which
one the record calls the parent. So the lookup works in both argument orders. The result keeps
the stored direction, because a child title only fits the child end.

A pair that no record names has no relationship. That is not the same as `acquaintance`,
which a record can set on purpose. When the load order names one pair twice, the later plugin
wins.

In vanilla every `RELA` names both ends, every association link resolves, and no pair is named
twice. Friendly ranks are far more common than hostile ones.

## Scripted ranks at runtime

`RELA` says what two bases were set up as. `Actor.SetRelationshipRank` changes what they are
now. OpenSky stores these changes per actor and saves them in the `RELS` chunk of the
[save file](/formats/opensky-save.md).

A scripted rank wins over the record. It is also the only way to give the player a rank,
because the player has no base record in OpenSky.

- Scripted ranks are keyed by reference, not by base. The script function takes two actors,
  and one of them is almost always the player. So two placements of the same base do not share
  a scripted rank. Vanilla scripts name unique actors, so this difference does not show.
- Both actors store the rank. `RELA` stores one record per pair, so either actor can answer
  alone. Setting a rank from an actor to itself is refused.
- A rank outside -4 to 4 is refused. There is no tenth rank for it to mean.
