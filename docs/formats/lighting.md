---
type: File Format
title: Interior lighting records
description: CELL XCLL, LGTM DATA/DALC, LIGH DATA/FNAM, and REFR light overrides.
tags: [format, plugin, cell, lighting, fog]
timestamp: 2026-07-19T00:00:00Z
---

# Interior lighting records

M3.7 inputs for interior forward lighting. Impl:
`opensky/Formats/ESM/Records/CellLighting.swift`, `LightRecord.swift`, and
`PlacedReference.swift`.

Sources:

* [UESP CELL/LGTM](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL)
* [UESP LIGH](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LIGH)
* [xEdit TES5 definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
* [xEdit common definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)

## CELL XCLL + LTMP

XCLL is 92 bytes in current SSE records. Decoder requires fixed 40-byte prefix, then
accepts tails truncated only at known field boundaries. Partial directional-ambient data
does not shift later offsets.

| offset | bytes | value |
| ------ | ----: | ----- |
| 0 | 4 | ambient RGBX |
| 4 | 4 | directional RGBX |
| 8 | 4 | near-fog RGBX |
| 12 | 4 | fog near float32 |
| 16 | 4 | fog far float32 |
| 20 | 4 | directional XY rotation int32 degrees |
| 24 | 4 | directional Z rotation int32 degrees |
| 28 | 4 | directional fade float32 |
| 32 | 4 | fog clip distance float32 |
| 36 | 4 | fog power float32 |
| 40 | 24 | directional ambient +X/-X/+Y/-Y/+Z/-Z RGBX |
| 64 | 4 | specular RGBX; decoded then unused |
| 68 | 4 | Fresnel power; decoded then unused |
| 72 | 4 | far-fog RGBX |
| 76 | 4 | fog maximum float32 |
| 80 | 4 | light fade begin float32 |
| 84 | 4 | light fade end float32 |
| 88 | 4 | inheritance flags uint32 |

LTMP is a FormID link to LGTM. Inheritance bits select LGTM per field: 0x001 ambient,
0x002 directional, 0x004 fog colors, 0x008 fog near, 0x010 fog far, 0x020 directional
rotation, 0x040 directional fade, 0x080 fog clip, 0x100 fog power, 0x200 fog maximum,
0x400 light fade distances. Optional missing values fall back to whichever source exists.

Directional rotation probe: Skyrim.esm `WhiteRunIntLightingTemplate` stores XY = 180.
Treating int32 values as degrees produces its expected direction; radians would collapse
modulo 2π and is rejected.

## LGTM DATA + DALC

LGTM DATA shares XCLL offsets 0-87; offset 88 is reserved, not inheritance. DALC is 32
bytes: six directional-ambient RGBX values, specular RGBX, Fresnel float32. DALC replaces
DATA's directional-ambient block when present. Specular + Fresnel remain parsed/ignored
until material support lands.

## LIGH

DATA is exact 48 bytes:

| offset | bytes | value |
| ------ | ----: | ----- |
| 0 | 4 | time int32 |
| 4 | 4 | radius uint32 |
| 8 | 4 | color RGBX |
| 12 | 4 | flags uint32 |
| 16 | 4 | falloff exponent float32 |
| 20 | 28 | FOV, near clip, animation values, value, weight; skipped |

FNAM is fade float32; absent -> 1. M3.7 accepts omni variants, including shadow omni.
Negative (0x004), spot (0x200), shadow spot (0x400), off-by-default (0x020), non-positive,
or non-finite-radius lights do not enter the render scene. Other animation flags decode
but do not animate yet.

## REFR overrides

REFR NAME may point directly to LIGH. XEMI may instead name a LIGH emitter on a drawable
base; XEMI wins. XRDS float32 overrides radius. Missing XRDS uses direct base LIGH radius
or emitted LIGH radius from whichever source won. Placement DATA supplies world position.

## Robustness + tests

Synthetic tests cover full + truncated XCLL, LTMP, DALC override, per-field inheritance,
exact LIGH size/flags/FNAM, XRDS/XEMI, unsupported shapes, and stable nearest-light
selection. No game records or extracted bytes enter fixtures.
