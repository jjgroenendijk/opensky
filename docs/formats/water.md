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

## WATR colors and surface

In Skyrim SE, `WATR DNAM` is 228 or 232 bytes. OpenSky reads only these two sizes and skips
any other. Both sizes share these offsets. Each color byte maps to 0...1.

| `DNAM` offset | Type | Meaning |
| --- | --- | --- |
| 16 | float32 | Sun specular power |
| 20 | float32 | Reflectivity amount |
| 24 | float32 | Fresnel amount |
| 32, 36 | float32 | Above-water fog near and far plane |
| 40 | RGBX | Shallow color |
| 44 | RGBX | Deep color |
| 48 | RGBX | Reflection color |
| 100 | float32 x3 | Noise wind direction, one per layer, in degrees |
| 112 | float32 x3 | Noise wind speed, one per layer |
| 172 | float32 x3 | Noise UV scale, one per layer |
| 184 | float32 x3 | Noise amplitude scale, one per layer |
| 196 | float32 | Reflection magnitude |
| 200 | float32 | Sun sparkle magnitude |
| 204 | float32 | Sun specular magnitude |
| 224 | float32 | Sun sparkle power |
| 228 | float32 | Flowmap scale (232-byte size only, not read) |

The rest of `DNAM` (rain and displacement simulation, under-water fog, depth factors) stays
unread. The fields around it, such as opacity, flags, material, sounds, velocities, and noise
texture paths, are read as xEdit dev-4.1.6 names them. The [water renderer](/rendering/water.md)
uses `ANAM` opacity and `NAM0` linear velocity. A cell with a missing or unknown `WATR` gets
fixed fallback colors.

Vanilla values (Skyrim.esm, 2026-10-08): wind directions lie in 0...360, wind speeds in
0.007...0.45, UV scales in 100...10000, amplitudes in 0...1, and sun specular powers in
1000...8400. Rivers such as `RiverWaterFlowNE` (`0E717C`) set `ANAM` 50 and a `NAM0` velocity of
about 3 units per second, and leave `NAM2`-`NAM4` empty. Creeks set `ANAM` 0.

Real data check: `WhiterunExterior17` (Tamriel 5,-4) has water and gives one plane.
