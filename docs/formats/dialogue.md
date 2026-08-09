---
type: File Format
title: Dialogue records (DIAL, INFO, VTYP)
description: Dialogue topics, ordered response records, voice types, actor voice links, and
  the immutable runtime index.
tags: [format, plugin, dialogue, dial, info, vtyp, npc, localization]
timestamp: 2026-08-09T00:00:00Z
---

# Dialogue records, Skyrim SE

Issue #204 supplies the plugin-side half of dialogue: DIAL topics, their ordered INFO
children, VTYP voice-directory identities, and NPC_ voice links. Topic selection,
condition evaluation, said-state and result-fragment dispatch are issue #426, the
[dialogue runtime](/engine/dialogue.md); scenes, audio paths and lip data are later M17
work.

Container framing: [ESM/ESP plugin container](/formats/esm.md). Shared condition layout:
[conditions](/formats/conditions.md). Actor template chains:
[actor records](/formats/actors.md).

## Contents

* Sources and ambiguity policy
* DIAL dialogue topic
* INFO topic response set
* VTYP voice type and NPC_ voice link
* DialogueStore traversal and indexes
* Defensive decode and vanilla sweep

## Sources and ambiguity policy

Layouts come from UESP "Skyrim Mod:Mod File Format" pages
[DIAL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DIAL),
[INFO](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO),
[VTYP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VTYP), and
[NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_), cross-checked against
xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`: `wbRecord(DIAL, ...)` around line 4754,
`wbRecord(VTYP, ...)` around line 6295, `wbRecord(INFO, ...)` around line 7796 and the
NPC_ `VTCK` declaration around line 8425.

Two disagreements need explicit policy:

* UESP presents DIAL DATA's last two bytes as a subtype byte plus an unused byte. xEdit
  reads them as one uint16 numeric subtype. OpenSky preserves the uint16 as
  `legacySubtype`; SNAM remains authoritative because UESP and xEdit agree that subtype
  positions moved and the official tools write SNAM after DATA to override them.
* The issue text called INFO NAM1 a DLSTRINGS value. UESP INFO calls it `ilstring`, and
  UESP's string-table page says ILSTRINGS contains subtitled conversations while
  DLSTRINGS contains journal and book text. The vanilla probe selected a nonzero shipped
  NAM1 ID: it resolved through `skyrim_english.ilstrings` and not the same ID in
  DLSTRINGS. `TopicInfo.Response.resolvedText(using:)` therefore passes `.ilstrings`
  explicitly instead of relying on `LocalizedStrings`' `.strings` default.

## DIAL dialogue topic

A DIAL record is immediately followed by a type-7 GRUP whose label is the DIAL FormID and
whose direct record children are INFOs.

| field | type | decoded |
| --- | --- | --- |
| EDID | zstring | `editorID` |
| FULL | lstring | `name`, the player's topic text |
| PNAM | float32 | `priority` |
| BNAM | formID | `owningBranch` (DLBR) |
| QNAM | formID | `owningQuest` (QUST) |
| DATA | 4 bytes | repeat behavior, category, legacy numeric subtype |
| SNAM | char[4] | authoritative `subtype`, such as `HELO` or `CUST` |
| TIFC | uint32 | allocation hint `declaredInfoCount` |

DIAL DATA is uint8 `doAllBeforeRepeating`, uint8 category and uint16 legacy subtype.
Categories 0 through 7 are player, favor, scene, combat, favors, detection, service and
miscellaneous; unknown values are retained. TIFC is never trusted over the child records.

## INFO topic response set

INFO carries selection flags and conditions plus zero or more response runs. DATA is the
legacy shape: uint16 dialogue tab, uint16 flags, float32 reset days. ENAM is the current
shape: uint16 flags plus a uint16 mapping 0...65535 to 0...24 reset hours. OpenSky
normalizes either shape to `resetHours`.

The flag word exposes every xEdit bit from 0 through 14: goodbye, random, say once,
requires player activation, info refusal, random end, invisible continue, walk away,
walk-away invisible in menu, force subtitle, can move while greeting, no LIP file,
requires post-processing, audio-output override and spends favor points.

| field | type | decoded |
| --- | --- | --- |
| EDID | zstring | `editorID` |
| VMAD | struct | attached scripts plus the decoded INFO result-fragment tail |
| DATA/ENAM | struct | flags, legacy tab and normalized reset hours |
| TPIC | formID | `previousTopic` |
| PNAM | formID | `previousInfo` |
| CNAM | uint8 | favor level none/small/medium/large |
| TCLT | formID | repeated follow-up `topicLinks` |
| DNAM | formID | `sharedInfo` whose response data replaces this record's |
| CTDA/CIS1/CIS2/CITC | condition run | `conditions` |
| RNAM | lstring | player `prompt` override |
| ANAM | formID | forced `speaker` NPC_ |
| TWAT | formID | walk-away DIAL |
| ONAM | formID | audio-output override |

TRDT opens a response. NAM1, NAM2, NAM3, SNAM and LNAM extend the open response until the
next TRDT or end of record; a field arriving without an open response is tallied as an
orphan rather than attached to another group.

| TRDT offset | type | decoded |
| --- | --- | --- |
| 0x00 | uint32 | emotion: neutral, anger, disgust, fear, sad, happy, surprise, puzzled |
| 0x04 | uint32 | emotion value, 0...100 |
| 0x08 | 4 bytes | unused |
| 0x0C | uint8 + 3 unused | response number |
| 0x10 | formID | SNDR sound, null allowed |
| 0x14 | uint8 + 3 unused | use emotion animation |

NAM1 is the ILSTRINGS-backed subtitle, NAM2 actor notes, NAM3 edits, and SNAM/LNAM the
speaker/listener IDLE animations. The latter two use the same field signatures as other
INFO-level concepts only inside an open TRDT run, which is why the decoder keeps explicit
group state.

## VTYP voice type and NPC_ voice link

VTYP has EDID plus one-byte DNAM flags: 0x01 allows default dialogue and 0x02 is female.
The editor ID is the directory identity later voice-path construction consumes.

NPC_`VTCK` is a VTYP FormID. It belongs to the ACBS `useTraits` template group alongside
gender, race, skin and head parts. `ActorTemplateResolver.resolve(base:)` therefore returns
it as an `ActorSourcedField<FormID?>`, retaining both the chosen voice and the NPC_ record
that supplied it.

## DialogueStore traversal and indexes

`DialogueStore` descends the DIAL top group rather than flattening it. For each type-7
child group it decodes direct INFO records under `parentFormID`, preserving their file
order. It provides topics by FormID and case-insensitive editor ID, per-topic INFO arrays,
INFOs by FormID, and VTYPs by FormID and case-insensitive editor ID. Structurally
unreadable records increment `skippedRecordCount`.

`CellProviderIndexes` builds the store beside `QuestStore`, and
`BuilderCellSceneProvider` exposes it through `DialogueDataProviding`. Since issue #426 the
store also resolves every INFO to a session-stable `ReferenceKey` — said-state is filed per
response and a save must not key it off a load-order-relative FormID — which is why the
initializer takes the plugin's file name the way `QuestStore`'s does.

## Defensive decode and vanilla sweep

Unknown, wrong-size and orphan response fields are recorded in `DialogueTally`; they do
not throw away a usable record. Only the wrong record type or unreadable ESM field
container throws. Synthetic tests cover every record model, compressed DIAL and INFO,
ordered child groups, ILSTRINGS resolution, malformed fields and actor voice inheritance.

The env-gated `DialogueRealDataTests` sweep decoded the five vanilla masters on
2026-08-09 with zero record failures and zero store record skips:

| plugin | DIAL | INFO | VTYP |
| --- | ---: | ---: | ---: |
| Skyrim.esm | 15037 | 31465 | 143 |
| Update.esm | 90 | 139 | 0 |
| Dawnguard.esm | 2038 | 3457 | 21 |
| HearthFires.esm | 482 | 1706 | 0 |
| Dragonborn.esm | 2197 | 4421 | 19 |
| total | 19844 | 41188 | 183 |

The pinned skip tally is 1,365 alias-object script properties and Skyrim.esm's legacy script
fields: 861 NEXT, 1,662 QNAM and 1,722 SCHR, all recorded rather than interpreted. The 7,661
INFO fragment tails the sweep skipped for issue #204 are decoded since issue #426 and are
counted rather than skipped: 7,661 tails carrying 8,009 result-script fragments, layout in
[Papyrus attachment data](/formats/vmad.md). The report is under the gitignored local run
directory `logs/dialogue-sweep/<stamp>/`.
