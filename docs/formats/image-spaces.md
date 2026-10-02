---
type: File Format
title: Image space records
description: Skyrim SE IMGS image spaces and IMAD image-space adapters with their keyframe channels.
tags: [format, plugin, rendering]
---

# Image space records

`IMGS` holds the post-process settings of a place or a weather: HDR, color grading, tint,
and depth of field. `IMAD` animates those settings over time, for example the flash of a
spell hit.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## IMGS

| Field | Size | Meaning |
| --- | --- | --- |
| `ENAM` | 56 | Older 14-float block, kept as floats |
| `HNAM` | 36 | HDR: eye-adapt speed, bloom blur radius, bloom threshold, bloom scale, receive-bloom threshold, white, sunlight scale, sky scale, eye-adapt strength |
| `CNAM` | 12 | Cinematic: saturation, brightness, contrast |
| `TNAM` | 16 | Tint: amount, then RGB |
| `DNAM` | 12 or 16 | Depth of field: strength, distance, range; the 16-byte form adds 2 unnamed bytes and a uint16 sky blur radius |

505 records: `DNAM` is 12 or 16 bytes.

## IMAD header

`DNAM` is 244 bytes in all 264 records.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | Animatable |
| 4 | float | Duration |
| 8 | 34 uint32 | Keyframe counts of the 17 HDR channels, multiply then add |
| 144 | 8 uint32 | Counts of the 4 cinematic channels, multiply then add |
| 176 | uint32 | Tint count |
| 180 | 5 uint32 | Counts: blur radius, double vision, radial blur strength, ramp up, start |
| 200 | uint32 | Radial blur uses target |
| 204 | 2 floats | Radial blur center |
| 212 | 3 uint32 | Counts: DoF strength, distance, range |
| 224 | uint8 | DoF uses target |
| 225 | uint8 | DoF flags: 0x01 front, 0x02 back, 0x04 no sky |
| 226 | 2 bytes | Unused |
| 228 | 4 uint32 | Counts: radial blur ramp down, down start, fade, motion blur |

## IMAD channels

Each channel field is a run of keyframes: time then value, 8 bytes each. `TNAM` (tint) and
`NAM3` (fade) hold 20-byte color keyframes: time then RGBA floats.

| Signatures | Channel |
| --- | --- |
| `BNAM`, `VNAM`, `RNAM`, `SNAM`, `UNAM`, `NAM1`, `NAM2` | Blur radius, double vision, radial blur strength, ramp up, start, ramp down, down start |
| `WNAM`, `XNAM`, `YNAM` | DoF strength, distance, range |
| `NAM4` | Motion blur strength |
| byte `0x00`-`0x10` then `IAD` | HDR channel 0-16, multiply |
| byte `0x40`-`0x50` then `IAD` | HDR channel 0-16, add |
| byte `0x11`-`0x14` then `IAD` | Cinematic channel 0-3, multiply |
| byte `0x51`-`0x54` then `IAD` | Cinematic channel 0-3, add |

The first byte of the counter signatures is often not printable. A channel whose keyframe
count differs from the header is tallied.
