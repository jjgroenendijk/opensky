---
type: File Format
title: Dialogue records (DIAL, INFO, VTYP)
description: Dialogue topics, response records, voice types, and the NPC_ voice link.
tags: [format, plugin, dialogue, dial, info, vtyp, npc, localization]
---

# Dialogue records (DIAL, INFO, VTYP)

- `DIAL` is a dialogue topic, such as a greeting or a player choice.
- `INFO` is one possible answer inside a topic. It has conditions and one or more lines.
- `VTYP` is a voice type. Its editor ID names the folder of voice files.

The runtime is on the [dialogue](/engine/dialogue.md) page. Conditions are on the
[conditions](/formats/conditions.md) page. Actor templates are on the
[actor records](/formats/actors.md) page.

Sources: UESP [DIAL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DIAL),
[INFO](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO),
[VTYP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VTYP), and
[NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_). Checked against xEdit
`dev-4.1.6` `Core/wbDefinitionsTES5.pas`: `wbRecord(DIAL, ...)` near line 4754,
`wbRecord(VTYP, ...)` near line 6295, `wbRecord(INFO, ...)` near line 7796, and `NPC_ VTCK`
near line 8425.

## Where the sources disagree

- `DIAL DATA` last two bytes. UESP says a subtype byte and an unused byte. xEdit reads one
  uint16 subtype. OpenSky keeps the uint16 as a legacy value. `SNAM` is the real subtype:
  both sources say subtype numbers moved, and the official tools write `SNAM` after `DATA`
  to override it.
- `INFO NAM1` table. UESP calls it an `ilstring`, and ILSTRINGS holds conversation
  subtitles. DLSTRINGS holds books and journal text. A real `NAM1` ID was checked: it
  resolves in `skyrim_english.ilstrings`, not in DLSTRINGS. So OpenSky looks up `NAM1` in
  `.ilstrings`.

## DIAL topic

A `DIAL` record is followed by a group of type 7. The group label is the `DIAL` FormID, and
the group's records are the topic's `INFO` records, in order.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Topic text the player sees |
| `PNAM` | float32 | Priority |
| `BNAM` | FormID | Owning branch (`DLBR`) |
| `QNAM` | FormID | Owning quest (`QUST`) |
| `DATA` | 4 bytes | uint8 "do all before repeating", uint8 category, uint16 legacy subtype |
| `SNAM` | char[4] | Subtype, such as `HELO` or `CUST` |
| `TIFC` | uint32 | Number of `INFO` records. A hint only |

Categories 0 to 7: player, favor, scene, combat, favors, detection, service, miscellaneous.
OpenSky counts the real child records and never trusts `TIFC`.

## INFO response set

The flags and reset time come in one of two shapes:

- `DATA` (old): uint16 dialogue tab, uint16 flags, float32 reset days.
- `ENAM` (current): uint16 flags, then uint16 reset time where 0 to 65535 maps to 0 to 24
  hours.

OpenSky turns both into reset hours.

Flag bits 0 to 14 (xEdit names): goodbye, random, say once, requires player activation, info
refusal, random end, invisible continue, walk away, walk away invisible in menu, force
subtitle, can move while greeting, no LIP file, requires post-processing, audio output
override, spends favor points.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `VMAD` | struct | Scripts and result fragments (see [VMAD](/formats/vmad.md)) |
| `DATA` or `ENAM` | struct | Flags and reset time |
| `TPIC` | FormID | Previous topic |
| `PNAM` | FormID | Previous `INFO` |
| `CNAM` | uint8 | Favor level: none, small, medium, large |
| `TCLT` | FormID | Follow-up topic. Repeats |
| `DNAM` | FormID | Shared `INFO` whose lines replace this record's lines |
| `CTDA`, `CIS1`, `CIS2`, `CITC` | conditions | Conditions |
| `RNAM` | lstring | Player prompt override |
| `ANAM` | FormID | Forced speaker (`NPC_`) |
| `TWAT` | FormID | Walk-away topic |
| `ONAM` | FormID | Audio output override |

## Response lines

`TRDT` starts one line. `NAM1`, `NAM2`, `NAM3`, `SNAM`, and `LNAM` belong to the open line
until the next `TRDT` or the end of the record. `SNAM` also exists at the record level with
another meaning, so the decoder must track whether a line is open. A line field with no open
line is counted and dropped.

| `TRDT` offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint32 | Emotion: neutral, anger, disgust, fear, sad, happy, surprise, puzzled |
| 0x04 | uint32 | Emotion value, 0 to 100 |
| 0x08 | 4 bytes | Unused |
| 0x0C | uint8 + 3 unused | Response number |
| 0x10 | FormID | Sound (`SNDR`), may be null |
| 0x14 | uint8 + 3 unused | Use emotion animation |

- `NAM1`: subtitle, an ILSTRINGS ID.
- `NAM2`: actor notes.
- `NAM3`: edits.
- `SNAM`, `LNAM`: speaker and listener idle animations.

## VTYP and the NPC_ voice

`VTYP` has an `EDID` and a one-byte `DNAM`: `0x01` allows default dialogue, `0x02` is female.
The editor ID is the voice folder name.

`NPC_ VTCK` is a `VTYP` FormID. It belongs to the "use traits" template group, together with
sex, race, skin, and head parts. So a templated actor takes its voice from the template that
supplies its traits (see [actor records](/formats/actors.md)).

## Store and identity

Topics are found by FormID or by editor ID (case-insensitive). Each topic keeps its `INFO`
records in file order.

Each `INFO` also gets a session-stable reference key. Said-state (which lines were already
spoken) is saved per line, so it must not use a FormID that depends on load order.

## Bad input

Unknown fields, fields with the wrong size, and orphan line fields are counted. They do not
throw away a usable record. Only a wrong record type or a broken field container is an
error. All vanilla masters decode with no failures.
