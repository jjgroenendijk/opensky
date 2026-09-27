---
type: File Format
title: Acoustic space (ASPC)
description: Skyrim SE ASPC record fields, how interiors get ambient sound, and the RDAT
  name clash with REGN.
tags: [format, plugin, audio, sound]
---

# Acoustic space (ASPC)

An `ASPC` record gives an interior cell its ambient sound. The cell points at an ASPC
through its `XCAS` field. The ASPC gives one ambient sound, and it can also borrow the sound
area of a region (`REGN`). See [world SFX and ambience](/engine/world-sfx.md) for how the
sound is played.

References: UESP [`ASPC`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASPC), and
xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
lines 5401-5407.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `OBND` | object bounds | Skipped |
| `SNAM` | FormID | Ambient sound, points at `SNDR` |
| `RDAT` | FormID | Region whose sound area is borrowed, points at `REGN` |
| `BNAM` | FormID | Reverb, points at `REVB`. Read but not used |

`SNAM`, `RDAT`, and `BNAM` are read only when they are exactly 4 bytes. Other sizes are
ignored.

## RDAT means two things

`ASPC.RDAT` is a 4-byte FormID. `REGN.RDAT` has the same name but is an 8-byte area header
(see [weather records](/formats/weather.md)). The two decoders read them separately.

The Creation Kit calls the ASPC field "Use Sound from Region (Interiors Only)". Interior
cells have no regions of their own (`XCLR`). This field lets an interior use the sound area
(type 7) of a region anyway.

The full chain is `CELL.XCAS -> ASPC.SNAM` for the direct sound, and
`ASPC.RDAT -> REGN -> RDSA` for the borrowed sounds.
