---
type: File Format
title: Interior lighting records
description: CELL XCLL, LGTM DATA and DALC, LIGH DATA and FNAM, and REFR light overrides.
tags: [format, plugin, cell, lighting, fog]
---

# Interior lighting records

These records set the light and fog of an interior cell, and the placed lights in it.

Sources:

- [UESP CELL and LGTM](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL)
- [UESP LIGH](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LIGH)
- [xEdit TES5 definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
- [xEdit common definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)

## CELL XCLL

`XCLL` is 92 bytes in current Skyrim SE records. The first 40 bytes are required. A shorter
record may stop at any field boundary after that. A cut inside the directional ambient
block does not move the offsets of later fields.

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
| 64 | 4 | Specular RGBX. Read, not used |
| 68 | 4 | Fresnel power. Read, not used |
| 72 | 4 | Far fog RGBX |
| 76 | 4 | Fog maximum, float32 |
| 80 | 4 | Light fade begin, float32 |
| 84 | 4 | Light fade end, float32 |
| 88 | 4 | Inheritance flags, uint32 |

The rotations are degrees, not radians. Real data shows this: `WhiteRunIntLightingTemplate`
stores XY = 180. As degrees this gives the expected direction.

## Lighting templates (LTMP and LGTM)

`CELL LTMP` is a FormID of a lighting template (`LGTM`). Each inheritance flag in `XCLL`
says "take this value from the template":

| Bit | Value | Bit | Value |
| --- | --- | --- | --- |
| `0x001` | Ambient | `0x040` | Directional fade |
| `0x002` | Directional | `0x080` | Fog clip |
| `0x004` | Fog colors | `0x100` | Fog power |
| `0x008` | Fog near | `0x200` | Fog maximum |
| `0x010` | Fog far | `0x400` | Light fade distances |
| `0x020` | Directional rotation | | |

When one source is missing a value, OpenSky uses the other source.

`LGTM DATA` uses the same offsets 0 to 87 as `XCLL`. Offset 88 is reserved, not flags.
`LGTM DALC` is 32 bytes: six directional ambient RGBX values, specular RGBX, and Fresnel
float32. When `DALC` exists, it replaces the directional ambient block of `DATA`.

## LIGH

`DATA` is exactly 48 bytes:

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 4 | Time, int32 |
| 4 | 4 | Radius, uint32 |
| 8 | 4 | Color RGBX |
| 12 | 4 | Flags, uint32 |
| 16 | 4 | Falloff exponent, float32 |
| 20 | 4 | FOV, float32. Skipped |
| 24 | 4 | Near clip, float32. Skipped |
| 28 | 4 | Flicker period, float32 |
| 32 | 4 | Flicker intensity amplitude, float32 |
| 36 | 4 | Flicker movement amplitude, float32 |
| 40 | 8 | Value (uint32) and weight (float32). Skipped |

`FNAM` is the fade, a float32. Without it the fade is 1.

OpenSky draws omni lights, including shadow omni lights. It does not draw a light with any
of these: flag `0x004` (negative), `0x200` (spot), `0x400` (shadow spot), `0x020` (off by
default), or a radius that is not a positive finite number.

The animation flags are `0x008` flicker, `0x040` flicker slow, `0x080` pulse, and `0x100`
pulse slow (xEdit dev-4.1.6). OpenSky reads the period as seconds per cycle, and a slow flag
doubles it. A flickering light gets smooth random brightness and moves by up to the movement
amplitude. A pulsing light follows a sine wave. The brightness swings by the intensity
amplitude, clamped to 0 to 1. [WARNING] The curve shapes, the period unit, and the slow factor
are OpenSky choices, not checked against the game. xEdit shows the period with a 0.01
display scale, so the stored unit may differ.

`World > Environment > Actor animation` has the "Flickering lights" switch and counts the
animated lights. It is the player setting `rendering.lightAnimation`, also on the launcher's
Graphics page.

## Placed lights (REFR)

A `REFR` `NAME` can point at a `LIGH` directly. Or `XEMI` can name a `LIGH` that a mesh
emits. When both exist, `XEMI` wins. `XRDS` (float32) overrides the radius. Without `XRDS`,
the radius comes from the winning `LIGH`. The position comes from the `REFR DATA`.
