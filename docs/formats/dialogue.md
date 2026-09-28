---
type: File Format
title: Dialogue records (DIAL, INFO, VTYP)
description: Dialogue topics, response records, voice types, and the NPC voice link.
tags: [format, plugin, dialogue, dial, info, vtyp, npc, localization]
---

# Dialogue records (DIAL, INFO, VTYP)

- `DIAL`: a dialogue topic, for example a greeting or a question the player can ask.
- `INFO`: one possible answer to a topic, with its conditions and spoken lines.
- `VTYP`: a voice type, for example `MaleNord`. It names the folder of voice files.

See [dialogue runtime](/engine/dialogue.md) for topic choice and conditions,
[conditions](/formats/conditions.md) for `CTDA`, and [actor records](/formats/actors.md)
for templates.

## Sources

UESP [DIAL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DIAL),
[INFO](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO),
[VTYP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VTYP), and
[NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_). Checked against xEdit
dev-4.1.6 `Core/wbDefinitionsTES5.pas`: `wbRecord(DIAL, ...)` near line 4754,
`wbRecord(VTYP, ...)` near line 6295, `wbRecord(INFO, ...)` near line 7796, and `NPC_ VTCK`
near line 8425.

The sources disagree in two places:

- UESP shows the last two bytes of `DIAL DATA` as a subtype byte and an unused byte. xEdit
  reads them as one uint16 subtype. OpenSky keeps the uint16 as a legacy subtype. It uses
  `SNAM` as the real subtype. Both sources say the subtype numbers changed, and that the
  official tools write `SNAM` after `DATA` to override them.
- `INFO NAM1` is an `ilstring`, not a `dlstring`. UESP says ILSTRINGS holds spoken lines,
  and DLSTRINGS holds books and journal text. A vanilla `NAM1` ID resolves in
  `skyrim_english.ilstrings` and not in the DLSTRINGS table. See
  [string tables](/formats/strings.md).

## DIAL

A `DIAL` record is followed directly by a group of type 7. Its label is the `DIAL` FormID.
Its direct children are the `INFO` records, in order.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Topic text the player sees |
| `PNAM` | float32 | Priority |
| `BNAM` | FormID | Owning branch (`DLBR`) |
| `QNAM` | FormID | Owning quest (`QUST`) |
| `DATA` | 4 bytes | uint8 "do all before repeating", uint8 category, uint16 legacy subtype |
| `SNAM` | char[4] | Subtype, for example `HELO` or `CUST` |
| `TIFC` | uint32 | Count of `INFO` children |

Categories 0 to 7: player, favor, scene, combat, favors, detection, service,
miscellaneous. OpenSky keeps unknown values. It never trusts `TIFC` over the real children.

## INFO

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `VMAD` | struct | Scripts and result fragments. See [VMAD](/formats/vmad.md) |
| `DATA` or `ENAM` | struct | Flags and reset time, below |
| `TPIC` | FormID | Previous topic |
| `PNAM` | FormID | Previous `INFO` |
| `CNAM` | uint8 | Favor level: none, small, medium, large |
| `TCLT` | FormID | A follow-up topic. Repeats |
| `DNAM` | FormID | Shared `INFO` whose responses replace this one's |
| `CTDA`, `CIS1`, `CIS2`, `CITC` | conditions | Conditions |
| `RNAM` | lstring | Player prompt that replaces the topic text |
| `ANAM` | FormID | Speaker (`NPC_`) |
| `TWAT` | FormID | Walk-away topic (`DIAL`) |
| `ONAM` | FormID | Audio output override |

`DATA` is the old shape: uint16 dialogue tab, uint16 flags, float32 reset days. `ENAM` is the
current shape: uint16 flags and a uint16 where 0...65535 maps to 0...24 reset hours.
OpenSky turns both into reset hours.

Flag bits 0 to 14 (xEdit): goodbye, random, say once, requires player activation, info
refusal, random end, invisible continue, walk away, walk away invisible in menu, force
subtitle, can move while greeting, no LIP file, requires post-processing, audio output
override, spends favor points.

### Responses

An `INFO` has zero or more responses. A response is a line of speech. `TRDT` starts a
response. `NAM1`, `NAM2`, `NAM3`, `SNAM`, and `LNAM` belong to the open response until the
next `TRDT` or the end of the record. OpenSky needs to track the open response, because
`SNAM` also appears at the `INFO` level with another meaning. A response field with no open
response is counted and ignored.

| `TRDT` offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint32 | Emotion: neutral, anger, disgust, fear, sad, happy, surprise, puzzled |
| 0x04 | uint32 | Emotion value, 0 to 100 |
| 0x08 | 4 bytes | Unused |
| 0x0C | uint8 + 3 unused | Response number |
| 0x10 | FormID | Sound (`SNDR`). May be null |
| 0x14 | uint8 + 3 unused | Use emotion animation |

`NAM1` is the subtitle (in ILSTRINGS). `NAM2` is actor notes. `NAM3` is edits. `SNAM` and
`LNAM` are the speaker and listener idle animations (`IDLE`).

## VTYP and the NPC voice

`VTYP` has an `EDID` and a one-byte `DNAM` of flags: `0x01` allow default dialogue, `0x02`
female. The editor ID is the name of the voice file folder.

`NPC_ VTCK` is a `VTYP` FormID. It belongs to the "use traits" template group, with gender,
race, skin, and head parts. So a template NPC can supply it. See
[actor records](/formats/actors.md).

## Errors

Unknown fields, fields of the wrong size, and response fields with no response are counted.
They do not throw away a usable record. Only a wrong record type or a broken field container
is an error.

## Vanilla counts

All five vanilla masters decode with no record errors.

| Plugin | DIAL | INFO | VTYP |
| --- | ---: | ---: | ---: |
| Skyrim.esm | 15037 | 31465 | 143 |
| Update.esm | 90 | 139 | 0 |
| Dawnguard.esm | 2038 | 3457 | 21 |
| HearthFires.esm | 482 | 1706 | 0 |
| Dragonborn.esm | 2197 | 4421 | 19 |

`Skyrim.esm` also has old script fields that OpenSky counts but does not read: `NEXT`,
`QNAM`, and `SCHR`.
