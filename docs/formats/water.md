---
type: File Format
title: Exterior water records
description: CELL, WRLD, and WATR fields that place and color exterior water.
tags: [format, plugin, water, cell, worldspace]
---

# Exterior water records

OpenSky draws exterior water as one flat plane per cell. This page lists the record fields
it reads for that plane. The record container is described in
[ESM/ESP plugin container](/formats/esm.md).

Sources:

- UESP pages for [CELL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
  [WRLD](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD), and
  [WATR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WATR).
- xEdit `dev-4.1.6`, `Core/wbDefinitionsTES5.pas`: `CELL XCLW`/`XCWT`, `WRLD`
  `DNAM`/`NAM2`/`PNAM`, and the 228- and 232-byte `WATR DNAM`. Used to confirm offsets and
  the parent flags.

## CELL

Bit `0x0002` of `CELL DATA` means the cell has water. Without it, there is no plane.

| Field | Type | Meaning |
| --- | --- | --- |
| `XCLW` | float32 | Water height for this cell |
| `XCWT` | FormID | Water type (`WATR`) for this cell |

Three `XCLW` bit patterns mean "no water": `0x7F7FFFFF` (documented), and `0x4F7FFFC9` and
`0xCF000000`, which the Creation Kit writes by mistake. These values do not fall back to the
worldspace. Other values that are not finite numbers are rejected. A cell with no `XCLW`
uses the worldspace water height.

## WRLD defaults and parents

`WRLD DNAM` is two float32 values: default land height, then default water height. `NAM2`
is the default `WATR` FormID. `WNAM` points at a parent worldspace. `PNAM` is a uint16 of
flags that say what to take from the parent:

- `0x0001`: use the parent's land data, so `DNAM` and its water height.
- `0x0008`: use the parent's water data, so `NAM2`.

OpenSky follows parents by FormID and stops on a loop. If the parent has no value, there is
no default. The `CELL` fields always win over the worldspace values.

## WATR colors

In Skyrim SE, `WATR DNAM` is 228 or 232 bytes. OpenSky reads only these two sizes and skips
any other. Both sizes share these colors:

| `DNAM` offset | Bytes | Meaning |
| --- | --- | --- |
| 40 | RGBX | Shallow color |
| 44 | RGBX | Deep color |
| 48 | RGBX | Reflection color |

Each byte maps to 0...1. OpenSky does not read the other fields (fog, noise, displacement,
textures). A cell with a missing or unknown `WATR` gets fixed fallback colors.

Real data check: `WhiterunExterior17` (Tamriel 5,-4) has water and gives one plane.
