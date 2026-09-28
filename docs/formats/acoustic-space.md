---
type: File Format
title: Acoustic space (ASPC)
description: ASPC record fields, how they give interiors ambient sound, and the RDAT name clash
  with REGN.
tags: [format, plugin, audio, sound]
---

# Acoustic space (ASPC)

An interior `CELL` points at an `ASPC` record through `XCAS`. The `ASPC` gives the interior
its ambient sound for [world sounds and ambience](/engine/world-sfx.md).

Sources: UESP [`ASPC`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASPC), and xEdit
`dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
lines 5401-5407.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID, optional |
| `OBND` | object bounds | Not read |
| `SNAM` | FormID | Ambient sound, points at `SNDR` |
| `RDAT` | FormID | Region whose sound area is borrowed, points at `REGN` |
| `BNAM` | FormID | Reverb, points at `REVB`. Read but not used |

## RDAT means two things

`ASPC.RDAT` is a 4-byte FormID. `REGN.RDAT` is an 8-byte area header (see
[weather records](/formats/weather.md)). The signature is the same, but the layout is not.
Each decoder reads `RDAT` by its own record's rules.

The Creation Kit calls the `ASPC` field "Use Sound from Region (Interiors Only)". Interior
cells have no `XCLR` regions. This field lets an interior borrow a region's type-7 sound area.
The runtime looks the region up through the [weather store](/engine/weather.md), which
already indexes `REGN`.

The full chain is `CELL.XCAS -> ASPC.SNAM`, plus `ASPC.RDAT -> REGN` for the borrowed area.

## Bad input

`SNAM`, `RDAT`, and `BNAM` are read only when they are exactly 4 bytes. Any other size is
ignored. Unknown fields are skipped. A missing field gives `nil`.
