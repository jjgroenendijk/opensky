---
type: File Format
title: Perks
description: PERK record layout — the header, the effect sections and their typed payloads,
  the entry-point enumeration and the EPFD function-data union — plus the store that indexes
  entry points and the histogram observed on a vanilla install.
tags: [format, esm, progression, perks, conditions, record]
timestamp: 2026-08-19T00:00:00Z
---

# Perks

PERK is the record behind every perk the player picks and every passive an actor carries. A
perk is a header, a run of availability conditions, and a list of typed effects: set a quest
stage, grant an ability spell, or hook an *entry point* — a named place in a combat, magic or
world formula where the engine asks "does anything modify this value?".

Entry points are the reason decode fidelity here matters. They are the interface between the
perk system and every other system, so what a perk can do at runtime is bounded by what this
record decodes.

## Contents

- Sources
- Record fields
- Effect sections
- Entry points
- Function data
- The two DATA fields
- Decode policy
- PerkStore
- Observed on a vanilla install
- The EPFD actor-value word is a float
- What is not decoded here

## Sources

- UESP "Skyrim Mod:Mod File Format/PERK",
  <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK>, including its "Perk Sections",
  "Perk Effect Types" and "Function Types" tables.
- xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`, `wbRecord(PERK, 'Perk', [...])` at line 5908,
  which gives the field order, the `wbPerkDATADecider` effect union, the `wbEPFDDecider`
  function-data union, and `wbEntryPointsEnum` at line 2426.

Where the two disagree, xEdit is followed: it enumerates all 92 entry points in index order,
while UESP lists them by hexadecimal id in an alphabetized table and stops short of the last
few. The two agree on every id they both name.

## Record fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor id. |
| `VMAD` | struct | Script attachments; PERK is a fragment carrier. See [VMAD](/formats/vmad.md). |
| `FULL` | lstring | In-game name. |
| `DESC` | lstring | Description. |
| `ICON` | zstring | Editor-side image path. |
| `CTDA` | struct | Availability conditions — whether the perk can be taken. See [conditions](/formats/conditions.md). |
| `DATA` | uint8[5] | Header, below. |
| `NNAM` | formid | The next rank of this perk, or NULL on the last one. |
| effects | section run | Repeated `PRKE`...`PRKF` sections, below. |

`DATA` at record level is five bytes, one per field:

| Offset | Type | Name |
| --- | --- | --- |
| 0x00 | uint8 | Is trait |
| 0x01 | uint8 | Minimum level |
| 0x02 | uint8 | Rank count |
| 0x03 | uint8 | Is playable |
| 0x04 | uint8 | Is hidden |

Ranks past the first are separate PERK records, chained through `NNAM`. The rank-count byte
is *not* the length of that chain and the level byte is not the skill requirement — both are
measured under "Observed on a vanilla install" below, because the reading matters and neither
source states it.

The engine type is `Perk` (`opensky/Engine/Formats/ESM/Records/Perk.swift`); the effect types
live in `PerkEffect.swift` and `PerkEntryPoint.swift`, and the field-run state machine in
`PerkDecoder.swift`.

## Effect sections

Every effect opens with `PRKE` and closes with `PRKF`. `PRKE` is three bytes — type, rank,
priority — and the type byte decides what the `DATA` inside the section means:

| Type | Section | `DATA` payload |
| --- | --- | --- |
| 0 | Quest | formid `QUST`, uint16 stage, two unused bytes carrying junk |
| 1 | Ability | formid `SPEL` |
| 2 | Entry point | uint8 entry point, uint8 function, uint8 declared condition-tab count |

The rank byte counts from zero, so a value of 0 is rank 1.

An entry-point section then carries its conditions and its function parameters:

| Field | Type | Meaning |
| --- | --- | --- |
| `PRKC` | int8 | Opens a condition tab; the value is which subject the tab runs against. |
| `CTDA` | struct | Belongs to the tab the last `PRKC` opened. |
| `EPFT` | uint8 | Declared shape of the `EPFD` payload. |
| `EPF2` | lstring | Button label, on the "add activate choice" function only. |
| `EPF3` | uint16[2] | Script flags (bit 0 run immediately, bit 1 replace default) and a VMAD fragment index. |
| `EPFD` | variable | The function's parameters. See "Function data". |

The declared tab count and the tabs a record actually authors need not agree: `Armsman40`
declares three for Mod Attack Damage and authors two. xEdit marks the count ignored on write
because it is fixed per entry point, so OpenSky keeps both numbers and enforces neither.

Which subject each `PRKC` index names depends on the entry point — typically perk owner,
target, attacker, weapon or spell, and UESP's "Perk Effect Types" table lists them per entry
point. OpenSky keeps the index raw rather than naming it, because nothing evaluates a tab
yet.

## Entry points

`PerkEntryPoint` wraps the raw byte and looks its name up in a 92-entry table taken from
`wbEntryPointsEnum`. It is deliberately not a 92-case enum: the id is what the runtime index
keys on, an id outside the table has to survive decoding, and the names exist only for
inspection surfaces. `isKnown` reports whether the table covers an id.

The second byte of an entry-point `DATA` is the *function* — how the entry point's value is
changed:

| Id | Function | `EPFT` |
| --- | --- | --- |
| 1 | Set value | 1 |
| 2 | Add value | 1 |
| 3 | Multiply value | 1 |
| 4 | Add range to value | 2 |
| 5 | Add actor value mult | 2 |
| 6 | Absolute value | none |
| 7 | Negative absolute value | none |
| 8 | Add leveled list | 3 |
| 9 | Add activate choice | 4 |
| 10 | Select spell | 5 |
| 11 | Select text | 6 |
| 12 | Set to actor value mult | 2 |
| 13 | Multiply actor value mult | 2 |
| 14 | Multiply 1 + actor value mult | 2 |
| 15 | Set text | 7 |

The `EPFT` column is what each function is expected to declare. OpenSky reads the record's
own `EPFT` rather than deriving it from the function, so a record that disagrees with the
table still decodes as authored.

## Function data

`EPFD` is a union read through `EPFT`, with one tie broken by the function byte:

| `EPFT` | Payload |
| --- | --- |
| 0 | Unknown; kept raw |
| 1 | float32 |
| 2 | float32, float32 — *or* uint32 actor value plus float32 factor |
| 3 | formid `LVLI` |
| 4 | formid `SPEL`, beside `EPF2` and `EPF3` |
| 5 | formid `SPEL` |
| 6 | zstring |
| 7 | lstring |

The `EPFT` 2 split is `wbEPFDDecider`: under functions 5, 12, 13 and 14 — the four
actor-value multipliers — the first word is an actor-value index rather than a float. Nothing
in the payload itself distinguishes the two readings, so the function byte from the section's
`DATA` is what decides, and it is read out of the already-decoded effect payload rather than
by looking ahead.

Because that decision needs a field that precedes `EPFD` in every vanilla record but is not
guaranteed to, the decoder keeps the `EPFD` field verbatim until the section closes and reads
it then. A payload whose length does not fit its declared shape decodes to `raw`, which keeps
the bytes visible instead of dropping them or guessing.

## The two DATA fields

`DATA` means two different things in one record, and `PRKE` is the only thing separating
them: before the first `PRKE` it is the five-byte header, and inside a section it is the
section's typed payload. A `CTDA` run is ambiguous in the same way — the perk's own
availability conditions before the first `PRKE`, an entry-point condition tab after one. The
decoder therefore keeps explicit open-section state, exactly as the QUST decoder does
([records](/formats/records.md)); the bookkeeping is the disambiguation, not an optimization.

## Decode policy

- A record whose type is not PERK throws. Nothing else does.
- A malformed or truncated subrecord is skipped and tallied as `malformedField`; the rest of
  the record still decodes, including the effects, because a perk with an unreadable header
  is still what a runtime formula queries.
- An effect-only subrecord (`PRKC`, `EPFT`, `EPF2`, `EPF3`, `EPFD`, `PRKF`) arriving with no
  section open is tallied as `fieldOutsideEffect`.
- A `CTDA` inside a section that no `PRKC` opened a tab for is tallied as
  `conditionOutsideTab`.
- A section that reaches the end of the record without its `PRKF` is still emitted, with
  `isTerminated` false, and tallied as `unterminatedEffect`.
- An unrecognized subrecord is tallied as `unknownField`.
- Every enumerated value — effect type, entry point, function, `EPFT` — keeps its raw byte
  when it falls outside the documented set, rather than throwing or being forced onto a
  neighbour.

## PerkStore

`opensky/Engine/GameData/PerkStore.swift` indexes PERK across the active load order in the
same shape as the magic stores ([magic records](/formats/magic-records.md)): the winning
record per identity, with lookup by `ResolvedFormID` and by editor id (case-insensitively).
It adds three joins:

- **Spells.** An ability effect's `DATA` link and a "select spell" function's `EPFD` link both
  resolve against `SpellStore`, so a caller reads the spell record rather than a raw form.
- **Rank chains.** `rankChain(from:)` walks `NNAM` from a perk to the last rank, with a
  visited set and a depth cap so a mod-authored loop yields a short chain instead of hanging.
- **The entry-point index.** Every entry-point effect in the load order is collected into one
  dictionary keyed by entry-point id and sorted by `PRKE` priority, so a formula asking
  "which perk effects hook Mod Attack Damage" does one lookup instead of scanning every perk.
  `matches(at:)` answers it; `entryPointHistogram` reports the whole distribution.

`openskycli record <editorid>` and the Asset Browser's `PERK — Perks` type print the same
summary: identity, header, availability conditions, then one block per effect with its typed
payload, its decoded function data, and its condition tabs rendered in the same
`<function> <operator> <value>` shape the runtime-state readout uses. The Asset Browser adds a
resolved rank-chain section. Perk links elsewhere now resolve to names too: a spell's
half-cost perk, a magic effect's perk to apply, and each box of an AVIF perk tree
([actor value information](/formats/actor-value-information.md)).

## Observed on a vanilla install

Measured by `PerkRealDataTests` over the active load order (Skyrim.esm plus the four official
masters):

- 532 PERK definitions across the five masters, all of which decode; 483 distinct
  identities, the difference being records the DLC masters override.
- 863 effects between them: 622 entry-point effects, 32 ability effects and 28 quest
  effects. Every ability link resolves to a SPEL in the same load order.
- 68 of the 92 entry points are hooked by at least one effect. No unread field, no malformed
  field, no unknown entry-point id and no unknown function id anywhere in the set.
- 279 records carry availability conditions, and 13 carry a VMAD script.
- The header bytes are nearly uniform: no record is a trait, every record leaves the level
  byte at zero, 46 are hidden, 34 are not playable, and 27 declare a rank count of 5 while
  the other 456 declare 1.

The entry-point histogram, which is what scopes the perk runtime — the top ten cover more
than half of every hook in the game:

| Entry point | Id | Effects |
| --- | --- | --- |
| Mod Attack Damage | 35 | 81 |
| Mod Spell Magnitude | 29 | 61 |
| Apply Combat Hit Spell | 51 | 58 |
| Mod Spell Cost | 38 | 43 |
| Mod Armor Rating | 85 | 31 |
| Mod Incoming Damage | 36 | 23 |
| Mod Tempering Health | 76 | 21 |
| Activate | 14 | 19 |
| Mod Spell Duration | 30 | 17 |
| Mod Buy Prices | 8 | 15 |
| Mod Sell Prices | 60 | 15 |
| Calculate My Critical Hit Chance | 1 | 14 |
| Mod Pickpocket Chance | 56 | 13 |
| Mod Lockpick Sweet Spot | 59 | 13 |
| Filter Activation | 74 | 13 |
| Mod Enchantment Power | 77 | 13 |
| Calculate Weapon Damage | 0 | 12 |
| Mod Alchemy Effectiveness | 66 | 11 |
| Mod Spell Range (Target Loc.) | 88 | 11 |
| Mod Armor Weight | 32 | 10 |
| Mod Detection Sneak Skill | 57 | 10 |

The remaining 47 hooked entry points carry eight effects or fewer each, and 24 are never
hooked by a vanilla perk at all. `PerkRealDataTests` prints the full histogram on every run.

### The rank count is not the rank chain

`Armsman00` declares a rank count of 1 while its `NNAM` chain is five records long
(`Armsman00`, `Armsman20`, `Armsman40`, `Armsman60`, `Armsman80`), and the same holds
across the set: the byte and the chain disagree often enough that neither can be derived from
the other. xEdit shows a rank count that matches the chain because it recomputes the value
after load (`wbPERKNumRanksAfterLoad`), not because the bytes say so.

The level byte tells a similar story: it is zero on every vanilla record, including
`Armsman80`, which the game only offers at One-Handed 80. The requirement is a condition on
the record (`GetBaseActorValue`), not a header field.

Both are exposed verbatim as `declaredRankCount` and `level`, and
`PerkRealDataTests.theDeclaredRankCountDoesNotTrackTheRankChain()` pins the finding so
nothing quietly starts trusting them.

## The EPFD actor-value word is a float

The four actor-value functions (`Add Actor Value Mult`, `Set AV Mult`, `Multiply AV Mult`,
`Multiply 1 + AV Mult`) take an `EPFT` 2 payload xEdit types as `Actor Value, Float`, and the
"actor value" word is stored as a **float holding the index** rather than as an integer. UESP
spells the payload "float AV, float FACTOR", and xEdit's `wbEPFDActorValueToStr`
(`Core/wbDefinitionsTES5.pas` line 889) reinterprets the `itU32` it read as a `Single` and
rounds it before looking the name up.

Reading the raw word as an integer therefore produces the bit pattern instead of the index:
`AlchemySkillBoosts` reports actor value 1125187584 rather than 146 (`0x43120000`).
`PerkFunctionData.actorValueIndex(fromFloat:)` rounds it to the signed index every other
actor-value field in the format carries, so a consumer never has to know where the number came
from. A payload outside `Int32`'s range reads as -1, the "no actor value" index the rest of
the engine uses.

## What is not decoded here

- Owning perks on an actor, and evaluating an entry point's conditions to fold its function
  into a formula. That is the perk runtime: [perks at runtime](/engine/perks.md).
- The perk-tree menu. Where a box is drawn comes from AVIF, not from here
  ([actor value information](/formats/actor-value-information.md)).
- The PERK tail of a `VMAD` fragment section. The primary scripts decode; the record-specific
  fragment tail is still counted and skipped, as it is for PACK and SCEN
  ([VMAD](/formats/vmad.md)).
