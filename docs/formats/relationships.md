---
type: File Format
title: Relationships (RELA, ASTP)
description: RELA record layout - the two NPC_ parents, the rank enum, the secret flag and
  the association-type link - plus ASTP titles and the load-order relationship store.
tags: [format, plugin, records, relationships, actors, dialogue]
timestamp: 2026-08-21T00:00:00Z
---

# Relationships (RELA, ASTP)

A `RELA` record names one pair of actor bases and says what they are to each other: a rank
running from lover to archnemesis, a secret flag, and an optional `ASTP` link naming the
association in words (`Spouse`, `ParentChild`, `JarlHousecarl`). An `ASTP` record is that
vocabulary: four gendered titles and a flag saying whether the association counts as family.

Together they are the relationship model that faction-aware hostility and dialogue
conditions read. OpenSky decodes them into links and raw values. Nothing here decides
hostility (issue #503) or evaluates `GetRelationshipRank` and `HasAssociationType`
(issue #508).

References:

- UESP [RELA](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RELA) and
  [ASTP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASTP).
- xEdit `dev-4.1.6`, `Core/wbDefinitionsTES5.pas`, `wbRecord(RELA, 'Relationship', ...)`
  and `wbRecord(ASTP, 'Association Type', ...)`.

## Contents

- Field list
- Relationship data (`RELA DATA`)
- Rank
- The two secret flags
- Association type (`ASTP`)
- Relationship store
- Observed counts

## Field list

`RELA`:

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `DATA` | struct[16] | the whole record - both parents, rank, flags, association link |

`ASTP`:

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `MPRT` | zstring | male parent title |
| `FPRT` | zstring | female parent title |
| `MCHT` | zstring | male child title |
| `FCHT` | zstring | female child title |
| `DATA` | uint32 | flags |

The four `ASTP` titles are plain zstrings, not lstrings: xEdit spells them `wbString`, so
they never go through the localized string tables and read the same in every language build.

## Relationship data (`RELA DATA`)

Sixteen bytes, fixed:

| offset | type | field |
| --- | --- | --- |
| 0 | FormID | parent, an `NPC_` or NULL |
| 4 | FormID | child, an `NPC_` or NULL |
| 8 | uint16 | rank |
| 12 | uint8 | unknown, kept verbatim |
| 13 | uint8 | flags |
| 14 | FormID | association type, an `ASTP` or NULL |

"Parent" and "child" are the record's own direction words and carry no biological meaning:
they are just the two ends of a link, and the association type is what says whether the pair
is a family, a courtship, an employment or a rivalry. A `Spouse` relationship has a parent
and a child like any other, and both sides read the same title.

Both links may be NULL, and OpenSky reads a null link as absent rather than as FormID zero.
A record that names only one side stays in the store for identity lookup but never enters
the pair index, because it names no pair.

A `DATA` shorter than sixteen bytes costs its own value and not the record:
`Relationship.data` is nil, the tally records one malformed `DATA`, and the editor ID still
decodes.

## Rank

The stored value counts up from the friendliest; the value `GetRelationshipRank` returns
counts down from `+4`. `RelationshipRank.signedRank` carries the conversion so no caller
re-derives it.

| raw | name | `GetRelationshipRank` |
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

Anything outside `0...8` decodes as `unknown(raw:)` with a nil `signedRank`, rather than
clamping - a clamp would silently turn a modded value into a real rank. The vanilla load
order authors no such value and no `archnemesis` at all.

## The two secret flags

The two sources disagree about where the secret bit lives, and both readings are decoded:

- xEdit reads offset 12 as one unnamed byte and offset 13 as a `uint8` flag whose `0x80` is
  named Secret. UESP reads offsets 12 to 13 as one `uint16` whose only named bit is
  `0x8000`. Little-endian, those are the same bit, so `RelationshipFlags.secret` covers both
  and the byte at offset 12 is kept verbatim as `RelationshipData.unknown`.
- xEdit *also* names bit 6 of the RELA **record header** flags Secret, which UESP does not
  mention. `Relationship.headerSecret` reads it separately.

Nothing in either source says which one the game reads, and they do not agree on the real
data: 7 records set the `DATA` bit, 6 set the header bit, and one record (`JulienneTasius`)
sets the `DATA` bit alone. So a consumer that needs "is this relationship secret" has to
decide which flag it trusts; the decode refuses to make that choice for it, and the
real-data suite prints the disagreeing records on every run.

## Association type (`ASTP`)

Four titles and one flag, `0x01` = family association. Both the parent and the child side
carry a gendered pair, and either side may be left unauthored - a symmetric association such
as `Courting` names only the parent side (`Boyfriend` / `Girlfriend`) and no child titles at
all. `parentTitle(female:)` and `childTitle(female:)` prefer the gendered title the caller
asked for and fall back to the other, so a record that authored only one still answers.

`Spouse` authors the same pair on both sides (`Husband` / `Wife`), which is what makes it
symmetric in practice despite the directed record.

## Relationship store

`RelationshipStore` layers RELA and ASTP lookup over `RecordIndex` in the same shape as
[`FactionStore`](/formats/factions.md): the load-order winner per identity, lookup by
`ResolvedFormID` or case-insensitive editor ID, and the joins a consumer would otherwise
redo. ASTP is indexed first, so a relationship joins its association type as it is added.

The query the rest of milestone M21 needs is the pair one - "what are these two actors to
each other", asked without knowing which of them the record calls the parent.
`relationship(between:and:)` and `rank(between:and:)` answer in either argument order, keyed
on an unordered `RelationshipPairKey` that normalizes plugin-name case. The record they
return keeps the authored direction in `parent` and `child`, because a child title only
makes sense on the child side. `relationships(involving:)` lists every relationship one
actor takes part in, on either side.

A pair no record names answers nil, which is not the same as `acquaintance` - the rank a
record can author to mean deliberate indifference. A load order that names one pair twice is
counted in `duplicatePairCount` and the load-order winner is the one kept.

`openskycli record <editorid>` and the preview detail pane print the decoded view: for RELA
the pair, the rank with its `GetRelationshipRank` value and both secret flags, and the raw
association link; for ASTP the family flag and whichever of the four titles the record
authored.

## Observed counts

Measured on 2026-08-21 against the active load order of the five masters plus the Creation
Club plugins this install carries (`RelationshipStoreRealDataTests`):

| measure | value |
| --- | --- |
| `RELA` records collected, all load-order winners, all decoded | 673 |
| `ASTP` records collected, all load-order winners, all decoded | 20 |
| malformed or unknown field tallies across both types | 0 |
| RELA records without a usable `DATA` | 0 |
| RELA records naming both sides | 673 |
| pairs named by more than one record | 0 |
| RELA records carrying an association-type link | 430 |
| association-type links that do not resolve | 0 |
| distinct `ASTP` records referenced | 20 of 20 |
| `ASTP` records with the family flag | 10 |
| relationships carrying the `Spouse` association | 59 |
| nonzero byte at `DATA` offset 12 | 0 |
| flag bits set that neither source names | 0 |

Rank histogram over all 673: ally 257, friend 152, confidant 89, acquaintance 68, lover 50,
rival 48, foe 8, enemy 1, archnemesis 0.

The twenty association types are `AuntUncle`, `BossEmployee`, `BusinessPartners`,
`Conspirators`, `Courting`, `Cousins`, `FavorTarget`, `GrandAuntUncle`,
`GrandparentGrandchild`, `GreatGrandparentGreatgrandchild`, `InLawAuntUncle`,
`InLawBrotherSister`, `InLawGrandparentGrandchild`, `InLawParentChild`, `JarlHousecarl`,
`JarlSteward`, `MasterAssistant`, `ParentChild`, `Siblings` and `Spouse`.
