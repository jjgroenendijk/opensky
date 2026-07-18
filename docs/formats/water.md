---
type: File Format
title: Exterior water records
description: CELL, WRLD, and WATR fields used to place and color exterior water.
tags: [format, plugin, water, cell, worldspace]
timestamp: 2026-07-18T00:00:00Z
---

# Exterior water records

Milestone 3.5 decodes only fields needed for a flat exterior-cell water surface. Container
framing follows [ESM/ESP plugin container](/formats/esm.md). Engine mapping lives in
`opensky/Formats/ESM/Records/` + `opensky/World/CellSceneBuilderWater.swift`.

Sources:

* UESP Skyrim Mod File Format pages for
  [CELL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
  [WRLD](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD), and
  [WATR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WATR).
* xEdit `dev-4.1.6`, `Core/wbDefinitionsTES5.pas`: CELL XCLW/XCWT, WRLD
  DNAM/NAM2/PNAM, WATR DNAM 228/232-byte definitions. Used to confirm offsets +
  parent-flag meaning; no xEdit code copied.

## CELL selection

CELL DATA bit `0x0002` means cell has water. Without it, no plane is emitted. Fields:

| field | disk type | meaning |
| --- | --- | --- |
| XCLW | float32 bits | cell water-height override |
| XCWT | formID | cell WATR override |

Three XCLW bit patterns explicitly suppress water: documented `0x7F7FFFFF`, plus CK-bug
values `0x4F7FFFC9` and `0xCF000000`. They do not fall back to WRLD. Other non-finite
floats are rejected defensively. Missing XCLW uses resolved WRLD DNAM water height.

## WRLD defaults + inheritance

WRLD DNAM is two float32 values: default land height, then default water height. NAM2 is
default WATR formID. WNAM links parent WRLD; PNAM uint16 flags choose inherited categories:

* `0x0001` use parent land data -> DNAM, including default water height.
* `0x0008` use parent water data -> NAM2.

Resolution recurses by FormID with cycle defense. Missing requested parent data yields no
default rather than guessing. CELL XCLW/XCWT always win over resolved WRLD values.

## WATR colors

SSE WATR DNAM appears as 228 or 232 bytes. OpenSky accepts only those exact sizes, skips
unknown variants, then reads three RGBX colors shared by both layouts:

| DNAM offset | bytes | engine value |
| --- | --- | --- |
| 40 | RGBX | shallow color |
| 44 | RGBX | deep color |
| 48 | RGBX | reflection color |

RGB bytes normalize to float 0...1. All remaining simulation, fog, displacement, noise,
and texture parameters stay unread. Missing/unknown WATR gets hardcoded visible fallback
colors; disk layout is never inferred.

## Verification

Synthetic decoder tests cover both WATR sizes, unknown-size skip, CELL overrides, all
three no-water sentinels, WRLD defaults, PNAM parent inheritance, and WATR color choice.
Real Skyrim.esm probe 2026-07-18 found nearby `WhiterunExterior17` (Tamriel 5,-4) with
water; shared CLI scene build resolved one plane without parse failure.
