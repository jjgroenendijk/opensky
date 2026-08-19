---
type: File Format
title: Actor value information
description: AVIF record layout — identity fields, the AVSK skill-use parameters, and the
  order-sensitive perk-tree node run — plus the name join that numbers a record and the
  counts observed on a vanilla install.
tags: [format, esm, progression, skills, perks, record]
timestamp: 2026-08-19T00:00:00Z
---

# Actor value information

AVIF describes the actor values themselves: what each one is called, how it is abbreviated
and described, and — for the eighteen skills — how using a skill turns into levelling it and
where each perk box sits in that skill's tree. It is the data root of progression: perk
resolution and skill advancement both start from a record decoded here.

AVIF carries no index of its own. The numbers every CTDA parameter, script native and stored
value use come from [actor values](/engine/actor-values.md), and a record is attached to one
of them by name, described under "Numbering a record" below.

## Contents

- Sources
- Record fields
- AVSK layout
- Perk-tree nodes
- The CNAM ambiguity
- Numbering a record
- Decode policy
- ActorValueInformationStore
- Observed on a vanilla install
- What is not decoded here

## Sources

- UESP "Skyrim Mod:Mod File Format/AVIF",
  <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AVIF>, including its "Perk Sections"
  table and its notes on the ANAM and CNAM quirks.
- xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`, `wbRecord(AVIF, 'Actor Value Information',
  [...])`, which gives the field order, the CNAM enum values and the
  `wbRArray('Perk Tree', wbRStruct('Node', [...]))` shape.

Where the two disagree, both readings are recorded rather than one being picked: see AVSK
below.

## Record fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor id. Vanilla prefixes most of these with `AV`. |
| `FULL` | lstring | In-game name. |
| `DESC` | lstring | Description. xEdit marks it required; a record without one still decodes. |
| `ICON` | zstring | Editor-side image path. |
| `ANAM` | zstring | Abbreviation. Rarely authored — nil is the normal answer. |
| `CNAM` | uint32 | Skill category, or something else entirely. See "The CNAM ambiguity". |
| `AVSK` | float[4] | Skill-use parameters. Only on records with a perk tree. |
| perk tree | node run | Repeated node group, below. |

The engine type is `ActorValueInformation`
(`opensky/Engine/Formats/ESM/Records/ActorValueInformation.swift`); the node types live in
`ActorValueInformationPerkTree.swift` beside it.

`CNAM` decodes to `ActorValueSkillCategory`: 0 none, 1 combat, 2 magic, 3 stealth, and
`unknown(raw:)` for anything else, with the raw word kept on the record either way.

## AVSK layout

Sixteen bytes, four little-endian floats:

| Offset | Type | Name |
| --- | --- | --- |
| 0x00 | float32 | Skill use multiplier |
| 0x04 | float32 | Skill use offset |
| 0x08 | float32 | Skill improve multiplier |
| 0x0C | float32 | Skill improve offset |

The two sources disagree on the second float: UESP calls it "Skill Use Offset" and xEdit
"Skill Offset Mult". Nothing in the engine depends on the reading yet, so OpenSky stores it
under UESP's name (`SkillUseParameters.useOffset`) and leaves the disagreement visible rather
than resolving it by guesswork. Turning these four numbers into experience gain is separate
work; nothing consumes them today.

A field that is not exactly sixteen bytes throws, is tallied as a malformed field, and leaves
`skillUse` nil — the rest of the record still decodes.

## Perk-tree nodes

The tree is a flat run of fields, not a sized array. Each node opens with `PNAM` and runs to
the next `PNAM` or the end of the record:

| Field | Type | Meaning |
| --- | --- | --- |
| `PNAM` | formid | The PERK this box grants. NULL on the entry node. |
| `FNAM` | uint32 | xEdit's "Parent Required" boolean. UESP records that the first node of a tree usually carries a very large value, so the raw word is kept and the boolean derived from it. |
| `XNAM` | uint32 | Perk-grid column. |
| `YNAM` | uint32 | Perk-grid row. |
| `HNAM` | float32 | Horizontal offset inside that grid cell. |
| `VNAM` | float32 | Vertical offset inside that grid cell. |
| `SNAM` | formid | The AVIF this node belongs to — normally the record carrying it. |
| `CNAM` | uint32 | A line from this box to the node with that `INAM`. Zero, one or many. |
| `INAM` | uint32 | This box's identity in the tree. Unique, not sequential. |

The entry node — NULL `PNAM`, `INAM` 0 — is bookkeeping rather than a drawn box, and its
numeric fields show it: on `AVMysticism` in Skyrim.esm it carries an `XNAM` of 14824284 and a
zero `FNAM`, which is the same "huge values on the first node" quirk UESP flags for `FNAM`.
Nothing reads those coordinates, so they are decoded verbatim and left alone rather than
sanitized.

Connections address `INAM` values, not array positions, which is why the index has to be
decoded rather than inferred. The grid is drawing information only: it says where a box is
painted, never what it costs or requires. Prerequisites live in the PERK record's own
conditions.

## The CNAM ambiguity

`CNAM` means two different things in one record, and position is the only thing separating
them: before the first `PNAM` it is the record-level skill category, and after one it is a
connection line belonging to the node that `PNAM` opened. This is why the decoder tracks
which node is open — the bookkeeping is the disambiguation, not an optimization. UESP flags
the same thing, and adds that on a record with no perk tree the record-level `CNAM` appears
to carry something other than a category ("large 4byte info"), which is why the raw word is
kept alongside the enum.

## Numbering a record

`ActorValueInformation.vanillaActorValueIndex` joins a record to the index table in
[actor values](/engine/actor-values.md) by name, trying in order:

1. the editor id as written,
2. the editor id with a leading `AV` dropped, which is how vanilla spells `AVOneHanded`,
3. the `FULL` name, when it is inline text.

`FULL` is last because a localized plugin stores it as a string-table id rather than text, so
it cannot be the primary key. The lookup compares with punctuation dropped and case folded,
so `One-Handed`, `OneHanded` and `one handed` are one name. A record no vanilla name matches
— a mod-added actor value — reports nil and is still stored and browsable.

Three vanilla skills would miss on all three attempts, because their editor ids use
Oblivion-era words the actor-value table does not carry: `AVMarksman`, `AVSpeechcraft` and
`AVMysticism`. `ActorValueIdentity.recordNameAliases` maps them, and the mapping is observed
rather than recalled — each record's own `FULL` string resolves through Skyrim.esm's string
table to the name on the right, which
`ActorValueInformationRealDataTests.legacyEditorIDsNameTheSkillTheirOwnFullStringSpells()`
pins:

| Editor id | `FULL` resolves to | Index |
| --- | --- | --- |
| `AVMarksman` | Archery | 8 |
| `AVSpeechcraft` | Speech | 17 |
| `AVMysticism` | Illusion | 21 |

The aliases sit behind `index(recordName:)`, a separate entry point from the
`index(named:)` that condition parameters and Papyrus natives use, so the measured miss
buckets in [actor values](/engine/actor-values.md) do not move.

## Decode policy

- A record whose type is not AVIF throws.
- A malformed or truncated field is skipped and tallied
  (`ActorValueInformationSkipKind.malformedField`); the rest of the record still decodes.
- An unrecognized field is tallied as `unknownField`.
- A node that ends without one of the fields xEdit marks required is still emitted, with
  zeroes standing in, and tallied as `incompletePerkTreeNode`.
- `hasPerkTree` means the record carries both `AVSK` and a non-empty tree. That is *not* the
  same question as "is this one of the eighteen skills" — see below.

## ActorValueInformationStore

`opensky/Engine/GameData/ActorValueInformationStore.swift` indexes AVIF across the active
load order in the same shape as the magic stores ([magic records](/formats/magic-records.md)):
the winning definition per identity, with lookup by `ResolvedFormID`, by editor id
(case-insensitively), and by actor-value index through the join above. A malformed override
falls back to the earlier readable definition, as everywhere else built on `RecordIndex`.

Two collection properties, and the difference between them is real data rather than
pedantry. `perkTreeRecords` is every record with a tree; `skills` is the subset whose joined
index falls inside the skill range. On a load order with Dawnguard those differ: the vampire
and werewolf trees hang off `AVMagickaRateMod` and `AVHealRatePowerMod`, which are not skills
and which the vanilla name table does not carry at all, so they appear in the first and not
the second.

`openskycli record <editorid>` and the Asset Browser's `AVIF — Actor value information` type
both print the same summary: identity, the joined actor value, the category, the four skill-use
parameters, and the perk-node table, whose boxes name the PERK they grant when the dump was
given a perk store ([perks](/formats/perks.md)) and print the raw link when it was not.

## Observed on a vanilla install

Measured by `ActorValueInformationRealDataTests` over the active load order (Skyrim.esm plus
the four official masters):

- 153 AVIF definitions, all of which decode; 149 distinct identities, the difference being
  records the DLC masters override.
- 20 records carry a perk tree, holding 230 nodes between them. 18 of those are the skills:
  they join to exactly the contiguous actor-value index range 6 (`One-Handed`) through 23
  (`Enchanting`). The other two are Dawnguard's, described above.
- 92 of the 164 vanilla actor values have a record describing them.
- No unread field, no malformed field and no incomplete perk-tree node anywhere in the set.
- 91 records carry a `CNAM` outside the 0-3 enum, which is what UESP's "large 4byte info"
  note describes. Every one of them is a record with no perk tree, so no skill category is
  ever read from a word that does not mean one.

## What is not decoded here

- PERK records. A node's `PNAM` stays a raw plugin-relative FormID; resolving it to a perk and
  naming it in the dump is separate work.
- Experience gain. `AVSK` is decoded and stored, and nothing reads it yet.
- Any progression UI beyond the Asset Browser row and the CLI dump.
