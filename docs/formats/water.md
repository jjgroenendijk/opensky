---
type: File Format
title: Exterior water records
description: CELL, WRLD, and WATR fields that place and color exterior water.
tags: [format, plugin, water, cell, worldspace]
---

# Exterior water records

OpenSky reads only the fields it needs for a flat water plane in an exterior cell. The
record container is described in [ESM/ESP plugin container](/formats/esm.md).

Sources: UESP pages for [CELL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
[WRLD](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD), and
[WATR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WATR). xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`, confirmed the offsets and the parent flags.

## CELL

Bit `0x0002` of `CELL DATA` means the cell has water. Without it there is no water plane.

| Field | Type | Meaning |
| --- | --- | --- |
| `XCLW` | float32 | Water height for this cell |
| `XCWT` | FormID | Water type (`WATR`) for this cell |

Three `XCLW` bit patterns mean "no water": `0x7F7FFFFF` (documented), and `0x4F7FFFC9` and
`0xCF000000` (written by a Creation Kit bug). These do not fall back to the worldspace
value. Other non-finite values are rejected. A missing `XCLW` uses the worldspace water
height.

## WRLD defaults and parents

- `DNAM` is two float32 values: default land height, then default water height.
- `NAM2` is the default `WATR` FormID.
- `WNAM` points at the parent worldspace.
- `PNAM` is a uint16 of flags that say what to take from the parent:
  - `0x0001`: use the parent's land data. This includes the default water height.
  - `0x0008`: use the parent's water data. This is `NAM2`.

OpenSky follows parents by FormID and stops on a loop. If a parent is missing, there is no
default. `CELL XCLW` and `XCWT` always win over worldspace values.

## WATR colors

In Skyrim SE, `WATR DNAM` is 228 or 232 bytes. OpenSky accepts only those two sizes. Both
share three colors:

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 40 | RGBX | Shallow color |
| 44 | RGBX | Deep color |
| 48 | RGBX | Reflection color |

Each byte is scaled to 0...1. The other fields (fog, noise, displacement) are not read. A
missing or unknown `WATR` uses fixed fallback colors.

Real-data example: `WhiterunExterior17` (Tamriel 5,-4) has water and gives one plane.
