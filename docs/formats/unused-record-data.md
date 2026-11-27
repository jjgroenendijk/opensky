---
type: File Format
title: Record data the game does not use
description: The record fields, flag bits, and enum values that plugins carry and the game does
  not read while it runs, with the source for each, and how the gap report counts them.
tags: [format, esm, coverage]
---

# Record data the game does not use

A plugin record carries some data that changes nothing in play. The Creation Kit writes it for
itself, or an older version of the format needed it. `RecordDataUnused` lists these fields
with one reason each. The [gap report](/tools/gaps.md) counts them as done, as it does for
[settings the game never uses](/formats/gmst.md#settings-the-game-never-uses).

A field goes on the list only when a source says the game does not use it. A field whose use
is not known stays off the list, even if OpenSky does not read it. The same list holds flag bits
and enum values.

## Reasons

| Reason | Examples | Source |
| --- | --- | --- |
| Record identity | `Keyword.formID`, `LeveledList.recordType` | A copy of the record header's form ID or type. Stores key each record by its header |
| List count | `KSIZ`, `COCT`, `LLCT`, `TIFC`, `IDLC`, `CITC`, `QNAM` of `SMQN`, `XWCN`, the count byte of `XRMR` | The list that follows holds the data. UESP "Mod File Format/DIAL": `TIFC` "is used to preallocate memory for the topic's info list, but shouldn't be required" |
| Layout | `VMAD` version and object format, `XPPA`, the `CAMS` `DATA` size | They say how the bytes after them are laid out. UESP "Mod File Format/VMAD Field" |
| Editor only | `INFO` `NAM2` and `NAM3`, `QUST` `ANAM` and `FLTR`, `DLVW`, the `SCEN` phase editor width, `TES4` `INTV` | UESP "Mod File Format/INFO": notes and edits, "the game doesn't load this". UESP "Mod File Format/QUST": `ANAM` "is used by CK when creating a new alias", `FLTR` is the object window filter. UESP "Mod File Format/DLVW": "strictly a UI". UESP "Mod File Format/TES4": `INTV` is "used only for TagifyMasterfile command-line option of the CK". xEdit `wbDefinitionsTES5.pas`: "Editor Width" |
| Legacy | `SOUN` `FNAM` and `SNDD`, the `INFO` `DATA` dialogue tab and `SCHR`, the `DIAL` `DATA` subtype, `CELL` `LNAM`, `TES4` master `DATA`, `WATR` `MNAM`, the unused `NPC_` `AIDT` byte | UESP "Mod File Format/SOUN": "FNAM and SNDD are no longer used". UESP "Mod File Format/INFO": the dialogue tab "is presumably unused", and `SCHR` is "old scripting info"; Skyrim runs Papyrus only. UESP "Mod File Format/DIAL": the `DATA` subtype is "unused if SNAM is present". UESP "Mod File Format/TES4": master `DATA` "may be vestigial". xEdit: `CELL` `LNAM` "leftover flags, they are now in XCLC", and the `AIDT` byte and `WATR` `MNAM` are unused |
| Dropped at load | The editor ID of `REFR`, `ACHR`, `INFO`, `TXST`, `IPCT`, `OTFT`, `LGTM`, `WATR`, `SOPM`, `MATO`, `GRAS`, `ASPC`, `VOLI`, `DEBR`, and `FSTP`; `OBND` on `SPEL`, `ENCH`, `DUAL`, `TXST`, `GRAS`, `ARTO`, and the leveled lists; `SCEN` `INAM`, `LCTN` `CNAM`, `REGN` `RCLR`; `TES4` `INCC` | The game reads each one and then throws it away, keeps it without a reader, or uses it only to reserve memory. No rule can find a form of these types by editor ID, and none of these bound types becomes a placed object |
| No effect | `INFO` `CNAM` favour level and its flag `0x4000` | The only rule that reads them never runs ([dialogue](/formats/dialogue.md)) |

Sources: <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DIAL>,
<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO>,
<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/QUST>,
<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DLVW>,
<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SOUN>,
<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TES4>,
<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field>, and xEdit
`wbDefinitionsTES5.pas`.

The decoders still read every one of these fields, so the "Record types" area stays exact.
