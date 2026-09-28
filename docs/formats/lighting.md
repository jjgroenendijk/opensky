---
type: File Format
title: Interior lighting records
description: CELL XCLL, LGTM DATA and DALC, LIGH DATA and FNAM, and REFR light overrides.
tags: [format, plugin, cell, lighting, fog]
---

# Interior lighting records

These records feed interior lighting and fog.

Sources: UESP [CELL and LGTM](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
UESP [LIGH](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LIGH), xEdit
[TES5 definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and [common definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).

## CELL XCLL

`XCLL` is 92 bytes in current SSE records. The first 40 bytes are required. After that, the
field may end early, but only at a field boundary.

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 4 | Ambient RGBX |
| 4 | 4 | Directional RGBX |
| 8 | 4 | Near fog RGBX |
| 12 | 4 | Fog near, float32 |
| 16 | 4 | Fog far, float32 |
| 20 | 4 | Directional XY rotation, int32 degrees |
| 24 | 4 | Directional Z rotation, int32 degrees |
| 28 | 4 | Directional fade, float32 |
| 32 | 4 | Fog clip distance, float32 |
| 36 | 4 | Fog power, float32 |
| 40 | 24 | Directional ambient +X, -X, +Y, -Y, +Z, -Z, RGBX each |
| 64 | 4 | Specular RGBX, not used |
| 68 | 4 | Fresnel power, not used |
| 72 | 4 | Far fog RGBX |
| 76 | 4 | Fog maximum, float32 |
| 80 | 4 | Light fade begin, float32 |
| 84 | 4 | Light fade end, float32 |
| 88 | 4 | Inheritance flags, uint32 |

The rotation is in degrees, not radians. Proof: `WhiteRunIntLightingTemplate` in
`Skyrim.esm` stores XY = 180. Read as degrees, the light points the expected way.

## LTMP and inheritance

`LTMP` is a FormID of a lighting template (`LGTM`). Each inheritance bit takes one value
from the template instead of the cell:

| Bit | Value |
| --- | --- |
| `0x001` | Ambient |
| `0x002` | Directional |
| `0x004` | Fog colors |
| `0x008` | Fog near |
| `0x010` | Fog far |
| `0x020` | Directional rotation |
| `0x040` | Directional fade |
| `0x080` | Fog clip |
| `0x100` | Fog power |
| `0x200` | Fog maximum |
| `0x400` | Light fade distances |

When one source lacks a value, the other source is used.

## LGTM DATA and DALC

`LGTM DATA` uses the same offsets as `XCLL` for bytes 0 to 87. Offset 88 is reserved, not
flags. `DALC` is 32 bytes: six directional-ambient RGBX colors, a specular RGBX, and a
Fresnel float32. When `DALC` exists, it replaces the directional-ambient block in `DATA`.

## LIGH

`DATA` is exactly 48 bytes:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 4 | Time, int32 |
| 4 | 4 | Radius, uint32 |
| 8 | 4 | Color RGBX |
| 12 | 4 | Flags, uint32 |
| 16 | 4 | Falloff exponent, float32 |
| 20 | 28 | FOV, near clip, animation values, value, weight. Not read |

`FNAM` is a fade float32. Without it, fade is 1.

OpenSky renders omni lights, including shadow omni lights. These lights are left out:
negative (`0x004`), spot (`0x200`), shadow spot (`0x400`), off by default (`0x020`), and
lights with a radius that is not positive or not finite. Animation flags are read but lights
do not animate yet.

## REFR overrides

A `REFR` whose `NAME` is a `LIGH` places that light. A `REFR` can instead carry `XEMI`,
which names a `LIGH` that a mesh emits. `XEMI` wins. `XRDS` (float32) overrides the radius.
Without `XRDS`, the radius comes from the winning `LIGH`. The placement `DATA` gives the
position.
