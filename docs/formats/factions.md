---
type: File Format
title: Factions (FACT, NPC_ SNAM)
description: FACT record layout - relations, crime values, ranks and the vendor block - plus
  NPC_ faction membership and the load-order faction store.
tags: [format, plugin, records, factions, crime, vendor, actors]
timestamp: 2026-08-22T00:00:00Z
---

# Factions (FACT, NPC_ SNAM)

A `FACT` record is four things bundled under one editor ID: how its members treat other
factions, how it responds to crime committed in its territory, what it calls its ranks, and

- for a merchant faction - what its shop sells and when. Actors join factions through the
`NPC_` `SNAM` subrecord, which carries the faction link and the member's rank.

OpenSky decodes the record into links and raw values. What *reads* those values lives
elsewhere: hostility is derived in the [combat loop](/engine/combat.md), and crime response
and trade are the rest of milestone M21.

References:

- UESP [FACT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FACT) and
  [NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_).
- xEdit `dev-4.1.6`, `Core/wbDefinitionsTES5.pas`, `wbRecord(FACT, ...)`, and
  `Core/wbDefinitionsCommon.pas`, `wbFaction` and `wbFactionRelations`.

## Contents

- Field list
- Interfaction relations (`XNAM`)
- Flags (`DATA`)
- Crime values (`CRVA`)
- Ranks (`RNAM` / `MNAM` / `FNAM`)
- Vendor block (`VEND`, `VENC`, `VENV`, `PLVD`, conditions)
- NPC_ membership (`SNAM`)
- Faction store
- Runtime membership
- Observed counts

## Field list

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | display name |
| `XNAM` | struct[12], repeated | interfaction relation |
| `DATA` | uint32 | flags |
| `JAIL` | REFR FormID | exterior jail marker |
| `WAIT` | REFR FormID | follower wait marker |
| `STOL` | REFR FormID | evidence chest for stolen goods |
| `PLCN` | REFR FormID | container holding the arrested player's inventory |
| `CRGR` | FLST FormID | shared crime-faction list |
| `JOUT` | OTFT FormID | jail outfit |
| `CRVA` | struct[12/16/20] | crime values |
| `RNAM` | uint32 | rank index, opens a rank group |
| `MNAM` / `FNAM` | lstring | male and female rank title |
| `VEND` | FLST FormID | vendor buy/sell list |
| `VENC` | REFR FormID | merchant container |
| `VENV` | struct[12] | vendor values |
| `PLVD` | struct[12] | where the vendor trades |
| `CITC` / `CTDA` | condition run | conditions the vendor trades under |

A link written as a null FormID is read as absent, which is how the other reference records
in OpenSky read a zero link.

## Interfaction relations (`XNAM`)

Twelve bytes, repeated once per relation:

| offset | type | meaning |
| --- | --- | --- |
| 0 | FormID | the other faction - a `FACT` or a `RACE` |
| 4 | int32 | disposition modifier |
| 8 | uint32 | combat reaction: 0 neutral, 1 enemy, 2 ally, 3 friend |

xEdit accepts `RACE` as well as `FACT` in the link, so a relation that does not resolve
against the faction store is normal rather than a fault. A reaction value outside 0...3
round-trips as `unknown(raw:)`.

The modifier is inert in Skyrim: xEdit notes the Creation Kit no longer edits it, and UESP
observes it nonzero on exactly one vanilla record.

## Flags (`DATA`)

One uint32. Bit names follow xEdit, which spells out which crime each "ignore" bit covers.

| mask | meaning |
| --- | --- |
| `0x00000001` | hidden from NPC |
| `0x00000002` | special combat |
| `0x00000040` | track crime |
| `0x00000080` | ignore murder |
| `0x00000100` | ignore assault |
| `0x00000200` | ignore stealing |
| `0x00000400` | ignore trespass |
| `0x00000800` | do not report crimes against members |
| `0x00001000` | crime gold, use defaults |
| `0x00002000` | ignore pickpocket |
| `0x00004000` | vendor |
| `0x00008000` | can be owner |
| `0x00010000` | ignore werewolf |

Any other bit stays in the raw word and prints as `unknown 0x...` in the record dump.

## Crime values (`CRVA`)

Twelve, sixteen or twenty bytes. The tail grew across record versions, so the decoder reads
the fields the payload actually reaches and leaves the rest nil rather than defaulting them
to zero - a caller that needs the steal multiplier has to decide what an absent one means,
and a zero would answer for it silently.

| offset | type | meaning |
| --- | --- | --- |
| 0 | uint8 | arrest |
| 1 | uint8 | attack on sight |
| 2 | uint16 | murder |
| 4 | uint16 | assault |
| 6 | uint16 | trespass |
| 8 | uint16 | pickpocket |
| 10 | uint16 | unused; nonzero in the wild, never read as gold |
| 12 | float | steal multiplier (16-byte payloads and longer) |
| 16 | uint16 | escape (20-byte payloads) |
| 18 | uint16 | werewolf (20-byte payloads) |

UESP records that the field is normally required and that one vanilla record,
`MS08AlikrFaction`, has none, so an absent `CRVA` is not a decode failure either.

## Ranks (`RNAM` / `MNAM` / `FNAM`)

`RNAM` opens a rank group and carries the rank index; the `MNAM` and `FNAM` that follow are
that rank's male and female titles. Either title may be missing, and OpenSky's
`Faction.rankTitle(_:female:)` falls back to the gender the record did author. Titles are
localizable, so on a localized plugin they decode to string-table IDs rather than text.

A title subrecord with no open rank group - which vanilla does not author - is tallied
rather than attached to the wrong rank. xEdit also lists an unused `INAM` insignia string;
nothing in the install carries one, and the decoder tallies it if it appears.

## Vendor block (`VEND`, `VENC`, `VENV`, `PLVD`, conditions)

`VENV` is twelve bytes, and the two sources disagree about offsets 4...7:

| offset | xEdit | UESP |
| --- | --- | --- |
| 4 | uint16 radius | uint32 radius |
| 6 | 2 unknown bytes | (part of the radius) |
| 8 | uint8 only buys stolen items | same |
| 9 | uint8 not sell/buy | same |
| 10 | 2 unknown bytes | uint16 unused |

OpenSky follows xEdit and counts every record whose word at offset 6 is nonzero. Across the
whole active load order that count is zero, so the two readings agree on every value this
install carries; the tally stays so a plugin that disagrees shows up rather than silently
producing a radius in the tens of thousands.

`PLVD` is a type selector, one word whose meaning the selector decides, and a signed radius.
The type registry is shared with package locations and is not implemented yet, so the middle
word stays raw.

The trailing `CITC`/`CTDA` run is decoded by the shared
[condition list](/formats/conditions.md): the vendor trades only while it holds.

## NPC_ membership (`SNAM`)

Eight bytes, repeated once per faction the actor belongs to:

| offset | type | meaning |
| --- | --- | --- |
| 0 | FACT FormID | the faction |
| 4 | int8 | rank |
| 5 | 3 bytes | unused in Skyrim |

The rank is signed, and vanilla authors negative ranks for members no rank title names.

The run inherits through the `ACBS` template-data flag `useFactions` (`0x0004`), resolved by
`ActorTemplateResolver.resolveFactions(base:)` exactly as the spell and package runs resolve
on their own flags: a record delegates its list upward only while it has a `TPLT` and the
flag is set, so a locally authored empty list stays authoritative
([actors](/formats/actors.md)).

## Faction store

`FactionStore` layers FACT lookup over `RecordIndex` in the same shape as
[`LocationStore`](/formats/locations.md): the load-order winner per identity, lookup by
`ResolvedFormID` or case-insensitive editor ID, and the joins a consumer would otherwise
redo - relations resolved to the records they name, and an actor's memberships resolved
through the template chain and joined to the faction records with their rank titles.

A link that does not resolve is reported as `[UNRESOLVED] <FormID>` rather than as a name, so
a missing record can never read as one.

`openskycli record <editorid>` and the Asset Browser's `FACT — Factions` type print the same
decoded view: the identity and flag line, the crime values and their support links, the rank
table, the relation table and the raw vendor block. In the Asset Browser the record inspector
adds the relations joined to the records they name.

## Runtime membership

The `SNAM` run says what an actor was *authored* into. What it belongs to *now* is
`ActorFactionState`, a world-state component holding one `(faction key, rank)` row per
faction in ascending key order, written through `FactionRuntime`
(`opensky/Engine/Factions/`). Joining, leaving and promoting all go through the store, so
they land in the journal, the dirty counts and the `FCTN` save chunk
([OpenSky save container](/formats/opensky-save.md)) exactly as learning a spell does.

Seeding is lazy and once per actor per session: the authored run is copied into the
component the first time anything asks about that actor, rather than at cell build, because a
street of townsfolk who never meet the player would otherwise write a component each to say
what their base records already say. A membership already present wins over the authored one,
so a quest that promoted somebody before anything asked is not undone by the seed that
arrives afterwards.

Two rules mirror the ones an owned perk follows, and they point in opposite directions on
purpose. Joining a faction the load order does not carry is *refused*, because a key nothing
resolves could never be read back and would sit unreadable in the save forever. A membership
already *stored* under a key that stops resolving is *kept*, because removing a plugin must
not destroy progress; it is simply absent from `resolvedFactions(of:)`.

`FactionStore.faction(key:)` is the lookup behind every stored membership. It is a separate
index rather than a `ResolvedFormID` round trip because `ReferenceKey` lowercases the plugin
name while `ResolvedFormID` keeps whatever spelling the `MAST` field used, so the two are not
interchangeable dictionary keys.

`FactionRelationIndex` flattens every `XNAM` in the load order into one directional
`(from, to) -> reaction` table, built once beside the store. The hostility derivation asks it
for every pair of memberships two actors hold, several times a frame, and a walk of one
faction's relation list per query would be a linear scan of up to eighty-five entries inside
that loop.

## Observed counts

Measured on 2026-08-20 against the active load order of the five masters plus the
Creation Club plugins this install carries (`FactionStoreRealDataTests`):

| measure | value |
| --- | --- |
| FACT records collected | 1424 |
| FACT load-order winners, all decoded | 1417 |
| factions with track crime | 74 |
| factions with the vendor flag | 286 |
| malformed, unknown or trailing-byte tallies | 0 |
| `VENV` records with a nonzero word at offset 6 | 0 |
| `LCTN` `FNAM` crime-faction links, all resolving | 9 |
| `NPC_` bases | 5118 |
| authored memberships after template resolution | 13157 |
| bases whose memberships came from a template | 2921 |
| members of `GuardFactionWhiterun` | 61 |
| authored `XNAM` relations, all indexed | 1185 |
| `XNAM` combat-reaction words the spec does not name | 0 |

`CrimeFactionWhiterun` decodes murder 1000, assault 40, trespass 5, pickpocket 25, steal
multiplier 0.5, escape 100 and werewolf 1000, with two relations and every crime-support
link present.
